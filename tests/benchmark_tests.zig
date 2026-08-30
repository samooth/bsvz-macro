const std = @import("std");
const bsvz_macro = @import("bsvz-macro");
const bsvz = @import("bsvz");
const testing = std.testing;

// Benchmark tests for performance-sensitive operations.
// Each bench: test prints its elapsed time (ms) to stderr via std.debug.print.
// Per docs/TESTING.md: no hard latency thresholds are asserted in-tree — CI
// machines vary too much. Timings are for local recording/regression bisection.
//
// Uses std.c.clock_gettime(CLOCK_MONOTONIC) because this Zig 0.16.0-dev build
// ships a reduced std.time with no Timer/Instant/nanoTimestamp.

fn monotonicMs() i64 {
    var ts: std.c.timespec = undefined;
    _ = std.c.clock_gettime(std.c.CLOCK.MONOTONIC, &ts);
    return @as(i64, ts.sec) * 1000 + @divTrunc(@as(i64, ts.nsec), 1_000_000);
}

// ==================== COMPILATION BENCHMARKS ====================

test "bench: compile simple script repeatedly" {
    const allocator = testing.allocator;
    const source = "OP_DUP OP_HASH160 OP_EQUAL";

    const t0 = monotonicMs();
    for (0..100) |_| {
        const result = try bsvz_macro.compile(allocator, source, .{});
        result.deinit(allocator);
    }
    std.debug.print("  bench: compile simple script repeatedly: {d}ms\n", .{monotonicMs() - t0});
}

test "bench: compile with macro expansion repeatedly" {
    const allocator = testing.allocator;
    const source = "OP_XSWAP[5]";

    const t0 = monotonicMs();
    for (0..100) |_| {
        const result = try bsvz_macro.compile(allocator, source, .{});
        result.deinit(allocator);
    }
    std.debug.print("  bench: compile with macro expansion repeatedly: {d}ms\n", .{monotonicMs() - t0});
}

test "bench: compile loop with many iterations" {
    const allocator = testing.allocator;
    const source = "LOOP[100]{ OP_DUP OP_HASH160 OP_EQUAL }";

    const t0 = monotonicMs();
    for (0..10) |_| {
        const result = try bsvz_macro.compile(allocator, source, .{});
        result.deinit(allocator);
    }
    std.debug.print("  bench: compile loop with many iterations: {d}ms\n", .{monotonicMs() - t0});
}

test "bench: compile large script" {
    const allocator = testing.allocator;
    var source: std.ArrayList(u8) = .empty;
    defer source.deinit(allocator);
    for (0..50) |_| {
        try source.appendSlice(allocator, "OP_DUP OP_HASH160 OP_EQUAL ");
    }

    const t0 = monotonicMs();
    for (0..10) |_| {
        const result = try bsvz_macro.compile(allocator, source.items, .{});
        result.deinit(allocator);
    }
    std.debug.print("  bench: compile large script: {d}ms\n", .{monotonicMs() - t0});
}

test "bench: compile with ASM emission" {
    const allocator = testing.allocator;
    const source = "OP_DUP OP_HASH160 OP_EQUAL";

    const t0 = monotonicMs();
    for (0..100) |_| {
        const result = try bsvz_macro.compile(allocator, source, .{ .emit_asm = true });
        result.deinit(allocator);
    }
    std.debug.print("  bench: compile with ASM emission: {d}ms\n", .{monotonicMs() - t0});
}

// ==================== SIMULATION BENCHMARKS ====================

test "bench: simulate simple bytecode" {
    const allocator = testing.allocator;
    const source = "OP_1 OP_2 OP_3 OP_4 OP_5 OP_6 OP_7 OP_8 OP_DUP OP_DROP";

    const t0 = monotonicMs();
    for (0..100) |_| {
        const result = try bsvz_macro.compile(allocator, source, .{});
        result.deinit(allocator);
    }
    std.debug.print("  bench: simulate simple bytecode: {d}ms\n", .{monotonicMs() - t0});
}

