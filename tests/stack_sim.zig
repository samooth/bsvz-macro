const std = @import("std");
const bsvz_macro = @import("bsvz-macro");
const bsvz = @import("bsvz");

const testing = std.testing;

test "stack sim: simple arithmetic" {
    const allocator = testing.allocator;
    const result = try bsvz_macro.compile(allocator, "OP_1 OP_2 OP_ADD", .{});
    defer result.deinit(allocator);

    try testing.expectEqual(@as(u16, 1), result.max_stack_height);
}

test "stack sim: dup" {
    const allocator = testing.allocator;
    const result = try bsvz_macro.compile(allocator, "OP_1 OP_DUP", .{});
    defer result.deinit(allocator);

    try testing.expectEqual(@as(u16, 2), result.max_stack_height);
}

test "stack sim: xswap3" {
    const allocator = testing.allocator;
    const result = try bsvz_macro.compile(allocator, "OP_XSWAP[3]", .{});
    defer result.deinit(allocator);

    try testing.expect(result.max_stack_height >= 2);
}
