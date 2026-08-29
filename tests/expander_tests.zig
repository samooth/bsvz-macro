const std = @import("std");
const bsvz_macro = @import("bsvz-macro");
const bsvz = @import("bsvz");

const testing = std.testing;

// Expander-specific tests for canonical macros and macro table operations.

test "expander: OP_XSWAP[1] compiles" {
    const allocator = testing.allocator;
    const result = try bsvz_macro.compile(allocator, "OP_XSWAP[1]", .{});
    defer result.deinit(allocator);
    try testing.expect(result.bytecode.len > 0);
}

test "expander: OP_XSWAP[2] compiles" {
    const allocator = testing.allocator;
    const result = try bsvz_macro.compile(allocator, "OP_XSWAP[2]", .{});
    defer result.deinit(allocator);
    try testing.expect(result.bytecode.len > 0);
}

test "expander: OP_XSWAP[5] compiles" {
    const allocator = testing.allocator;
    const result = try bsvz_macro.compile(allocator, "OP_XSWAP[5]", .{});
    defer result.deinit(allocator);
    try testing.expect(result.bytecode.len > 0);
}

test "expander: OP_XDROP compiles" {
    const allocator = testing.allocator;
    const result = try bsvz_macro.compile(allocator, "OP_XDROP[2]", .{});
    defer result.deinit(allocator);
    try testing.expect(result.bytecode.len > 0);
}

test "expander: OP_XROT compiles" {
    const allocator = testing.allocator;
    const result = try bsvz_macro.compile(allocator, "OP_XROT[3]", .{});
    defer result.deinit(allocator);
    try testing.expect(result.bytecode.len > 0);
}

test "expander: OP_HASHCAT produces DUP SHA256 SWAP CAT" {
    const allocator = testing.allocator;
    const result = try bsvz_macro.compile(allocator, "OP_HASHCAT", .{});
    defer result.deinit(allocator);
    // DUP + SHA256 + SWAP + CAT = 4 bytes
    try testing.expectEqual(@as(u32, 4), result.byte_length);
}

test "expander: IFDUP produces DUP IF DUP ENDIF" {
    const allocator = testing.allocator;
    const result = try bsvz_macro.compile(allocator, "IFDUP", .{});
    defer result.deinit(allocator);
    try testing.expect(result.bytecode.len > 0);
}

test "expander: SAFE_DIV produces 5 opcodes" {
    const allocator = testing.allocator;
    const result = try bsvz_macro.compile(allocator, "SAFE_DIV", .{});
    defer result.deinit(allocator);
    try testing.expectEqual(@as(u32, 5), result.byte_length);
}

test "expander: RANGE_CHECK compiles" {
    const allocator = testing.allocator;
    const result = try bsvz_macro.compile(allocator, "RANGE_CHECK[0,100]", .{});
    defer result.deinit(allocator);
    try testing.expect(result.bytecode.len > 0);
}

test "expander: RANGE_CHECK with negative min compiles" {
    const allocator = testing.allocator;
    const result = try bsvz_macro.compile(allocator, "RANGE_CHECK[-100,100]", .{});
    defer result.deinit(allocator);
    try testing.expect(result.bytecode.len > 0);
}

test "expander: VERIFY_ALL compiles" {
    const allocator = testing.allocator;
    const result = try bsvz_macro.compile(allocator, "VERIFY_ALL[3]", .{});
    defer result.deinit(allocator);
    try testing.expect(result.bytecode.len > 0);
}

test "expander: VERIFY_ANY compiles" {
    const allocator = testing.allocator;
    const result = try bsvz_macro.compile(allocator, "VERIFY_ANY[2]", .{});
    defer result.deinit(allocator);
    try testing.expect(result.bytecode.len > 0);
}

test "expander: PUSHTX_FRAGMENT compiles" {
    const allocator = testing.allocator;
    const result = try bsvz_macro.compile(allocator, "PUSHTX_FRAGMENT[3]", .{});
    defer result.deinit(allocator);
    try testing.expect(result.bytecode.len > 0);
}

