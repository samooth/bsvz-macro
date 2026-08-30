const std = @import("std");
const bsvz_macro = @import("bsvz-macro");

const testing = std.testing;

test "flags: @era selects then branch in matching era" {
    const allocator = testing.allocator;
    const source = "@era(chronicle){ OP_LSHIFTNUM } else { OP_NOP }";

    const chronicle = try bsvz_macro.compile(allocator, source, .{ .era = .chronicle });
    defer chronicle.deinit(allocator);
    try testing.expectEqual(@as(u32, 1), chronicle.byte_length);

    const genesis = try bsvz_macro.compile(allocator, source, .{ .era = .genesis });
    defer genesis.deinit(allocator);
    try testing.expectEqual(@as(u32, 1), genesis.byte_length);

    const bsv_era = try bsvz_macro.compile(allocator, source, .{ .era = .bsv_pre_genesis });
    defer bsv_era.deinit(allocator);
    try testing.expectEqualSlices(u8, genesis.bytecode, bsv_era.bytecode);
}

test "flags: @has(cat) tracks era feature derivation" {
    const allocator = testing.allocator;
    const source = "@has(cat){ OP_CAT } else { OP_NOP }";

    const chronicle = try bsvz_macro.compile(allocator, source, .{ .era = .chronicle });
    defer chronicle.deinit(allocator);
    try testing.expectEqual(@as(u8, 0x7e), chronicle.bytecode[0]);

    const bip = try bsvz_macro.compile(allocator, source, .{ .era = .bip });
    defer bip.deinit(allocator);
    try testing.expectEqual(@as(u8, 0x61), bip.bytecode[0]);

    const satoshi = try bsvz_macro.compile(allocator, source, .{ .era = .satoshi });
    defer satoshi.deinit(allocator);
    try testing.expectEqualSlices(u8, bip.bytecode, satoshi.bytecode);
}

test "flags: @has(mul) is genesis-only" {
    const allocator = testing.allocator;
    const source = "@has(mul){ OP_MUL } else { OP_NOP }";

    const genesis = try bsvz_macro.compile(allocator, source, .{ .era = .genesis });
    defer genesis.deinit(allocator);
    try testing.expectEqual(@as(u8, 0x95), genesis.bytecode[0]);

    const pre = try bsvz_macro.compile(allocator, source, .{ .era = .bsv_pre_genesis });
    defer pre.deinit(allocator);
    try testing.expectEqual(@as(u8, 0x61), pre.bytecode[0]);
}

test "flags: @has(unknown) parses and evaluates false with warning" {
    const allocator = testing.allocator;
    var diags = bsvz_macro.DiagnosticList.init(allocator);
    defer diags.deinit();

    const result = try bsvz_macro.compileWithDiagnostics(
        allocator,
        "@has(nonexistent){ OP_DUP } else { OP_DROP }",
        .{},
        &diags,
    );
    defer result.deinit(allocator);

    try testing.expectEqualSlices(u8, &[_]u8{0x75}, result.bytecode);

    var warn_count: usize = 0;
    for (diags.items.items) |d| {
        if (d.severity == .warning) warn_count += 1;
    }
    try testing.expect(warn_count >= 1);
}

test "flags: @has(lshiftnum) requires chronicle era" {
    const allocator = testing.allocator;
    const source = "@has(lshiftnum){ OP_LSHIFTNUM } else { OP_NOP }";

    const chronicle = try bsvz_macro.compile(allocator, source, .{ .era = .chronicle });
    defer chronicle.deinit(allocator);
    const chronicle_expected = try bsvz_macro.compile(allocator, "OP_LSHIFTNUM", .{});
    defer chronicle_expected.deinit(allocator);
    try testing.expectEqualSlices(u8, chronicle_expected.bytecode, chronicle.bytecode);

    const genesis = try bsvz_macro.compile(allocator, source, .{ .era = .genesis });
    defer genesis.deinit(allocator);
    const genesis_expected = try bsvz_macro.compile(allocator, "OP_NOP", .{});
    defer genesis_expected.deinit(allocator);
    try testing.expectEqualSlices(u8, genesis_expected.bytecode, genesis.bytecode);
}

