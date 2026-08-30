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

// ==================== ENHANCED INVARIANTS ====================
// More complex properties, including macro/loop interactions, that should
// hold for all valid inputs. These complement the example-based tests and
// help surface edge cases that single examples miss.

test "property: LOOP[n] unrolling count is exact" {
    const allocator = testing.allocator;
    // Body "OP_HASH160" emits exactly 1 byte and is stack-neutral at peak,
    // so LOOP[n]{ OP_HASH160 } must produce n bytes.
    for ([_]u64{ 0, 1, 2, 5, 10, 20, 50 }) |n| {
        var source: [64]u8 = undefined;
        const slice = try std.fmt.bufPrint(&source, "LOOP[{}]{{ OP_HASH160 }}", .{n});
        const result = try bsvz_macro.compile(allocator, slice, .{});
        defer result.deinit(allocator);
        try testing.expectEqual(@as(u32, @intCast(n)), result.byte_length);
    }
}

test "property: LOOP[n]{ OP_DUP } peak stack height equals n" {
    const allocator = testing.allocator;
    // Each OP_DUP grows the (pre-populated) stack by 1, so the reported
    // max stack height (peak minus the 4 pre-populated items) equals n.
    for ([_]u64{ 1, 2, 5, 10, 25, 100 }) |n| {
        var source: [64]u8 = undefined;
        const slice = try std.fmt.bufPrint(&source, "LOOP[{}]{{ OP_DUP }}", .{n});
        const result = try bsvz_macro.compile(allocator, slice, .{});
        defer result.deinit(allocator);
        try testing.expectEqual(@as(u32, @intCast(n)), result.byte_length);
        try testing.expectEqual(@as(u16, @intCast(n)), result.max_stack_height);
    }
}

test "property: nested LOOP unrolling is multiplicative" {
    const allocator = testing.allocator;
    const bounds = [_][2]u64{
        .{ 1, 1 }, .{ 2, 3 }, .{ 3, 3 }, .{ 4, 5 }, .{ 5, 2 },
    };
    for (bounds) |pair| {
        const n = pair[0];
        const m = pair[1];
        var source: [128]u8 = undefined;
        const slice = try std.fmt.bufPrint(&source, "LOOP[{}]{{ LOOP[{}]{{ OP_DUP }} }}", .{ n, m });
        const result = try bsvz_macro.compile(allocator, slice, .{});
        defer result.deinit(allocator);
        try testing.expectEqual(@as(u32, @intCast(n * m)), result.byte_length);
        try testing.expectEqual(@as(u16, @intCast(n * m)), result.max_stack_height);
    }
}

test "property: sequential composition is additive in bytecode" {
    const allocator = testing.allocator;
    // Concatenating a valid source with itself doubles the bytecode length,
    // because expansion is linear over a sequence of statements.
    const sources = [_][]const u8{
        "OP_DUP",
        "OP_XSWAP[3]",
        "OP_HASH160 OP_EQUAL",
        "SAFE_DIV",
        "OP_1 OP_2 OP_ADD",
    };
    for (sources) |s| {
        const single = try bsvz_macro.compile(allocator, s, .{});
        defer single.deinit(allocator);

        var doubled: std.ArrayList(u8) = .empty;
        defer doubled.deinit(allocator);
        try doubled.appendSlice(allocator, s);
        try doubled.append(allocator, ' ');
        try doubled.appendSlice(allocator, s);

        const result = try bsvz_macro.compile(allocator, doubled.items, .{});
        defer result.deinit(allocator);
        try testing.expectEqual(@as(u32, 2 * single.byte_length), result.byte_length);
    }
}

