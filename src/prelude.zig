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
    var out: std.ArrayListUnmanaged(u8) = .empty;
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
    var out: std.ArrayListUnmanaged(u8) = .empty;
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
    var out: std.ArrayListUnmanaged(u8) = .empty;
    defer out.deinit(allocator);
    emitMinimalPushInt(&out, allocator, n - 1) catch return ExpandError.TypeMismatch;
    try emitOpcode(&out, allocator, .OP_ROLL);
    return out.toOwnedSlice(allocator);
}

fn hashcatExpand(allocator: std.mem.Allocator, args: []const AstNode, body: ?[]const AstNode, table: *const MacroTable) ExpandError![]const u8 {
    _ = args; _ = body; _ = table;
    var out: std.ArrayListUnmanaged(u8) = .empty;
    defer out.deinit(allocator);
    try emitOpcode(&out, allocator, .OP_DUP);
    try emitOpcode(&out, allocator, .OP_SHA256);
    try emitOpcode(&out, allocator, .OP_SWAP);
    try emitOpcode(&out, allocator, .OP_CAT);
    return out.toOwnedSlice(allocator);
}

fn ifdupExpand(allocator: std.mem.Allocator, args: []const AstNode, body: ?[]const AstNode, table: *const MacroTable) ExpandError![]const u8 {
    _ = args; _ = body; _ = table;
    var out: std.ArrayListUnmanaged(u8) = .empty;
    defer out.deinit(allocator);
    try emitOpcode(&out, allocator, .OP_DUP);
    try emitOpcode(&out, allocator, .OP_IF);
    try emitOpcode(&out, allocator, .OP_DUP);
    try emitOpcode(&out, allocator, .OP_ENDIF);
    return out.toOwnedSlice(allocator);
}

