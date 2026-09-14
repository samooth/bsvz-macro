const std = @import("std");
const bsvz = @import("bsvz");
const Opcode = bsvz.script.opcode.Opcode;
const builder = bsvz.script.builder;
const AstNode = @import("parser/ast.zig").AstNode;
const ExpandError = @import("expander/error.zig").ExpandError;
const MacroTable = @import("expander/table.zig").MacroTable;
const ParamType = @import("expander/table.zig").ParamType;

// ── Helpers ─────────────────────────────────────────────────────────────

fn emitOpcode(out: *std.ArrayListUnmanaged(u8), allocator: std.mem.Allocator, op: Opcode) !void {
    try out.append(allocator, op.toByte());
}

fn emitPushData(out: *std.ArrayListUnmanaged(u8), allocator: std.mem.Allocator, data: []const u8) ExpandError!void {
    builder.appendPushData(out, allocator, data) catch return ExpandError.OutOfMemory;
}

fn emitPushHex(out: *std.ArrayListUnmanaged(u8), allocator: std.mem.Allocator, raw: []const u8) ExpandError!void {
    const hex_str = if (raw.len >= 2 and raw[0] == '0' and (raw[1] == 'x' or raw[1] == 'X')) raw[2..] else raw;
    if (hex_str.len == 0 or (hex_str.len % 2) != 0) return ExpandError.TypeMismatch;
    const decoded = try allocator.alloc(u8, hex_str.len / 2);
    defer allocator.free(decoded);
    _ = std.fmt.hexToBytes(decoded, hex_str) catch return ExpandError.TypeMismatch;
    try emitPushData(out, allocator, decoded);
}

fn emitPushHexFixed(allocator: std.mem.Allocator, out: *std.ArrayListUnmanaged(u8), raw: []const u8, expected_len: usize) ExpandError!void {
    const hex_str = if (raw.len >= 2 and raw[0] == '0' and (raw[1] == 'x' or raw[1] == 'X')) raw[2..] else raw;
    if (hex_str.len == 0 or (hex_str.len % 2) != 0) return ExpandError.TypeMismatch;
    if (hex_str.len / 2 != expected_len) return ExpandError.TypeMismatch;
    const decoded = try allocator.alloc(u8, expected_len);
    defer allocator.free(decoded);
    _ = std.fmt.hexToBytes(decoded, hex_str) catch return ExpandError.TypeMismatch;
    try emitPushData(out, allocator, decoded);
}

fn decodeHexOwned(allocator: std.mem.Allocator, raw: []const u8, expected_len: usize) ExpandError![]u8 {
    const hex_str = if (raw.len >= 2 and raw[0] == '0' and (raw[1] == 'x' or raw[1] == 'X')) raw[2..] else raw;
    if (hex_str.len == 0 or (hex_str.len % 2) != 0) return ExpandError.TypeMismatch;
    if (hex_str.len / 2 != expected_len) return ExpandError.TypeMismatch;
    const decoded = try allocator.alloc(u8, expected_len);
    _ = std.fmt.hexToBytes(decoded, hex_str) catch return ExpandError.TypeMismatch;
    return decoded;
}

fn comptimeHexLiteral(comptime hex_str: []const u8) [hex_str.len / 2]u8 {
    comptime {
        @setEvalBranchQuota(hex_str.len * 10);
        if (hex_str.len % 2 != 0) @compileError("hex literal must have even length");
        var result: [hex_str.len / 2]u8 = undefined;
        for (0..result.len) |i| {
            const hi = hexNibble(hex_str[i * 2]);
            const lo = hexNibble(hex_str[i * 2 + 1]);
            result[i] = (@as(u8, hi) << 4) | @as(u8, lo);
        }
        return result;
    }
}

fn hexNibble(comptime c: u8) u4 {
    return switch (c) {
        '0'...'9' => @intCast(c - '0'),
        'a'...'f' => @intCast(c - 'a' + 10),
        'A'...'F' => @intCast(c - 'A' + 10),
        else => @compileError("invalid hex character"),
    };
}

fn emitMinimalPushInt(out: *std.ArrayListUnmanaged(u8), allocator: std.mem.Allocator, value: i64) ExpandError!void {
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
        try emitPushData(out, allocator, buf[0..i]);
    }
}

fn writeJsonEscaped(buf: *std.ArrayListUnmanaged(u8), allocator: std.mem.Allocator, s: []const u8) ExpandError!void {
    for (s) |c| {
        switch (c) {
            '"' => try buf.appendSlice(allocator, "\\\""),
            '\\' => try buf.appendSlice(allocator, "\\\\"),
            '\n' => try buf.appendSlice(allocator, "\\n"),
            '\r' => try buf.appendSlice(allocator, "\\r"),
            '\t' => try buf.appendSlice(allocator, "\\t"),
            else => {
                if (c < 0x20) {
                    var tmp: [8]u8 = undefined;
                    const esc = std.fmt.bufPrint(&tmp, "\\u{x:0>4}", .{c}) catch return ExpandError.OutOfMemory;
                    try buf.appendSlice(allocator, esc);
                } else {
                    buf.append(allocator, c) catch return ExpandError.OutOfMemory;
                }
            },
        }
    }
}

// ── Constants ───────────────────────────────────────────────────────────

