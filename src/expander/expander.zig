const std = @import("std");
const Opcode = @import("bsvz").script.opcode.Opcode;
const builder = @import("bsvz").script.builder;
const AstNode = @import("../parser/ast.zig").AstNode;
const Condition = @import("../parser/ast.zig").Condition;
const LegacyFlag = @import("../parser/ast.zig").LegacyFlag;
const ExpandError = @import("error.zig").ExpandError;
const MacroTable = @import("table.zig").MacroTable;
const MacroDefinition = @import("table.zig").MacroDefinition;
const ParamType = @import("table.zig").ParamType;
const CompileOptions = @import("../lib.zig").CompileOptions;
const FeatureSet = @import("../lib.zig").FeatureSet;
const LimitSet = @import("../lib.zig").LimitSet;
const StandardnessFlags = @import("../lib.zig").StandardnessFlags;
const DiagnosticList = @import("../diagnostics.zig").DiagnosticList;
const SourceLocation = @import("../diagnostics.zig").SourceLocation;

const max_recursion_depth = 32;
const max_expansion_opcodes = 1_000_000;

pub const Expander = struct {
    table: *const MacroTable,
    options: CompileOptions,
    resolved_features: FeatureSet,
    resolved_limits: LimitSet,
    recursion_depth: u8 = 0,
    total_opcodes: usize = 0,
    diagnostics: ?*DiagnosticList = null,
    stmt_locs: []const SourceLocation = &.{},

    pub fn init(table: *const MacroTable, options: CompileOptions) Expander {
        return .{
            .table = table,
            .options = options,
            .resolved_features = options.effectiveFeatures(),
            .resolved_limits = options.effectiveLimits(),
        };
    }

    pub fn expand(
        self: *Expander,
        allocator: std.mem.Allocator,
        nodes: []const AstNode,
    ) ExpandError![]const u8 {
        var out: std.ArrayListUnmanaged(u8) = .empty;
        defer out.deinit(allocator);

        for (nodes, 0..) |node, i| {
            const bytes = self.expandNode(allocator, node) catch |e| {
                self.reportExpand(e, i);
                return e;
            };
            defer allocator.free(bytes);
            try out.appendSlice(allocator, bytes);
        }

        return out.toOwnedSlice(allocator);
    }

    fn reportExpand(self: *Expander, err: anyerror, stmt_index: usize) void {
        const diags = self.diagnostics orelse return;
        const loc: SourceLocation = if (self.stmt_locs.len > stmt_index)
            self.stmt_locs[stmt_index]
        else
            .{ .line = 0, .column = 0, .offset = 0, .length = 0 };
        diags.append(.expand, .@"error", "expand error: {s}", loc, .{@errorName(err)});
    }

    fn expandNode(self: *Expander, allocator: std.mem.Allocator, node: AstNode) ExpandError![]const u8 {
        switch (node) {
            .opcode_literal => |op| {
                self.total_opcodes += 1;
                if (self.total_opcodes > max_expansion_opcodes) return ExpandError.Overflow;
                var out: std.ArrayListUnmanaged(u8) = .empty;
                try out.append(allocator, op.toByte());
                return out.toOwnedSlice(allocator);
            },
            .integer_literal => |val| {
                var out: std.ArrayListUnmanaged(u8) = .empty;
                emitMinimalPushInt(&out, allocator, val) catch return ExpandError.TypeMismatch;
                return out.toOwnedSlice(allocator);
            },
            .string_literal => |str| {
                // Try hex decode first, else treat as raw bytes
                var out: std.ArrayListUnmanaged(u8) = .empty;
                if (str.len >= 2 and str[0] == '0' and str[1] == 'x') {
                    const hex_str = str[2..];
                    if (hex_str.len % 2 != 0) return ExpandError.TypeMismatch;
                    const decoded = try allocator.alloc(u8, hex_str.len / 2);
                    defer allocator.free(decoded);
                    _ = std.fmt.hexToBytes(decoded, hex_str) catch return ExpandError.TypeMismatch;
                    builder.appendPushData(&out, allocator, decoded) catch return ExpandError.TypeMismatch;
                } else {
                    builder.appendPushData(&out, allocator, str) catch return ExpandError.TypeMismatch;
                }
                return out.toOwnedSlice(allocator);
            },
            .macro_invocation => |m| {
                return try self.expandMacro(allocator, m.name, m.args, m.body);
            },
            .loop_block => |l| {
                return try self.expandLoop(allocator, l);
            },
            .conditional => |c| {
                return try self.expandConditional(allocator, c);
            },
            .compile_error => |e| {
                const diags = self.diagnostics orelse return ExpandError.CompileError;
                diags.append(.expand, .@"error", "compile error: {s}", unknownLocation, .{e.message});
                return ExpandError.CompileError;
            },
            .block => |b| {
                return try self.expand(allocator, b);
            },
            .iterator_ref => {
                // Should have been substituted before reaching here
                return ExpandError.TypeMismatch;
            },
        }
    }

    fn expandMacro(
        self: *Expander,
        allocator: std.mem.Allocator,
        name: []const u8,
        args: []const AstNode,
        body: ?[]const AstNode,
    ) ExpandError![]const u8 {
        self.recursion_depth += 1;
        if (self.recursion_depth > max_recursion_depth) {
            return ExpandError.MacroRecursionDepthExceeded;
        }
        defer self.recursion_depth -= 1;

        const def = self.table.lookup(name) orelse return ExpandError.UnboundMacro;

        if (args.len != def.arity) return ExpandError.ArityMismatch;

        // Type check args
        for (args, def.param_types) |arg, expected_type| {
            const actual_type: ParamType = switch (arg) {
                .integer_literal => .integer,
                .string_literal => .string,
                .opcode_literal => .opcode,
                .block => .block,
                else => return ExpandError.TypeMismatch,
            };
            if (actual_type != expected_type) return ExpandError.TypeMismatch;
        }

        // Expand args to literal values for the macro function
        var expanded_args: std.ArrayList(AstNode) = .empty;
        defer {
            for (expanded_args.items) |arg| {
                switch (arg) {
                    .string_literal => |s| allocator.free(s),
                    else => {},
                }
            }
            expanded_args.deinit(allocator);
        }

        for (args) |arg| {
            switch (arg) {
                .integer_literal, .opcode_literal => try expanded_args.append(allocator, arg),
                .string_literal => |s| try expanded_args.append(allocator, .{ .string_literal = try allocator.dupe(u8, s) }),
                else => return ExpandError.TypeMismatch,
            }
        }

        const result = try def.expand_fn(allocator, expanded_args.items, body, self.table);
        return result;
    }

    fn expandLoop(self: *Expander, allocator: std.mem.Allocator, loop: @TypeOf(@as(AstNode, undefined).loop_block)) ExpandError![]const u8 {
        if (loop.bound == 0) return try allocator.dupe(u8, &.{});
        if (loop.bound > 1000) return ExpandError.LoopBoundTooLarge;

        // Fast path: when the body never references the loop iterator, the
        // expansion is identical on every iteration. Expand once and repeat the
        // bytecode instead of cloning + expanding the AST per iteration.
        if (!bodyReferencesIterator(loop.body, loop.iterator_var)) {
            const bytes = try self.expand(allocator, loop.body);
            errdefer allocator.free(bytes);
            var repeated: std.ArrayListUnmanaged(u8) = .empty;
            defer repeated.deinit(allocator);
            for (0..@as(usize, @intCast(loop.bound))) |_| {
                try repeated.appendSlice(allocator, bytes);
            }
            allocator.free(bytes);
            return repeated.toOwnedSlice(allocator);
        }

        var out: std.ArrayListUnmanaged(u8) = .empty;
        defer out.deinit(allocator);

        for (0..@as(usize, @intCast(loop.bound))) |i| {
            const substituted = try substituteIterator(allocator, loop.body, loop.iterator_var, i);
            defer {
                for (substituted) |node| deinitNode(allocator, node);
                allocator.free(substituted);
            }
            const bytes = try self.expand(allocator, substituted);
            defer allocator.free(bytes);
            try out.appendSlice(allocator, bytes);
        }

        return out.toOwnedSlice(allocator);
    }

    /// Returns true if any node in `nodes` is an `.iterator_ref` equal to
    /// `var_name`, recursing into macro args/bodies, nested loop bodies,
    /// conditional branches, and blocks.
    fn bodyReferencesIterator(nodes: []const AstNode, var_name: []const u8) bool {
        for (nodes) |node| {
            if (nodeReferencesIterator(node, var_name)) return true;
        }
        return false;
    }

    fn nodeReferencesIterator(node: AstNode, var_name: []const u8) bool {
        switch (node) {
            .iterator_ref => |r| return std.mem.eql(u8, r, var_name),
            .macro_invocation => |m| {
                if (bodyReferencesIterator(m.args, var_name)) return true;
                if (m.body) |b| if (bodyReferencesIterator(b, var_name)) return true;
                return false;
            },
            .loop_block => |l| {
                // A nested loop shadowing var_name does not count as a reference
                // to the outer var, but substituteIterator does not implement
                // shadowing, so conservatively treat any same-named reference as
                // a use. Nested bodies are still scanned for other references.
                return bodyReferencesIterator(l.body, var_name);
            },
            .conditional => |c| {
                if (bodyReferencesIterator(c.then_branch, var_name)) return true;
                if (c.else_branch) |eb| if (bodyReferencesIterator(eb, var_name)) return true;
                return false;
            },
            .block => |b| return bodyReferencesIterator(b, var_name),
            else => return false,
        }
    }

    fn expandConditional(self: *Expander, allocator: std.mem.Allocator, cond: @TypeOf(@as(AstNode, undefined).conditional)) ExpandError![]const u8 {
        const should_expand = self.evaluateCondition(cond.condition);

        if (should_expand) {
            return try self.expand(allocator, cond.then_branch);
        } else if (cond.else_branch) |else_b| {
            return try self.expand(allocator, else_b);
        } else {
            return try allocator.dupe(u8, &.{});
        }
    }

    fn evaluateCondition(self: *Expander, condition: Condition) bool {
        const features = self.resolved_features;
        return switch (condition) {
            .era => |era| switch (era) {
                .satoshi => features.era_satoshi,
                .bip => features.era_bip,
                .bch => features.era_bch,
                .bsv_pre_genesis => features.era_bsv_pre_genesis,
                .genesis => features.era_genesis,
                .chronicle => features.era_chronicle,
            },
            .has_feature => |name| blk: {
                if (!FeatureSet.isKnownFeature(name)) {
                    self.reportUnknownFeature(name);
                    break :blk false;
                }
                break :blk features.hasByName(name);
            },
            .limit => |lim| blk: {
                const actual: u32 = switch (lim.kind) {
                    .push => self.resolved_limits.push,
                    .script => self.resolved_limits.script,
                    .opcodes => self.resolved_limits.opcodes,
                    .stack => self.resolved_limits.stack,
                };
                break :blk actual >= lim.threshold;
            },
            .network => |net| self.options.effectiveNetwork() == net,
            .standardness => |name| blk: {
                if (!StandardnessFlags.isKnownFlag(name)) {
                    self.reportUnknownStandardness(name);
                    break :blk false;
                }
                break :blk self.options.standardness.hasByName(name);
            },
            .version_check => |ver| self.options.protocol_version >= ver,
            .legacy_flag => |flag| switch (flag) {
                .bsv => features.bsv,
                .chronicle => features.era_chronicle,
                .btc_strict => features.btc_strict,
            },
        };
    }

    fn reportUnknownFeature(self: *Expander, name: []const u8) void {
        const diags = self.diagnostics orelse return;
        diags.append(.expand, .warning, "unknown feature flag: @has({s}) evaluates to false", unknownLocation, .{name});
    }

    fn reportUnknownStandardness(self: *Expander, name: []const u8) void {
        const diags = self.diagnostics orelse return;
        diags.append(.expand, .warning, "unknown standardness flag: @standardness({s}) evaluates to false", unknownLocation, .{name});
    }
};

