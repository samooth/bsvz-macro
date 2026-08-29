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

// PUSHTX helpers (WP1605, nChain, 2021)

// secp256k1 curve constants used by PUSHTX_SIGN with the k=a=1 optimisation.
const SECP256K1_GX: [32]u8 = .{
    0x79, 0xbe, 0x66, 0x7e, 0xf9, 0xdc, 0xbb, 0xac, 0x55, 0xa0, 0x62, 0x95, 0xce, 0x87, 0x0b, 0x07,
    0x02, 0x9b, 0xfc, 0xdb, 0x2d, 0xce, 0x28, 0xd9, 0x59, 0xf2, 0x81, 0x5b, 0x16, 0xf8, 0x17, 0x98,
};
const SECP256K1_N: [32]u8 = .{
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xfe,
    0xba, 0xae, 0xdc, 0xe6, 0xaf, 0x48, 0xa0, 0x3b, 0xbf, 0xd2, 0x5e, 0x8c, 0xd0, 0x36, 0x41, 0x41,
};
const SECP256K1_N_HALF: [32]u8 = .{
    0x7f, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xfe,
    0x5d, 0x57, 0x6e, 0x73, 0x57, 0xa4, 0x50, 0x1d, 0xdf, 0xe9, 0x2f, 0x46, 0x68, 0x1b, 0x20, 0xa0,
};

fn emitPushBytes(out: *std.ArrayListUnmanaged(u8), allocator: std.mem.Allocator, data: []const u8) ExpandError!void {
    if (data.len > 520) return ExpandError.Overflow;
    builder.appendPushData(out, allocator, data) catch return ExpandError.OutOfMemory;
}

fn emitPushInt32LE(out: *std.ArrayListUnmanaged(u8), allocator: std.mem.Allocator, value: i64) ExpandError!void {
    if (value < 0 or value > 0xffffffff) return ExpandError.Overflow;
    const v: u32 = @intCast(value);
    const bytes: [4]u8 = .{ @truncate(v), @truncate(v >> 8), @truncate(v >> 16), @truncate(v >> 24) };
    try emitPushBytes(out, allocator, &bytes);
}

fn hexCharVal(c: u8) u4 {
    return switch (c) {
        '0'...'9' => @intCast(c - '0'),
        'a'...'f' => @intCast(c - 'a' + 10),
        'A'...'F' => @intCast(c - 'A' + 10),
        else => 0,
    };
}

fn decodeHex(out: []u8, hex: []const u8) bool {
    var i: usize = 0;
    var j: usize = 0;
    while (i < hex.len) : (i += 2) {
        if (i + 1 >= hex.len) return false;
        const hi = hexCharVal(hex[i]);
        const lo = hexCharVal(hex[i + 1]);
        out[j] = (@as(u8, hi) << 4) | lo;
        j += 1;
    }
    return true;
}

fn emitPushHexString(out: *std.ArrayListUnmanaged(u8), allocator: std.mem.Allocator, raw: []const u8) ExpandError!void {
    const hex_str = if (raw.len >= 2 and raw[0] == '0' and (raw[1] == 'x' or raw[1] == 'X'))
        raw[2..]
    else
        raw;
    if (hex_str.len == 0 or (hex_str.len % 2) != 0) return ExpandError.TypeMismatch;
    var buf: [260]u8 = undefined;
    if (hex_str.len / 2 > buf.len) return ExpandError.Overflow;
    if (!decodeHex(buf[0 .. hex_str.len / 2], hex_str)) return ExpandError.TypeMismatch;
    try emitPushBytes(out, allocator, buf[0 .. hex_str.len / 2]);
}

fn requireStringArg(arg: AstNode) ExpandError![]const u8 {
    if (arg != .string_literal) return ExpandError.TypeMismatch;
    return arg.string_literal;
}

fn pushTxTocanonicalExpand(allocator: std.mem.Allocator, args: []const AstNode, body: ?[]const AstNode, table: *const MacroTable) ExpandError![]const u8 {
    _ = body; _ = table;
    if (args.len != 0) return ExpandError.ArityMismatch;
    var out = std.ArrayListUnmanaged(u8){};
    defer out.deinit(allocator);
    // [toCanonical]: force s in [0, n/2]; if s > n/2, replace with n - s.
    try emitOpcode(&out, allocator, .OP_DUP);
    try emitPushBytes(&out, allocator, &SECP256K1_N_HALF);
    try emitOpcode(&out, allocator, .OP_GREATERTHAN);
    try emitOpcode(&out, allocator, .OP_IF);
    try emitPushBytes(&out, allocator, &SECP256K1_N);
    try emitOpcode(&out, allocator, .OP_SWAP);
    try emitOpcode(&out, allocator, .OP_SUB);
    try emitOpcode(&out, allocator, .OP_ENDIF);
    return out.toOwnedSlice(allocator);
}

