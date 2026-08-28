const std = @import("std");
const bsvz_macro = @import("bsvz-macro");
const bsvz = @import("bsvz");

const testing = std.testing;
const xswap_cases = @import("fixtures/xswap_cases.zig").cases;

test "canonical: XSWAP expansion" {
    const allocator = testing.allocator;
    for (xswap_cases) |case| {
        const result = try bsvz_macro.compile(allocator, case.source, .{});
        defer result.deinit(allocator);
        try testing.expect(result.bytecode.len > 0);
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
    try testing.expect(result.bytecode.len > 0);
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
