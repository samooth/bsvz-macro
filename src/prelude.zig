const std = @import("std");
const Opcode = @import("bsvz").script.opcode.Opcode;
const builder = @import("bsvz").script.builder;
const AstNode = @import("parser/ast.zig").AstNode;
const ExpandError = @import("expander/error.zig").ExpandError;
const MacroTable = @import("expander/table.zig").MacroTable;
const MacroDefinition = @import("expander/table.zig").MacroDefinition;
const ParamType = @import("expander/table.zig").ParamType;

fn emitOpcode(out: *std.ArrayListUnmanaged(u8), allocator: std.mem.Allocator, op: Opcode) !void {
    try out.append(allocator, op.toByte());
}

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

fn xswapExpand(allocator: std.mem.Allocator, args: []const AstNode, body: ?[]const AstNode, table: *const MacroTable) ExpandError![]const u8 {
    _ = body; _ = table;
    if (args.len != 1) return ExpandError.ArityMismatch;
    if (args[0] != .integer_literal) return ExpandError.TypeMismatch;
    const n = args[0].integer_literal;
    if (n < 1) return ExpandError.TypeMismatch;
    var out = std.ArrayListUnmanaged(u8){};
    defer out.deinit(allocator);
    emitMinimalPushInt(&out, allocator, n - 1) catch return ExpandError.TypeMismatch;
    try emitOpcode(&out, allocator, .OP_PICK);
    emitMinimalPushInt(&out, allocator, n - 1) catch return ExpandError.TypeMismatch;
    try emitOpcode(&out, allocator, .OP_ROLL);
    try emitOpcode(&out, allocator, .OP_SWAP);
    try emitOpcode(&out, allocator, .OP_DROP);
    return out.toOwnedSlice(allocator);
}

fn xdropExpand(allocator: std.mem.Allocator, args: []const AstNode, body: ?[]const AstNode, table: *const MacroTable) ExpandError![]const u8 {
    _ = body; _ = table;
    if (args.len != 1) return ExpandError.ArityMismatch;
    if (args[0] != .integer_literal) return ExpandError.TypeMismatch;
    const n = args[0].integer_literal;
    if (n < 1) return ExpandError.TypeMismatch;
    var out = std.ArrayListUnmanaged(u8){};
    defer out.deinit(allocator);
    emitMinimalPushInt(&out, allocator, n - 1) catch return ExpandError.TypeMismatch;
    try emitOpcode(&out, allocator, .OP_ROLL);
    try emitOpcode(&out, allocator, .OP_DROP);
    return out.toOwnedSlice(allocator);
}

fn xrotExpand(allocator: std.mem.Allocator, args: []const AstNode, body: ?[]const AstNode, table: *const MacroTable) ExpandError![]const u8 {
    _ = body; _ = table;
    if (args.len != 1) return ExpandError.ArityMismatch;
    if (args[0] != .integer_literal) return ExpandError.TypeMismatch;
    const n = args[0].integer_literal;
    if (n < 1) return ExpandError.TypeMismatch;
    var out = std.ArrayListUnmanaged(u8){};
    defer out.deinit(allocator);
    emitMinimalPushInt(&out, allocator, n - 1) catch return ExpandError.TypeMismatch;
    try emitOpcode(&out, allocator, .OP_ROLL);
    return out.toOwnedSlice(allocator);
}

fn hashcatExpand(allocator: std.mem.Allocator, args: []const AstNode, body: ?[]const AstNode, table: *const MacroTable) ExpandError![]const u8 {
    _ = args; _ = body; _ = table;
    var out = std.ArrayListUnmanaged(u8){};
    defer out.deinit(allocator);
    try emitOpcode(&out, allocator, .OP_DUP);
    try emitOpcode(&out, allocator, .OP_SHA256);
    try emitOpcode(&out, allocator, .OP_SWAP);
    try emitOpcode(&out, allocator, .OP_CAT);
    return out.toOwnedSlice(allocator);
}

fn ifdupExpand(allocator: std.mem.Allocator, args: []const AstNode, body: ?[]const AstNode, table: *const MacroTable) ExpandError![]const u8 {
    _ = args; _ = body; _ = table;
    var out = std.ArrayListUnmanaged(u8){};
    defer out.deinit(allocator);
    try emitOpcode(&out, allocator, .OP_DUP);
    try emitOpcode(&out, allocator, .OP_IF);
    try emitOpcode(&out, allocator, .OP_DUP);
    try emitOpcode(&out, allocator, .OP_ENDIF);
    return out.toOwnedSlice(allocator);
}

fn safeDivExpand(allocator: std.mem.Allocator, args: []const AstNode, body: ?[]const AstNode, table: *const MacroTable) ExpandError![]const u8 {
    _ = args; _ = body; _ = table;
    var out = std.ArrayListUnmanaged(u8){};
    defer out.deinit(allocator);
    try emitOpcode(&out, allocator, .OP_SWAP);
    try emitOpcode(&out, allocator, .OP_DUP);
    try emitOpcode(&out, allocator, .OP_0NOTEQUAL);
    try emitOpcode(&out, allocator, .OP_VERIFY);
    try emitOpcode(&out, allocator, .OP_DIV);
    return out.toOwnedSlice(allocator);
}