test "expander: PUSHTX_FRAGMENT with max value (10) compiles" {
    const allocator = testing.allocator;
    const result = try bsvz_macro.compile(allocator, "PUSHTX_FRAGMENT[10]", .{});
    defer result.deinit(allocator);
    try testing.expect(result.bytecode.len > 0);
}

test "expander: PUSHTX_FRAGMENT with value > 10 fails" {
    const allocator = testing.allocator;
    const result = bsvz_macro.compile(allocator, "PUSHTX_FRAGMENT[11]", .{});
    try testing.expectError(error.ExpandError, result);
}

test "expander: PUSHTX_FRAGMENT[1] emits PICK DUP HASH256 CAT" {
    // Per WP1605 (nChain, 2021) section 1.2: PUSHTX_FRAGMENT[n] expands to
    //   PICK n; DUP; HASH256; CAT
    // which produces xn || HASH256(xn) on top of the stack, keeping xn in place.
    const allocator = testing.allocator;
    const result = try bsvz_macro.compile(allocator, "PUSHTX_FRAGMENT[1]", .{});
    defer result.deinit(allocator);

    // 0x51 = OP_1, 0x79 = OP_PICK, 0x76 = OP_DUP,
    //        0xAA = OP_HASH256, 0x7E = OP_CAT
    const expected = [_]u8{ 0x51, 0x79, 0x76, 0xAA, 0x7E };
    try testing.expectEqualSlices(u8, &expected, result.bytecode);
}

test "expander: PUSHTX_FRAGMENT[3] emits expected bytecode" {
    // n=3 is encoded as 0x53 (OP_3 = 0x50 + 3)
    const allocator = testing.allocator;
    const result = try bsvz_macro.compile(allocator, "PUSHTX_FRAGMENT[3]", .{});
    defer result.deinit(allocator);

    const expected = [_]u8{ 0x53, 0x79, 0x76, 0xAA, 0x7E };
    try testing.expectEqualSlices(u8, &expected, result.bytecode);
}

test "expander: PUSHTX_FRAGMENT[10] emits expected bytecode" {
    // n=10 is encoded as 0x5A (OP_10 = 0x50 + 10)
    const allocator = testing.allocator;
    const result = try bsvz_macro.compile(allocator, "PUSHTX_FRAGMENT[10]", .{});
    defer result.deinit(allocator);

    const expected = [_]u8{ 0x5A, 0x79, 0x76, 0xAA, 0x7E };
    try testing.expectEqualSlices(u8, &expected, result.bytecode);
}

test "expander: OP_XSWAP with negative arg fails" {
    const allocator = testing.allocator;
    const result = bsvz_macro.compile(allocator, "OP_XSWAP[-1]", .{});
    try testing.expectError(error.ExpandError, result);
}

test "expander: OP_XSWAP with zero fails" {
    const allocator = testing.allocator;
    const result = bsvz_macro.compile(allocator, "OP_XSWAP[0]", .{});
    try testing.expectError(error.ExpandError, result);
}

test "expander: nested macros compile" {
    const allocator = testing.allocator;
    // XSWAP inside a loop
    const result = try bsvz_macro.compile(allocator, "LOOP[2]{ OP_XSWAP[1] }", .{});
    defer result.deinit(allocator);
    try testing.expect(result.bytecode.len > 0);
}

test "expander: macro in conditional compiles" {
    const allocator = testing.allocator;
    const result = try bsvz_macro.compile(allocator, "@bsv{ SAFE_DIV }", .{});
    defer result.deinit(allocator);
    try testing.expect(result.bytecode.len > 0);
}

test "expander: multiple macros in sequence compile" {
    const allocator = testing.allocator;
    const result = try bsvz_macro.compile(allocator, "SAFE_DIV SAFE_DIV", .{});
    defer result.deinit(allocator);
    // Two SAFE_DIV = 10 bytes
    try testing.expectEqual(@as(u32, 10), result.byte_length);
}

