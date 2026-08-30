const std = @import("std");
const bsvz_macro = @import("bsvz-macro");
const testing = std.testing;

test "diagnostics: lex error carries location" {
    const allocator = testing.allocator;
    var diags = bsvz_macro.DiagnosticList.init(allocator);
    defer diags.deinit();

    // '!' is not a valid token
    const result = bsvz_macro.compileWithDiagnostics(allocator, "OP_DUP ! OP_DROP", .{}, &diags);
    try testing.expectError(error.LexError, result);
    try testing.expect(diags.len() >= 1);

    const d = diags.get(0).?;
    try testing.expectEqual(bsvz_macro.Phase.lex, d.phase);
    try testing.expect(d.location.line >= 1);
    try testing.expect(d.location.column >= 1);
    try testing.expect(d.location.offset > 0);
}

test "diagnostics: parse error carries line and column" {
    const allocator = testing.allocator;
    var diags = bsvz_macro.DiagnosticList.init(allocator);
    defer diags.deinit();

    // Missing closing bracket in LOOP
    const result = bsvz_macro.compileWithDiagnostics(allocator, "OP_DUP LOOP[3 OP_DUP", .{}, &diags);
    try testing.expectError(error.ParseError, result);
    try testing.expect(diags.len() >= 1);

    const d = diags.get(0).?;
    try testing.expectEqual(bsvz_macro.Phase.parse, d.phase);
    try testing.expectEqual(@as(u32, 1), d.location.line);
    // The error should point at or after the LOOP token
    try testing.expect(d.location.offset >= 7);
}

test "diagnostics: expand error carries statement location" {
    const allocator = testing.allocator;
    var diags = bsvz_macro.DiagnosticList.init(allocator);
    defer diags.deinit();

    // Undefined macro (expand phase)
    const result = bsvz_macro.compileWithDiagnostics(allocator, "OP_DUP UNDEFINED_MACRO OP_DROP", .{}, &diags);
    try testing.expectError(error.ExpandError, result);
    try testing.expect(diags.len() >= 1);

    const d = diags.get(0).?;
    try testing.expectEqual(bsvz_macro.Phase.expand, d.phase);
    try testing.expectEqual(@as(u32, 1), d.location.line);
    try testing.expect(d.location.offset > 0);
}

test "diagnostics: simulate error carries byte offset" {
    const allocator = testing.allocator;
    var diags = bsvz_macro.DiagnosticList.init(allocator);
    defer diags.deinit();

    // LOOP[100]{OP_HASHCAT} grows the stack beyond limits
    const result = bsvz_macro.compileWithDiagnostics(allocator, "LOOP[100]{OP_HASHCAT}", .{}, &diags);
    try testing.expectError(error.SimError, result);
    try testing.expect(diags.len() >= 1);

    const d = diags.get(0).?;
    try testing.expectEqual(bsvz_macro.Phase.simulate, d.phase);
    try testing.expect(d.location.offset > 0);
}

test "diagnostics: multiple parse errors accumulate" {
    const allocator = testing.allocator;
    var diags = bsvz_macro.DiagnosticList.init(allocator);
    defer diags.deinit();

    // Two bad statements separated by ';'
    const result = bsvz_macro.compileWithDiagnostics(allocator, "LOOP[3 OP_DUP ; LOOP[4 OP_DROP", .{}, &diags);
    try testing.expectError(error.ParseError, result);
    try testing.expect(diags.len() >= 2);

    const first = diags.get(0).?;
    const second = diags.get(1).?;
    try testing.expectEqual(bsvz_macro.Phase.parse, first.phase);
    try testing.expectEqual(bsvz_macro.Phase.parse, second.phase);
    // The second error is further along in the source
    try testing.expect(second.location.offset > first.location.offset);
}

test "diagnostics: successful compile produces no error diagnostics" {
    const allocator = testing.allocator;
    var diags = bsvz_macro.DiagnosticList.init(allocator);
    defer diags.deinit();

    const result = try bsvz_macro.compileWithDiagnostics(allocator, "SAFE_DIV", .{}, &diags);
    defer result.deinit(allocator);

    var error_count: usize = 0;
    for (diags.items.items) |d| {
        if (d.severity == .@"error") error_count += 1;
    }
    try testing.expectEqual(@as(usize, 0), error_count);
}

test "diagnostics: same result as compile on success" {
    const allocator = testing.allocator;
    var diags = bsvz_macro.DiagnosticList.init(allocator);
    defer diags.deinit();

    const with_diags = try bsvz_macro.compileWithDiagnostics(allocator, "RANGE_CHECK[0,100]", .{}, &diags);
    defer with_diags.deinit(allocator);
    const plain = try bsvz_macro.compile(allocator, "RANGE_CHECK[0,100]", .{});
    defer plain.deinit(allocator);

    try testing.expectEqualSlices(u8, plain.bytecode, with_diags.bytecode);
    try testing.expectEqual(plain.opcode_count, with_diags.opcode_count);
    try testing.expectEqual(plain.is_standard, with_diags.is_standard);
    try testing.expectEqualSlices(u8, &plain.hash, &with_diags.hash);
}
