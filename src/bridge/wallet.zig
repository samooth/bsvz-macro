const std = @import("std");
const bsvz = @import("bsvz");
const CompileOptions = @import("../lib.zig").CompileOptions;
const MacroError = @import("../lib.zig").MacroError;
const compile = @import("../lib.zig").compile;

pub fn addMacroOutput(
    builder: *bsvz.transaction.Builder,
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
    builder: *bsvz.transaction.Builder,
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

pub fn addP2pkhOutput(
    builder: *bsvz.transaction.Builder,
    pubkey_hash: []const u8,
    satoshis: i64,
    options: CompileOptions,
) MacroError!void {
    _ = options;
    if (pubkey_hash.len != 20) return MacroError.ValError;
    const allocator = builder.allocator;
    const script_bytes = allocator.alloc(u8, 25) catch return MacroError.OutOfMemory;
    errdefer allocator.free(script_bytes);
    script_bytes[0] = 0x76; // OP_DUP
    script_bytes[1] = 0xa9; // OP_HASH160
    script_bytes[2] = 0x14; // push 20 bytes
    @memcpy(script_bytes[3..23], pubkey_hash);
    script_bytes[23] = 0x88; // OP_EQUALVERIFY
    script_bytes[24] = 0xac; // OP_CHECKSIG

    const output = bsvz.transaction.Output{
        .satoshis = satoshis,
        .locking_script = bsvz.script.Script.init(script_bytes),
    };
    try builder.addOutput(output);
    allocator.free(script_bytes);
}

pub fn addP2shOutput(
    builder: *bsvz.transaction.Builder,
    script_hash: []const u8,
    satoshis: i64,
    options: CompileOptions,
) MacroError!void {
    _ = options;
    if (script_hash.len != 20) return MacroError.ValError;
    const allocator = builder.allocator;
    const script_bytes = allocator.alloc(u8, 23) catch return MacroError.OutOfMemory;
    errdefer allocator.free(script_bytes);
    script_bytes[0] = 0xa9; // OP_HASH160
    script_bytes[1] = 0x14; // push 20 bytes
    @memcpy(script_bytes[2..22], script_hash);
    script_bytes[22] = 0x87; // OP_EQUAL

    const output = bsvz.transaction.Output{
        .satoshis = satoshis,
        .locking_script = bsvz.script.Script.init(script_bytes),
    };
    try builder.addOutput(output);
    allocator.free(script_bytes);
}

pub fn addPelsOutput(
    builder: *bsvz.transaction.Builder,
    source: []const u8,
    satoshis: i64,
    options: CompileOptions,
) MacroError!void {
    return addMacroOutput(builder, source, satoshis, options);
}
