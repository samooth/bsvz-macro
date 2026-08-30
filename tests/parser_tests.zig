const std = @import("std");
const bsvz_macro = @import("bsvz-macro");
const bsvz = @import("bsvz");

const testing = std.testing;

// Parser-specific tests for AST generation and error conditions.

test "parser: single statement compiles" {
    const allocator = testing.allocator;
    const result = try bsvz_macro.compile(allocator, "OP_DUP", .{});
    defer result.deinit(allocator);
    try testing.expect(result.bytecode.len > 0);
}

test "parser: multiple statements compile" {
    const allocator = testing.allocator;
    const result = try bsvz_macro.compile(allocator, "OP_DUP OP_DROP OP_DUP OP_DROP", .{});
    defer result.deinit(allocator);
    try testing.expectEqual(@as(u32, 4), result.byte_length);
}

test "parser: macro with no args compiles" {
    const allocator = testing.allocator;
    const result = try bsvz_macro.compile(allocator, "SAFE_DIV", .{});
    defer result.deinit(allocator);
    try testing.expect(result.bytecode.len > 0);
}

test "parser: macro with one arg compiles" {
    const allocator = testing.allocator;
    const result = try bsvz_macro.compile(allocator, "OP_XSWAP[3]", .{});
    defer result.deinit(allocator);
    try testing.expect(result.bytecode.len > 0);
}

test "parser: macro with two args compiles" {
    const allocator = testing.allocator;
    const result = try bsvz_macro.compile(allocator, "RANGE_CHECK[0,100]", .{});
    defer result.deinit(allocator);
    try testing.expect(result.bytecode.len > 0);
}

test "parser: loop block compiles" {
    const allocator = testing.allocator;
    const result = try bsvz_macro.compile(allocator, "LOOP[3]{ OP_DUP }", .{});
    defer result.deinit(allocator);
    try testing.expect(result.bytecode.len > 0);
}

test "parser: nested loop compiles" {
    const allocator = testing.allocator;
    const result = try bsvz_macro.compile(allocator, "LOOP[2]{ LOOP[2]{ OP_DUP } }", .{});
    defer result.deinit(allocator);
    try testing.expect(result.bytecode.len > 0);
}

test "parser: conditional with bsv flag compiles" {
    const allocator = testing.allocator;
    const result = try bsvz_macro.compile(allocator, "@bsv{ OP_CAT }", .{});
    defer result.deinit(allocator);
    try testing.expect(result.bytecode.len > 0);
}

test "parser: conditional with chronicle flag compiles" {
    const allocator = testing.allocator;
    const result = try bsvz_macro.compile(allocator, "@chronicle{ OP_CAT }", .{
        .era = .chronicle,
    });
    defer result.deinit(allocator);
    try testing.expect(result.bytecode.len > 0);
}

test "parser: conditional with btc_strict flag compiles" {
    const allocator = testing.allocator;
    const result = try bsvz_macro.compile(allocator, "@btc_strict{ OP_NOP }", .{
        .target = .btc_strict,
    });
    defer result.deinit(allocator);
    try testing.expect(result.bytecode.len > 0);
}

test "parser: conditional with else branch compiles" {
    const allocator = testing.allocator;
    const result = try bsvz_macro.compile(allocator, "@bsv{ OP_DUP } else { OP_DROP }", .{});
    defer result.deinit(allocator);
    try testing.expect(result.bytecode.len > 0);
}

test "parser: version check conditional compiles" {
    const allocator = testing.allocator;
    const result = try bsvz_macro.compile(allocator, "@version[1]{ OP_DUP }", .{});
    defer result.deinit(allocator);
    try testing.expect(result.bytecode.len > 0);
}

test "parser: invalid condition keyword causes error" {
    const allocator = testing.allocator;
    const result = bsvz_macro.compile(allocator, "@invalid{ OP_DUP }", .{});
    try testing.expectError(error.ParseError, result);
}

test "parser: missing closing bracket in loop causes error" {
    const allocator = testing.allocator;
    const result = bsvz_macro.compile(allocator, "LOOP[3 OP_DUP }", .{});
    try testing.expectError(error.ParseError, result);
}

test "parser: empty loop body compiles" {
    const allocator = testing.allocator;
    const result = try bsvz_macro.compile(allocator, "LOOP[3]{ }", .{});
    defer result.deinit(allocator);
    try testing.expectEqual(@as(u32, 0), result.byte_length);
}

test "parser: block statement compiles" {
    const allocator = testing.allocator;
    // Standalone block
    const result = try bsvz_macro.compile(allocator, "{ OP_DUP OP_DROP }", .{});
    defer result.deinit(allocator);
    try testing.expectEqual(@as(u32, 2), result.byte_length);
}

test "parser: semicolons between statements" {
    const allocator = testing.allocator;
    const result = try bsvz_macro.compile(allocator, "OP_DUP; OP_DROP; OP_DUP", .{});
    defer result.deinit(allocator);
    try testing.expectEqual(@as(u32, 3), result.byte_length);
}

test "parser: trailing semicolon is allowed" {
    const allocator = testing.allocator;
    const result = try bsvz_macro.compile(allocator, "OP_DUP;", .{});
    defer result.deinit(allocator);
    try testing.expectEqual(@as(u32, 1), result.byte_length);
}

test "parser: iterator ref as loop body statement compiles" {
    const allocator = testing.allocator;
    // <i> is substituted by the loop and emitted as a push per iteration.
    const result = try bsvz_macro.compile(allocator, "LOOP[3]{ <i> }", .{});
    defer result.deinit(allocator);
    try testing.expectEqual(@as(u32, 3), result.byte_length);
}

test "parser: iterator ref inside macro argument compiles" {
    const allocator = testing.allocator;
    // RANGE_CHECK[<i>,100] substitutes <i> per iteration (0..n-1).
    const result = try bsvz_macro.compile(allocator, "LOOP[3]{ RANGE_CHECK[<i>,100] }", .{});
    defer result.deinit(allocator);
    try testing.expect(result.bytecode.len > 0);
}