fn pushTxConcatenationsExpand(allocator: std.mem.Allocator, args: []const AstNode, body: ?[]const AstNode, table: *const MacroTable) ExpandError![]const u8 {
    _ = body; _ = table;
    if (args.len != 0) return ExpandError.ArityMismatch;
    var out = std.ArrayListUnmanaged(u8){};
    defer out.deinit(allocator);
    // [concatenations]: build DER bytes (30 || len || 02 20 Gx 02 || s) from r (below) and s (top).
    // Per WP1605 [concatenations]:= OP_SIZE OP_DUP <0x24> OP_ADD <0x30> OP_SWAP OP_CAT
    //   <0220||Gx||02> OP_CAT OP_SWAP OP_CAT OP_SWAP OP_CAT
    try emitOpcode(&out, allocator, .OP_SIZE);
    try emitOpcode(&out, allocator, .OP_DUP);
    emitMinimalPushInt(&out, allocator, 0x24) catch return ExpandError.TypeMismatch;
    try emitOpcode(&out, allocator, .OP_ADD);
    emitMinimalPushInt(&out, allocator, 0x30) catch return ExpandError.TypeMismatch;
    try emitOpcode(&out, allocator, .OP_SWAP);
    try emitOpcode(&out, allocator, .OP_CAT);
    // push 0x02 0x20 || Gx || 0x02 (34 bytes)
    var gx_tagged: [34]u8 = undefined;
    gx_tagged[0] = 0x02;
    gx_tagged[1] = 0x20;
    @memcpy(gx_tagged[2..34], &SECP256K1_GX);
    gx_tagged[33] = 0x02;
    try emitPushBytes(&out, allocator, &gx_tagged);
    try emitOpcode(&out, allocator, .OP_CAT);
    try emitOpcode(&out, allocator, .OP_SWAP);
    try emitOpcode(&out, allocator, .OP_CAT);
    try emitOpcode(&out, allocator, .OP_SWAP);
    try emitOpcode(&out, allocator, .OP_CAT);
    return out.toOwnedSlice(allocator);
}
fn pushTxToderExpand(allocator: std.mem.Allocator, args: []const AstNode, body: ?[]const AstNode, table: *const MacroTable) ExpandError![]const u8 {
    _ = body;
    if (args.len != 0) return ExpandError.ArityMismatch;
    // [toDER]:= [toCanonical][concatenations]; expand inline to avoid recursive macro call.
    var out = std.ArrayListUnmanaged(u8){};
    defer out.deinit(allocator);
    const canonical = try pushTxTocanonicalExpand(allocator, args, null, table);
    defer allocator.free(canonical);
    const concats = try pushTxConcatenationsExpand(allocator, args, null, table);
    defer allocator.free(concats);
    try out.appendSlice(allocator, canonical);
    try out.appendSlice(allocator, concats);
    return out.toOwnedSlice(allocator);
}

fn pushTxSignExpand(allocator: std.mem.Allocator, args: []const AstNode, body: ?[]const AstNode, table: *const MacroTable) ExpandError![]const u8 {
    _ = body;
    if (args.len != 1) return ExpandError.ArityMismatch;
    if (args[0] != .integer_literal) return ExpandError.TypeMismatch;
    const sighash = args[0].integer_literal;
    var out = std.ArrayListUnmanaged(u8){};
    defer out.deinit(allocator);
    // [sign] with k=a=1: OP_HASH256 <Gx> OP_ADD <n> OP_MOD [toDER] <sighash> OP_CAT <Gcomp> OP_CAT
    try emitOpcode(&out, allocator, .OP_HASH256);
    try emitPushBytes(&out, allocator, &SECP256K1_GX);
    try emitOpcode(&out, allocator, .OP_ADD);
    try emitPushBytes(&out, allocator, &SECP256K1_N);
    try emitOpcode(&out, allocator, .OP_MOD);
    const toder = try pushTxToderExpand(allocator, &.{}, null, table);
    defer allocator.free(toder);
    try out.appendSlice(allocator, toder);
    try emitPushInt32LE(&out, allocator, sighash);
    try emitOpcode(&out, allocator, .OP_CAT);
    // Gcompressed = 0x02 || Gx (33 bytes)
    var gcomp: [33]u8 = undefined;
    gcomp[0] = 0x02;
    @memcpy(gcomp[1..33], &SECP256K1_GX);
    try emitPushBytes(&out, allocator, &gcomp);
    try emitOpcode(&out, allocator, .OP_CAT);
    return out.toOwnedSlice(allocator);
}

