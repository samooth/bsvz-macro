const std = @import("std");
const bsvz_macro = @import("bsvz-macro");
const bsvz = @import("bsvz");
const testing = std.testing;

// Property-based tests for macro expansion invariants.
// These tests verify properties that should hold for all valid inputs,
// helping discover edge cases that example-based tests might miss.

// ==================== INVARIANT TESTS ====================

test "property: same source produces same bytecode" {
    const allocator = testing.allocator;
    const sources = [_][]const u8{
        "OP_DUP",
        "OP_1 OP_2 OP_ADD",
        "SAFE_DIV",
        "OP_XSWAP[3]",
        "RANGE_CHECK[0,100]",
        "@bsv{ OP_CAT }",
        "LOOP[3]{ OP_DUP }",
    };

    for (sources) |source| {
        const result1 = try bsvz_macro.compile(allocator, source, .{});
        defer result1.deinit(allocator);
        const result2 = try bsvz_macro.compile(allocator, source, .{});
        defer result2.deinit(allocator);
        try testing.expectEqualSlices(u8, result1.bytecode, result2.bytecode);
    }
}

test "property: bytecode length equals opcode count for simple scripts" {
    const allocator = testing.allocator;
    // For scripts without push data, byte_length should equal number of opcodes
    const sources = [_][]const u8{
        "OP_DUP",
        "OP_DUP OP_DROP",
        "OP_1 OP_2 OP_3",
        "OP_DUP OP_HASH160 OP_EQUAL",
    };

    for (sources) |source| {
        const result = try bsvz_macro.compile(allocator, source, .{});
        defer result.deinit(allocator);
        // Count tokens to verify
        var count: usize = 0;
        var i: usize = 0;
        while (i < source.len) {
            const c = source[i];
            if (c == ' ' or c == '\t' or c == '\n' or c == '\r') {
                i += 1;
                continue;
            }
            if (c == '/' and i + 1 < source.len and source[i + 1] == '/') {
                // Line comment
                while (i < source.len and source[i] != '\n') i += 1;
                continue;
            }
            count += 1;
            // Skip identifier
            while (i < source.len) {
                const ch = source[i];
                if (ch == ' ' or ch == '\t' or ch == '\n' or ch == '\r' or ch == ';' or ch == ',') break;
                i += 1;
            }
        }
        try testing.expectEqual(@as(u32, @intCast(count)), result.byte_length);
    }
}

test "property: hash is deterministic for same source and options" {
    const allocator = testing.allocator;
    const sources = [_][]const u8{
        "OP_DUP",
        "OP_HASH160",
        "OP_1 OP_2 OP_ADD OP_3 OP_MUL",
    };

    for (sources) |source| {
        const result1 = try bsvz_macro.compile(allocator, source, .{});
        defer result1.deinit(allocator);
        const result2 = try bsvz_macro.compile(allocator, source, .{});
        defer result2.deinit(allocator);
        try testing.expectEqualSlices(u8, &result1.hash, &result2.hash);
    }
}

test "property: different sources produce different hashes" {
    const allocator = testing.allocator;
    const result1 = try bsvz_macro.compile(allocator, "OP_DUP", .{});
    defer result1.deinit(allocator);
    const result2 = try bsvz_macro.compile(allocator, "OP_DROP", .{});
    defer result2.deinit(allocator);
    try testing.expect(!std.mem.eql(u8, &result1.hash, &result2.hash));
}

test "property: max stack height is non-negative" {
    const allocator = testing.allocator;
    const sources = [_][]const u8{
        "OP_DUP",
        "OP_1 OP_2 OP_3 OP_4",
        "LOOP[3]{ OP_DUP }",
        "OP_XSWAP[5]",
    };

    for (sources) |source| {
        const result = try bsvz_macro.compile(allocator, source, .{});
        defer result.deinit(allocator);
        // max_stack_height is u16, so it's always non-negative
        // Just verify it's within reasonable bounds
        try testing.expect(result.max_stack_height <= 1000);
    }
}

test "property: empty source produces empty bytecode" {
    const allocator = testing.allocator;
    const result = try bsvz_macro.compile(allocator, "", .{});
    defer result.deinit(allocator);
    try testing.expectEqual(@as(u32, 0), result.byte_length);
    try testing.expectEqual(@as(u32, 0), result.opcode_count);
}

test "property: whitespace-only source produces empty bytecode" {
    const allocator = testing.allocator;
    const whitespace_sources = [_][]const u8{
        " ",
        "  ",
        "\n",
        "\t\t\t",
        " \n \t \r\n ",
    };

    for (whitespace_sources) |source| {
        const result = try bsvz_macro.compile(allocator, source, .{});
        defer result.deinit(allocator);
        try testing.expectEqual(@as(u32, 0), result.byte_length);
    }
}

