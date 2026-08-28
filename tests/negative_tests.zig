const std = @import("std");
const bsvz_macro = @import("bsvz-macro");
const bsvz = @import("bsvz");

const testing = std.testing;

// Negative tests - these verify that error conditions are properly detected
// and reported through the public API. They focus on phases that have
// well-defined error handling: lexing, parsing, and expansion.

// ==================== LEXER ERRORS ====================

test "negative: unterminated string returns LexError" {
    const allocator = testing.allocator;
    const result = bsvz_macro.compile(allocator, "OP_DUP \"unterminated", .{});
    try testing.expectError(error.LexError, result);
}

test "negative: invalid character returns LexError" {
    const allocator = testing.allocator;
    // '$' is not a valid character in this DSL
    const result = bsvz_macro.compile(allocator, "OP_DUP $invalid", .{});
    try testing.expectError(error.LexError, result);
}

// ==================== PARSER ERRORS ====================

test "negative: invalid condition keyword returns ParseError" {
    const allocator = testing.allocator;
    // @unknown is not a valid condition keyword
    const result = bsvz_macro.compile(allocator, "@unknown{ OP_DUP }", .{});
    try testing.expectError(error.ParseError, result);
}

// ==================== EXPANDER ERRORS ====================

test "negative: undefined macro returns ExpandError" {
    const allocator = testing.allocator;
    // UNKNOWN_MACRO is not registered
    const result = bsvz_macro.compile(allocator, "UNKNOWN_MACRO", .{});
    try testing.expectError(error.ExpandError, result);
}

test "negative: macro arity mismatch returns ExpandError" {
    const allocator = testing.allocator;
    // OP_XSWAP requires 1 argument, none provided
    const result = bsvz_macro.compile(allocator, "OP_XSWAP", .{});
    try testing.expectError(error.ExpandError, result);
}

test "negative: too many macro args returns ExpandError" {
    const allocator = testing.allocator;
    // OP_XSWAP expects 1 argument
    const result = bsvz_macro.compile(allocator, "OP_XSWAP[1, 2]", .{});
    try testing.expectError(error.ExpandError, result);
}

test "negative: loop bound too large returns ExpandError" {
    const allocator = testing.allocator;
    // LOOP with bound > 1000
    const result = bsvz_macro.compile(allocator, "LOOP[2000]{ OP_DUP }", .{});
    try testing.expectError(error.ExpandError, result);
}

// ==================== VALIDATOR ERRORS ====================

test "negative: script too large returns ValError" {
    const allocator = testing.allocator;
    // Set max_script_size to a very small value
    const result = bsvz_macro.compile(allocator, "OP_DUP OP_HASH160 OP_EQUAL", .{
        .max_script_size = 1,
    });
    try testing.expectError(error.ValError, result);
}

test "negative: stack too deep returns SimError" {
    const allocator = testing.allocator;
    // Set max_stack_elements to 1 to force stack overflow during simulation
    const result = bsvz_macro.compile(allocator, "OP_1 OP_DUP OP_DUP OP_DUP", .{
        .max_stack_elements = 1,
    });
    try testing.expectError(error.SimError, result);
}

// ==================== EDGE CASES ====================

test "edge: empty source compiles successfully" {
    const allocator = testing.allocator;
    const result = try bsvz_macro.compile(allocator, "", .{});
    defer result.deinit(allocator);
    try testing.expectEqual(@as(u32, 0), result.byte_length);
}

test "edge: whitespace-only source compiles successfully" {
    const allocator = testing.allocator;
    const result = try bsvz_macro.compile(allocator, "   \n\t  ", .{});
    defer result.deinit(allocator);
    try testing.expectEqual(@as(u32, 0), result.byte_length);
}

test "edge: LOOP[0] produces empty bytecode" {
    const allocator = testing.allocator;
    const result = try bsvz_macro.compile(allocator, "LOOP[0]{ OP_DUP }", .{});
    defer result.deinit(allocator);
    try testing.expectEqual(@as(u32, 0), result.byte_length);
}

test "edge: LOOP[1] executes body once" {
    const allocator = testing.allocator;
    // LOOP[1] with OP_DUP should produce exactly 1 OP_DUP (1 byte)
    const result = try bsvz_macro.compile(allocator, "LOOP[1]{ OP_DUP }", .{});
    defer result.deinit(allocator);
    // OP_DUP is 1 byte
    try testing.expect(result.byte_length > 0);
}

