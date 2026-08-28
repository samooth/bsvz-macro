const std = @import("std");
const CompileOptions = @import("../lib.zig").CompileOptions;

pub const PolicyChecker = struct {
    options: CompileOptions,

    pub fn checkStandardness(self: *const PolicyChecker, bytecode: []const u8) bool {
        _ = self;
        _ = bytecode;
        return true;
    }
};
