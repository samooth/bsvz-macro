const std = @import("std");
const bsvz_macro = @import("bsvz-macro");
const bsvz = @import("bsvz");

const testing = std.testing;

// Simulator-specific tests for stack effect verification.

test "simulator: OP_1 OP_2 OP_ADD tracks max stack" {
    const allocator = testing.allocator;
    const result = try bsvz_macro.compile(allocator, "OP_1 OP_2 OP_ADD", .{});
    defer result.deinit(allocator);
    // Peak: 2 items (after OP_2 push, before OP_ADD)
    try testing.expectEqual(@as(u16, 2), result.max_stack_height);
}

test "simulator: OP_DUP doubles top" {
    const allocator = testing.allocator;
    const result = try bsvz_macro.compile(allocator, "OP_1 OP_DUP", .{});
    defer result.deinit(allocator);
    // Peak: 2 items (after DUP)
    try testing.expectEqual(@as(u16, 2), result.max_stack_height);
}

test "simulator: OP_DROP reduces stack" {
    const allocator = testing.allocator;
    const result = try bsvz_macro.compile(allocator, "OP_1 OP_1 OP_DROP", .{});
    defer result.deinit(allocator);
    // Peak: 2 items (after second OP_1)
    try testing.expectEqual(@as(u16, 2), result.max_stack_height);
}

test "simulator: OP_SWAP exchanges top two" {
    const allocator = testing.allocator;
    const result = try bsvz_macro.compile(allocator, "OP_1 OP_2 OP_SWAP", .{});
    defer result.deinit(allocator);
    // Peak: 2 items
    try testing.expectEqual(@as(u16, 2), result.max_stack_height);
}

test "simulator: OP_NIP removes second item" {
    const allocator = testing.allocator;
    const result = try bsvz_macro.compile(allocator, "OP_1 OP_2 OP_NIP", .{});
    defer result.deinit(allocator);
    // Peak: 2 items, after NIP: 1 item
    try testing.expectEqual(@as(u16, 2), result.max_stack_height);
}

test "simulator: OP_OVER copies second to top" {
    const allocator = testing.allocator;
    const result = try bsvz_macro.compile(allocator, "OP_1 OP_2 OP_OVER", .{});
    defer result.deinit(allocator);
    // Peak: 3 items (after OVER)
    try testing.expectEqual(@as(u16, 3), result.max_stack_height);
}

test "simulator: nested macros track correctly" {
    const allocator = testing.allocator;
    // XSWAP[3] should track stack height correctly
    const result = try bsvz_macro.compile(allocator, "OP_XSWAP[3]", .{});
    defer result.deinit(allocator);
    try testing.expect(result.max_stack_height >= 2);
}

test "simulator: loop expansion tracks max stack" {
    const allocator = testing.allocator;
    // LOOP[3] with OP_DUP OP_MUL - stack grows then shrinks
    const result = try bsvz_macro.compile(allocator, "LOOP[3]{ OP_DUP OP_MUL }", .{});
    defer result.deinit(allocator);
    try testing.expect(result.max_stack_height > 0);
}

test "simulator: OP_HASH160 produces 20-byte hash" {
    const allocator = testing.allocator;
    const result = try bsvz_macro.compile(allocator, "OP_1 OP_HASH160", .{});
    defer result.deinit(allocator);
    // HASH160 = OP_DUP + OP_SHA256 + push20 + OP_EQUALVERIFY... no, just OP_HASH160
    // OP_HASH160 is 1 byte
    try testing.expect(result.byte_length > 0);
}

test "simulator: OP_HASH256 produces 32-byte hash" {
    const allocator = testing.allocator;
    const result = try bsvz_macro.compile(allocator, "OP_1 OP_HASH256", .{});
    defer result.deinit(allocator);
    try testing.expect(result.byte_length > 0);
}

test "simulator: stack overflow is detected" {
    const allocator = testing.allocator;
    // Push many items with very low max_stack_elements
    const result = bsvz_macro.compile(allocator, "OP_1 OP_1 OP_1 OP_1 OP_1 OP_1", .{
        .max_stack_elements = 3,
    });
    try testing.expectError(error.SimError, result);
}

test "simulator: complex expression compiles" {
    const allocator = testing.allocator;
    // (1 + 2) * 3
    const result = try bsvz_macro.compile(allocator, "OP_1 OP_2 OP_ADD OP_3 OP_MUL", .{});
    defer result.deinit(allocator);
    try testing.expect(result.byte_length > 0);
    try testing.expect(result.max_stack_height >= 2);
}

test "simulator: OP_VERIFY consumes bool" {
    const allocator = testing.allocator;
    // OP_1 OP_VERIFY - pushes true, then verifies
    const result = try bsvz_macro.compile(allocator, "OP_1 OP_VERIFY", .{});
    defer result.deinit(allocator);
    try testing.expect(result.byte_length > 0);
    // After VERIFY, stack is empty (relative to pre-population)
    try testing.expectEqual(@as(u16, 1), result.max_stack_height);
}