test "bench: simulate complex expression" {
    const allocator = testing.allocator;
    const source = "OP_1 OP_2 OP_ADD OP_3 OP_MUL OP_4 OP_SUB OP_DUP OP_HASH160 OP_EQUAL";

    const t0 = monotonicMs();
    for (0..100) |_| {
        const result = try bsvz_macro.compile(allocator, source, .{});
        result.deinit(allocator);
    }
    std.debug.print("  bench: simulate complex expression: {d}ms\n", .{monotonicMs() - t0});
}

// ==================== ENCODER BENCHMARKS ====================

test "bench: toAsm conversion repeatedly" {
    const allocator = testing.allocator;
    const source = "OP_DUP OP_HASH160 OP_EQUAL OP_VERIFY";
    const result = try bsvz_macro.compile(allocator, source, .{});
    defer result.deinit(allocator);

    const t0 = monotonicMs();
    for (0..1000) |_| {
        const asm_str = try bsvz_macro.toAsm(allocator, result.bytecode);
        allocator.free(asm_str);
    }
    std.debug.print("  bench: toAsm conversion repeatedly: {d}ms\n", .{monotonicMs() - t0});
}

test "bench: fromAsm conversion repeatedly" {
    const allocator = testing.allocator;
    const asm_source = "OP_DUP OP_HASH160 OP_EQUAL OP_VERIFY";

    const t0 = monotonicMs();
    for (0..1000) |_| {
        const bytecode = try bsvz_macro.fromAsm(allocator, asm_source);
        allocator.free(bytecode);
    }
    std.debug.print("  bench: fromAsm conversion repeatedly: {d}ms\n", .{monotonicMs() - t0});
}

// ==================== ROUND-TRIP BENCHMARKS ====================

test "bench: full roundtrip repeatedly" {
    const allocator = testing.allocator;
    const source = "OP_DUP OP_HASH160 OP_EQUALVERIFY";

    const t0 = monotonicMs();
    for (0..100) |_| {
        const result = try bsvz_macro.compile(allocator, source, .{});
        defer result.deinit(allocator);

        const asm_str = try bsvz_macro.toAsm(allocator, result.bytecode);
        defer allocator.free(asm_str);

        const bytecode = try bsvz_macro.fromAsm(allocator, asm_str);
        defer allocator.free(bytecode);
    }
    std.debug.print("  bench: full roundtrip repeatedly: {d}ms\n", .{monotonicMs() - t0});
}

// ==================== MEMORY USAGE BENCHMARKS ====================

test "bench: memory usage for large compilation" {
    const allocator = testing.allocator;
    var source: std.ArrayList(u8) = .empty;
    defer source.deinit(allocator);
    for (0..20) |_| {
        try source.appendSlice(allocator, "OP_XSWAP[5] ");
    }

    const t0 = monotonicMs();
    for (0..10) |_| {
        const result = try bsvz_macro.compile(allocator, source.items, .{});
        result.deinit(allocator);
    }
    std.debug.print("  bench: memory usage for large compilation: {d}ms\n", .{monotonicMs() - t0});
}

// ==================== STRESS TESTS ====================

test "stress: many small compilations" {
    const allocator = testing.allocator;
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
    const source = "LOOP[3]{ LOOP[3]{ LOOP[3]{ OP_DUP } } }";
    const result = try bsvz_macro.compile(allocator, source, .{});
    defer result.deinit(allocator);
    try testing.expectEqual(@as(u32, 27), result.byte_length);
}

test "stress: many conditional branches" {
    const allocator = testing.allocator;
    const source = "@bsv{ OP_DUP } @chronicle{ OP_DROP } @btc_strict{ OP_NOP }";
    const result = try bsvz_macro.compile(allocator, source, .{});
    defer result.deinit(allocator);
    try testing.expectEqual(@as(u32, 2), result.byte_length);
}
