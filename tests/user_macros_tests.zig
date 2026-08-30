const std = @import("std");
const bsvz_macro = @import("bsvz-macro");
const testing = std.testing;

fn myDupDropExpand(allocator: std.mem.Allocator, args: []const bsvz_macro.AstNode, body: ?[]const bsvz_macro.AstNode, table: *const bsvz_macro.MacroTable) bsvz_macro.ExpandError![]const u8 {
    _ = args;
    _ = body;
    _ = table;
    var out = std.ArrayListUnmanaged(u8){};
    defer out.deinit(allocator);
    try out.appendSlice(allocator, &.{ 0x76, 0x75 });
    return out.toOwnedSlice(allocator);
}

fn doubleArgExpand(allocator: std.mem.Allocator, args: []const bsvz_macro.AstNode, body: ?[]const bsvz_macro.AstNode, table: *const bsvz_macro.MacroTable) bsvz_macro.ExpandError![]const u8 {
    _ = body;
    _ = table;
    if (args.len != 1) return error.ArityMismatch;
    if (args[0] != .integer_literal) return error.TypeMismatch;
    const n = args[0].integer_literal;
    var out = std.ArrayListUnmanaged(u8){};
    defer out.deinit(allocator);
    var i: i64 = 0;
    while (i < n) : (i += 1) {
        try out.appendSlice(allocator, &.{0x76});
    }
    return out.toOwnedSlice(allocator);
}

test "user macros: custom macro compiles via compileWithTable" {
    const allocator = testing.allocator;
    var table = bsvz_macro.MacroTable.init(allocator);
    defer table.deinit();
    try bsvz_macro.prelude.registerCanonicalMacros(&table);
    try bsvz_macro.registerMacro(&table, "MY_DUP_DROP", .{
        .arity = 0,
        .param_types = &.{},
        .expand_fn = myDupDropExpand,
    });

    const result = try bsvz_macro.compileWithTable(allocator, "MY_DUP_DROP", .{}, &table);
    defer result.deinit(allocator);
    try testing.expectEqualSlices(u8, &.{ 0x76, 0x75 }, result.bytecode);
}

test "user macros: custom macro with args" {
    const allocator = testing.allocator;
    var table = bsvz_macro.MacroTable.init(allocator);
    defer table.deinit();
    try bsvz_macro.prelude.registerCanonicalMacros(&table);
    try bsvz_macro.registerMacro(&table, "MY_MULTI_DUP", .{
        .arity = 1,
        .param_types = &.{.integer},
        .expand_fn = doubleArgExpand,
    });

    const result = try bsvz_macro.compileWithTable(allocator, "MY_MULTI_DUP[3]", .{}, &table);
    defer result.deinit(allocator);
    try testing.expectEqualSlices(u8, &.{ 0x76, 0x76, 0x76 }, result.bytecode);
}

test "user macros: table reusable across compiles" {
    const allocator = testing.allocator;
    var table = bsvz_macro.MacroTable.init(allocator);
    defer table.deinit();
    try bsvz_macro.prelude.registerCanonicalMacros(&table);
    try bsvz_macro.registerMacro(&table, "MY_DUP_DROP", .{
        .arity = 0,
        .param_types = &.{},
        .expand_fn = myDupDropExpand,
    });

    const r1 = try bsvz_macro.compileWithTable(allocator, "MY_DUP_DROP", .{}, &table);
    defer r1.deinit(allocator);
    const r2 = try bsvz_macro.compileWithTable(allocator, "MY_DUP_DROP OP_DUP", .{}, &table);
    defer r2.deinit(allocator);

    try testing.expectEqualSlices(u8, &.{ 0x76, 0x75 }, r1.bytecode);
    try testing.expectEqualSlices(u8, &.{ 0x76, 0x75, 0x76 }, r2.bytecode);
}

test "user macros: canonical macros still work in custom table" {
    const allocator = testing.allocator;
    var table = bsvz_macro.MacroTable.init(allocator);
    defer table.deinit();
    try bsvz_macro.prelude.registerCanonicalMacros(&table);

    const with_table = try bsvz_macro.compileWithTable(allocator, "SAFE_DIV", .{}, &table);
    defer with_table.deinit(allocator);
    const plain = try bsvz_macro.compile(allocator, "SAFE_DIV", .{});
    defer plain.deinit(allocator);

    try testing.expectEqualSlices(u8, plain.bytecode, with_table.bytecode);
}

test "user macros: custom macro overrides canonical registration order" {
    const allocator = testing.allocator;
    var table = bsvz_macro.MacroTable.init(allocator);
    defer table.deinit();
    try bsvz_macro.prelude.registerCanonicalMacros(&table);
    try bsvz_macro.registerMacro(&table, "SAFE_DIV", .{
        .arity = 0,
        .param_types = &.{},
        .expand_fn = myDupDropExpand,
    });

    const result = try bsvz_macro.compileWithTable(allocator, "SAFE_DIV", .{}, &table);
    defer result.deinit(allocator);
    // User registration replaced the canonical SAFE_DIV
    try testing.expectEqualSlices(u8, &.{ 0x76, 0x75 }, result.bytecode);
}

test "user macros: compileWithTableAndDiagnostics reports custom macro errors" {
    const allocator = testing.allocator;
    var table = bsvz_macro.MacroTable.init(allocator);
    defer table.deinit();
    try bsvz_macro.prelude.registerCanonicalMacros(&table);
    try bsvz_macro.registerMacro(&table, "MY_MULTI_DUP", .{
        .arity = 1,
        .param_types = &.{.integer},
        .expand_fn = doubleArgExpand,
    });

    var diags = bsvz_macro.DiagnosticList.init(allocator);
    defer diags.deinit();

    // Arity mismatch: MY_MULTI_DUP without args
    const result = bsvz_macro.compileWithTableAndDiagnostics(allocator, "MY_MULTI_DUP", .{}, &table, &diags);
    try testing.expectError(error.ExpandError, result);
    try testing.expect(diags.len() >= 1);
    try testing.expectEqual(bsvz_macro.Phase.expand, diags.get(0).?.phase);
}