fn rangeCheckExpand(allocator: std.mem.Allocator, args: []const AstNode, body: ?[]const AstNode, table: *const MacroTable) ExpandError![]const u8 {
    _ = body; _ = table;
    if (args.len != 2) return ExpandError.ArityMismatch;
    if (args[0] != .integer_literal or args[1] != .integer_literal) return ExpandError.TypeMismatch;
    const min = args[0].integer_literal;
    const max = args[1].integer_literal;
    var out = std.ArrayListUnmanaged(u8){};
    defer out.deinit(allocator);
    try emitOpcode(&out, allocator, .OP_DUP);
    emitMinimalPushInt(&out, allocator, min) catch return ExpandError.TypeMismatch;
    try emitOpcode(&out, allocator, .OP_GREATERTHANOREQUAL);
    try emitOpcode(&out, allocator, .OP_SWAP);
    emitMinimalPushInt(&out, allocator, max) catch return ExpandError.TypeMismatch;
    try emitOpcode(&out, allocator, .OP_LESSTHANOREQUAL);
    try emitOpcode(&out, allocator, .OP_BOOLAND);
    try emitOpcode(&out, allocator, .OP_VERIFY);
    return out.toOwnedSlice(allocator);
}

fn p2pkhFromPubkeyExpand(allocator: std.mem.Allocator, args: []const AstNode, body: ?[]const AstNode, table: *const MacroTable) ExpandError![]const u8 {
    _ = args; _ = body; _ = table;
    var out = std.ArrayListUnmanaged(u8){};
    defer out.deinit(allocator);
    try emitOpcode(&out, allocator, .OP_DUP);
    try emitOpcode(&out, allocator, .OP_HASH160);
    const placeholder = [_]u8{0} ** 20;
    builder.appendPushData(&out, allocator, &placeholder) catch return ExpandError.TypeMismatch;
    try emitOpcode(&out, allocator, .OP_EQUALVERIFY);
    try emitOpcode(&out, allocator, .OP_CHECKSIG);
    return out.toOwnedSlice(allocator);
}

fn verifyAllExpand(allocator: std.mem.Allocator, args: []const AstNode, body: ?[]const AstNode, table: *const MacroTable) ExpandError![]const u8 {
    _ = body; _ = table;
    if (args.len < 1) return ExpandError.ArityMismatch;
    var out = std.ArrayListUnmanaged(u8){};
    defer out.deinit(allocator);
    // BOOLAND chain: pop N items, verify all are true
    for (1..args.len) |_| {
        try emitOpcode(&out, allocator, .OP_BOOLAND);
    }
    try emitOpcode(&out, allocator, .OP_VERIFY);
    return out.toOwnedSlice(allocator);
}

fn verifyAnyExpand(allocator: std.mem.Allocator, args: []const AstNode, body: ?[]const AstNode, table: *const MacroTable) ExpandError![]const u8 {
    _ = body; _ = table;
    if (args.len < 1) return ExpandError.ArityMismatch;
    var out = std.ArrayListUnmanaged(u8){};
    defer out.deinit(allocator);
    // BOOLOR chain: pop N items, verify at least one is true
    for (1..args.len) |_| {
        try emitOpcode(&out, allocator, .OP_BOOLOR);
    }
    try emitOpcode(&out, allocator, .OP_VERIFY);
    return out.toOwnedSlice(allocator);
}

fn pushTxFragmentExpand(allocator: std.mem.Allocator, args: []const AstNode, body: ?[]const AstNode, table: *const MacroTable) ExpandError![]const u8 {
    _ = body; _ = table;
    if (args.len != 1) return ExpandError.ArityMismatch;
    if (args[0] != .integer_literal) return ExpandError.TypeMismatch;
    const n = args[0].integer_literal;
    if (n < 1 or n > 10) return ExpandError.TypeMismatch;
    var out = std.ArrayListUnmanaged(u8){};
    defer out.deinit(allocator);
    // PUSHTX helper: PICK n; DUP; HASH256; CAT
    // Per WP1605 (nChain, 2021) section 1.2 message construction:
    // access the item at depth n, duplicate it, hash the copy, and concatenate
    // the original with the hash to form a fragment suitable for the preimage.
    emitMinimalPushInt(&out, allocator, n) catch return ExpandError.TypeMismatch;
    try emitOpcode(&out, allocator, .OP_PICK);
    try emitOpcode(&out, allocator, .OP_DUP);
    try emitOpcode(&out, allocator, .OP_HASH256);
    try emitOpcode(&out, allocator, .OP_CAT);
    return out.toOwnedSlice(allocator);
}

pub fn registerCanonicalMacros(table: *MacroTable) !void {
    try table.register("OP_XSWAP", .{ .arity = 1, .param_types = &.{.integer}, .expand_fn = xswapExpand });
    try table.register("OP_XDROP", .{ .arity = 1, .param_types = &.{.integer}, .expand_fn = xdropExpand });
    try table.register("OP_XROT", .{ .arity = 1, .param_types = &.{.integer}, .expand_fn = xrotExpand });
    try table.register("OP_HASHCAT", .{ .arity = 0, .param_types = &.{}, .expand_fn = hashcatExpand });
    try table.register("IFDUP", .{ .arity = 0, .param_types = &.{}, .expand_fn = ifdupExpand });
    try table.register("SAFE_DIV", .{ .arity = 0, .param_types = &.{}, .expand_fn = safeDivExpand });
    try table.register("RANGE_CHECK", .{ .arity = 2, .param_types = &.{ .integer, .integer }, .expand_fn = rangeCheckExpand });
    try table.register("P2PKH_FROM_PUBKEY", .{ .arity = 0, .param_types = &.{}, .expand_fn = p2pkhFromPubkeyExpand });
    try table.register("VERIFY_ALL", .{ .arity = 1, .param_types = &.{.integer}, .expand_fn = verifyAllExpand });
    try table.register("VERIFY_ANY", .{ .arity = 1, .param_types = &.{.integer}, .expand_fn = verifyAnyExpand });
    try table.register("PUSHTX_FRAGMENT", .{ .arity = 1, .param_types = &.{.integer}, .expand_fn = pushTxFragmentExpand });
}
