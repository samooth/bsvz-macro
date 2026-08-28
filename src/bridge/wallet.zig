const std = @import("std");
const bsvz = @import("bsvz");
const CompileOptions = @import("../lib.zig").CompileOptions;
const MacroError = @import("../lib.zig").MacroError;
const compile = @import("../lib.zig").compile;

pub fn addMacroOutput(
    builder: *bsvz.transaction.builder.Builder,
    source: []const u8,
    satoshis: i64,
    options: CompileOptions,
) MacroError!void {
    const expanded = compile(builder.allocator, source, options) catch |e| return e;
    defer expanded.deinit(builder.allocator);

    const output = bsvz.transaction.Output{
        .satoshis = satoshis,
        .locking_script = bsvz.script.Script.init(expanded.bytecode),
    };
    try builder.addOutput(output);
}

pub fn addMacroInput(
    builder: *bsvz.transaction.builder.Builder,
    input_index: u32,
    source: []const u8,
    options: CompileOptions,
) MacroError!void {
    const expanded = compile(builder.allocator, source, options) catch |e| return e;
    defer expanded.deinit(builder.allocator);

    if (input_index >= builder.inputs.items.len) return MacroError.ValError;
    builder.inputs.items[input_index].unlocking_script =
        try bsvz.script.Script.init(expanded.bytecode).clone(builder.allocator);
}