test "flags: @limit(push, 520) reflects effective push limit" {
    const allocator = testing.allocator;
    const source = "@limit(push, 520){ OP_DUP } else { OP_DROP }";

    const default_opts = try bsvz_macro.compile(allocator, source, .{});
    defer default_opts.deinit(allocator);
    try testing.expectEqualSlices(u8, &[_]u8{0x76}, default_opts.bytecode);

    const bigger = try bsvz_macro.compile(allocator, source, .{ .limits = .{ .push = 1_000_000 } });
    defer bigger.deinit(allocator);
    try testing.expectEqualSlices(u8, &[_]u8{0x76}, bigger.bytecode);

    const smaller = try bsvz_macro.compile(allocator, source, .{ .limits = .{ .push = 100 } });
    defer smaller.deinit(allocator);
    try testing.expectEqualSlices(u8, &[_]u8{0x75}, smaller.bytecode);
}

test "flags: @limit honors suffixed magnitudes" {
    const allocator = testing.allocator;
    const source = "@limit(push, 32MB){ OP_DUP } else { OP_DROP }";

    const chronicle = try bsvz_macro.compile(allocator, source, .{ .limits = .{ .push = 32_000_000 } });
    defer chronicle.deinit(allocator);
    try testing.expectEqualSlices(u8, &[_]u8{0x76}, chronicle.bytecode);

    const default_opts = try bsvz_macro.compile(allocator, source, .{});
    defer default_opts.deinit(allocator);
    try testing.expectEqualSlices(u8, &[_]u8{0x75}, default_opts.bytecode);
}

test "flags: @limit(stack, ...) reflects effective stack limit" {
    const allocator = testing.allocator;
    const source = "@limit(stack, 1000){ OP_DUP } else { OP_DROP }";

    const default_opts = try bsvz_macro.compile(allocator, source, .{});
    defer default_opts.deinit(allocator);
    try testing.expectEqualSlices(u8, &[_]u8{0x76}, default_opts.bytecode);

    const tiny = try bsvz_macro.compile(allocator, source, .{ .limits = .{ .stack = 100 } });
    defer tiny.deinit(allocator);
    try testing.expectEqualSlices(u8, &[_]u8{0x75}, tiny.bytecode);
}

test "flags: @network matches effective network" {
    const allocator = testing.allocator;
    const source = "@network(bsv_mainnet){ OP_DUP } else { OP_DROP }";

    const bsv = try bsvz_macro.compile(allocator, source, .{ .network = .bsv_mainnet });
    defer bsv.deinit(allocator);
    try testing.expectEqualSlices(u8, &[_]u8{0x76}, bsv.bytecode);

    const btc = try bsvz_macro.compile(allocator, source, .{ .network = .btc_mainnet });
    defer btc.deinit(allocator);
    try testing.expectEqualSlices(u8, &[_]u8{0x75}, btc.bytecode);

    const legacy = try bsvz_macro.compile(allocator, source, .{ .target = .bsv_mainnet });
    defer legacy.deinit(allocator);
    try testing.expectEqualSlices(u8, &[_]u8{0x76}, legacy.bytecode);
}

test "flags: @network legacy target normalization" {
    const allocator = testing.allocator;
    const source = "@network(btc_mainnet){ OP_DUP } else { OP_DROP }";

    const legacy_btc = try bsvz_macro.compile(allocator, source, .{ .target = .btc_strict });
    defer legacy_btc.deinit(allocator);
    try testing.expectEqualSlices(u8, &[_]u8{0x76}, legacy_btc.bytecode);
}