pub const MAP_PREFIX = "1PuQa7K62MiKCtssSLKy1kh56WWU7MtUR5";
pub const B_PREFIX = "19HxigV4QyBv3tHpQVcUEQyq1pzZVdoAut";
pub const AIP_PREFIX = "15PciHG22SNLQJXMoSUaWVi7WSqc7hCfva";
pub const BCAT_NAMESPACE = "15DHFxWZJT58f9nhyGnsRBqrgwK4W6h4Up";
pub const BCAT_PART_NAMESPACE = "1ChDHzdd1H4wSjgGMHyndZm6qxEDGjqpJL";
pub const SIGMA_PREFIX = "SIGMA";
pub const CONTENT_TYPE_BSV20 = "application/bsv-20";
pub const ORD_MARKER = [3]u8{ 0x6f, 0x72, 0x64 };

pub const ORDLOCK_PREFIX = comptimeHexLiteral(
    "2097dfd76851bf465e8f715593b217714858bbe9570ff3bd5e33840a34e20ff026" ++
        "2102ba79df5f8ae7604a9830f03c7933028186aede0675a16f025dc4f8be8eec0382" ++
        "201008ce7480da41702918d1ec8e6849ba32b4d65b1e40dc669c31a1e6306b266c" ++
        "0000",
);

pub const ORDLOCK_SUFFIX = comptimeHexLiteral(
    "615179547a75537a537a537a0079537a75527a527a7575615579008763567901c161" ++
        "517957795779210ac407f0e4bd44bfc207355a778b046225a7068fc59ee7eda43ad9" ++
        "05aadbffc800206c266b30e6a1319c66dc401e5bd6b432ba49688eecd118297041da" ++
        "8074ce081059795679615679aa0079610079517f517f517f517f517f517f517f517f" ++
        "517f517f517f517f517f517f517f517f517f517f517f517f517f517f517f517f517f" ++
        "517f517f517f517f517f517f7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c" ++
        "7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c" ++
        "7e7c7e7c7e7c7e7c7e01007e81517a75615779567956795679567961537956795479" ++
        "577995939521414136d08c5ed2bf3ba048afe6dcaebafeffffffffffffffffffffff" ++
        "ffffff00517951796151795179970079009f63007952799367007968517a75517a7551" ++
        "7a7561527a75517a517951795296a0630079527994527a75517a6853798277527982" ++
        "775379012080517f517f517f517f517f517f517f517f517f517f517f517f517f517f" ++
        "517f517f517f517f517f517f517f517f517f517f517f517f517f517f517f517f517f" ++
        "7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e" ++
        "7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e0120" ++
        "5279947f7754537993527993013051797e527e54797e58797e527e53797e52797e57" ++
        "797e0079517a75517a75517a75517a75517a75517a75517a75517a75517a75517a75" ++
        "517a75517a75517a756100795779ac517a75517a75517a75517a75517a75517a75517a" ++
        "75517a75517a7561517a75517a756169587951797e58797eaa577961007982775179" ++
        "517958947f7551790128947f77517a75517a75618777777777777777777767557951" ++
        "876351795779a9876957795779ac777777777777777767006868",
);

pub const OPNS_CONTRACT: *const [5892]u8 = @embedFile("opns_contract.bin");

pub const GENESIS_OUTPOINT = blk: {
    const txid_hex = "58b7558ea379f24266c7e2f5fe321992ad9a724fd7a87423ba412677179ccb25";
    var txid_le: [32]u8 = undefined;
    for (0..32) |i| {
        const hi = hexNibble(txid_hex[i * 2]);
        const lo = hexNibble(txid_hex[i * 2 + 1]);
        txid_le[31 - i] = (@as(u8, hi) << 4) | @as(u8, lo);
    }
    var result: [36]u8 = undefined;
    @memcpy(result[0..32], &txid_le);
    result[32] = 0x00;
    result[33] = 0x00;
    result[34] = 0x00;
    result[35] = 0x00;
    break :blk result;
};

// ── Inscription ─────────────────────────────────────────────────────────

fn inscriptionExpand(allocator: std.mem.Allocator, args: []const AstNode, body: ?[]const AstNode, table: *const MacroTable) ExpandError![]const u8 {
    _ = body;
    _ = table;
    if (args.len != 2) return ExpandError.ArityMismatch;
    if (args[0] != .string_literal) return ExpandError.TypeMismatch;
    if (args[1] != .string_literal) return ExpandError.TypeMismatch;
    const content = args[0].string_literal;
    const content_type = args[1].string_literal;

    var out: std.ArrayListUnmanaged(u8) = .empty;
    defer out.deinit(allocator);

    try emitOpcode(&out, allocator, Opcode.OP_0);
    try emitOpcode(&out, allocator, Opcode.OP_IF);
    try emitPushData(&out, allocator, &ORD_MARKER);
    try emitOpcode(&out, allocator, Opcode.OP_1);
    try emitPushData(&out, allocator, content_type);
    try emitOpcode(&out, allocator, Opcode.OP_0);
    try emitPushData(&out, allocator, content);
    try emitOpcode(&out, allocator, Opcode.OP_ENDIF);

    return out.toOwnedSlice(allocator);
}

fn inscriptionFullExpand(allocator: std.mem.Allocator, args: []const AstNode, body: ?[]const AstNode, table: *const MacroTable) ExpandError![]const u8 {
    _ = body;
    _ = table;
    if (args.len != 4) return ExpandError.ArityMismatch;
    for (args) |arg| {
        if (arg != .string_literal) return ExpandError.TypeMismatch;
    }

    var out: std.ArrayListUnmanaged(u8) = .empty;
    defer out.deinit(allocator);

    if (args[0].string_literal.len > 0) {
        try emitPushHex(&out, allocator, args[0].string_literal);
    }
    try emitOpcode(&out, allocator, Opcode.OP_0);
    try emitOpcode(&out, allocator, Opcode.OP_IF);
    try emitPushData(&out, allocator, &ORD_MARKER);
    try emitOpcode(&out, allocator, Opcode.OP_1);
    try emitPushData(&out, allocator, args[1].string_literal);
    try emitOpcode(&out, allocator, Opcode.OP_0);
    try emitPushData(&out, allocator, args[2].string_literal);
    try emitOpcode(&out, allocator, Opcode.OP_ENDIF);
    if (args[3].string_literal.len > 0) {
        try emitPushHex(&out, allocator, args[3].string_literal);
    }

    return out.toOwnedSlice(allocator);
}