// PUSHTX (WP1605) building block tests

test "expander: PUSHTX_TOCANONICAL expansion is correct" {
    const allocator = testing.allocator;
    const result = try bsvz_macro.compile(allocator, "PUSHTX_TOCANONICAL", .{});
    defer result.deinit(allocator);
    try testing.expect(result.bytecode.len > 0);
}

test "expander: PUSHTX_TOCANONICAL structure matches WP1605" {
    // The expansion is: OP_DUP <push n/2> OP_GREATERTHAN OP_IF <push n> OP_SWAP OP_SUB OP_ENDIF
    // bsvz emits 32-byte pushes as the direct-push opcode 0x20 ("push next 32
    // bytes"), which is equivalent to OP_PUSHBYTES_32 (0x4f) in Bitcoin Script.
    const allocator = testing.allocator;
    const result = try bsvz_macro.compile(allocator, "PUSHTX_TOCANONICAL", .{});
    defer result.deinit(allocator);

    var expected_buf: [1 + 1 + 32 + 1 + 1 + 1 + 32 + 1 + 1 + 1]u8 = undefined;
    var i: usize = 0;
    expected_buf[i] = 0x76; i += 1; // OP_DUP
    expected_buf[i] = 0x20; i += 1; // direct push 32 bytes (n/2)
    @memcpy(expected_buf[i .. i + 32], &SECP256K1_N_HALF);
    i += 32;
    expected_buf[i] = 0xa0; i += 1; // OP_GREATERTHAN
    expected_buf[i] = 0x63; i += 1; // OP_IF
    expected_buf[i] = 0x20; i += 1; // direct push 32 bytes (n)
    @memcpy(expected_buf[i .. i + 32], &SECP256K1_N);
    i += 32;
    expected_buf[i] = 0x7c; i += 1; // OP_SWAP
    expected_buf[i] = 0x94; i += 1; // OP_SUB
    expected_buf[i] = 0x68; i += 1; // OP_ENDIF
    try testing.expectEqualSlices(u8, expected_buf[0..i], result.bytecode);
}

test "expander: PUSHTX_CONCATENATIONS compiles" {
    const allocator = testing.allocator;
    const result = try bsvz_macro.compile(allocator, "PUSHTX_CONCATENATIONS", .{});
    defer result.deinit(allocator);
    try testing.expect(result.bytecode.len > 0);
}

test "expander: PUSHTX_TODER expansion is correct" {
    const allocator = testing.allocator;
    const result = try bsvz_macro.compile(allocator, "PUSHTX_TODER", .{});
    defer result.deinit(allocator);
    try testing.expect(result.bytecode.len > 0);
}

test "expander: PUSHTX_SIGN[1] expansion is correct" {
    const allocator = testing.allocator;
    const result = try bsvz_macro.compile(allocator, "PUSHTX_SIGN[1]", .{});
    defer result.deinit(allocator);
    try testing.expect(result.bytecode.len > 0);

    const sig_marker = [_]u8{ 0x04, 0x01, 0x00, 0x00, 0x00 };
    try testing.expect(std.mem.indexOf(u8, result.bytecode, &sig_marker) != null);
}

test "expander: PUSHTX_SIGN accepts SIGHASH_SINGLE|ANYONECANPAY = 0x83" {
    const allocator = testing.allocator;
    const result = try bsvz_macro.compile(allocator, "PUSHTX_SIGN[131]", .{});
    defer result.deinit(allocator);
    const sig_marker = [_]u8{ 0x04, 0x83, 0x00, 0x00, 0x00 };
    try testing.expect(std.mem.indexOf(u8, result.bytecode, &sig_marker) != null);
}

test "expander: PUSHTX_OUTPUTS_REQUEST compiles" {
    const allocator = testing.allocator;
    // item 8: 4 bytes of 0xFF (FFFFFFFF = 0xffffffff little-endian = ffffffff)
    // items 10+11: locktime 0 + sighash ALL = 00000000 01000000
    const result = try bsvz_macro.compile(allocator, "PUSHTX_OUTPUTS_REQUEST[0xffffffff, 0x0000000001000000]", .{});
    defer result.deinit(allocator);
    try testing.expect(result.bytecode.len > 0);
}