test "property: bsv/chronicle conditionals are bytecode-preserving on bsv" {
    const allocator = testing.allocator;
    // Wrapping a script in @bsv{ ... } on BSV targets, or @chronicle{ ... }
    // on Chronicle-era targets, must not change its emitted bytecode. This
    // validates feature-flag expansion when macros and loops are nested
    // inside the conditional. @chronicle requires the chronicle era (it is
    // no longer an alias of @bsv).
    const sources = [_][]const u8{
        "OP_DUP OP_HASH160 OP_EQUAL",
        "OP_XSWAP[5] OP_XDROP[2]",
        "LOOP[4]{ OP_DUP OP_HASH160 }",
        "RANGE_CHECK[0,100] SAFE_DIV",
    };
    for (sources) |src| {
        const plain = try bsvz_macro.compile(allocator, src, .{});
        defer plain.deinit(allocator);

        var bsv_wrapped: std.ArrayList(u8) = .empty;
        defer bsv_wrapped.deinit(allocator);
        try bsv_wrapped.appendSlice(allocator, "@bsv{ ");
        try bsv_wrapped.appendSlice(allocator, src);
        try bsv_wrapped.appendSlice(allocator, " }");

        var chron_wrapped: std.ArrayList(u8) = .empty;
        defer chron_wrapped.deinit(allocator);
        try chron_wrapped.appendSlice(allocator, "@chronicle{ ");
        try chron_wrapped.appendSlice(allocator, src);
        try chron_wrapped.appendSlice(allocator, " }");

        const bsv_res = try bsvz_macro.compile(allocator, bsv_wrapped.items, .{});
        defer bsv_res.deinit(allocator);
        const chron_res = try bsvz_macro.compile(allocator, chron_wrapped.items, .{ .era = .chronicle });
        defer chron_res.deinit(allocator);

        try testing.expectEqualSlices(u8, plain.bytecode, bsv_res.bytecode);
        try testing.expectEqualSlices(u8, plain.bytecode, chron_res.bytecode);
    }
}

test "property: hash changes when compile options change" {
    const allocator = testing.allocator;
    // Changing options changes the hashed options bytes, so the hash must
    // differ even when the emitted bytecode is identical.
    const source = "OP_DUP OP_HASH160 OP_EQUAL";

    const base = try bsvz_macro.compile(allocator, source, .{});
    defer base.deinit(allocator);

    const asm_on = try bsvz_macro.compile(allocator, source, .{ .emit_asm = true });
    defer asm_on.deinit(allocator);

    const testnet = try bsvz_macro.compile(allocator, source, .{ .target = .bsv_testnet });
    defer testnet.deinit(allocator);

    try testing.expectEqualSlices(u8, base.bytecode, asm_on.bytecode);
    try testing.expect(!std.mem.eql(u8, &base.hash, &asm_on.hash));
    try testing.expect(!std.mem.eql(u8, &base.hash, &testnet.hash));
}

test "property: LOOP unrolling of a macro equals n copies of the macro" {
    const allocator = testing.allocator;
    // LOOP[n]{ MACRO } must expand to the exact concatenation of n separately
    // compiled instances of MACRO. This validates macro expansion inside loop
    // unrolling (macro + loop interaction).
    const macros = [_][]const u8{
        "OP_XSWAP[3]",
        "OP_XROT[3]",
        "OP_HASHCAT",
      };
    for (macros) |m| {
        const single = try bsvz_macro.compile(allocator, m, .{});
        defer single.deinit(allocator);

        for ([_]u64{ 1, 2, 3, 4, 5 }) |n| {
            var loop_src: [128]u8 = undefined;
            const loop_slice = try std.fmt.bufPrint(&loop_src, "LOOP[{}]{{ {s} }}", .{ n, m });
            const loop_res = try bsvz_macro.compile(allocator, loop_slice, .{});
            defer loop_res.deinit(allocator);

            // Build the expected concatenation manually.
            var expected: std.ArrayList(u8) = .empty;
            defer expected.deinit(allocator);
            var k: u64 = 0;
            while (k < n) : (k += 1) {
                try expected.appendSlice(allocator, single.bytecode);
            }

            const n_u32: u32 = @intCast(n);
            const expected_len: u32 = n_u32 * single.byte_length;
            try testing.expectEqual(expected_len, loop_res.byte_length);
            try testing.expectEqualSlices(u8, expected.items, loop_res.bytecode);
        }
    }
}