// ── Lock (CLTV) ─────────────────────────────────────────────────────────

fn lockExpand(allocator: std.mem.Allocator, args: []const AstNode, body: ?[]const AstNode, table: *const MacroTable) ExpandError![]const u8 {
    _ = body;
    _ = table;
    if (args.len != 2) return ExpandError.ArityMismatch;
    if (args[0] != .string_literal) return ExpandError.TypeMismatch;
    if (args[1] != .integer_literal) return ExpandError.TypeMismatch;

    const pkh_hex = args[0].string_literal;
    const block_height = args[1].integer_literal;
    if (block_height < 0) return ExpandError.TypeMismatch;

    var out: std.ArrayListUnmanaged(u8) = .empty;
    defer out.deinit(allocator);

    try emitMinimalPushInt(&out, allocator, block_height);
    try emitOpcode(&out, allocator, Opcode.OP_CHECKLOCKTIMEVERIFY);
    try emitOpcode(&out, allocator, Opcode.OP_DROP);
    try emitOpcode(&out, allocator, Opcode.OP_DUP);
    try emitOpcode(&out, allocator, Opcode.OP_HASH160);
    try emitPushHexFixed(allocator, &out, pkh_hex, 20);
    try emitOpcode(&out, allocator, Opcode.OP_EQUALVERIFY);
    try emitOpcode(&out, allocator, Opcode.OP_CHECKSIG);

    return out.toOwnedSlice(allocator);
}

// ── BSV-21 ──────────────────────────────────────────────────────────────

fn bsv21DeployExpand(allocator: std.mem.Allocator, args: []const AstNode, body: ?[]const AstNode, table: *const MacroTable) ExpandError![]const u8 {
    _ = body;
    _ = table;
    if (args.len != 3) return ExpandError.ArityMismatch;
    if (args[0] != .string_literal) return ExpandError.TypeMismatch;
    if (args[1] != .integer_literal) return ExpandError.TypeMismatch;
    if (args[2] != .integer_literal) return ExpandError.TypeMismatch;

    const symbol = args[0].string_literal;
    if (symbol.len == 0 or symbol.len > 32) return ExpandError.TypeMismatch;
    const decimals = args[1].integer_literal;
    if (decimals < 0 or decimals > 18) return ExpandError.TypeMismatch;
    const max_supply = args[2].integer_literal;
    if (max_supply <= 0) return ExpandError.TypeMismatch;

    var out: std.ArrayListUnmanaged(u8) = .empty;
    defer out.deinit(allocator);

    try emitOpcode(&out, allocator, Opcode.OP_0);
    try emitOpcode(&out, allocator, Opcode.OP_IF);
    try emitPushData(&out, allocator, &ORD_MARKER);
    try emitOpcode(&out, allocator, Opcode.OP_1);

    var json_buf: std.ArrayListUnmanaged(u8) = .empty;
    defer json_buf.deinit(allocator);

    try json_buf.appendSlice(allocator, "{\"p\":\"bsv-20\",\"op\":\"deploy+mint\",\"sym\":\"");
    try writeJsonEscaped(&json_buf, allocator, symbol);
    try json_buf.appendSlice(allocator, "\",\"amt\":\"");
    var amt_buf: [32]u8 = undefined;
    const amt_str = std.fmt.bufPrint(&amt_buf, "{d}", .{max_supply}) catch return ExpandError.OutOfMemory;
    try json_buf.appendSlice(allocator, amt_str);
    try json_buf.append(allocator, '"');
    if (decimals > 0) {
        var dec_buf: [8]u8 = undefined;
        const dec_str = std.fmt.bufPrint(&dec_buf, "{d}", .{decimals}) catch return ExpandError.OutOfMemory;
        try json_buf.appendSlice(allocator, ",\"dec\":\"");
        try json_buf.appendSlice(allocator, dec_str);
        try json_buf.append(allocator, '"');
    }
    try json_buf.append(allocator, '}');

    try emitPushData(&out, allocator, json_buf.items);
    try emitOpcode(&out, allocator, Opcode.OP_ENDIF);

    return out.toOwnedSlice(allocator);
}

fn bsv21TransferExpand(allocator: std.mem.Allocator, args: []const AstNode, body: ?[]const AstNode, table: *const MacroTable) ExpandError![]const u8 {
    _ = body;
    _ = table;
    if (args.len != 2) return ExpandError.ArityMismatch;
    if (args[0] != .string_literal) return ExpandError.TypeMismatch;
    if (args[1] != .integer_literal) return ExpandError.TypeMismatch;

    const token_id = args[0].string_literal;
    if (token_id.len == 0) return ExpandError.TypeMismatch;
    const amount = args[1].integer_literal;
    if (amount <= 0) return ExpandError.TypeMismatch;

    return emitBsv21Json(allocator, "transfer", token_id, amount);
}