fn safeDivExpand(allocator: std.mem.Allocator, args: []const AstNode, body: ?[]const AstNode, table: *const MacroTable) ExpandError![]const u8 {
    _ = args; _ = body; _ = table;
    var out: std.ArrayListUnmanaged(u8) = .empty;
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
    var out: std.ArrayListUnmanaged(u8) = .empty;
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
    var out: std.ArrayListUnmanaged(u8) = .empty;
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
    var out: std.ArrayListUnmanaged(u8) = .empty;
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
    var out: std.ArrayListUnmanaged(u8) = .empty;
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
    var out: std.ArrayListUnmanaged(u8) = .empty;
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

// PUSHTX_BIT_SHIFT precomputed values (from zkscript_package, verified on-chain).
// k = 2^security, so R = 2^security * G and P = a * G with a * R_x = -1 mod n.
// Signature uses s = (HASH256(z) >> security) - R_x mod n, which is much
// cheaper than (HASH256(z) + Gx) mod n because the shifted value is already
// in [0, n). Requires the unlocking key to grind tx_in.sequence until
// HASH256(z) % 2^security == 1 and HASH256(z) >> security >= 2^248.
const PUSHTX_BIT_SHIFT_DATA = [_]struct {
    // DER signature prefix: 0x30 0x45 0x02 0x21 0x00 (5B) for sec=2
    //                       0x30 0x44 0x02 0x20     (4B) for sec=3
    // We pad to 5 bytes using 0x00 as a sentinel.
    signature_prefix: [5]u8,
    prefix_len: u8,
    R: [33]u8,
    P: [33]u8,
}{
    // security = 2 (k = 4)
    .{
        .signature_prefix = .{ 0x30, 0x45, 0x02, 0x21, 0x00 },
        .prefix_len = 5,
        .R = .{
            0x02, 0xe4, 0x93, 0xdb, 0xf1, 0xc1, 0x0d, 0x80, 0xf3, 0x58, 0x1e, 0x49, 0x04, 0x93, 0x0b, 0x14,
            0x04, 0xcc, 0x6c, 0x13, 0x90, 0x0e, 0xe0, 0x75, 0x84, 0x74, 0xfa, 0x94, 0xab, 0xe8, 0xc4, 0xcd, 0x13,
        },
        .P = .{
            0x03, 0x42, 0x18, 0x42, 0x6b, 0x38, 0xc7, 0x5b, 0x70, 0x6d, 0xb9, 0x01, 0x0a, 0xad, 0x77, 0x95,
            0xfd, 0x05, 0xb8, 0x72, 0x06, 0x09, 0x21, 0xc0, 0x48, 0xd9, 0xa6, 0x79, 0xd8, 0x87, 0x8c, 0x76, 0x60,
        },
    },
    // security = 3 (k = 8)
    .{
        .signature_prefix = .{ 0x30, 0x44, 0x02, 0x20, 0x00 },
        .prefix_len = 4,
        .R = .{
            0x02, 0x2f, 0x01, 0xe5, 0xe1, 0x5c, 0xca, 0x35, 0x1d, 0xaf, 0xf3, 0x84, 0x3f, 0xb7, 0x0f, 0x3c,
            0x2f, 0x0a, 0x1b, 0xdd, 0x05, 0xe5, 0xaf, 0x88, 0x8a, 0x67, 0x78, 0x4e, 0xf3, 0xe1, 0x0a, 0x2a, 0x01,
        },
        .P = .{
            0x03, 0xad, 0x36, 0xfa, 0xd5, 0x57, 0x27, 0xeb, 0xf7, 0x6f, 0x8a, 0xf9, 0x6c, 0x7c, 0x2d, 0xf9,
            0xa2, 0x98, 0xdc, 0x21, 0xd6, 0xc1, 0x52, 0x69, 0xfd, 0xed, 0xfd, 0x47, 0xa7, 0x0b, 0x32, 0x76, 0x37,
        },
    },
};

fn emitPushBytes(out: *std.ArrayListUnmanaged(u8), allocator: std.mem.Allocator, data: []const u8) ExpandError!void {
    if (data.len > 520) return ExpandError.Overflow;
    builder.appendPushData(out, allocator, data) catch return ExpandError.OutOfMemory;
}

fn emitPushBytesSafe(out: *std.ArrayListUnmanaged(u8), allocator: std.mem.Allocator, data: []const u8) ExpandError!void {
    // Like emitPushBytes but always uses OP_PUSHDATA1 to avoid ambiguity
    // when the data starts with a byte that could be interpreted as a
    // push opcode. The bsvz appendPushData uses the length as a direct
    // push opcode for l <= 75, which can be ambiguous if the first
    // data byte is in the range 0x01-0x4b.
    if (data.len > 0xff) return ExpandError.Overflow;
    try out.append(allocator, 0x4c); // OP_PUSHDATA1
    try out.append(allocator, @intCast(data.len));
    try out.appendSlice(allocator, data);
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
    var out: std.ArrayListUnmanaged(u8) = .empty;
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
    var out: std.ArrayListUnmanaged(u8) = .empty;
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
fn reverseEndianness32(allocator: std.mem.Allocator) ExpandError![]u8 {
    // Reverse the endianness of a 32-byte stack element.
    // Per zkscript reverse_endianness_fixed_length(32):
    //   OP_1 OP_SPLIT (×31) then OP_SWAP OP_CAT (×31)
    // Total: 93 opcodes. This is the main contributor to the ~228 bytes
    // of endianness overhead in the full PUSHTX (per Federico Barbacovi's
    // article, https://hackmd.io/@federicobarbacovi/By6zkFmfyl).
    var out: std.ArrayListUnmanaged(u8) = .empty;
    defer out.deinit(allocator);
    // OP_1 OP_SPLIT repeated 31 times: splits off the last byte 31 times,
    // leaving 31 single-byte items + 1 remaining byte on the stack.
    var i: usize = 0;
    while (i < 31) : (i += 1) {
        try emitOpcode(&out, allocator, .OP_1);
        try emitOpcode(&out, allocator, .OP_SPLIT);
    }
    // OP_SWAP OP_CAT repeated 31 times: builds the reversed string.
    i = 0;
    while (i < 31) : (i += 1) {
        try emitOpcode(&out, allocator, .OP_SWAP);
        try emitOpcode(&out, allocator, .OP_CAT);
    }
    return out.toOwnedSlice(allocator);
}

fn pushTxToderExpand(allocator: std.mem.Allocator, args: []const AstNode, body: ?[]const AstNode, table: *const MacroTable) ExpandError![]const u8 {
    _ = body;
    if (args.len != 0) return ExpandError.ArityMismatch;
    // [toDER]:= [toCanonical][concatenations]; expand inline to avoid recursive macro call.
    //
    // Bug fix (vs zkscript reference): the zkscript `int_sig_to_s_component`
    // reverses endianness of the s value after the canonical-form check.
    // Without this reversal, the DER signature has s in little-endian
    // (from OP_ADD/OP_MOD math) instead of big-endian (required by DER),
    // producing an invalid signature. We add the reversal here.
    var out: std.ArrayListUnmanaged(u8) = .empty;
    defer out.deinit(allocator);
    const canonical = try pushTxTocanonicalExpand(allocator, args, null, table);
    defer allocator.free(canonical);
    try out.appendSlice(allocator, canonical);
    const reverse = try reverseEndianness32(allocator);
    defer allocator.free(reverse);
    try out.appendSlice(allocator, reverse);
    const concats = try pushTxConcatenationsExpand(allocator, args, null, table);
    defer allocator.free(concats);
    try out.appendSlice(allocator, concats);
    return out.toOwnedSlice(allocator);
}

fn pushTxSignExpand(allocator: std.mem.Allocator, args: []const AstNode, body: ?[]const AstNode, table: *const MacroTable) ExpandError![]const u8 {
    _ = body;
    if (args.len != 1) return ExpandError.ArityMismatch;
    if (args[0] != .integer_literal) return ExpandError.TypeMismatch;
    const sighash = args[0].integer_literal;
    var out: std.ArrayListUnmanaged(u8) = .empty;
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

// Alt-stack optimized variants per WP1605 §1.4.
// White paper errata: the published sequence has [sign] pushing Gx first
// (so Gx is on top of the alt stack) and [toCanonical] then comparing s
// with Gx/2 instead of n/2. The corrected sequence pushes n first, so
// n is on top of the alt stack; [toCanonical] pops n, computes n/2, and
// replaces s with n - s when s > n/2 (matching the original semantics).

fn pushTxOutputsRequestExpand(allocator: std.mem.Allocator, args: []const AstNode, body: ?[]const AstNode, table: *const MacroTable) ExpandError![]const u8 {
    _ = body; _ = table;
    if (args.len != 2) return ExpandError.ArityMismatch;
    const item8_hex = try requireStringArg(args[0]);
    const items10_11_hex = try requireStringArg(args[1]);
    var out: std.ArrayListUnmanaged(u8) = .empty;
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

    var out: std.ArrayListUnmanaged(u8) = .empty;
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

fn pelsLockingScriptBitShiftExpand(allocator: std.mem.Allocator, args: []const AstNode, body: ?[]const AstNode, table: *const MacroTable) ExpandError![]const u8 {
    _ = body;
    if (args.len != 5) return ExpandError.ArityMismatch;
    if (args[0] != .integer_literal) return ExpandError.TypeMismatch;
    const security = args[0].integer_literal;
    if (security < 2 or security > 3) return ExpandError.TypeMismatch;
    if (args[1] != .integer_literal) return ExpandError.TypeMismatch;
    _ = try requireStringArg(args[2]);
    _ = try requireStringArg(args[3]);
    const pk_b_hash160_hex = try requireStringArg(args[4]);

    const pk_bytes = decodeHexAlloc(allocator, pk_b_hash160_hex) catch return ExpandError.TypeMismatch;
    defer allocator.free(pk_bytes);
    if (pk_bytes.len != 20) return ExpandError.TypeMismatch;

    var out: std.ArrayListUnmanaged(u8) = .empty;
    defer out.deinit(allocator);

    const orq = try pushTxOutputsRequestExpand(allocator, args[2..4], null, table);
    defer allocator.free(orq);
    try out.appendSlice(allocator, orq);

    const sign_args = [_]AstNode{ args[0], args[1] };
    const sign = try pushTxSignBitShiftExpand(allocator, &sign_args, null, table);
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

fn pushTxSignBitShiftExpand(allocator: std.mem.Allocator, args: []const AstNode, body: ?[]const AstNode, table: *const MacroTable) ExpandError![]const u8 {
    _ = body; _ = table;
    if (args.len != 2) return ExpandError.ArityMismatch;
    if (args[0] != .integer_literal) return ExpandError.TypeMismatch;
    const security = args[0].integer_literal;
    if (security < 2 or security > 3) return ExpandError.TypeMismatch;
    if (args[1] != .integer_literal) return ExpandError.TypeMismatch;
    const sighash = args[1].integer_literal;
    const idx: usize = @intCast(security - 2);
    const data = PUSHTX_BIT_SHIFT_DATA[idx];

    var out: std.ArrayListUnmanaged(u8) = .empty;
    defer out.deinit(allocator);
    // PUSHTX_BIT_SHIFT: take top of stack (the message hash digest z = HASH256(preimage)),
    // right-shift by `security` bits, then build the DER signature inline.
    //
    // Stack effect:
    //   in:  [.., data, ..]    (z on top, already double-SHA256'd by caller)
    //   out: [.., data, ..]    (signature on top, then OP_CHECKSIG consumes it)
    //
    // Expansion:
    //   push security
    //   OP_RSHIFT               -> [.., data, .., z >> security]
    //   push <prefix || R || 0x0220>
    //   OP_SWAP OP_CAT           -> [.., data, .., <prefix || R || 0x0220 || z>>security>]
    //   push <sighash_flag>      (4 bytes LE)
    //   OP_CAT                   -> [.., data, .., <DER(R,s) || sighash>]
    //   push P
    //   OP_CHECKSIG              -> [.., data, .., bool]

    emitMinimalPushInt(&out, allocator, @intCast(security)) catch return ExpandError.TypeMismatch;
    try emitOpcode(&out, allocator, .OP_RSHIFT);

    // Build the prefix || R || 0x0220 blob.
    // prefix is 5 bytes (security=2) or 4 bytes (security=3), stored as [5]u8 with 0-padding.
    const prefix_len: usize = data.prefix_len;
    const R_len: usize = data.R.len;
    const total_len: usize = prefix_len + R_len + 2; // 2 bytes for 0x0220
    var blob: [5 + 33 + 2]u8 = undefined;
    @memcpy(blob[0..prefix_len], data.signature_prefix[0..prefix_len]);
    @memcpy(blob[prefix_len..prefix_len + R_len], &data.R);
    blob[prefix_len + R_len] = 0x02;
    blob[prefix_len + R_len + 1] = 0x20;
    try emitPushBytes(&out, allocator, blob[0..total_len]);
    try emitOpcode(&out, allocator, .OP_SWAP);
    try emitOpcode(&out, allocator, .OP_CAT);
    try emitPushInt32LE(&out, allocator, sighash);
    try emitOpcode(&out, allocator, .OP_CAT);
    try emitPushBytes(&out, allocator, &data.P);
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
    try table.register("PUSHTX_SIGN_BIT_SHIFT", .{ .arity = 2, .param_types = &.{ .integer, .integer }, .expand_fn = pushTxSignBitShiftExpand });
    try table.register("PUSHTX_OUTPUTS_REQUEST", .{ .arity = 2, .param_types = &.{ .string, .string }, .expand_fn = pushTxOutputsRequestExpand });
    try table.register("PELS_LOCKING_SCRIPT", .{ .arity = 4, .param_types = &.{ .integer, .string, .string, .string }, .expand_fn = pelsLockingScriptExpand });
    try table.register("PELS_LOCKING_SCRIPT_BIT_SHIFT", .{ .arity = 5, .param_types = &.{ .integer, .integer, .string, .string, .string }, .expand_fn = pelsLockingScriptBitShiftExpand });
}