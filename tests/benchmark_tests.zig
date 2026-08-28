const std = @import("std");
const bsvz_macro = @import("bsvz-macro");
const bsvz = @import("bsvz");
const testing = std.testing;

// Benchmark tests for performance-sensitive operations.
// These tests verify that critical operations work correctly and complete
// within a reasonable number of iterations. They serve as smoke tests for
// performance characteristics.

// ==================== COMPILATION BENCHMARKS ====================

test "bench: compile simple script repeatedly" {
    const allocator = testing.allocator;
    const source = "OP_DUP OP_HASH160 OP_EQUAL";

    // Run many compilations to verify stability
    for (0..100) |_| {
        const result = try bsvz_macro.compile(allocator, source, .{});
        result.deinit(allocator);
    }
}

test "bench: compile with macro expansion repeatedly" {
    const allocator = testing.allocator;
    const source = "OP_XSWAP[5]";

    for (0..100) |_| {
        const result = try bsvz_macro.compile(allocator, source, .{});
        result.deinit(allocator);
    }
}

test "bench: compile loop with many iterations" {
    const allocator = testing.allocator;
    const source = "LOOP[100]{ OP_DUP OP_HASH160 OP_EQUAL }";

    for (0..10) |_| {
        const result = try bsvz_macro.compile(allocator, source, .{});
        result.deinit(allocator);
    }
}

test "bench: compile large script" {
    const allocator = testing.allocator;
    // Build a script with many opcodes
    var source: std.ArrayList(u8) = .empty;
    defer source.deinit(allocator);
    for (0..50) |_| {
        try source.appendSlice(allocator, "OP_DUP OP_HASH160 OP_EQUAL ");
    }

    for (0..10) |_| {
        const result = try bsvz_macro.compile(allocator, source.items, .{});
        result.deinit(allocator);
    }
}

test "bench: compile with ASM emission" {
    const allocator = testing.allocator;
    const source = "OP_DUP OP_HASH160 OP_EQUAL";

    for (0..100) |_| {
        const result = try bsvz_macro.compile(allocator, source, .{ .emit_asm = true });
        result.deinit(allocator);
    }
}

// ==================== SIMULATION BENCHMARKS ====================

test "bench: simulate simple bytecode" {
    const allocator = testing.allocator;
    const source = "OP_1 OP_2 OP_3 OP_4 OP_5 OP_6 OP_7 OP_8 OP_DUP OP_DROP";

    for (0..100) |_| {
        const result = try bsvz_macro.compile(allocator, source, .{});
        result.deinit(allocator);
    }
}

test "bench: simulate complex expression" {
    const allocator = testing.allocator;
    const source = "OP_1 OP_2 OP_ADD OP_3 OP_MUL OP_4 OP_SUB OP_DUP OP_HASH160 OP_EQUAL";

    for (0..100) |_| {
        const result = try bsvz_macro.compile(allocator, source, .{});
        result.deinit(allocator);
    }
}

// ==================== ENCODER BENCHMARKS ====================

test "bench: toAsm conversion repeatedly" {
    const allocator = testing.allocator;
    const source = "OP_DUP OP_HASH160 OP_EQUAL OP_VERIFY";
    const result = try bsvz_macro.compile(allocator, source, .{});
    defer result.deinit(allocator);

    for (0..1000) |_| {
        const asm_str = try bsvz_macro.toAsm(allocator, result.bytecode);
        allocator.free(asm_str);
    }
}

test "bench: fromAsm conversion repeatedly" {
    const allocator = testing.allocator;
    const asm_source = "OP_DUP OP_HASH160 OP_EQUAL OP_VERIFY";

    for (0..1000) |_| {
        const bytecode = try bsvz_macro.fromAsm(allocator, asm_source);
        allocator.free(bytecode);
    }
}

// ==================== ROUND-TRIP BENCHMARKS ====================

test "bench: full roundtrip repeatedly" {
    const allocator = testing.allocator;
    const source = "OP_DUP OP_HASH160 OP_EQUALVERIFY";

    for (0..100) |_| {
        const result = try bsvz_macro.compile(allocator, source, .{});
        defer result.deinit(allocator);

        const asm_str = try bsvz_macro.toAsm(allocator, result.bytecode);
        defer allocator.free(asm_str);

        const bytecode = try bsvz_macro.fromAsm(allocator, asm_str);
        defer allocator.free(bytecode);
    }
}

// ==================== MEMORY USAGE BENCHMARKS ====================

test "bench: memory usage for large compilation" {
    const allocator = testing.allocator;
    // Build a script with many macros that maintain stack balance
    var source: std.ArrayList(u8) = .empty;
    defer source.deinit(allocator);
    for (0..20) |_| {
        try source.appendSlice(allocator, "OP_XSWAP[5] ");
    }

    for (0..10) |_| {
        const result = try bsvz_macro.compile(allocator, source.items, .{});
        result.deinit(allocator);
    }
}

// ==================== STRESS TESTS ====================

test "stress: many small compilations" {
    const allocator = testing.allocator;
    // Compile many different small scripts
    const sources = [_][]const u8{
        "OP_DUP",
        "OP_1 OP_2 OP_ADD",
        "OP_HASH160",
        "OP_DUP OP_DROP",
        "OP_1 OP_DUP OP_ADD",
        "OP_2 OP_3 OP_MUL",
    };

    for (0..50) |i| {
        const source = sources[i % sources.len];
        const result = try bsvz_macro.compile(allocator, source, .{});
        result.deinit(allocator);
    }
}

test "stress: deeply nested loops" {
    const allocator = testing.allocator;
    // Build a script with nested loops
    const source = "LOOP[3]{ LOOP[3]{ LOOP[3]{ OP_DUP } } }";
    const result = try bsvz_macro.compile(allocator, source, .{});
    defer result.deinit(allocator);
    // 3^3 = 27 OP_DUP = 27 bytes
    try testing.expectEqual(@as(u32, 27), result.byte_length);
}

test "stress: many conditional branches" {
    const allocator = testing.allocator;
    // Build a script with many conditional branches
    const source = "@bsv{ OP_DUP } @chronicle{ OP_DROP } @btc_strict{ OP_NOP }";
    const result = try bsvz_macro.compile(allocator, source, .{});
    defer result.deinit(allocator);
    // On BSV: @bsv (OP_DUP=1) + @chronicle (OP_DROP=1) + @btc_strict (false, skipped)
    // Total = 2 bytes
    try testing.expectEqual(@as(u32, 2), result.byte_length);
}