fn bsv21BurnExpand(allocator: std.mem.Allocator, args: []const AstNode, body: ?[]const AstNode, table: *const MacroTable) ExpandError![]const u8 {
    _ = body;
    _ = table;
    if (args.len != 2) return ExpandError.ArityMismatch;
    if (args[0] != .string_literal) return ExpandError.TypeMismatch;
    if (args[1] != .integer_literal) return ExpandError.TypeMismatch;

    const token_id = args[0].string_literal;
    if (token_id.len == 0) return ExpandError.TypeMismatch;
    const amount = args[1].integer_literal;
    if (amount <= 0) return ExpandError.TypeMismatch;

    return emitBsv21Json(allocator, "burn", token_id, amount);
}

fn emitBsv21Json(allocator: std.mem.Allocator, op: []const u8, token_id: []const u8, amount: i64) ExpandError![]const u8 {
    var out: std.ArrayListUnmanaged(u8) = .empty;
    defer out.deinit(allocator);

    try emitOpcode(&out, allocator, Opcode.OP_0);
    try emitOpcode(&out, allocator, Opcode.OP_IF);
    try emitPushData(&out, allocator, &ORD_MARKER);
    try emitOpcode(&out, allocator, Opcode.OP_1);

    var json_buf: std.ArrayListUnmanaged(u8) = .empty;
    defer json_buf.deinit(allocator);

    try json_buf.appendSlice(allocator, "{\"p\":\"bsv-20\",\"op\":\"");
    try json_buf.appendSlice(allocator, op);
    try json_buf.appendSlice(allocator, "\",\"id\":\"");
    try writeJsonEscaped(&json_buf, allocator, token_id);
    try json_buf.appendSlice(allocator, "\",\"amt\":\"");
    var amt_buf: [32]u8 = undefined;
    const amt_str = std.fmt.bufPrint(&amt_buf, "{d}", .{amount}) catch return ExpandError.OutOfMemory;
    try json_buf.appendSlice(allocator, amt_str);
    try json_buf.append(allocator, '}');

    try emitPushData(&out, allocator, json_buf.items);
    try emitOpcode(&out, allocator, Opcode.OP_ENDIF);

    return out.toOwnedSlice(allocator);
}

// ── BSV-20 ───────────────────────────────────────────────────────────────

fn bsv20DeployExpand(allocator: std.mem.Allocator, args: []const AstNode, body: ?[]const AstNode, table: *const MacroTable) ExpandError![]const u8 {
    _ = body;
    _ = table;
    if (args.len != 4) return ExpandError.ArityMismatch;
    if (args[0] != .string_literal) return ExpandError.TypeMismatch;
    if (args[1] != .integer_literal) return ExpandError.TypeMismatch;
    if (args[2] != .integer_literal) return ExpandError.TypeMismatch;
    if (args[3] != .integer_literal) return ExpandError.TypeMismatch;

    const tick = args[0].string_literal;
    if (tick.len == 0) return ExpandError.TypeMismatch;
    const max_supply = args[1].integer_literal;
    if (max_supply <= 0) return ExpandError.TypeMismatch;
    const decimals = args[2].integer_literal;
    if (decimals < 0 or decimals > 18) return ExpandError.TypeMismatch;
    const mint_limit = args[3].integer_literal;
    if (mint_limit < 0) return ExpandError.TypeMismatch;

    var out: std.ArrayListUnmanaged(u8) = .empty;
    defer out.deinit(allocator);

    try emitOpcode(&out, allocator, Opcode.OP_0);
    try emitOpcode(&out, allocator, Opcode.OP_IF);
    try emitPushData(&out, allocator, &ORD_MARKER);
    try emitOpcode(&out, allocator, Opcode.OP_1);

    var json_buf: std.ArrayListUnmanaged(u8) = .empty;
    defer json_buf.deinit(allocator);

    try json_buf.appendSlice(allocator, "{\"p\":\"bsv-20\",\"op\":\"deploy\",\"tick\":\"");
    try writeJsonEscaped(&json_buf, allocator, tick);
    try json_buf.appendSlice(allocator, "\",\"max\":\"");
    var amt_buf: [32]u8 = undefined;
    const amt_str = std.fmt.bufPrint(&amt_buf, "{d}", .{max_supply}) catch return ExpandError.OutOfMemory;
    try json_buf.appendSlice(allocator, amt_str);
    try json_buf.appendSlice(allocator, "\",\"lim\":\"");
    const lim_str = std.fmt.bufPrint(&amt_buf, "{d}", .{mint_limit}) catch return ExpandError.OutOfMemory;
    try json_buf.appendSlice(allocator, lim_str);
    if (decimals > 0) {
        try json_buf.appendSlice(allocator, "\",\"dec\":\"");
        var dec_buf: [8]u8 = undefined;
        const dec_str = std.fmt.bufPrint(&dec_buf, "{d}", .{decimals}) catch return ExpandError.OutOfMemory;
        try json_buf.appendSlice(allocator, dec_str);
    }
    try json_buf.appendSlice(allocator, "\"}");

    try emitPushData(&out, allocator, json_buf.items);
    try emitOpcode(&out, allocator, Opcode.OP_ENDIF);

    return out.toOwnedSlice(allocator);
}

fn bsv20MintExpand(allocator: std.mem.Allocator, args: []const AstNode, body: ?[]const AstNode, table: *const MacroTable) ExpandError![]const u8 {
    _ = body;
    _ = table;
    if (args.len != 2) return ExpandError.ArityMismatch;
    if (args[0] != .string_literal) return ExpandError.TypeMismatch;
    if (args[1] != .integer_literal) return ExpandError.TypeMismatch;

    const tick = args[0].string_literal;
    if (tick.len == 0) return ExpandError.TypeMismatch;
    const amount = args[1].integer_literal;
    if (amount <= 0) return ExpandError.TypeMismatch;

    return emitBsv20Json(allocator, "mint", tick, amount);
}

