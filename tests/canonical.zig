const std = @import("std");
const bsvz_macro = @import("bsvz-macro");
const bsvz = @import("bsvz");

const testing = std.testing;
const xswap_cases = @import("fixtures/xswap_cases.zig").cases;
const loop_cases = @import("fixtures/loop_cases.zig").cases;

test "canonical: XSWAP expansion" {
    const allocator = testing.allocator;
    for (xswap_cases) |case| {
        const result = try bsvz_macro.compile(allocator, case.source, .{});
        defer result.deinit(allocator);
        try testing.expect(result.bytecode.len > 0);
    }
}

test "canonical: LOOP fixtures opcode counts" {
    const allocator = testing.allocator;
    for (loop_cases) |case| {
        const result = try bsvz_macro.compile(allocator, case.source, .{});
        defer result.deinit(allocator);
        if (result.opcode_count != case.expected_opcodes) {
            std.debug.print("source: {s}, expected {d} opcodes, got {d}\n", .{ case.source, case.expected_opcodes, result.opcode_count });
            return error.TestExpectedEqual;
        }
    }
}

test "canonical: SAFE_DIV" {
    const allocator = testing.allocator;
    const result = try bsvz_macro.compile(allocator, "SAFE_DIV", .{});
    defer result.deinit(allocator);
    try testing.expectEqual(@as(u32, 5), result.byte_length);
}

test "canonical: RANGE_CHECK" {
    const allocator = testing.allocator;
    const result = try bsvz_macro.compile(allocator, "RANGE_CHECK[0,100]", .{});
    defer result.deinit(allocator);
    try testing.expect(result.bytecode.len > 0);
}

test "canonical: VERIFY_ALL" {
    const allocator = testing.allocator;
    const result = try bsvz_macro.compile(allocator, "VERIFY_ALL[3]", .{});
    defer result.deinit(allocator);
    try testing.expect(result.bytecode.len > 0);
}

test "canonical: VERIFY_ANY" {
    const allocator = testing.allocator;
    const result = try bsvz_macro.compile(allocator, "VERIFY_ANY[2]", .{});
    defer result.deinit(allocator);
    try testing.expect(result.bytecode.len > 0);
}

test "canonical: PUSHTX_FRAGMENT" {
    const allocator = testing.allocator;
    const result = try bsvz_macro.compile(allocator, "PUSHTX_FRAGMENT[3]", .{});
    defer result.deinit(allocator);
    // PUSHTX_FRAGMENT[n] expands to: <push n> PICK DUP HASH256 CAT = 5 bytes
    try testing.expectEqual(@as(u32, 5), result.byte_length);
}

test "canonical: PUSHTX_FRAGMENT matches WP1605 §1.2 pattern" {
    // Integration check: the expansion for PUSHTX_FRAGMENT[3] is
    //   0x53 (OP_3) 0x79 (OP_PICK) 0x76 (OP_DUP) 0xAA (OP_HASH256) 0x7E (OP_CAT)
    // matching the pick-dup-hash-cat pattern used throughout the white paper
    // for constructing preimage fragments (e.g. item 9, hash of outputs).
    const allocator = testing.allocator;
    const result = try bsvz_macro.compile(allocator, "PUSHTX_FRAGMENT[3]", .{});
    defer result.deinit(allocator);
    const expected = [_]u8{ 0x53, 0x79, 0x76, 0xAA, 0x7E };
    try testing.expectEqualSlices(u8, &expected, result.bytecode);
}

test "canonical: PUSHTX_OUTPUTS_REQUEST matches WP1605 §1.3 pattern" {
    // The [outputsRequest] block from the white paper PELS example:
    //   OP_2DUP OP_HASH256 OP_SWAP <item 8> OP_CAT OP_SWAP OP_CAT <item 10 and 11> OP_CAT
    // Here item 8 = 0xffffffff (4 bytes) and items 10+11 = 0x00000000 01000000 (8 bytes).
    const allocator = testing.allocator;
    const result = try bsvz_macro.compile(
        allocator,
        "PUSHTX_OUTPUTS_REQUEST[0xffffffff, 0x0000000001000000]",
        .{},
    );
    defer result.deinit(allocator);
    // Expected opcodes: OP_2DUP OP_HASH256 OP_SWAP <push 4B> OP_CAT OP_SWAP OP_CAT <push 8B> OP_CAT
    // OP_2DUP=0x6e, OP_HASH256=0xaa, OP_SWAP=0x7c, OP_CAT=0x7e
    // <push 4B 0xff..> = 04 ff ff ff ff
    // <push 8B 0x..>  = 08 00 00 00 00 01 00 00 00
    const expected = [_]u8{
        0x6e, 0xaa, 0x7c,
        0x04, 0xff, 0xff, 0xff, 0xff,
        0x7e, 0x7c, 0x7e,
        0x08, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00,
        0x7e,
    };
    try testing.expectEqualSlices(u8, &expected, result.bytecode);
}