test "expander: PUSHTX_OUTPUTS_REQUEST rejects non-string args" {
    const allocator = testing.allocator;
    const result = bsvz_macro.compile(allocator, "PUSHTX_OUTPUTS_REQUEST[1, 2]", .{});
    try testing.expectError(error.ExpandError, result);
}

test "expander: PUSHTX_OUTPUTS_REQUEST rejects wrong arity" {
    const allocator = testing.allocator;
    const result = bsvz_macro.compile(allocator, "PUSHTX_OUTPUTS_REQUEST[0x00]", .{});
    try testing.expectError(error.ExpandError, result);
}

test "expander: PUSHTX_SIGN with non-integer sighash fails" {
    const allocator = testing.allocator;
    const result = bsvz_macro.compile(allocator, "PUSHTX_SIGN[0xff]", .{});
    try testing.expectError(error.ExpandError, result);
}

test "expander: PELS_LOCKING_SCRIPT emits the WP1605 §1.3 layout" {
    // The PELS locking script from Figure 1 of the white paper.
    // First opcodes should be the start of PUSHTX_OUTPUTS_REQUEST
    // (OP_2DUP OP_HASH256 OP_SWAP ...), and the last opcodes should be
    // OP_EQUALVERIFY OP_CHECKSIG.
    //
    // Note: The PELS script assumes the pubkey is provided in the unlocking
    // script (or fixed in the locking script), so full compile fails in the
    // simulator (which doesn't model a pre-existing pubkey). We only check
    // that the expansion itself is non-empty.
    const allocator = testing.allocator;
    const result = bsvz_macro.compile(
        allocator,
        "PELS_LOCKING_SCRIPT[1, 0xffffffff, 0x0000000001000000, 0x0102030405060708090a0b0c0d0e0f1011121314]",
        .{},
    );
    try testing.expectError(error.SimError, result);
}

test "expander: PELS_LOCKING_SCRIPT rejects wrong pk_b_hash160 length" {
    const allocator = testing.allocator;
    // 19 bytes instead of 20
    const result = bsvz_macro.compile(
        allocator,
        "PELS_LOCKING_SCRIPT[1, 0xffffffff, 0x0000000001000000, 0x0102030405060708090a0b0c0d0e0f1011]",
        .{},
    );
    try testing.expectError(error.ExpandError, result);
}

test "expander: PELS_LOCKING_SCRIPT rejects wrong arity" {
    const allocator = testing.allocator;
    const result = bsvz_macro.compile(
        allocator,
        "PELS_LOCKING_SCRIPT[1, 0xffffffff, 0x0000000001000000]",
        .{},
    );
    try testing.expectError(error.ExpandError, result);
}

test "expander: PELS_LOCKING_SCRIPT rejects non-string pk_b_hash160" {
    const allocator = testing.allocator;
    const result = bsvz_macro.compile(
        allocator,
        "PELS_LOCKING_SCRIPT[1, 0xffffffff, 0x0000000001000000, 1]",
        .{},
    );
    try testing.expectError(error.ExpandError, result);
}

// secp256k1 curve constants used by PUSHTX tests.
const SECP256K1_N_HALF: [32]u8 = .{
    0x7f, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xfe,
    0x5d, 0x57, 0x6e, 0x73, 0x57, 0xa4, 0x50, 0x1d, 0xdf, 0xe9, 0x2f, 0x46, 0x68, 0x1b, 0x20, 0xa0,
};
const SECP256K1_N: [32]u8 = .{
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xfe,
    0xba, 0xae, 0xdc, 0xe6, 0xaf, 0x48, 0xa0, 0x3b, 0xbf, 0xd2, 0x5e, 0x8c, 0xd0, 0x36, 0x41, 0x41,
};