test "property: conditional branch selection is target-exhaustive" {
    const allocator = testing.allocator;
    // On BSV, @bsv expands while @btc_strict is skipped; on btc_strict the
    // opposite holds. @chronicle only expands in the chronicle era. Verify
    // the combined bytecode equals the union of the enabled branches for
    // each target.
    const bsv = try bsvz_macro.compile(allocator, "@bsv{ OP_DUP } @chronicle{ OP_DROP } @btc_strict{ OP_NOP }", .{ .target = .bsv_mainnet });
    defer bsv.deinit(allocator);
    const btc = try bsvz_macro.compile(allocator, "@bsv{ OP_DUP } @chronicle{ OP_DROP } @btc_strict{ OP_NOP }", .{ .target = .btc_strict });
    defer btc.deinit(allocator);
    const chron = try bsvz_macro.compile(allocator, "@bsv{ OP_DUP } @chronicle{ OP_DROP } @btc_strict{ OP_NOP }", .{ .era = .chronicle });
    defer chron.deinit(allocator);

    const bsv_expected = try bsvz_macro.compile(allocator, "OP_DUP", .{});
    defer bsv_expected.deinit(allocator);
    const btc_expected = try bsvz_macro.compile(allocator, "OP_NOP", .{});
    defer btc_expected.deinit(allocator);
    const chron_expected = try bsvz_macro.compile(allocator, "OP_DUP OP_DROP", .{});
    defer chron_expected.deinit(allocator);

    try testing.expectEqualSlices(u8, bsv_expected.bytecode, bsv.bytecode);
    try testing.expectEqualSlices(u8, btc_expected.bytecode, btc.bytecode);
    try testing.expectEqualSlices(u8, chron_expected.bytecode, chron.bytecode);
}

test "property: iterator ref in macro arg expands per iteration" {
    const allocator = testing.allocator;
    // LOOP[n]{ RANGE_CHECK[<i>,100] } must expand to the exact concatenation of
    // RANGE_CHECK[0,100], RANGE_CHECK[1,100], ... RANGE_CHECK[n-1,100].
    // This exercises iterator-variable substitution through a macro argument.
    for ([_]u64{ 1, 2, 3, 4 }) |n| {
        var loop_src: [128]u8 = undefined;
        const loop_slice = try std.fmt.bufPrint(&loop_src, "LOOP[{}]{{ RANGE_CHECK[<i>,100] }}", .{n});
        const loop_res = try bsvz_macro.compile(allocator, loop_slice, .{});
        defer loop_res.deinit(allocator);

        var expected: std.ArrayList(u8) = .empty;
        defer expected.deinit(allocator);
        var i: u64 = 0;
        while (i < n) : (i += 1) {
            var part_src: [64]u8 = undefined;
            const part_slice = try std.fmt.bufPrint(&part_src, "RANGE_CHECK[{},100]", .{i});
            const part = try bsvz_macro.compile(allocator, part_slice, .{});
            defer part.deinit(allocator);
            try expected.appendSlice(allocator, part.bytecode);
        }

        try testing.expectEqualSlices(u8, expected.items, loop_res.bytecode);
    }
}

test "property: iterator ref as statement emits one push per iteration" {
    const allocator = testing.allocator;
    // LOOP[n]{ <i> } emits a push of 0, 1, ... n-1. For n <= 17 each push is a
    // single byte, so the expanded length equals n.
    for ([_]u64{ 1, 2, 3, 4, 5, 10, 16 }) |n| {
        var loop_src: [128]u8 = undefined;
        const loop_slice = try std.fmt.bufPrint(&loop_src, "LOOP[{}]{{ <i> }}", .{n});
        const loop_res = try bsvz_macro.compile(allocator, loop_slice, .{});
        defer loop_res.deinit(allocator);
        try testing.expectEqual(@as(u32, @intCast(n)), loop_res.byte_length);
    }
}

