const std = @import("std");
const Opcode = @import("bsvz").script.opcode.Opcode;
const builder = @import("bsvz").script.builder;
const AstNode = @import("../parser/ast.zig").AstNode;
const Condition = @import("../parser/ast.zig").Condition;
const FeatureFlag = @import("../parser/ast.zig").FeatureFlag;
const ExpandError = @import("error.zig").ExpandError;
const MacroTable = @import("table.zig").MacroTable;
const MacroDefinition = @import("table.zig").MacroDefinition;
const ParamType = @import("table.zig").ParamType;
const CompileOptions = @import("../lib.zig").CompileOptions;
const Target = @import("../lib.zig").Target;

const max_recursion_depth = 32;
const max_expansion_opcodes = 1_000_000;

pub const Expander = struct {
    table: *const MacroTable,
    options: CompileOptions,
    recursion_depth: u8 = 0,
    total_opcodes: usize = 0,

    pub fn init(table: *const MacroTable, options: CompileOptions) Expander {
        return .{
            .table = table,
            .options = options,
        };
    }

    pub fn expand(
        self: *Expander,
        allocator: std.mem.Allocator,
        nodes: []const AstNode,
    ) ExpandError![]const u8 {
        var out = std.ArrayListUnmanaged(u8){};
        defer out.deinit(allocator);

        for (nodes) |node| {
            const bytes = try self.expandNode(allocator, node);
            defer allocator.free(bytes);
            try out.appendSlice(allocator, bytes);
        }

        return out.toOwnedSlice(allocator);
    }

    fn expandNode(self: *Expander, allocator: std.mem.Allocator, node: AstNode) ExpandError![]const u8 {
        switch (node) {
            .opcode_literal => |op| {
                self.total_opcodes += 1;
                if (self.total_opcodes > max_expansion_opcodes) return ExpandError.Overflow;
                var out = std.ArrayListUnmanaged(u8){};
                try out.append(allocator, op.toByte());
                return out.toOwnedSlice(allocator);
            },
            .integer_literal => |val| {
                var out = std.ArrayListUnmanaged(u8){};
                emitMinimalPushInt(&out, allocator, val) catch return ExpandError.TypeMismatch;
                return out.toOwnedSlice(allocator);
            },
            .string_literal => |str| {
                // Try hex decode first, else treat as raw bytes
                var out = std.ArrayListUnmanaged(u8){};
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

        var out = std.ArrayListUnmanaged(u8){};
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

    fn expandConditional(self: *Expander, allocator: std.mem.Allocator, cond: @TypeOf(@as(AstNode, undefined).conditional)) ExpandError![]const u8 {
        const should_expand = switch (cond.condition) {
            .feature_flag => |flag| switch (flag) {
                .bsv => self.options.target == .bsv_mainnet or self.options.target == .bsv_testnet,
                .chronicle => self.options.target == .bsv_mainnet or self.options.target == .bsv_testnet, // Chronicle is BSV
                .btc_strict => self.options.target == .btc_strict,
            },
            .version_check => |ver| ver <= 2, // Default: accept version <= 2
        };

        if (should_expand) {
            return try self.expand(allocator, cond.then_branch);
        } else if (cond.else_branch) |else_b| {
            return try self.expand(allocator, else_b);
        } else {
            return try allocator.dupe(u8, &.{});
        }
    }
};

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
                    .condition = c.condition,
                    .then_branch = new_then,
                    .else_branch = new_else,
                },
            };
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
        },
        .block => |b| {
            for (b) |n| deinitNode(allocator, n);
            allocator.free(b);
        },
        .string_literal => |s| allocator.free(s),
        .iterator_ref => |s| allocator.free(s),
        else => {},
    }
}
