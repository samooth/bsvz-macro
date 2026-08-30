const std = @import("std");
const Opcode = @import("bsvz").script.opcode.Opcode;
const options_mod = @import("../options.zig");
const Era = options_mod.Era;
const Network = options_mod.Network;
const LimitKind = options_mod.LimitKind;

pub const AstNode = union(enum) {
    opcode_literal: Opcode,
    macro_invocation: struct {
        name: []const u8,
        args: []const AstNode,
        body: ?[]const AstNode,
    },
    loop_block: struct {
        bound: u64,
        iterator_var: []const u8,
        body: []const AstNode,
    },
    conditional: struct {
        condition: Condition,
        then_branch: []const AstNode,
        else_branch: ?[]const AstNode,
    },
    compile_error: struct {
        message: []const u8,
    },
    block: []const AstNode,
    integer_literal: i64,
    string_literal: []const u8,
    iterator_ref: []const u8,
};

pub const Condition = union(enum) {
    era: Era,
    has_feature: []const u8,
    limit: struct {
        kind: LimitKind,
        threshold: u32,
    },
    network: Network,
    standardness: []const u8,
    version_check: u32,
    legacy_flag: LegacyFlag,
};

pub const LegacyFlag = enum {
    bsv,
    chronicle,
    btc_strict,
};

pub const ScriptAst = struct {
    statements: []const AstNode,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *ScriptAst) void {
        deinitNodes(self.statements, self.allocator);
        self.allocator.free(self.statements);
        self.* = undefined;
    }
};

pub fn deinitNodes(nodes: []const AstNode, allocator: std.mem.Allocator) void {
    for (nodes) |node| {
        switch (node) {
            .macro_invocation => |m| {
                allocator.free(m.name);
                deinitNodes(m.args, allocator);
                allocator.free(m.args);
                if (m.body) |body| {
                    deinitNodes(body, allocator);
                    allocator.free(body);
                }
            },
            .loop_block => |l| {
                allocator.free(l.iterator_var);
                deinitNodes(l.body, allocator);
                allocator.free(l.body);
            },
            .conditional => |c| {
                switch (c.condition) {
                    .has_feature => |name| allocator.free(name),
                    .standardness => |name| allocator.free(name),
                    else => {},
                }
                deinitNodes(c.then_branch, allocator);
                allocator.free(c.then_branch);
                if (c.else_branch) |eb| {
                    deinitNodes(eb, allocator);
                    allocator.free(eb);
                }
            },
            .compile_error => |e| allocator.free(e.message),
            .block => |b| {
                deinitNodes(b, allocator);
                allocator.free(b);
            },
            .string_literal => |s| allocator.free(s),
            .iterator_ref => |s| allocator.free(s),
            else => {},
        }
    }
}

pub fn deinit(allocator: std.mem.Allocator, node: AstNode) void {
    deinitNodes(&[_]AstNode{node}, allocator);
}