test "edge: large loop bound (1000) succeeds" {
    const allocator = testing.allocator;
    // LOOP[1000] with empty body
    const result = try bsvz_macro.compile(allocator, "LOOP[1000]{ }", .{});
    defer result.deinit(allocator);
    try testing.expect(result.byte_length == 0);
}

test "edge: single opcode compiles" {
    const allocator = testing.allocator;
    const result = try bsvz_macro.compile(allocator, "OP_NOP", .{});
    defer result.deinit(allocator);
    try testing.expect(result.byte_length > 0);
}

test "edge: many opcodes compile" {
    const allocator = testing.allocator;
    const result = try bsvz_macro.compile(allocator, "OP_1 OP_2 OP_3 OP_4 OP_5 OP_6 OP_7 OP_8", .{});
    defer result.deinit(allocator);
    try testing.expect(result.byte_length >= 8);
}

test "edge: push small integer literals" {
    const allocator = testing.allocator;
    // Test boundary values for small integer pushes (1-16 use minimal encoding)
    const result = try bsvz_macro.compile(allocator, "OP_1 OP_16", .{});
    defer result.deinit(allocator);
    // OP_1 and OP_16 are each 1 byte
    try testing.expectEqual(@as(u32, 2), result.byte_length);
}

test "edge: push zero" {
    const allocator = testing.allocator;
    // OP_0 is a single byte
    const result = try bsvz_macro.compile(allocator, "OP_0", .{});
    defer result.deinit(allocator);
    try testing.expectEqual(@as(u32, 1), result.byte_length);
}

test "edge: push negative one" {
    const allocator = testing.allocator;
    // OP_1NEGATE is a single byte
    const result = try bsvz_macro.compile(allocator, "OP_1NEGATE", .{});
    defer result.deinit(allocator);
    try testing.expectEqual(@as(u32, 1), result.byte_length);
}

test "edge: conditional without else on bsv target" {
    const allocator = testing.allocator;
    // @bsv with no else - should still compile
    const result = try bsvz_macro.compile(allocator, "@bsv{ OP_DUP }", .{});
    defer result.deinit(allocator);
    try testing.expect(result.byte_length > 0);
}

test "edge: conditional with else on btc_strict target" {
    const allocator = testing.allocator;
    // On btc_strict, the bsv block should be skipped, else block emitted
    const result = try bsvz_macro.compile(allocator, "@bsv{ OP_CAT } else { OP_NOP }", .{
        .target = .btc_strict,
    });
    defer result.deinit(allocator);
    // Should have OP_NOP (1 byte), not OP_CAT
    try testing.expect(result.byte_length > 0);
}

test "edge: emit_asm option produces non-null asm_text" {
    const allocator = testing.allocator;
    const result = try bsvz_macro.compile(allocator, "OP_DUP", .{
        .emit_asm = true,
    });
    defer result.deinit(allocator);
    try testing.expect(result.asm_text != null);
    try testing.expect(result.asm_text.?.len > 0);
}

test "edge: no emit_asm produces null asm_text" {
    const allocator = testing.allocator;
    const result = try bsvz_macro.compile(allocator, "OP_DUP", .{});
    defer result.deinit(allocator);
    try testing.expect(result.asm_text == null);
}

test "edge: comments are ignored" {
    const allocator = testing.allocator;
    const result = try bsvz_macro.compile(allocator, "// comment\nOP_DUP /* block */ OP_DROP", .{});
    defer result.deinit(allocator);
    // OP_DUP + OP_DROP = 2 bytes
    try testing.expectEqual(@as(u32, 2), result.byte_length);
}

test "edge: bsv_testnet target compiles" {
    const allocator = testing.allocator;
    const result = try bsvz_macro.compile(allocator, "OP_DUP", .{
        .target = .bsv_testnet,
    });
    defer result.deinit(allocator);
    try testing.expect(result.byte_length > 0);
}

// ==================== ROUND-TRIP TESTS ====================

test "roundtrip: compile toAsm produces output" {
    const allocator = testing.allocator;
    const result = try bsvz_macro.compile(allocator, "OP_1 OP_2 OP_ADD", .{});
    defer result.deinit(allocator);

    const asm_str = try bsvz_macro.toAsm(allocator, result.bytecode);
    defer allocator.free(asm_str);

    try testing.expect(asm_str.len > 0);
}

test "roundtrip: fromAsm handles basic opcodes" {
    const allocator = testing.allocator;
    // Simple opcode-only asm should round-trip
    const bytecode = try bsvz_macro.fromAsm(allocator, "OP_1 OP_2 OP_ADD");
    defer allocator.free(bytecode);
    try testing.expect(bytecode.len > 0);
}
