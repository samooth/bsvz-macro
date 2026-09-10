// Port of the b017 BOLT token contract templates (SimpleMultiBOLT fungible,
// MinSimpleBOLT identity NFT, pay2Proof) as canonical macros. Every suffix
// byte array is golden-tested against the sha256 fingerprints published in the
// b017 REGISTRY, and the composed locks are checked against the exact byte
// layouts the b017 templates produce (leading data pushes + static suffix).

const std = @import("std");
const testing = std.testing;
const bsvz_macro = @import("bsvz-macro");
const bsvz = @import("bsvz");
const bolt = bsvz_macro.bolt;

const golden_smb_lock_len: u32 = 5103;
const golden_smb_unlock_len: u32 = 414;
const golden_ms_lock_len: u32 = 1113;
const golden_ms_unlock_len: u32 = 414;

test "bolt port: suffix macros emit exactly the golden suffix bytes" {
    const allocator = testing.allocator;

    const smb_lock = try bsvz_macro.compile(allocator, "BOLT_SMB_LOCK_SUFFIX", .{});
    defer smb_lock.deinit(allocator);
    try testing.expectEqual(golden_smb_lock_len, smb_lock.byte_length);
    try testing.expectEqualSlices(u8, &bolt.smb_lock_suffix, smb_lock.bytecode);

    const smb_unlock = try bsvz_macro.compile(allocator, "BOLT_SMB_UNLOCK_SUFFIX", .{});
    defer smb_unlock.deinit(allocator);
    try testing.expectEqual(golden_smb_unlock_len, smb_unlock.byte_length);
    try testing.expectEqualSlices(u8, &bolt.smb_unlock_suffix, smb_unlock.bytecode);

    const ms_lock = try bsvz_macro.compile(allocator, "BOLT_MS_LOCK_SUFFIX", .{});
    defer ms_lock.deinit(allocator);
    try testing.expectEqual(golden_ms_lock_len, ms_lock.byte_length);
    try testing.expectEqualSlices(u8, &bolt.ms_lock_suffix, ms_lock.bytecode);
}

test "bolt port: suffix macros are deterministic" {
    const allocator = testing.allocator;
    const a = try bsvz_macro.compile(allocator, "BOLT_SMB_LOCK_SUFFIX", .{});
    defer a.deinit(allocator);
    const b = try bsvz_macro.compile(allocator, "BOLT_SMB_LOCK_SUFFIX", .{});
    defer b.deinit(allocator);
    try testing.expectEqualSlices(u8, a.bytecode, b.bytecode);
}

const zeros16 = "0x" ++ "00" ** 16;
const zeros20 = "0x" ++ "00" ** 20;
const zeros36 = "0x" ++ "00" ** 36;
const issuer33 = "0x02" ++ "11" ** 32;

test "bolt port: BOLT_SMB_LOCK with genesis args ends in the golden suffix" {
    const allocator = testing.allocator;
    const src = "BOLT_SMB_LOCK[" ++ zeros16 ++ ", " ++ zeros16 ++ ", " ++ zeros20 ++ ", " ++
        zeros20 ++ ", " ++ zeros20 ++ ", " ++ zeros36 ++ ", 0x20, 0x00, " ++ zeros36 ++ ", " ++
        zeros36 ++ ", " ++ issuer33 ++ "]";
    const result = try bsvz_macro.compile(allocator, src, .{});
    defer result.deinit(allocator);

    // 11 pushes, each with a 1-byte length prefix (all fields <= 75 bytes)
    const expected_push_bytes = 16 + 16 + 20 + 20 + 20 + 36 + 1 + 1 + 36 + 36 + 33 + 11;
    try testing.expectEqual(@as(u32, expected_push_bytes), result.byte_length - golden_smb_lock_len);
    try testing.expectEqualSlices(u8, &bolt.smb_lock_suffix, result.bytecode[expected_push_bytes..]);
}

test "bolt port: BOLT_MS_LOCK with genesis args ends in the golden suffix" {
    const allocator = testing.allocator;
    const src = "BOLT_MS_LOCK[" ++ zeros20 ++ ", " ++ issuer33 ++ ", " ++ zeros20 ++
        ", 0x00, " ++ zeros36 ++ ", " ++ zeros36 ++ "]";
    const result = try bsvz_macro.compile(allocator, src, .{});
    defer result.deinit(allocator);

    // 6 pushes, each with a 1-byte length prefix
    const expected_push_bytes = 20 + 33 + 20 + 1 + 36 + 36 + 6;
    try testing.expectEqual(@as(u32, expected_push_bytes), result.byte_length - golden_ms_lock_len);
    try testing.expectEqualSlices(u8, &bolt.ms_lock_suffix, result.bytecode[expected_push_bytes..]);
}

