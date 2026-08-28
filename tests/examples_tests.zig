const std = @import("std");
const bsvz_macro = @import("bsvz-macro");
const bsv = @import("bsvz");

const testing = std.testing;
const helpers = @import("helpers.zig");
const test_data = @import("test_data.zig");

// Example tests using the helper utilities to demonstrate their value.
// These replace common boilerplate patterns with concise helper calls.

test "examples: compile and verify using helpers" {
    const allocator = testing.allocator;

    // Instead of repeating compile + deinit + assertions in every test,
    // use the helper functions:
    try helpers.expectBytecodeLength(allocator, "OP_DUP OP_DROP", 2);
    try helpers.expectNonEmptyBytecode(allocator, "OP_HASH160");
    try helpers.expectMaxStack(allocator, "OP_1 OP_2 OP_ADD", 2);
    try helpers.expectStandard(allocator, "OP_DUP");
    try helpers.expectDeterministicHash(allocator, "OP_DUP OP_HASH160");
}

test "examples: error cases using helpers" {
    const allocator = testing.allocator;

    // Error cases are also concise:
    try helpers.compileExpectError(allocator, "UNKNOWN_MACRO", error.ExpandError);
    try helpers.compileExpectError(allocator, "OP_XSWAP", error.ExpandError);
    try helpers.compileExpectError(allocator, "LOOP[2000]{ OP_DUP }", error.ExpandError);
}

test "examples: script builder for complex sources" {
    const allocator = testing.allocator;

    // Build a script string using the builder
    var builder = test_data.ScriptBuilder.init(allocator);
    defer builder.deinit();

    try builder.addOpcode(bsv.script.opcode.Opcode.OP_DUP);
    try builder.addOpcode(bsv.script.opcode.Opcode.OP_HASH160);
    try builder.addOpcode(bsv.script.opcode.Opcode.OP_EQUAL);

    const source = try builder.build();
    defer allocator.free(source);

    const result = try bsvz_macro.compile(allocator, source, .{});
    defer result.deinit(allocator);

    // OP_DUP + OP_HASH160 + OP_EQUAL = 3 bytes
    try testing.expectEqual(@as(u32, 3), result.byte_length);
}

test "examples: loop macro with builder" {
    const allocator = testing.allocator;

    var builder = test_data.ScriptBuilder.init(allocator);
    defer builder.deinit();

    try builder.addRaw("LOOP[3]{ ");
    try builder.addOpcode(bsv.script.opcode.Opcode.OP_DUP);
    try builder.addRaw(" }");

    const source = try builder.build();
    defer allocator.free(source);

    const result = try bsvz_macro.compile(allocator, source, .{});
    defer result.deinit(allocator);

    try testing.expect(result.byte_length > 0);
}

test "examples: conditional macro with builder" {
    const allocator = testing.allocator;

    var builder = test_data.ScriptBuilder.init(allocator);
    defer builder.deinit();

    try builder.addRaw("@bsv{ ");
    try builder.addOpcode(bsv.script.opcode.Opcode.OP_CAT);
    try builder.addRaw(" } else { ");
    try builder.addOpcode(bsv.script.opcode.Opcode.OP_NOP);
    try builder.addRaw(" }");

    const source = try builder.build();
    defer allocator.free(source);

    const result = try bsvz_macro.compile(allocator, source, .{
        .target = .btc_strict,
    });
    defer result.deinit(allocator);

    // On btc_strict, the else branch (OP_NOP) is emitted
    try testing.expect(result.byte_length > 0);
}

test "examples: repeated assertion pattern" {
    const allocator = testing.allocator;

    // Demonstrate that helper reduces repetition for multiple assertions
    const sources = [_][]const u8{
        "OP_DUP",
        "OP_DROP",
        "OP_HASH160",
        "OP_1NEGATE",
    };

    for (sources) |source| {
        try helpers.expectNonEmptyBytecode(allocator, source);
    }
}