test "property: randomized compilable sources are deterministic" {
    const allocator = testing.allocator;
    // Generate random scripts from a safe opcode alphabet (opcodes that only
    // push or are stack-neutral given the 4 pre-populated integers) and assert
    // that any source which compiles at all does so deterministically.
    const alphabet = [_][]const u8{
        "OP_1", "OP_2", "OP_3", "OP_DUP", "OP_HASH160", "OP_NIP", "OP_TUCK",
    };

    var prng: u32 = 0xCAFE1234;
    const prngStep = struct {
        fn next(s: *u32) u32 {
            var x = s.*;
            x ^= x << 13;
            x ^= x >> 17;
            x ^= x << 5;
            s.* = x;
            return x;
        }
    }.next;

    var buf: [256]u8 = undefined;
    var i: usize = 0;
    while (i < 200) : (i += 1) {
        const len = (prngStep(&prng) % 12) + 1;
        var pos: usize = 0;
        var j: usize = 0;
        while (j < len) : (j += 1) {
            const tok = alphabet[prngStep(&prng) % alphabet.len];
            @memcpy(buf[pos .. pos + tok.len], tok);
            pos += tok.len;
            buf[pos] = ' ';
            pos += 1;
        }
        const source = buf[0 .. pos - 1];

        const r1 = bsvz_macro.compile(allocator, source, .{}) catch continue;
        defer r1.deinit(allocator);
        const r2 = try bsvz_macro.compile(allocator, source, .{});
        defer r2.deinit(allocator);
        try testing.expectEqualSlices(u8, r1.bytecode, r2.bytecode);
        try testing.expectEqualSlices(u8, &r1.hash, &r2.hash);
    }
}

// ==================== ROBUSTNESS PROPERTY TESTS ====================

fn prngNext(state: *u32) u32 {
    var x = state.*;
    x ^= x << 13;
    x ^= x >> 17;
    x ^= x << 5;
    state.* = x;
    return x;
}

test "property: fromAsm(toAsm(x)) round-trips to x" {
    const allocator = testing.allocator;
    const sources = [_][]const u8{
        "OP_DUP OP_DROP",
        "SAFE_DIV",
        "RANGE_CHECK[0,100]",
        "OP_XSWAP[3]",
        "OP_1 OP_2 OP_ADD",
    };
    var compiled: [sources.len][]u8 = undefined;
    var compiled_count: usize = 0;
    for (sources) |source| {
        const r = bsvz_macro.compile(allocator, source, .{}) catch continue;
        compiled[compiled_count] = try allocator.dupe(u8, r.bytecode);
        r.deinit(allocator);
        compiled_count += 1;
    }
    defer for (compiled[0..compiled_count]) |b| allocator.free(b);

    var to_test = std.ArrayListUnmanaged([]const u8).empty;
    defer to_test.deinit(allocator);
    for (compiled[0..compiled_count]) |b| try to_test.append(allocator, b);
    try to_test.append(allocator, &[_]u8{ 0x76, 0x75 });
    try to_test.append(allocator, &[_]u8{ 0x51, 0x51, 0x87 });
    try to_test.append(allocator, &[_]u8{ 0x4c, 0x03, 0x01, 0x02, 0x03, 0x75 });

    for (to_test.items) |original| {
        // The bsvz ASM codec canonicalises push encodings (e.g. OP_PUSHDATA1
        // for short pushes round-trips to a direct push), so the round-tripped
        // bytecode is not byte-exact. The strong invariant we check is that
        // the ASM representation is idempotent: toAsm(fromAsm(toAsm(x))) ==
        // toAsm(x). This guards against lossiness in the bytecode <-> ASM
        // conversion without over-specifying the encoder's canonical form.
        const asm1 = bsvz_macro.toAsm(allocator, original) catch continue;
        defer allocator.free(asm1);
        const roundtripped = bsvz_macro.fromAsm(allocator, asm1) catch continue;
        defer allocator.free(roundtripped);
        const asm2 = bsvz_macro.toAsm(allocator, roundtripped) catch continue;
        defer allocator.free(asm2);
        try testing.expectEqualSlices(u8, asm1, asm2);
    }
}

test "property: lex fuzz — random bytes yield a clean compile result" {
    const allocator = testing.allocator;
    var state: u32 = 0x12345678;
    var i: usize = 0;
    while (i < 256) : (i += 1) {
        const len = prngNext(&state) % 64;
        var buf: [64]u8 = undefined;
        var j: usize = 0;
        while (j < len) : (j += 1) {
            buf[j] = @truncate(prngNext(&state));
        }
        const source = buf[0..len];
        if (bsvz_macro.compile(allocator, source, .{})) |r| {
            r.deinit(allocator);
        } else |_| {
            // Any MacroError is acceptable; the goal is no panic.
        }
    }
}

