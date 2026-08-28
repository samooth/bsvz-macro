const std = @import("std");
const bsvz_asm = @import("bsvz").script.bitcoin_asm;

pub const Error = error{ InvalidOpcode, InvalidHex, InvalidPushData, OutOfMemory };

pub fn toAsm(allocator: std.mem.Allocator, bytecode: []const u8) Error![]const u8 {
    const script = @import("bsvz").script.Script.init(bytecode);
    return bsvz_asm.toAsmAlloc(allocator, script) catch |e| switch (e) {
        error.InvalidOpcode => return error.InvalidOpcode,
        error.InvalidHex => return error.InvalidHex,
        error.InvalidPushData => return error.InvalidPushData,
        else => return error.OutOfMemory,
    };
}

pub fn fromAsm(allocator: std.mem.Allocator, asm_source: []const u8) Error![]const u8 {
    return bsvz_asm.fromAsmAlloc(allocator, asm_source) catch |e| switch (e) {
        error.InvalidOpcode => return error.InvalidOpcode,
        error.InvalidHex => return error.InvalidHex,
        error.InvalidPushData => return error.InvalidPushData,
        else => return error.OutOfMemory,
    };
}