fn bsv20TransferExpand(allocator: std.mem.Allocator, args: []const AstNode, body: ?[]const AstNode, table: *const MacroTable) ExpandError![]const u8 {
    _ = body;
    _ = table;
    if (args.len != 2) return ExpandError.ArityMismatch;
    if (args[0] != .string_literal) return ExpandError.TypeMismatch;
    if (args[1] != .integer_literal) return ExpandError.TypeMismatch;

    const tick = args[0].string_literal;
    if (tick.len == 0) return ExpandError.TypeMismatch;
    const amount = args[1].integer_literal;
    if (amount <= 0) return ExpandError.TypeMismatch;

    return emitBsv20Json(allocator, "transfer", tick, amount);
}

fn emitBsv20Json(allocator: std.mem.Allocator, op: []const u8, tick: []const u8, amount: i64) ExpandError![]const u8 {
    var out: std.ArrayListUnmanaged(u8) = .empty;
    defer out.deinit(allocator);

    try emitOpcode(&out, allocator, Opcode.OP_0);
    try emitOpcode(&out, allocator, Opcode.OP_IF);
    try emitPushData(&out, allocator, &ORD_MARKER);
    try emitOpcode(&out, allocator, Opcode.OP_1);

    var json_buf: std.ArrayListUnmanaged(u8) = .empty;
    defer json_buf.deinit(allocator);

    try json_buf.appendSlice(allocator, "{\"p\":\"bsv-20\",\"op\":\"");
    try json_buf.appendSlice(allocator, op);
    try json_buf.appendSlice(allocator, "\",\"tick\":\"");
    try writeJsonEscaped(&json_buf, allocator, tick);
    try json_buf.appendSlice(allocator, "\",\"amt\":\"");
    var amt_buf: [32]u8 = undefined;
    const amt_str = std.fmt.bufPrint(&amt_buf, "{d}", .{amount}) catch return ExpandError.OutOfMemory;
    try json_buf.appendSlice(allocator, amt_str);
    try json_buf.append(allocator, '"');
    try json_buf.append(allocator, '}');

    try emitPushData(&out, allocator, json_buf.items);
    try emitOpcode(&out, allocator, Opcode.OP_ENDIF);

    return out.toOwnedSlice(allocator);
}

// ── MAP ─────────────────────────────────────────────────────────────────

fn mapSetExpand(allocator: std.mem.Allocator, args: []const AstNode, body: ?[]const AstNode, table: *const MacroTable) ExpandError![]const u8 {
    _ = body;
    _ = table;
    if (args.len != 2) return ExpandError.ArityMismatch;
    if (args[0] != .string_literal) return ExpandError.TypeMismatch;
    if (args[1] != .string_literal) return ExpandError.TypeMismatch;

    var out: std.ArrayListUnmanaged(u8) = .empty;
    defer out.deinit(allocator);

    try emitOpcode(&out, allocator, Opcode.OP_RETURN);
    try emitPushData(&out, allocator, MAP_PREFIX);
    try emitPushData(&out, allocator, "SET");
    try emitPushData(&out, allocator, args[0].string_literal);
    try emitPushData(&out, allocator, args[1].string_literal);

    return out.toOwnedSlice(allocator);
}

fn mapDelExpand(allocator: std.mem.Allocator, args: []const AstNode, body: ?[]const AstNode, table: *const MacroTable) ExpandError![]const u8 {
    _ = body;
    _ = table;
    if (args.len != 1) return ExpandError.ArityMismatch;
    if (args[0] != .string_literal) return ExpandError.TypeMismatch;

    var out: std.ArrayListUnmanaged(u8) = .empty;
    defer out.deinit(allocator);

    try emitOpcode(&out, allocator, Opcode.OP_RETURN);
    try emitPushData(&out, allocator, MAP_PREFIX);
    try emitPushData(&out, allocator, "DEL");
    try emitPushData(&out, allocator, args[0].string_literal);

    return out.toOwnedSlice(allocator);
}

// ── OrdLock ─────────────────────────────────────────────────────────────

fn ordlockExpand(allocator: std.mem.Allocator, args: []const AstNode, body: ?[]const AstNode, table: *const MacroTable) ExpandError![]const u8 {
    _ = body;
    _ = table;
    if (args.len != 3) return ExpandError.ArityMismatch;
    if (args[0] != .string_literal) return ExpandError.TypeMismatch;
    if (args[1] != .string_literal) return ExpandError.TypeMismatch;
    if (args[2] != .integer_literal) return ExpandError.TypeMismatch;

    const seller_pkh = try decodeHexOwned(allocator, args[0].string_literal, 20);
    defer allocator.free(seller_pkh);
    const pay_pkh = try decodeHexOwned(allocator, args[1].string_literal, 20);
    defer allocator.free(pay_pkh);
    const price_sats = args[2].integer_literal;
    if (price_sats < 0) return ExpandError.TypeMismatch;

    var out: std.ArrayListUnmanaged(u8) = .empty;
    defer out.deinit(allocator);

    try out.appendSlice(allocator, &ORDLOCK_PREFIX);
    try emitPushData(&out, allocator, seller_pkh);

    var payout: [34]u8 = undefined;
    std.mem.writeInt(i64, payout[0..8], @bitCast(@as(u64, @intCast(price_sats))), .little);
    payout[8] = 25;
    payout[9] = 0x76;
    payout[10] = 0xa9;
    payout[11] = 0x14;
    @memcpy(payout[12..32], pay_pkh);
    payout[32] = 0x88;
    payout[33] = 0xac;
    try emitPushData(&out, allocator, &payout);

    try out.appendSlice(allocator, &ORDLOCK_SUFFIX);

    return out.toOwnedSlice(allocator);
}