const unknownLocation: SourceLocation = .{ .line = 0, .column = 0, .offset = 0, .length = 0 };

fn emitMinimalPushInt(out: *std.ArrayListUnmanaged(u8), allocator: std.mem.Allocator, value: i64) (std.mem.Allocator.Error || error{ InvalidOpcodeType, DataTooBig })!void {
    if (value == 0) {
        try out.append(allocator, Opcode.OP_0.toByte());
    } else if (value >= 1 and value <= 16) {
        try out.append(allocator, @intCast(0x50 + value));
    } else if (value == -1) {
        try out.append(allocator, Opcode.OP_1NEGATE.toByte());
    } else {
        var buf: [8]u8 = undefined;
        const negative = value < 0;
        var abs_val = if (negative) -value else value;
        var i: usize = 0;
        while (abs_val > 0) : (i += 1) {
            buf[i] = @truncate(@as(u64, @intCast(abs_val)));
            abs_val >>= 8;
        }
        if (i > 0 and (buf[i - 1] & 0x80) != 0) {
            buf[i] = if (negative) 0x80 else 0x00;
            i += 1;
        } else if (negative and i > 0) {
            buf[i - 1] |= 0x80;
        }
        const data = buf[0..i];
        try builder.appendPushData(out, allocator, data);
    }
}

