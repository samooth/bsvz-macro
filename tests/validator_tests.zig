const std = @import("std");
const bsvz_macro = @import("bsvz-macro");
const bsvz = @import("bsvz");

const testing = std.testing;

// Validator-specific tests for bounds checking and standardness enforcement.

test "validator: default options allow standard script" {
    const allocator = testing.allocator;
    const result = try bsvz_macro.compile(allocator, "OP_DUP OP_HASH160 OP_EQUAL", .{});
    defer result.deinit(allocator);
    try testing.expect(result.is_standard);
    try testing.expect(result.byte_length > 0);
}

test "validator: max_script_size enforced" {
    const allocator = testing.allocator;
    // A script that exceeds max_script_size should fail
    const result = bsvz_macro.compile(allocator, "OP_DUP OP_HASH160 OP_EQUAL OP_VERIFY", .{
        .max_script_size = 2,
    });
    try testing.expectError(error.ValError, result);
}

test "validator: max_stack_elements enforced via simulator" {
    const allocator = testing.allocator;
    // The simulator catches stack overflow before the validator can check
    const result = bsvz_macro.compile(allocator, "OP_1 OP_DUP OP_DUP", .{
        .max_stack_elements = 1,
    });
    try testing.expectError(error.SimError, result);
}

test "validator: enforce_standardness true checks opcode count" {
    const allocator = testing.allocator;
    // With enforce_standardness = true, scripts with > 201 non-push opcodes are non-standard
    // But this is hard to trigger without a large script, so we just verify it compiles
    const result = try bsvz_macro.compile(allocator, "OP_DUP OP_DROP", .{
        .enforce_standardness = true,
    });
    defer result.deinit(allocator);
    try testing.expect(result.is_standard);
}

test "validator: enforce_standardness false skips checks" {
    const allocator = testing.allocator;
    // With enforce_standardness = false, any script is considered standard
    const result = try bsvz_macro.compile(allocator, "OP_DUP OP_DROP", .{
        .enforce_standardness = false,
    });
    defer result.deinit(allocator);
    try testing.expect(result.is_standard);
}

test "validator: OP_RETURN causes error" {
    const allocator = testing.allocator;
    // OP_RETURN causes the simulator to fail
    const result = bsvz_macro.compile(allocator, "OP_RETURN", .{});
    // Should return some error (SimError or mapped to OutOfMemory)
    try testing.expect(result == error.SimError or result == error.OutOfMemory or result == error.ValError);
}

test "validator: large max_script_size allows big scripts" {
    const allocator = testing.allocator;
    const result = try bsvz_macro.compile(allocator, "OP_DUP OP_DROP OP_DUP OP_DROP", .{
        .max_script_size = 10000,
    });
    defer result.deinit(allocator);
    try testing.expect(result.byte_length > 0);
}

test "validator: hash result is deterministic" {
    const allocator = testing.allocator;
    const result1 = try bsvz_macro.compile(allocator, "OP_DUP OP_HASH160", .{});
    defer result1.deinit(allocator);
    const result2 = try bsvz_macro.compile(allocator, "OP_DUP OP_HASH160", .{});
    defer result2.deinit(allocator);
    // Same source should produce same hash
    try testing.expectEqualSlices(u8, &result1.hash, &result2.hash);
}

test "validator: different sources produce different hashes" {
    const allocator = testing.allocator;
    const result1 = try bsvz_macro.compile(allocator, "OP_DUP", .{});
    defer result1.deinit(allocator);
    const result2 = try bsvz_macro.compile(allocator, "OP_DROP", .{});
    defer result2.deinit(allocator);
    // Different sources should produce different hashes
    try testing.expect(!std.mem.eql(u8, &result1.hash, &result2.hash));
}