// ── B protocol ──────────────────────────────────────────────────────────

fn bEncodeExpand(allocator: std.mem.Allocator, args: []const AstNode, body: ?[]const AstNode, table: *const MacroTable) ExpandError![]const u8 {
    _ = body;
    _ = table;
    if (args.len != 4) return ExpandError.ArityMismatch;
    if (args[0] != .string_literal) return ExpandError.TypeMismatch;
    if (args[1] != .string_literal) return ExpandError.TypeMismatch;
    if (args[2] != .string_literal) return ExpandError.TypeMismatch;
    if (args[3] != .string_literal) return ExpandError.TypeMismatch;

    const raw_content = args[0].string_literal;
    const content_hex = if (raw_content.len >= 2 and raw_content[0] == '0' and (raw_content[1] == 'x' or raw_content[1] == 'X')) raw_content[2..] else raw_content;
    const content = try decodeHexOwned(allocator, raw_content, content_hex.len / 2);
    defer allocator.free(content);
    const content_type = args[1].string_literal;
    const encoding = args[2].string_literal;
    const filename = args[3].string_literal;

    var out: std.ArrayListUnmanaged(u8) = .empty;
    defer out.deinit(allocator);

    try emitOpcode(&out, allocator, Opcode.OP_RETURN);
    try emitPushData(&out, allocator, B_PREFIX);
    try emitPushData(&out, allocator, content);
    try emitPushData(&out, allocator, content_type);
    try emitPushData(&out, allocator, encoding);
    if (filename.len > 0) {
        try emitPushData(&out, allocator, filename);
    }

    return out.toOwnedSlice(allocator);
}

// ── OpNS ────────────────────────────────────────────────────────────────

fn opnsLockExpand(allocator: std.mem.Allocator, args: []const AstNode, body: ?[]const AstNode, table: *const MacroTable) ExpandError![]const u8 {
    _ = body;
    _ = table;
    if (args.len != 3) return ExpandError.ArityMismatch;
    if (args[0] != .string_literal) return ExpandError.TypeMismatch;
    if (args[1] != .string_literal) return ExpandError.TypeMismatch;
    if (args[2] != .string_literal) return ExpandError.TypeMismatch;

    const claimed = args[0].string_literal;
    const domain = args[1].string_literal;
    const pow = args[2].string_literal;

    const claimed_hex = if (claimed.len >= 2 and claimed[0] == '0' and (claimed[1] == 'x' or claimed[1] == 'X')) claimed[2..] else claimed;
    const claimed_bytes = try decodeHexOwned(allocator, claimed, claimed_hex.len / 2);
    defer allocator.free(claimed_bytes);
    const pow_hex = if (pow.len >= 2 and pow[0] == '0' and (pow[1] == 'x' or pow[1] == 'X')) pow[2..] else pow;
    const pow_bytes = try decodeHexOwned(allocator, pow, pow_hex.len / 2);
    defer allocator.free(pow_bytes);

    var out: std.ArrayListUnmanaged(u8) = .empty;
    defer out.deinit(allocator);

    try out.appendSlice(allocator, OPNS_CONTRACT);

    try emitOpcode(&out, allocator, Opcode.OP_RETURN);
    try emitOpcode(&out, allocator, Opcode.OP_0);
    try emitPushData(&out, allocator, &GENESIS_OUTPOINT);
    try emitPushData(&out, allocator, claimed_bytes);
    try emitPushData(&out, allocator, domain);
    try emitPushData(&out, allocator, pow_bytes);

    const state_len: u32 = @intCast(out.items.len - 2 - 1);
    const size_bytes = std.mem.toBytes(std.mem.nativeToLittle(u32, state_len));
    try out.appendSlice(allocator, &size_bytes);
    try out.append(allocator, 0x00);

    return out.toOwnedSlice(allocator);
}

fn opnsInscribeExpand(allocator: std.mem.Allocator, args: []const AstNode, body: ?[]const AstNode, table: *const MacroTable) ExpandError![]const u8 {
    _ = body;
    _ = table;
    if (args.len != 2) return ExpandError.ArityMismatch;
    if (args[0] != .string_literal) return ExpandError.TypeMismatch;
    if (args[1] != .string_literal) return ExpandError.TypeMismatch;

    const name = args[0].string_literal;
    if (name.len == 0) return ExpandError.TypeMismatch;
    const owner_hex = args[1].string_literal;
    const owner_hex_no_prefix = if (owner_hex.len >= 2 and owner_hex[0] == '0' and (owner_hex[1] == 'x' or owner_hex[1] == 'X')) owner_hex[2..] else owner_hex;
    const expected_owner_len = owner_hex_no_prefix.len / 2;
    const owner_script = try decodeHexOwned(allocator, owner_hex, expected_owner_len);
    defer allocator.free(owner_script);

    var out: std.ArrayListUnmanaged(u8) = .empty;
    defer out.deinit(allocator);

    try emitPushData(&out, allocator, owner_script);
    try emitOpcode(&out, allocator, Opcode.OP_0);
    try emitOpcode(&out, allocator, Opcode.OP_IF);
    try emitPushData(&out, allocator, "ord");
    try emitOpcode(&out, allocator, Opcode.OP_1);
    try emitPushData(&out, allocator, "application/op-ns");
    try emitOpcode(&out, allocator, Opcode.OP_0);
    try emitPushData(&out, allocator, name);
    try emitOpcode(&out, allocator, Opcode.OP_ENDIF);
    try emitOpcode(&out, allocator, Opcode.OP_RETURN);
    try emitPushData(&out, allocator, "1opNSUJVbBc2Vf8LFNSoywGGK4jMcGVrC");
    try emitPushData(&out, allocator, &GENESIS_OUTPOINT);

    return out.toOwnedSlice(allocator);
}