fn substituteIterator(allocator: std.mem.Allocator, nodes: []const AstNode, var_name: []const u8, value: usize) ExpandError![]const AstNode {
    var result: std.ArrayList(AstNode) = .empty;
    defer result.deinit(allocator);

    for (nodes) |node| {
        const new_node = try substituteNode(allocator, node, var_name, value);
        try result.append(allocator, new_node);
    }

    return result.toOwnedSlice(allocator);
}

fn substituteNode(allocator: std.mem.Allocator, node: AstNode, var_name: []const u8, value: usize) ExpandError!AstNode {
    switch (node) {
        .iterator_ref => |ref| {
            if (std.mem.eql(u8, ref, var_name)) {
                return .{ .integer_literal = @intCast(value) };
            }
            return .{ .iterator_ref = try allocator.dupe(u8, ref) };
        },
        .macro_invocation => |m| {
            var new_args: std.ArrayList(AstNode) = .empty;
            defer new_args.deinit(allocator);
            for (m.args) |arg| {
                try new_args.append(allocator, try substituteNode(allocator, arg, var_name, value));
            }
            var new_body: ?[]const AstNode = null;
            if (m.body) |body| {
                new_body = try substituteIterator(allocator, body, var_name, value);
            }
            return .{
                .macro_invocation = .{
                    .name = try allocator.dupe(u8, m.name),
                    .args = try new_args.toOwnedSlice(allocator),
                    .body = new_body,
                },
            };
        },
        .loop_block => |l| {
            return .{
                .loop_block = .{
                    .bound = l.bound,
                    .iterator_var = try allocator.dupe(u8, l.iterator_var),
                    .body = try substituteIterator(allocator, l.body, var_name, value),
                },
            };
        },
        .conditional => |c| {
            const new_then = try substituteIterator(allocator, c.then_branch, var_name, value);
            var new_else: ?[]const AstNode = null;
            if (c.else_branch) |eb| {
                new_else = try substituteIterator(allocator, eb, var_name, value);
            }
            return .{
                .conditional = .{
                    .condition = switch (c.condition) {
                        .has_feature => |name| .{ .has_feature = try allocator.dupe(u8, name) },
                        .standardness => |name| .{ .standardness = try allocator.dupe(u8, name) },
                        else => c.condition,
                    },
                    .then_branch = new_then,
                    .else_branch = new_else,
                },
            };
        },
        .compile_error => |e| {
            return .{ .compile_error = .{ .message = try allocator.dupe(u8, e.message) } };
        },
        .block => |b| {
            return .{ .block = try substituteIterator(allocator, b, var_name, value) };
        },
        .string_literal => |s| {
            return .{ .string_literal = try allocator.dupe(u8, s) };
        },
        else => return node,
    }
}

fn deinitNode(allocator: std.mem.Allocator, node: AstNode) void {
    switch (node) {
        .macro_invocation => |m| {
            allocator.free(m.name);
            for (m.args) |arg| deinitNode(allocator, arg);
            allocator.free(m.args);
            if (m.body) |body| {
                for (body) |n| deinitNode(allocator, n);
                allocator.free(body);
            }
        },
        .loop_block => |l| {
            allocator.free(l.iterator_var);
            for (l.body) |n| deinitNode(allocator, n);
            allocator.free(l.body);
        },
        .conditional => |c| {
            for (c.then_branch) |n| deinitNode(allocator, n);
            allocator.free(c.then_branch);
            if (c.else_branch) |eb| {
                for (eb) |n| deinitNode(allocator, n);
                allocator.free(eb);
            }
            switch (c.condition) {
                .has_feature => |name| allocator.free(name),
                .standardness => |name| allocator.free(name),
                else => {},
            }
        },
        .compile_error => |e| allocator.free(e.message),
        .block => |b| {
            for (b) |n| deinitNode(allocator, n);
            allocator.free(b);
        },
        .string_literal => |s| allocator.free(s),
        .iterator_ref => |s| allocator.free(s),
        else => {},
    }
}