test "flags: @standardness reads CompileOptions.standardness" {
    const allocator = testing.allocator;
    const source = "@standardness(cleanstack){ OP_DUP } else { OP_DROP }";

    const default_opts = try bsvz_macro.compile(allocator, source, .{});
    defer default_opts.deinit(allocator);
    try testing.expectEqualSlices(u8, &[_]u8{0x76}, default_opts.bytecode);

    const off = try bsvz_macro.compile(allocator, source, .{ .standardness = .{ .cleanstack = false } });
    defer off.deinit(allocator);
    try testing.expectEqualSlices(u8, &[_]u8{0x75}, off.bytecode);
}

test "flags: @standardness(unknown) warns and evaluates false" {
    const allocator = testing.allocator;
    var diags = bsvz_macro.DiagnosticList.init(allocator);
    defer diags.deinit();

    const result = try bsvz_macro.compileWithDiagnostics(
        allocator,
        "@standardness(nonexistent){ OP_DUP } else { OP_DROP }",
        .{},
        &diags,
    );
    defer result.deinit(allocator);
    try testing.expectEqualSlices(u8, &[_]u8{0x75}, result.bytecode);

    var warn_count: usize = 0;
    for (diags.items.items) |d| {
        if (d.severity == .warning) warn_count += 1;
    }
    try testing.expect(warn_count >= 1);
}

test "flags: @version uses protocol_version, not hardcoded 2" {
    const allocator = testing.allocator;
    const source = "@version[3]{ OP_DUP } else { OP_DROP }";

    const v1 = try bsvz_macro.compile(allocator, source, .{});
    defer v1.deinit(allocator);
    try testing.expectEqualSlices(u8, &[_]u8{0x75}, v1.bytecode);

    const v3 = try bsvz_macro.compile(allocator, source, .{ .protocol_version = 3 });
    defer v3.deinit(allocator);
    try testing.expectEqualSlices(u8, &[_]u8{0x76}, v3.bytecode);
}

test "flags: @version[1] and @version[2] still work with default" {
    const allocator = testing.allocator;
    const src1 = try bsvz_macro.compile(allocator, "@version[1]{ OP_DUP }", .{});
    defer src1.deinit(allocator);
    try testing.expectEqualSlices(u8, &[_]u8{0x76}, src1.bytecode);

    const src2 = try bsvz_macro.compile(allocator, "@version[2]{ OP_DUP }", .{ .protocol_version = 2 });
    defer src2.deinit(allocator);
    try testing.expectEqualSlices(u8, &[_]u8{0x76}, src2.bytecode);
}

test "flags: @compileError fails with message when reached" {
    const allocator = testing.allocator;
    var diags = bsvz_macro.DiagnosticList.init(allocator);
    defer diags.deinit();

    const result = bsvz_macro.compileWithDiagnostics(
        allocator,
        "@compileError(\"requires Chronicle\")",
        .{},
        &diags,
    );
    try testing.expectError(error.ExpandError, result);

    var found_msg = false;
    for (diags.items.items) |d| {
        if (d.severity == .@"error" and std.mem.indexOf(u8, d.message, "requires Chronicle") != null) {
            found_msg = true;
        }
    }
    try testing.expect(found_msg);
}

test "flags: @compileError in dead branch is inert" {
    const allocator = testing.allocator;
    const result = try bsvz_macro.compile(
        allocator,
        "@era(bip){ OP_DUP } else { @compileError(\"nope\") }",
        .{ .era = .bip },
    );
    defer result.deinit(allocator);
    try testing.expectEqualSlices(u8, &[_]u8{0x76}, result.bytecode);
}

test "flags: @compileError without diagnostics still fails" {
    const allocator = testing.allocator;
    const result = bsvz_macro.compile(allocator, "@compileError(\"boom\")", .{});
    try testing.expectError(error.ExpandError, result);
}