fn bcatHeaderExpand(allocator: std.mem.Allocator, args: []const AstNode, body: ?[]const AstNode, table: *const MacroTable) ExpandError![]const u8 {
    _ = body;
    _ = table;
    if (args.len != 6) return ExpandError.ArityMismatch;
    for (args) |arg| {
        if (arg != .string_literal) return ExpandError.TypeMismatch;
    }

    const info = args[0].string_literal;
    if (info.len > 128) return ExpandError.TypeMismatch;
    const mime = args[1].string_literal;
    if (mime.len > 128) return ExpandError.TypeMismatch;
    const charset = args[2].string_literal;
    if (charset.len > 16) return ExpandError.TypeMismatch;
    const filename = args[3].string_literal;
    if (filename.len > 256) return ExpandError.TypeMismatch;
    const flag = args[4].string_literal;
    if (flag.len > 16) return ExpandError.TypeMismatch;
    const txids_hex = args[5].string_literal;

    const txids_hex_no_prefix = if (txids_hex.len >= 2 and txids_hex[0] == '0' and (txids_hex[1] == 'x' or txids_hex[1] == 'X')) txids_hex[2..] else txids_hex;
    if (txids_hex_no_prefix.len == 0 or (txids_hex_no_prefix.len % 64) != 0) return ExpandError.TypeMismatch;

    var out: std.ArrayListUnmanaged(u8) = .empty;
    defer out.deinit(allocator);

    try emitOpcode(&out, allocator, Opcode.OP_RETURN);
    try emitPushData(&out, allocator, BCAT_NAMESPACE);
    try emitPushData(&out, allocator, info);
    try emitPushData(&out, allocator, mime);
    try emitPushData(&out, allocator, charset);
    try emitPushData(&out, allocator, filename);
    try emitPushData(&out, allocator, flag);

    const txid_bytes = try decodeHexOwned(allocator, txids_hex, txids_hex_no_prefix.len / 2);
    defer allocator.free(txid_bytes);

    var i: usize = 0;
    while (i < txid_bytes.len) : (i += 32) {
        try emitPushData(&out, allocator, txid_bytes[i..i+32]);
    }

    return out.toOwnedSlice(allocator);
}

fn bcatPartExpand(allocator: std.mem.Allocator, args: []const AstNode, body: ?[]const AstNode, table: *const MacroTable) ExpandError![]const u8 {
    _ = body;
    _ = table;
    if (args.len != 1) return ExpandError.ArityMismatch;
    if (args[0] != .string_literal) return ExpandError.TypeMismatch;

    const data_hex = args[0].string_literal;
    const data_hex_no_prefix = if (data_hex.len >= 2 and data_hex[0] == '0' and (data_hex[1] == 'x' or data_hex[1] == 'X')) data_hex[2..] else data_hex;
    if (data_hex_no_prefix.len == 0 or (data_hex_no_prefix.len % 2) != 0) return ExpandError.TypeMismatch;

    const data = try decodeHexOwned(allocator, data_hex, data_hex_no_prefix.len / 2);
    defer allocator.free(data);

    var out: std.ArrayListUnmanaged(u8) = .empty;
    defer out.deinit(allocator);

    try emitOpcode(&out, allocator, Opcode.OP_RETURN);
    try emitPushData(&out, allocator, BCAT_PART_NAMESPACE);
    try emitPushData(&out, allocator, data);

    return out.toOwnedSlice(allocator);
}

fn sigilNftExpand(allocator: std.mem.Allocator, args: []const AstNode, body: ?[]const AstNode, table: *const MacroTable) ExpandError![]const u8 {
    _ = body;
    _ = table;
    if (args.len != 3) return ExpandError.ArityMismatch;
    if (args[0] != .string_literal) return ExpandError.TypeMismatch;
    if (args[1] != .string_literal) return ExpandError.TypeMismatch;
    if (args[2] != .string_literal) return ExpandError.TypeMismatch;

    const project_hash_hex = args[0].string_literal;
    const project_hash = try decodeHexOwned(allocator, project_hash_hex, 20);
    defer allocator.free(project_hash);

    const p2pkh_hash_hex = args[1].string_literal;
    const p2pkh_hash = try decodeHexOwned(allocator, p2pkh_hash_hex, 20);
    defer allocator.free(p2pkh_hash);

    const metadata = args[2].string_literal;

    var out: std.ArrayListUnmanaged(u8) = .empty;
    defer out.deinit(allocator);

    try emitOpcode(&out, allocator, Opcode.OP_HASH160);
    try emitPushData(&out, allocator, project_hash);
    try emitOpcode(&out, allocator, Opcode.OP_EQUALVERIFY);
    try emitOpcode(&out, allocator, Opcode.OP_DUP);
    try emitOpcode(&out, allocator, Opcode.OP_HASH160);
    try emitPushData(&out, allocator, p2pkh_hash);
    try emitOpcode(&out, allocator, Opcode.OP_EQUALVERIFY);
    try emitOpcode(&out, allocator, Opcode.OP_CHECKSIG);
    try emitOpcode(&out, allocator, Opcode.OP_RETURN);
    try emitPushData(&out, allocator, metadata);

    return out.toOwnedSlice(allocator);
}