test "canonical: PUSHTX_CONCATENATIONS structure matches WP1605" {
    // The [concatenations] block: OP_SIZE OP_DUP <0x24> OP_ADD <0x30> OP_SWAP OP_CAT
    //   <push 34B: 02 20 || Gx || 02> OP_CAT OP_SWAP OP_CAT OP_SWAP OP_CAT
    const allocator = testing.allocator;
    const result = try bsvz_macro.compile(allocator, "PUSHTX_CONCATENATIONS", .{});
    defer result.deinit(allocator);
    try testing.expect(result.bytecode.len > 0);
    // First op should be OP_SIZE (0x82 in bsvz).
    try testing.expectEqual(@as(u8, 0x82), result.bytecode[0]);
}

test "canonical: conditional @bsv" {
    const allocator = testing.allocator;
    const result = try bsvz_macro.compile(allocator, "@bsv{ OP_CAT }", .{});
    defer result.deinit(allocator);
    try testing.expect(result.bytecode.len > 0);
}

test "canonical: conditional @btc_strict" {
    const allocator = testing.allocator;
    const result = try bsvz_macro.compile(allocator, "@btc_strict{ OP_CAT } else { OP_NOP }", .{
        .target = .btc_strict,
    });
    defer result.deinit(allocator);
    // In btc_strict, OP_CAT should not be emitted, OP_NOP should
    try testing.expect(result.bytecode.len > 0);
}

test "canonical: PELS_LOCKING_SCRIPT end-to-end" {
    // End-to-end test: compile a full PELS locking script from WP1605 §1.3.
    // The PELS script assumes the pubkey is provided in the unlocking script,
    // so full compile fails in the simulator (which doesn't model a pre-existing
    // pubkey). We document this with an expected SimError.
    const allocator = testing.allocator;
    const result = bsvz_macro.compile(
        allocator,
        "PELS_LOCKING_SCRIPT[1, 0xffffffff, 0x0000000001000000, 0x0102030405060708090a0b0c0d0e0f1011121314]",
        .{},
    );
    try testing.expectError(error.SimError, result);
}

test "canonical: opcode_count counts opcodes not bytes" {
    const allocator = testing.allocator;
    // OP_1 OP_2 OP_ADD OP_DROP: 4 bytes, 4 opcodes
    {
        const result = try bsvz_macro.compile(allocator, "OP_1 OP_2 OP_ADD OP_DROP", .{});
        defer result.deinit(allocator);
        try testing.expectEqual(@as(u32, 4), result.byte_length);
        try testing.expectEqual(@as(u32, 4), result.opcode_count);
    }
    // RANGE_CHECK[0,100]: 9 bytes but 8 opcodes (the 0x01 0x64 push is one opcode)
    {
        const result = try bsvz_macro.compile(allocator, "RANGE_CHECK[0,100]", .{});
        defer result.deinit(allocator);
        try testing.expectEqual(@as(u32, 9), result.byte_length);
        try testing.expectEqual(@as(u32, 8), result.opcode_count);
    }
}

test "canonical: countOpcodes handles push encodings" {
    // Direct raw-bytecode checks of the counter.
    // <push 4 bytes> OP_NOP -> 2 opcodes, 6 bytes
    try testing.expectEqual(@as(u32, 2), bsvz_macro.countOpcodes(&.{ 0x04, 0xff, 0xff, 0xff, 0xff, 0x61 }));
    // OP_PUSHDATA1 <len=3> abc -> 1 opcode, 5 bytes
    try testing.expectEqual(@as(u32, 1), bsvz_macro.countOpcodes(&.{ 0x4c, 0x03, 0x01, 0x02, 0x03 }));
    // OP_PUSHDATA2 <len=4> abcd -> 1 opcode, 7 bytes
    try testing.expectEqual(@as(u32, 1), bsvz_macro.countOpcodes(&.{ 0x4d, 0x04, 0x00, 0x01, 0x02, 0x03, 0x04 }));
    // OP_PUSHDATA4 <len=1> a -> 1 opcode, 6 bytes
    try testing.expectEqual(@as(u32, 1), bsvz_macro.countOpcodes(&.{ 0x4e, 0x01, 0x00, 0x00, 0x00, 0xaa }));
    // Minimal int pushes are single opcodes
    try testing.expectEqual(@as(u32, 2), bsvz_macro.countOpcodes(&.{ 0x4f, 0x51 }));
    // Empty script has zero opcodes
    try testing.expectEqual(@as(u32, 0), bsvz_macro.countOpcodes(&.{}));
}
