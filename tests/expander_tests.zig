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