// ── AIP ─────────────────────────────────────────────────────────────────

fn aipEncodeExpand(allocator: std.mem.Allocator, args: []const AstNode, body: ?[]const AstNode, table: *const MacroTable) ExpandError![]const u8 {
    _ = body;
    _ = table;
    if (args.len < 3) return ExpandError.ArityMismatch;

    var out: std.ArrayListUnmanaged(u8) = .empty;
    defer out.deinit(allocator);

    try emitPushData(&out, allocator, AIP_PREFIX);

    for (args) |arg| {
        if (arg != .string_literal) return ExpandError.TypeMismatch;
        try emitPushData(&out, allocator, arg.string_literal);
    }

    return out.toOwnedSlice(allocator);
}

// ── SIGMA ───────────────────────────────────────────────────────────────

fn sigmaEncodeExpand(allocator: std.mem.Allocator, args: []const AstNode, body: ?[]const AstNode, table: *const MacroTable) ExpandError![]const u8 {
    _ = body;
    _ = table;
    if (args.len < 4) return ExpandError.ArityMismatch;

    var out: std.ArrayListUnmanaged(u8) = .empty;
    defer out.deinit(allocator);

    try emitPushData(&out, allocator, SIGMA_PREFIX);

    for (args) |arg| {
        switch (arg) {
            .string_literal => |s| try emitPushData(&out, allocator, s),
            .integer_literal => |v| {
                var buf: [12]u8 = undefined;
                const str = std.fmt.bufPrint(&buf, "{d}", .{v}) catch unreachable;
                try emitPushData(&out, allocator, str);
            },
            else => return ExpandError.TypeMismatch,
        }
    }

    return out.toOwnedSlice(allocator);
}

// ── Registration ────────────────────────────────────────────────────────

pub fn registerTemplateMacros(table: *MacroTable) !void {
    try table.register("INSCRIPTION", .{
        .arity = 2,
        .param_types = &.{ .string, .string },
        .expand_fn = inscriptionExpand,
    });
    try table.register("INSCRIPTION_FULL", .{
        .arity = 4,
        .param_types = &.{ .string, .string, .string, .string },
        .expand_fn = inscriptionFullExpand,
    });
    try table.register("LOCK", .{
        .arity = 2,
        .param_types = &.{ .string, .integer },
        .expand_fn = lockExpand,
    });
    try table.register("BSV21_DEPLOY", .{
        .arity = 3,
        .param_types = &.{ .string, .integer, .integer },
        .expand_fn = bsv21DeployExpand,
    });
    try table.register("BSV21_TRANSFER", .{
        .arity = 2,
        .param_types = &.{ .string, .integer },
        .expand_fn = bsv21TransferExpand,
    });
    try table.register("BSV21_BURN", .{
        .arity = 2,
        .param_types = &.{ .string, .integer },
        .expand_fn = bsv21BurnExpand,
    });
    try table.register("BSV20_DEPLOY", .{
        .arity = 4,
        .param_types = &.{ .string, .integer, .integer, .integer },
        .expand_fn = bsv20DeployExpand,
    });
    try table.register("BSV20_MINT", .{
        .arity = 2,
        .param_types = &.{ .string, .integer },
        .expand_fn = bsv20MintExpand,
    });
    try table.register("BSV20_TRANSFER", .{
        .arity = 2,
        .param_types = &.{ .string, .integer },
        .expand_fn = bsv20TransferExpand,
    });
    try table.register("MAP_SET", .{
        .arity = 2,
        .param_types = &.{ .string, .string },
        .expand_fn = mapSetExpand,
    });
    try table.register("MAP_DEL", .{
        .arity = 1,
        .param_types = &.{.string},
        .expand_fn = mapDelExpand,
    });
    try table.register("ORDLOCK", .{
        .arity = 3,
        .param_types = &.{ .string, .string, .integer },
        .expand_fn = ordlockExpand,
    });
    try table.register("B_ENCODE", .{
        .arity = 4,
        .param_types = &.{ .string, .string, .string, .string },
        .expand_fn = bEncodeExpand,
    });
    try table.register("OPNS_LOCK", .{
        .arity = 3,
        .param_types = &.{ .string, .string, .string },
        .expand_fn = opnsLockExpand,
    });
    try table.register("OPNS_INSCRIBE", .{
        .arity = 2,
        .param_types = &.{ .string, .string },
        .expand_fn = opnsInscribeExpand,
    });
    try table.register("BCAT_HEADER", .{
        .arity = 6,
        .param_types = &.{ .string, .string, .string, .string, .string, .string },
        .expand_fn = bcatHeaderExpand,
    });
    try table.register("BCAT_PART", .{
        .arity = 1,
        .param_types = &.{.string},
        .expand_fn = bcatPartExpand,
    });
    try table.register("SIGIL_NFT", .{
        .arity = 3,
        .param_types = &.{ .string, .string, .string },
        .expand_fn = sigilNftExpand,
    });
    try table.register("AIP_ENCODE", .{
        .arity = 3,
        .param_types = &.{ .string, .string, .string },
        .expand_fn = aipEncodeExpand,
    });
    try table.register("SIGMA_ENCODE", .{
        .arity = 4,
        .param_types = &.{ .string, .string, .string, .integer },
        .expand_fn = sigmaEncodeExpand,
    });
}
