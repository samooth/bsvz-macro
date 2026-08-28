const std = @import("std");
const ValError = @import("error.zig").ValError;
const CompileOptions = @import("../lib.zig").CompileOptions;

pub const BoundsValidator = struct {
    options: CompileOptions,

    pub fn init(options: CompileOptions) BoundsValidator {
        return .{ .options = options };
    }

    pub fn validate(self: *const BoundsValidator, bytecode: []const u8, max_stack: u16) ValError!bool {
        if (bytecode.len > self.options.max_script_size) return ValError.ScriptTooLarge;
        if (max_stack > self.options.max_stack_elements) return ValError.StackTooDeep;

        var is_standard = true;
        if (self.options.enforce_standardness) {
            var opcode_count: u32 = 0;
            var pc: usize = 0;
            while (pc < bytecode.len) {
                const b = bytecode[pc];
                if (b > 0x00 and b <= 0x4e) {
                    if (b <= 75) {
                        pc += 1 + b;
                    } else if (b == 0x4c) {
                        if (pc + 1 >= bytecode.len) break;
                        pc += 2 + bytecode[pc + 1];
                    } else if (b == 0x4d) {
                        if (pc + 2 >= bytecode.len) break;
                        pc += 3 + std.mem.readInt(u16, bytecode[pc + 1..][0..2], .little);
                    } else {
                        if (pc + 4 >= bytecode.len) break;
                        pc += 5 + std.mem.readInt(u32, bytecode[pc + 1..][0..4], .little);
                    }
                    continue;
                }
                opcode_count += 1;
                pc += 1;
            }
            if (opcode_count > 201) is_standard = false;
        }
        return is_standard;
    }
};