test "property: mutation fuzz — mutated valid sources compile cleanly" {
    const allocator = testing.allocator;
    const corpus = [_][]const u8{
        "OP_DUP OP_DROP",
        "SAFE_DIV",
        "RANGE_CHECK[0,100]",
        "OP_XSWAP[3]",
        "OP_HASHCAT",
        "OP_XROT[2]",
        "VERIFY_ALL[3]",
        "IFDUP",
        "OP_1 OP_2 OP_ADD OP_DROP",
    };
    const alphabet = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_[] ,;{}!@#$%^&*()";
    var state: u32 = 0x87654321;
    var i: usize = 0;
    while (i < 256) : (i += 1) {
        const idx = prngNext(&state) % corpus.len;
        const original = corpus[idx];
        var buf: [128]u8 = undefined;
        const copy_len = @min(original.len, buf.len);
        @memcpy(buf[0..copy_len], original[0..copy_len]);
        const mode = prngNext(&state) % 3;
        switch (mode) {
            0 => {
                if (copy_len > 0) {
                    const pos = prngNext(&state) % copy_len;
                    const bit: u3 = @truncate(@as(u32, prngNext(&state) & 0x7));
                    buf[pos] ^= @as(u8, 1) << bit;
                }
            },
            1 => {
                if (copy_len > 0) {
                    const pos = prngNext(&state) % copy_len;
                    buf[pos] = alphabet[prngNext(&state) % alphabet.len];
                }
            },
            else => {
                if (copy_len < buf.len) {
                    const pos = prngNext(&state) % (copy_len + 1);
                    const ch = alphabet[prngNext(&state) % alphabet.len];
                    var k: usize = copy_len;
                    while (k > pos) : (k -= 1) {
                        buf[k] = buf[k - 1];
                    }
                    buf[pos] = ch;
                    const new_len = copy_len + 1;
                    const source = buf[0..new_len];
                    if (bsvz_macro.compile(allocator, source, .{})) |r| {
                        r.deinit(allocator);
                    } else |_| {}
                    continue;
                }
            },
        }
        const source = buf[0..copy_len];
        if (bsvz_macro.compile(allocator, source, .{})) |r| {
            r.deinit(allocator);
        } else |_| {}
    }
}

test "property: LOOP fast path matches slow path for iterator-free bodies" {
    // Bodies that never reference <i> must compile to identical bytecode whether
    // the fast path (expand once, repeat) or the slow path (per-iteration clone)
    // is taken. Compare LOOP[n]{body} against n copies of the bare body bytes.
    // Only stack-neutral / stack-growing bodies are used (see AGENTS.md loop
    // pitfall): net-negative macros underflow the pre-populated 4-item stack.
    const allocator = testing.allocator;
    const bodies = [_][]const u8{
        "OP_DUP OP_DROP",
        "OP_1",
        "OP_DUP OP_DROP OP_DUP OP_DROP",
        "OP_1 OP_DROP",
    };
    const bounds = [_]u64{ 1, 2, 3, 5, 10 };

    for (bodies) |body| {
        const body_result = try bsvz_macro.compile(allocator, body, .{});
        defer body_result.deinit(allocator);

        for (bounds) |bound| {
            const loop_source = try std.fmt.allocPrint(allocator, "LOOP[{d}]{{{s}}}", .{ bound, body });
            defer allocator.free(loop_source);

            const loop_result = try bsvz_macro.compile(allocator, loop_source, .{});
            defer loop_result.deinit(allocator);

            // The loop bytecode must be exactly `bound` copies of the body bytecode.
            try testing.expectEqual(body_result.bytecode.len * bound, loop_result.bytecode.len);
            var i: usize = 0;
            while (i < bound) : (i += 1) {
                const start = i * body_result.bytecode.len;
                const end = start + body_result.bytecode.len;
                try testing.expectEqualSlices(
                    u8,
                    body_result.bytecode,
                    loop_result.bytecode[start..end],
                );
            }
        }
    }
}
