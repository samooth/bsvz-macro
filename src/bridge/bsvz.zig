const std = @import("std");
const bsvz = @import("bsvz");
const MacroExpansion = @import("../lib.zig").MacroExpansion;

pub fn toBsvzScript(expansion: MacroExpansion) bsvz.script.Script {
    return bsvz.script.Script.init(expansion.bytecode);
}

pub fn executeInBsvz(
    allocator: std.mem.Allocator,
    bytecode: []const u8,
) !bsvz.script.context.ExecutionResult {
    const script = bsvz.script.Script.init(bytecode);
    const ctx = bsvz.script.context.ExecutionContext{
        .allocator = allocator,
    };
    return bsvz.script.engine.executeScript(ctx, script);
}