test "bolt port: BOLT_SMB_LOCK field pushes match the b017 data layout" {
    const allocator = testing.allocator;
    const balance = "0xfeffffffffff1f00" ++ "00" ** 8;
    const txo_type = "0x21";
    const src = "BOLT_SMB_LOCK[" ++ balance ++ ", " ++ zeros16 ++ ", " ++ zeros20 ++ ", " ++
        zeros20 ++ ", " ++ zeros20 ++ ", " ++ zeros36 ++ ", " ++ txo_type ++ ", 0x00, " ++
        zeros36 ++ ", " ++ zeros36 ++ ", " ++ issuer33 ++ "]";
    const result = try bsvz_macro.compile(allocator, src, .{});
    defer result.deinit(allocator);

    // balance field: 1-byte length prefix (16) + 16 LE bytes, then balanceCommit prefix
    try testing.expectEqual(@as(u8, 16), result.bytecode[0]);
    try testing.expectEqual(@as(u8, 0xfe), result.bytecode[1]);
    try testing.expectEqual(@as(u8, 16), result.bytecode[17]);
    // txoType push sits right after the first 6 pushes (with their length prefixes)
    const pushes_end = (1 + 16) + (1 + 16) + (1 + 20) + (1 + 20) + (1 + 20) + (1 + 36);
    try testing.expectEqual(@as(u8, 1), result.bytecode[pushes_end]);
    try testing.expectEqual(@as(u8, 0x21), result.bytecode[pushes_end + 1]);
    // issuer push: length 33 then 0x02 prefix (compressed even-y)
    const issuer_off = pushes_end + (1 + 1) + (1 + 1) + (1 + 36) + (1 + 36);
    try testing.expectEqual(@as(u8, 33), result.bytecode[issuer_off]);
    try testing.expectEqual(@as(u8, 0x02), result.bytecode[issuer_off + 1]);
}

test "bolt port: BOLT_P2P_LOCK emits the b017 pay2Proof lock layout" {
    const allocator = testing.allocator;
    const pkh = "0x" ++ "ab" ** 20;
    // the p2p lock runs on top of the unlock's <sig> <pub> <marker> items
    const unlocking = [_]bsvz_macro.StackItem{
        .{ .type = .signature },
        .{ .type = .pubkey },
        .{ .type = .{ .bytes = 3 } },
    };
    const result = try bsvz_macro.compileWithUnlockingScript(allocator, "BOLT_P2P_LOCK[" ++ pkh ++ "]", .{}, &unlocking);
    defer result.deinit(allocator);

    // expected: 03 02 b0 17 (push the marker payload) | 88 | 76 | a9 | 14 <20-byte pkh> | 88 | ac
    const Opcode = bsvz.script.opcode.Opcode;
    var expected: std.ArrayListUnmanaged(u8) = .empty;
    defer expected.deinit(allocator);
    try expected.append(allocator, 3);
    try expected.appendSlice(allocator, &bolt.p2p_marker);
    try expected.append(allocator, Opcode.OP_EQUALVERIFY.toByte());
    try expected.append(allocator, Opcode.OP_DUP.toByte());
    try expected.append(allocator, Opcode.OP_HASH160.toByte());
    try expected.append(allocator, 20);
    var buf: [20]u8 = undefined;
    _ = hexDecode(&buf, pkh[2..]);
    try expected.appendSlice(allocator, &buf);
    try expected.append(allocator, Opcode.OP_EQUALVERIFY.toByte());
    try expected.append(allocator, Opcode.OP_CHECKSIG.toByte());

    try testing.expectEqualSlices(u8, expected.items, result.bytecode);
}

test "bolt port: BOLT_P2P_UNLOCK emits sig, pubkey, then the b017 marker" {
    const allocator = testing.allocator;
    const sig = "0x30" ++ "45" ** 72;
    const pubkey_hex = "0x02" ++ "33" ** 32;
    const result = try bsvz_macro.compile(allocator, "BOLT_P2P_UNLOCK[" ++ sig ++ ", " ++ pubkey_hex ++ "]", .{});
    defer result.deinit(allocator);

    // last three bytes are the marker push 02 b0 17
    const n = result.bytecode.len;
    try testing.expectEqual(@as(u8, 0x02), result.bytecode[n - 3]);
    try testing.expectEqual(@as(u8, 0xb0), result.bytecode[n - 2]);
    try testing.expectEqual(@as(u8, 0x17), result.bytecode[n - 1]);
    // first push: 73-byte DER sig (1 length prefix + 73 data bytes)
    try testing.expectEqual(@as(u8, 73), result.bytecode[0]);
}

test "bolt port: wrong arity fails closed" {
    const allocator = testing.allocator;
    try expectCompileError(allocator, "BOLT_SMB_LOCK[0x00]");
    try expectCompileError(allocator, "BOLT_MS_LOCK[0x00, 0x01]");
    try expectCompileError(allocator, "BOLT_P2P_LOCK[]");
    try expectCompileError(allocator, "BOLT_P2P_UNLOCK[0x00]");
}

test "bolt port: odd-length hex arg fails closed" {
    const allocator = testing.allocator;
    try expectCompileError(allocator, "BOLT_P2P_LOCK[0x123]");
}

fn expectCompileError(allocator: std.mem.Allocator, source: []const u8) !void {
    if (bsvz_macro.compile(allocator, source, .{})) |_| {
        return error.TestExpectedError;
    } else |_| {}
}

fn hexDecode(out: []u8, hex: []const u8) bool {
    var i: usize = 0;
    while (i < hex.len / 2) : (i += 1) {
        const hi = std.fmt.charToDigit(hex[i * 2], 16) catch return false;
        const lo = std.fmt.charToDigit(hex[i * 2 + 1], 16) catch return false;
        out[i] = (@as(u8, hi) << 4) | lo;
    }
    return true;
}