test "flags: nested flags compose" {
    const allocator = testing.allocator;
    const source = "@era(chronicle){ @has(lshiftnum){ OP_LSHIFTNUM } else { OP_LSHIFT } } else { @has(cat){ OP_CAT } else { OP_NOP } }";

    const chronicle = try bsvz_macro.compile(allocator, source, .{ .era = .chronicle });
    defer chronicle.deinit(allocator);
    const chronicle_expected = try bsvz_macro.compile(allocator, "OP_LSHIFTNUM", .{});
    defer chronicle_expected.deinit(allocator);
    try testing.expectEqualSlices(u8, chronicle_expected.bytecode, chronicle.bytecode);

    const bch = try bsvz_macro.compile(allocator, source, .{ .era = .bch });
    defer bch.deinit(allocator);
    const bch_expected = try bsvz_macro.compile(allocator, "OP_CAT", .{});
    defer bch_expected.deinit(allocator);
    try testing.expectEqualSlices(u8, bch_expected.bytecode, bch.bytecode);

    const bip = try bsvz_macro.compile(allocator, source, .{ .era = .bip });
    defer bip.deinit(allocator);
    const bip_expected = try bsvz_macro.compile(allocator, "OP_NOP", .{});
    defer bip_expected.deinit(allocator);
    try testing.expectEqualSlices(u8, bip_expected.bytecode, bip.bytecode);
}

test "flags: block_height auto-derives era" {
    const allocator = testing.allocator;
    const source = "@era(chronicle){ OP_NOP } else { OP_DUP }";

    const heights = [_]struct { h: u32, expected: []const u8 }{
        .{ .h = 620_538, .expected = "OP_DUP" },
        .{ .h = 943_815, .expected = "OP_DUP" },
        .{ .h = 943_816, .expected = "OP_NOP" },
        .{ .h = 1_000_000, .expected = "OP_NOP" },
    };
    for (heights) |case| {
        const result = try bsvz_macro.compile(allocator, source, .{ .block_height = case.h });
        defer result.deinit(allocator);
        const expected = try bsvz_macro.compile(allocator, case.expected, .{});
        defer expected.deinit(allocator);
        try testing.expectEqualSlices(u8, expected.bytecode, result.bytecode);
    }
}

test "flags: era override beats block_height" {
    const allocator = testing.allocator;
    const source = "@era(chronicle){ OP_NOP } else { OP_DUP }";

    const forced = try bsvz_macro.compile(allocator, source, .{ .block_height = 620_538, .era = .chronicle });
    defer forced.deinit(allocator);
    const nop = try bsvz_macro.compile(allocator, "OP_NOP", .{});
    defer nop.deinit(allocator);
    try testing.expectEqualSlices(u8, nop.bytecode, forced.bytecode);
}

test "flags: hash changes when new option fields change" {
    const allocator = testing.allocator;
    const source = "OP_DUP OP_HASH160 OP_EQUAL";

    const base = try bsvz_macro.compile(allocator, source, .{});
    defer base.deinit(allocator);

    const era_variant = try bsvz_macro.compile(allocator, source, .{ .era = .chronicle });
    defer era_variant.deinit(allocator);

    const net_variant = try bsvz_macro.compile(allocator, source, .{ .network = .bsv_regtest });
    defer net_variant.deinit(allocator);

    const ver_variant = try bsvz_macro.compile(allocator, source, .{ .protocol_version = 2 });
    defer ver_variant.deinit(allocator);

    const std_variant = try bsvz_macro.compile(allocator, source, .{ .standardness = .{ .cleanstack = false } });
    defer std_variant.deinit(allocator);

    try testing.expectEqualSlices(u8, base.bytecode, era_variant.bytecode);
    try testing.expect(!std.mem.eql(u8, &base.hash, &era_variant.hash));
    try testing.expect(!std.mem.eql(u8, &base.hash, &net_variant.hash));
    try testing.expect(!std.mem.eql(u8, &base.hash, &ver_variant.hash));
    try testing.expect(!std.mem.eql(u8, &base.hash, &std_variant.hash));
}