fn pushTxOutputsRequestExpand(allocator: std.mem.Allocator, args: []const AstNode, body: ?[]const AstNode, table: *const MacroTable) ExpandError![]const u8 {
    _ = body; _ = table;
    if (args.len != 2) return ExpandError.ArityMismatch;
    const item8_hex = try requireStringArg(args[0]);
    const items10_11_hex = try requireStringArg(args[1]);
    var out = std.ArrayListUnmanaged(u8){};
    defer out.deinit(allocator);
    // [outputsRequest]:= OP_2DUP OP_HASH256 OP_SWAP <item 8> OP_CAT OP_SWAP OP_CAT <item 10 and 11> OP_CAT
    try emitOpcode(&out, allocator, .OP_2DUP);
    try emitOpcode(&out, allocator, .OP_HASH256);
    try emitOpcode(&out, allocator, .OP_SWAP);
    try emitPushHexString(&out, allocator, item8_hex);
    try emitOpcode(&out, allocator, .OP_CAT);
    try emitOpcode(&out, allocator, .OP_SWAP);
    try emitOpcode(&out, allocator, .OP_CAT);
    try emitPushHexString(&out, allocator, items10_11_hex);
    try emitOpcode(&out, allocator, .OP_CAT);
    return out.toOwnedSlice(allocator);
}

fn pelsLockingScriptExpand(allocator: std.mem.Allocator, args: []const AstNode, body: ?[]const AstNode, table: *const MacroTable) ExpandError![]const u8 {
    _ = body;
    if (args.len != 4) return ExpandError.ArityMismatch;
    if (args[0] != .integer_literal) return ExpandError.TypeMismatch;
    _ = try requireStringArg(args[1]);
    _ = try requireStringArg(args[2]);
    const pk_b_hash160_hex = try requireStringArg(args[3]);

    const pk_bytes = decodeHexAlloc(allocator, pk_b_hash160_hex) catch return ExpandError.TypeMismatch;
    defer allocator.free(pk_bytes);
    if (pk_bytes.len != 20) return ExpandError.TypeMismatch;

    var out = std.ArrayListUnmanaged(u8){};
    defer out.deinit(allocator);

    const orq = try pushTxOutputsRequestExpand(allocator, args[1..3], null, table);
    defer allocator.free(orq);
    try out.appendSlice(allocator, orq);

    const sign_args = [_]AstNode{args[0]};
    const sign = try pushTxSignExpand(allocator, &sign_args, null, table);
    defer allocator.free(sign);
    try out.appendSlice(allocator, sign);

    try emitOpcode(&out, allocator, .OP_CHECKSIGVERIFY);
    try emitOpcode(&out, allocator, .OP_SWAP);
    emitMinimalPushInt(&out, allocator, 0x68) catch return ExpandError.TypeMismatch;
    try emitOpcode(&out, allocator, .OP_SPLIT);
    try emitOpcode(&out, allocator, .OP_NIP);
    try emitOpcode(&out, allocator, .OP_SWAP);
    emitMinimalPushInt(&out, allocator, 0x8) catch return ExpandError.TypeMismatch;
    try emitOpcode(&out, allocator, .OP_SPLIT);
    try emitOpcode(&out, allocator, .OP_SWAP);
    try emitOpcode(&out, allocator, .OP_CAT);
    try emitOpcode(&out, allocator, .OP_EQUALVERIFY);
    try emitOpcode(&out, allocator, .OP_DUP);
    try emitOpcode(&out, allocator, .OP_HASH160);
    try emitPushBytes(&out, allocator, pk_bytes);
    try emitOpcode(&out, allocator, .OP_EQUALVERIFY);
    try emitOpcode(&out, allocator, .OP_CHECKSIG);
    return out.toOwnedSlice(allocator);
}

fn decodeHexAlloc(allocator: std.mem.Allocator, raw: []const u8) ![]u8 {
    const hex_str = if (raw.len >= 2 and raw[0] == '0' and (raw[1] == 'x' or raw[1] == 'X'))
        raw[2..]
    else
        raw;
    if (hex_str.len == 0 or (hex_str.len % 2) != 0) return error.InvalidHex;
    const out = try allocator.alloc(u8, hex_str.len / 2);
    if (!decodeHex(out, hex_str)) return error.InvalidHex;
    return out;
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
    try table.register("PUSHTX_TOCANONICAL", .{ .arity = 0, .param_types = &.{}, .expand_fn = pushTxTocanonicalExpand });
    try table.register("PUSHTX_CONCATENATIONS", .{ .arity = 0, .param_types = &.{}, .expand_fn = pushTxConcatenationsExpand });
    try table.register("PUSHTX_TODER", .{ .arity = 0, .param_types = &.{}, .expand_fn = pushTxToderExpand });
    try table.register("PUSHTX_SIGN", .{ .arity = 1, .param_types = &.{.integer}, .expand_fn = pushTxSignExpand });
    try table.register("PUSHTX_OUTPUTS_REQUEST", .{ .arity = 2, .param_types = &.{ .string, .string }, .expand_fn = pushTxOutputsRequestExpand });
    try table.register("PELS_LOCKING_SCRIPT", .{ .arity = 4, .param_types = &.{ .integer, .string, .string, .string }, .expand_fn = pelsLockingScriptExpand });
}