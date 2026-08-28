const std = @import("std");
const bsvz_macro = @import("bsvz-macro");
const bsvz = @import("bsvz");

const testing = std.testing;

// Lexer-specific tests for token generation and error conditions.
// These tests verify the lexer behavior through the public API.

test "lexer: single opcode tokenizes" {
    const allocator = testing.allocator;
    const result = try bsvz_macro.compile(allocator, "OP_DUP", .{});
    defer result.deinit(allocator);
    try testing.expectEqual(@as(u32, 1), result.byte_length);
}

test "lexer: multiple opcodes with whitespace" {
    const allocator = testing.allocator;
    const result = try bsvz_macro.compile(allocator, "OP_DUP  OP_DROP", .{});
    defer result.deinit(allocator);
    try testing.expectEqual(@as(u32, 2), result.byte_length);
}

test "lexer: opcodes separated by semicolons" {
    const allocator = testing.allocator;
    const result = try bsvz_macro.compile(allocator, "OP_DUP; OP_DROP", .{});
    defer result.deinit(allocator);
    try testing.expectEqual(@as(u32, 2), result.byte_length);
}

test "lexer: line comments are ignored" {
    const allocator = testing.allocator;
    const result = try bsvz_macro.compile(allocator, "OP_DUP // this is a comment\nOP_DROP", .{});
    defer result.deinit(allocator);
    try testing.expectEqual(@as(u32, 2), result.byte_length);
}

test "lexer: block comments are ignored" {
    const allocator = testing.allocator;
    const result = try bsvz_macro.compile(allocator, "OP_DUP /* block comment */ OP_DROP", .{});
    defer result.deinit(allocator);
    try testing.expectEqual(@as(u32, 2), result.byte_length);
}

test "lexer: nested block comments" {
    const allocator = testing.allocator;
    const result = try bsvz_macro.compile(allocator, "OP_DUP /* outer /* inner */ still outer */ OP_DROP", .{});
    defer result.deinit(allocator);
    try testing.expectEqual(@as(u32, 2), result.byte_length);
}

test "lexer: integer literals" {
    const allocator = testing.allocator;
    // Small integers use minimal encoding (1 byte each)
    const result = try bsvz_macro.compile(allocator, "OP_1 OP_2 OP_3", .{});
    defer result.deinit(allocator);
    try testing.expectEqual(@as(u32, 3), result.byte_length);
}

test "lexer: large integer literal requires push data" {
    const allocator = testing.allocator;
    // 100 is outside the 1-16 range, needs push data (2 bytes: opcode + value)
    // Use it as a macro argument
    const result = try bsvz_macro.compile(allocator, "OP_XSWAP[100]", .{});
    defer result.deinit(allocator);
    try testing.expect(result.byte_length > 0);
}

test "lexer: negative integer literal" {
    const allocator = testing.allocator;
    // Negative integers as macro arguments
    const result = try bsvz_macro.compile(allocator, "RANGE_CHECK[-10,10]", .{});
    defer result.deinit(allocator);
    try testing.expect(result.byte_length > 0);
}


test "lexer: unterminated string causes error" {
    const allocator = testing.allocator;
    const result = bsvz_macro.compile(allocator, "\"unterminated", .{});
    try testing.expectError(error.LexError, result);
}

test "lexer: invalid character causes error" {
    const allocator = testing.allocator;
    // ~ is not a valid character
    const result = bsvz_macro.compile(allocator, "OP_DUP ~OP_DROP", .{});
    try testing.expectError(error.LexError, result);
}

test "lexer: invalid hex literal causes error" {
    const allocator = testing.allocator;
    // 0xZ is not valid hex
    const result = bsvz_macro.compile(allocator, "0xZ", .{});
    try testing.expectError(error.LexError, result);
}

test "lexer: odd-length hex literal causes error" {
    const allocator = testing.allocator;
    // 0xABC (odd length) should be rejected
    const result = bsvz_macro.compile(allocator, "0xABC", .{});
    try testing.expectError(error.LexError, result);
}

test "lexer: integer overflow causes error" {
    const allocator = testing.allocator;
    // Number larger than i64 max
    const result = bsvz_macro.compile(allocator, "99999999999999999999999999999999", .{});
    try testing.expectError(error.LexError, result);
}

test "lexer: tab and newline are whitespace" {
    const allocator = testing.allocator;
    const result = try bsvz_macro.compile(allocator, "OP_DUP\t\nOP_DROP", .{});
    defer result.deinit(allocator);
    try testing.expectEqual(@as(u32, 2), result.byte_length);
}

test "lexer: macro name is recognized" {
    const allocator = testing.allocator;
    // XSWAP (not OP_ prefixed) should be treated as a macro name
    // But it's registered as OP_XSWAP, so we use that
    const result = try bsvz_macro.compile(allocator, "OP_XSWAP[1]", .{});
    defer result.deinit(allocator);
    try testing.expect(result.bytecode.len > 0);
}

test "lexer: underscores in identifiers" {
    const allocator = testing.allocator;
    // Underscores are valid in identifiers
    const result = try bsvz_macro.compile(allocator, "OP_DUP OP_DROP", .{});
    defer result.deinit(allocator);
    try testing.expect(result.bytecode.len > 0);
}

test "lexer: else keyword is recognized" {
    const allocator = testing.allocator;
    // "else" should be parsed as else_keyword, not as identifier
    const result = try bsvz_macro.compile(allocator, "@bsv{ OP_DUP } else { OP_DROP }", .{});
    defer result.deinit(allocator);
    try testing.expect(result.bytecode.len > 0);
}