test "flags: legacy target is equivalent to network for conditionals" {
    const allocator = testing.allocator;
    const source = "@network(bsv_mainnet){ OP_DUP } @bsv{ OP_HASH160 }";

    const via_target = try bsvz_macro.compile(allocator, source, .{ .target = .bsv_mainnet });
    defer via_target.deinit(allocator);
    const via_network = try bsvz_macro.compile(allocator, source, .{ .network = .bsv_mainnet });
    defer via_network.deinit(allocator);

    try testing.expectEqualSlices(u8, via_target.bytecode, via_network.bytecode);
}

test "flags: era→feature derivation table is complete" {
    const cases = [_]struct { era: bsvz_macro.Era, feature: []const u8, expected: bool }{
        .{ .era = .satoshi, .feature = "cat", .expected = false },
        .{ .era = .satoshi, .feature = "bigpush", .expected = false },
        .{ .era = .bip, .feature = "dersig", .expected = true },
        .{ .era = .bip, .feature = "p2sh", .expected = true },
        .{ .era = .bip, .feature = "cat", .expected = false },
        .{ .era = .bch, .feature = "cat", .expected = true },
        .{ .era = .bch, .feature = "split", .expected = true },
        .{ .era = .bch, .feature = "forkid", .expected = true },
        .{ .era = .bch, .feature = "mul", .expected = false },
        .{ .era = .bsv_pre_genesis, .feature = "cltv", .expected = true },
        .{ .era = .bsv_pre_genesis, .feature = "csv", .expected = true },
        .{ .era = .genesis, .feature = "mul", .expected = true },
        .{ .era = .genesis, .feature = "invert", .expected = true },
        .{ .era = .genesis, .feature = "lshift", .expected = true },
        .{ .era = .genesis, .feature = "bigpush", .expected = true },
        .{ .era = .genesis, .feature = "cltv", .expected = false },
        .{ .era = .genesis, .feature = "p2sh", .expected = false },
        .{ .era = .genesis, .feature = "sigpushonly", .expected = true },
        .{ .era = .chronicle, .feature = "lshiftnum", .expected = true },
        .{ .era = .chronicle, .feature = "rshiftnum", .expected = true },
        .{ .era = .chronicle, .feature = "otda", .expected = true },
        .{ .era = .chronicle, .feature = "codesep_sigsig", .expected = true },
        .{ .era = .chronicle, .feature = "bigscript", .expected = true },
        .{ .era = .chronicle, .feature = "malleability_fixes", .expected = false },
        .{ .era = .chronicle, .feature = "cltv", .expected = false },
    };
    for (cases) |case| {
        const feats = bsvz_macro.featuresForEra(case.era);
        const actual = feats.hasByName(case.feature);
        if (actual != case.expected) {
            std.debug.print("era {s}: expected {s} = {}, got {}\n", .{ @tagName(case.era), case.feature, case.expected, actual });
            return error.TestExpectedEqual;
        }
    }
}

test "flags: invalid flag syntax returns ParseError" {
    const allocator = testing.allocator;
    const bad_sources = [_][]const u8{
        "@era(notanera){ OP_DUP }",
        "@has{ OP_DUP }",
        "@limit(push){ OP_DUP }",
        "@limit(notakind, 100){ OP_DUP }",
        "@network(notanet){ OP_DUP }",
        "@weird{ OP_DUP }",
    };
    for (bad_sources) |src| {
        const result = bsvz_macro.compile(allocator, src, .{});
        try testing.expectError(error.ParseError, result);
    }
}

test "flags: @limit invalid magnitude returns ParseError" {
    const allocator = testing.allocator;
    const result = bsvz_macro.compile(allocator, "@limit(push, 10XB){ OP_DUP }", .{});
    try testing.expectError(error.ParseError, result);
}

