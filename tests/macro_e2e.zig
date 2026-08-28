const std = @import("std");
const bsvz_macro = @import("bsvz-macro");
const bsvz = @import("bsvz");

const testing = std.testing;

test "e2e: compile simple macro" {
    const allocator = testing.allocator;
    const result = try bsvz_macro.compile(allocator, "OP_XSWAP[3]", .{});
    defer result.deinit(allocator);

    try testing.expect(result.bytecode.len > 0);
    try testing.expectEqual(@as(u32, 6), result.byte_length);
}

test "e2e: compile loop macro" {
    const allocator = testing.allocator;
    const result = try bsvz_macro.compile(allocator, "LOOP[3]{ OP_DUP OP_MUL }", .{});
    defer result.deinit(allocator);

    try testing.expect(result.bytecode.len > 0);
    try testing.expect(result.max_stack_height > 0);
}

test "e2e: compile with asm output" {
    const allocator = testing.allocator;
    const result = try bsvz_macro.compile(allocator, "OP_DUP OP_HASH160", .{
        .emit_asm = true,
    });
    defer result.deinit(allocator);

    try testing.expect(result.asm_text != null);
    try testing.expect(result.asm_text.?.len > 0);
}

test "e2e: compile hashcat" {
    const allocator = testing.allocator;
    const result = try bsvz_macro.compile(allocator, "OP_HASHCAT", .{});
    defer result.deinit(allocator);

    try testing.expectEqual(@as(u32, 4), result.byte_length);
}

test "e2e: hex roundtrip" {
    const allocator = testing.allocator;
    const result = try bsvz_macro.compile(allocator, "OP_1 OP_2 OP_ADD", .{});
    defer result.deinit(allocator);

    const asm_str = try bsvz_macro.toAsm(allocator, result.bytecode);
    defer allocator.free(asm_str);

    try testing.expect(asm_str.len > 0);
}