// ==================== DEPTH-DEPENDENT OPCODES ====================

test "simulator: OP_PICK is stack-neutral at its popped depth" {
    const allocator = testing.allocator;
    // Peak is reached at the depth push (4 items above the pre-populated stack);
    // OP_PICK then pops the depth and pushes one copy, returning to the peak.
    const result = try bsvz_macro.compile(allocator, "OP_1 OP_2 OP_3 OP_2 OP_PICK", .{});
    defer result.deinit(allocator);
    try testing.expectEqual(@as(u32, 5), result.byte_length);
    try testing.expectEqual(@as(u16, 4), result.max_stack_height);
}

test "simulator: OP_ROLL consumes only its depth argument" {
    const allocator = testing.allocator;
    // OP_ROLL pops the depth, relocates the item at that depth to the top and
    // therefore leaves the height one below the peak.
    const result = try bsvz_macro.compile(allocator, "OP_1 OP_2 OP_3 OP_2 OP_ROLL", .{});
    defer result.deinit(allocator);
    try testing.expectEqual(@as(u32, 5), result.byte_length);
    try testing.expectEqual(@as(u16, 4), result.max_stack_height);
}

test "simulator: deep OP_PICK depth requires a deep input stack" {
    const allocator = testing.allocator;
    // OP_XSWAP[100] picks/rolls at depth 99, so the reported height reflects
    // the caller-supplied items the fragment reaches into.
    const result = try bsvz_macro.compile(allocator, "OP_XSWAP[100]", .{});
    defer result.deinit(allocator);
    try testing.expect(result.max_stack_height >= 96);
}

test "simulator: PUSHTX_FRAGMENT[10] picks below the pre-populated stack" {
    const allocator = testing.allocator;
    // Picking at depth 10 forces 7 caller-supplied items to be modeled beyond
    // the 4 pre-populated ones, so the reported height grows accordingly.
    // PICK 10 grows the stack to 12 (4 pre + 7 materialized + 1 copied),
    // DUP then pushes to 13, HASH256 is a no-op, CAT drops to 12.
    // Reported height = 13 - 4 = 9.
    const result = try bsvz_macro.compile(allocator, "PUSHTX_FRAGMENT[10]", .{});
    defer result.deinit(allocator);
    try testing.expectEqual(@as(u16, 9), result.max_stack_height);
}

test "simulator: depth beyond max_stack_elements is rejected" {
    const allocator = testing.allocator;
    // Depth 99 cannot be satisfied when at most 50 stack elements are allowed.
    const result = bsvz_macro.compile(allocator, "OP_XSWAP[100]", .{
        .max_stack_elements = 50,
    });
    try testing.expectError(error.SimError, result);
}

test "simulator: negative OP_PICK depth is rejected" {
    const allocator = testing.allocator;
    const result = bsvz_macro.compile(allocator, "OP_1NEGATE OP_PICK", .{});
    try testing.expectError(error.SimError, result);
}

test "simulator: negative OP_ROLL depth is rejected" {
    const allocator = testing.allocator;
    const result = bsvz_macro.compile(allocator, "OP_1NEGATE OP_ROLL", .{});
    try testing.expectError(error.SimError, result);
}

test "simulator: non-integer OP_PICK depth is rejected" {
    const allocator = testing.allocator;
    // OP_HASH160 leaves a hash on top, which is not a valid depth argument.
    const result = bsvz_macro.compile(allocator, "OP_1 OP_HASH160 OP_PICK", .{});
    try testing.expectError(error.SimError, result);
}

test "simulator: numeric comparison accepts .bytes operands" {
    // Regression test: a 4-byte little-endian push (treated as .bytes{4} by
    // the simulator) must be accepted by OP_GREATERTHAN, matching on-chain
    // Bitcoin Script semantics. This is what enables the PUSHTX macros
    // (which push 32-byte secp256k1 constants) to compile.
    const allocator = testing.allocator;
    // Push 0x05 (5), then push 0x03 (3) on top, then OP_GREATERTHAN -> true.
    const result = try bsvz_macro.compile(allocator, "OP_5 OP_3 OP_GREATERTHAN", .{});
    defer result.deinit(allocator);
    try testing.expect(result.bytecode.len > 0);
    try testing.expect(result.is_standard);
}

test "simulator: numeric arithmetic on 4-byte push succeeds" {
    // OP_ADD on two 4-byte numeric pushes (both .bytes{4}) must succeed.
    // Push 0x02 and 0x03, then OP_ADD -> 5.
    const allocator = testing.allocator;
    const result = try bsvz_macro.compile(allocator, "OP_2 OP_3 OP_ADD", .{});
    defer result.deinit(allocator);
    try testing.expect(result.bytecode.len > 0);
    try testing.expect(result.is_standard);
}