test "flags: @has inside LOOP body evaluates per options" {
    const allocator = testing.allocator;
    const source = "LOOP[3]{ @has(cat){ OP_CAT } else { OP_NOP } }";

    const bch = try bsvz_macro.compile(allocator, source, .{ .era = .bch });
    defer bch.deinit(allocator);
    try testing.expectEqual(@as(u32, 3), bch.byte_length);
    try testing.expectEqual(@as(u8, 0x7e), bch.bytecode[0]);

    const bip = try bsvz_macro.compile(allocator, source, .{ .era = .bip });
    defer bip.deinit(allocator);
    const expected = try bsvz_macro.compile(allocator, "LOOP[3]{ OP_NOP }", .{});
    defer expected.deinit(allocator);
    try testing.expectEqualSlices(u8, expected.bytecode, bip.bytecode);
}

test "flags: iterator substitution works inside new-style conditionals" {
    const allocator = testing.allocator;
    const source = "LOOP[3]{ @has(cat){ RANGE_CHECK[<i>,100] } else { OP_NOP } }";

    const bch = try bsvz_macro.compile(allocator, source, .{ .era = .bch });
    defer bch.deinit(allocator);
    const expected = try bsvz_macro.compile(allocator, "LOOP[3]{ RANGE_CHECK[<i>,100] }", .{});
    defer expected.deinit(allocator);
    try testing.expectEqualSlices(u8, expected.bytecode, bch.bytecode);
}

test "flags: p2sh and cltv removed in genesis" {
    const allocator = testing.allocator;
    const p2sh_src = "@has(p2sh){ OP_DUP } else { OP_DROP }";
    const cltv_src = "@has(cltv){ OP_DUP } else { OP_DROP }";

    const genesis = try bsvz_macro.compile(allocator, p2sh_src, .{ .era = .genesis });
    defer genesis.deinit(allocator);
    try testing.expectEqualSlices(u8, &[_]u8{0x75}, genesis.bytecode);

    const genesis_cltv = try bsvz_macro.compile(allocator, cltv_src, .{ .era = .genesis });
    defer genesis_cltv.deinit(allocator);
    try testing.expectEqualSlices(u8, &[_]u8{0x75}, genesis_cltv.bytecode);

    const pre = try bsvz_macro.compile(allocator, p2sh_src, .{ .era = .bsv_pre_genesis });
    defer pre.deinit(allocator);
    try testing.expectEqualSlices(u8, &[_]u8{0x76}, pre.bytecode);
}

test "flags: legacy max_push_size maps to limits.push" {
    const allocator = testing.allocator;
    const source = "@limit(push, 600){ OP_DUP } else { OP_DROP }";

    const legacy = try bsvz_macro.compile(allocator, source, .{ .max_push_size = 600 });
    defer legacy.deinit(allocator);
    try testing.expectEqualSlices(u8, &[_]u8{0x76}, legacy.bytecode);

    const via_limits = try bsvz_macro.compile(allocator, source, .{ .limits = .{ .push = 600 } });
    defer via_limits.deinit(allocator);
    try testing.expectEqualSlices(u8, &[_]u8{0x76}, via_limits.bytecode);
}

test "flags: malleability_fixes only pre-chronicle" {
    const allocator = testing.allocator;
    const source = "@has(malleability_fixes){ OP_DUP } else { OP_DROP }";

    const genesis = try bsvz_macro.compile(allocator, source, .{ .era = .genesis });
    defer genesis.deinit(allocator);
    try testing.expectEqualSlices(u8, &[_]u8{0x75}, genesis.bytecode);

    const pre = try bsvz_macro.compile(allocator, source, .{ .era = .bip });
    defer pre.deinit(allocator);
    try testing.expectEqualSlices(u8, &[_]u8{0x76}, pre.bytecode);

    const chronicle = try bsvz_macro.compile(allocator, source, .{ .era = .chronicle });
    defer chronicle.deinit(allocator);
    try testing.expectEqualSlices(u8, &[_]u8{0x75}, chronicle.bytecode);
}