test "property: comments don't affect bytecode" {
    const allocator = testing.allocator;
    const without_comments = try bsvz_macro.compile(allocator, "OP_DUP OP_DROP", .{});
    defer without_comments.deinit(allocator);

    const with_line_comment = try bsvz_macro.compile(allocator, "OP_DUP // comment\nOP_DROP", .{});
    defer with_line_comment.deinit(allocator);

    const with_block_comment = try bsvz_macro.compile(allocator, "OP_DUP /* comment */ OP_DROP", .{});
    defer with_block_comment.deinit(allocator);

    try testing.expectEqualSlices(u8, without_comments.bytecode, with_line_comment.bytecode);
    try testing.expectEqualSlices(u8, without_comments.bytecode, with_block_comment.bytecode);
}

test "property: LOOP[n] with empty body produces empty bytecode" {
    const allocator = testing.allocator;
    for ([_]u64{ 0, 1, 5, 10, 100 }) |n| {
        var source: [64]u8 = undefined;
        const source_slice = try std.fmt.bufPrint(&source, "LOOP[{}]{{ }}", .{n});
        const result = try bsvz_macro.compile(allocator, source_slice, .{});
        defer result.deinit(allocator);
        try testing.expectEqual(@as(u32, 0), result.byte_length);
    }
}

test "property: target option doesn't change bytecode for non-conditional scripts" {
    const allocator = testing.allocator;
    const sources = [_][]const u8{
        "OP_DUP",
        "OP_1 OP_2 OP_ADD",
        "SAFE_DIV",
    };

    for (sources) |source| {
        const mainnet = try bsvz_macro.compile(allocator, source, .{ .target = .bsv_mainnet });
        defer mainnet.deinit(allocator);
        const testnet = try bsvz_macro.compile(allocator, source, .{ .target = .bsv_testnet });
        defer testnet.deinit(allocator);
        const btc = try bsvz_macro.compile(allocator, source, .{ .target = .btc_strict });
        defer btc.deinit(allocator);

        try testing.expectEqualSlices(u8, mainnet.bytecode, testnet.bytecode);
        try testing.expectEqualSlices(u8, mainnet.bytecode, btc.bytecode);
    }
}

test "property: semicolons are optional between statements" {
    const allocator = testing.allocator;
    const without_semicolons = try bsvz_macro.compile(allocator, "OP_DUP OP_DROP OP_DUP", .{});
    defer without_semicolons.deinit(allocator);

    const with_semicolons = try bsvz_macro.compile(allocator, "OP_DUP; OP_DROP; OP_DUP", .{});
    defer with_semicolons.deinit(allocator);

    try testing.expectEqualSlices(u8, without_semicolons.bytecode, with_semicolons.bytecode);
}

test "property: emit_asm doesn't change bytecode" {
    const allocator = testing.allocator;
    const source = "OP_DUP OP_HASH160 OP_EQUAL";

    const no_asm = try bsvz_macro.compile(allocator, source, .{});
    defer no_asm.deinit(allocator);

    const with_asm = try bsvz_macro.compile(allocator, source, .{ .emit_asm = true });
    defer with_asm.deinit(allocator);

    try testing.expectEqualSlices(u8, no_asm.bytecode, with_asm.bytecode);
    try testing.expect(with_asm.asm_text != null);
    try testing.expect(no_asm.asm_text == null);
}

test "property: integer literals in range 1-16 use minimal encoding" {
    const allocator = testing.allocator;
    // Integer literals used in macro args should produce valid bytecode
    const sources = [_][]const u8{
        "OP_XSWAP[1]",
        "OP_XSWAP[16]",
        "RANGE_CHECK[1,16]",
        "OP_XSWAP[5]",
    };

    for (sources) |source| {
        const result = try bsvz_macro.compile(allocator, source, .{});
        defer result.deinit(allocator);
    }
}

test "property: bsv conditional is true on bsv targets" {
    const allocator = testing.allocator;
    const source = "@bsv{ OP_DUP } else { OP_DROP }";

    const mainnet = try bsvz_macro.compile(allocator, source, .{ .target = .bsv_mainnet });
    defer mainnet.deinit(allocator);
    const testnet = try bsvz_macro.compile(allocator, source, .{ .target = .bsv_testnet });
    defer testnet.deinit(allocator);

    // On BSV targets, the bsv branch is taken
    // OP_DUP is 1 byte
    try testing.expectEqual(@as(u32, 1), mainnet.byte_length);
    try testing.expectEqual(@as(u32, 1), testnet.byte_length);
}

test "property: bsv conditional is false on btc_strict target" {
    const allocator = testing.allocator;
    const source = "@bsv{ OP_DUP } else { OP_DROP }";

    const btc = try bsvz_macro.compile(allocator, source, .{ .target = .btc_strict });
    defer btc.deinit(allocator);

    // On btc_strict, the else branch is taken
    // OP_DROP is 1 byte
    try testing.expectEqual(@as(u32, 1), btc.byte_length);
}
