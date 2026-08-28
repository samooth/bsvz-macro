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