test "flags: chronicle string-opcode features are chronicle-only" {
    const allocator = testing.allocator;
    const features = [_][]const u8{ "substr", "left", "right", "2mul", "2div", "ver", "verif" };
    for (features) |feat| {
        var source_buf: [96]u8 = undefined;
        const source = try std.fmt.bufPrint(&source_buf, "@has({s}){{ OP_DUP }} else {{ OP_DROP }}", .{feat});

        const chronicle = try bsvz_macro.compile(allocator, source, .{ .era = .chronicle });
        defer chronicle.deinit(allocator);
        try testing.expectEqualSlices(u8, &[_]u8{0x76}, chronicle.bytecode);

        const genesis = try bsvz_macro.compile(allocator, source, .{ .era = .genesis });
        defer genesis.deinit(allocator);
        try testing.expectEqualSlices(u8, &[_]u8{0x75}, genesis.bytecode);
    }
}

test "flags: chronicle opcodes emit correct bytes and round-trip through ASM" {
    const allocator = testing.allocator;
    const cases = [_]struct { name: []const u8, byte: u8 }{
        .{ .name = "OP_SUBSTR", .byte = 0xb3 },
        .{ .name = "OP_LEFT", .byte = 0xb4 },
        .{ .name = "OP_RIGHT", .byte = 0xb5 },
        .{ .name = "OP_LSHIFTNUM", .byte = 0xb6 },
        .{ .name = "OP_RSHIFTNUM", .byte = 0xb7 },
        .{ .name = "OP_2MUL", .byte = 0x8d },
        .{ .name = "OP_2DIV", .byte = 0x8e },
    };
    for (cases) |case| {
        const result = try bsvz_macro.compile(allocator, case.name, .{ .era = .chronicle });
        defer result.deinit(allocator);
        try testing.expectEqualSlices(u8, &[_]u8{case.byte}, result.bytecode);

        const asm_text = try bsvz_macro.toAsm(allocator, result.bytecode);
        defer allocator.free(asm_text);
        const roundtrip = try bsvz_macro.fromAsm(allocator, asm_text);
        defer allocator.free(roundtrip);
        try testing.expectEqualSlices(u8, result.bytecode, roundtrip);
    }
}

test "flags: legacy NOP names still lex after bsvz 0.2.0 rename" {
    const allocator = testing.allocator;
    const cases = [_]struct { name: []const u8, byte: u8 }{
        .{ .name = "OP_NOP4", .byte = 0xb3 },
        .{ .name = "OP_NOP7", .byte = 0xb6 },
        .{ .name = "OP_NOP8", .byte = 0xb7 },
    };
    for (cases) |case| {
        const result = try bsvz_macro.compile(allocator, case.name, .{});
        defer result.deinit(allocator);
        try testing.expectEqualSlices(u8, &[_]u8{case.byte}, result.bytecode);
    }
}

test "flags: chronicle numeric opcodes keep stack heights correct" {
    const allocator = testing.allocator;
    {
        const result = try bsvz_macro.compile(allocator, "OP_LSHIFTNUM", .{ .era = .chronicle });
        defer result.deinit(allocator);
        try testing.expectEqual(@as(u16, 0), result.max_stack_height);
    }
    {
        const result = try bsvz_macro.compile(allocator, "OP_2MUL", .{ .era = .chronicle });
        defer result.deinit(allocator);
        try testing.expectEqual(@as(u16, 0), result.max_stack_height);
    }
    {
        const result = try bsvz_macro.compile(allocator, "OP_SUBSTR", .{ .era = .chronicle });
        defer result.deinit(allocator);
        try testing.expectEqual(@as(u16, 0), result.max_stack_height);
    }
}

test "flags: LOOP over chronicle opcodes unrolls" {
    const allocator = testing.allocator;
    const result = try bsvz_macro.compile(allocator, "LOOP[4]{ OP_2MUL OP_2DIV }", .{ .era = .chronicle });
    defer result.deinit(allocator);
    try testing.expectEqual(@as(u32, 8), result.byte_length);
}
