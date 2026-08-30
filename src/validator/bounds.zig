const std = @import("std");
const ValError = @import("error.zig").ValError;
const CompileOptions = @import("../lib.zig").CompileOptions;
const DiagnosticList = @import("../diagnostics.zig").DiagnosticList;
const SourceLocation = @import("../diagnostics.zig").SourceLocation;

pub const BoundsValidator = struct {
    options: CompileOptions,

    pub fn init(options: CompileOptions) BoundsValidator {
        return .{ .options = options };
    }

    pub fn validate(self: *const BoundsValidator, bytecode: []const u8, max_stack: u16) ValError!bool {
        return self.validateWithDiagnostics(bytecode, max_stack, null);
    }

    pub fn validateWithDiagnostics(self: *const BoundsValidator, bytecode: []const u8, max_stack: u16, diagnostics: ?*DiagnosticList) ValError!bool {
        var is_standard = true;

        if (bytecode.len > self.options.max_script_size) {
            if (diagnostics) |diags| {
                diags.append(.validate, .@"error", "script too large: {d} bytes exceeds limit {d}", unknownLocation, .{ bytecode.len, self.options.max_script_size });
            }
            return ValError.ScriptTooLarge;
        }
        if (max_stack > self.options.max_stack_elements) {
            if (diagnostics) |diags| {
                diags.append(.validate, .@"error", "stack too deep: {d} elements exceeds limit {d}", unknownLocation, .{ max_stack, self.options.max_stack_elements });
            }
            return ValError.StackTooDeep;
        }

        if (self.options.enforce_standardness) {
            var opcode_count: u32 = 0;
            var pc: usize = 0;
            var max_push: u32 = 0;
            while (pc < bytecode.len) {
                const b = bytecode[pc];
                if (b > 0x00 and b <= 0x4e) {
                    var push_len: u32 = 0;
                    if (b <= 75) {
                        push_len = b;
                        pc += 1 + b;
                    } else if (b == 0x4c) {
                        if (pc + 1 >= bytecode.len) break;
                        push_len = bytecode[pc + 1];
                        pc += 2 + bytecode[pc + 1];
                    } else if (b == 0x4d) {
                        if (pc + 2 >= bytecode.len) break;
                        push_len = std.mem.readInt(u16, bytecode[pc + 1..][0..2], .little);
                        pc += 3 + push_len;
                    } else {
                        if (pc + 4 >= bytecode.len) break;
                        push_len = std.mem.readInt(u32, bytecode[pc + 1..][0..4], .little);
                        pc += 5 + push_len;
                    }
                    if (push_len > max_push) max_push = push_len;
                    continue;
                }
                opcode_count += 1;
                pc += 1;
            }
            if (opcode_count > 201) {
                if (diagnostics) |diags| {
                    diags.append(.validate, .@"error", "non-standard: {d} opcodes exceeds 201", unknownLocation, .{opcode_count});
                }
                is_standard = false;
            }
            if (max_push > self.options.max_push_size) {
                if (diagnostics) |diags| {
                    diags.append(.validate, .@"error", "non-standard: push of {d} bytes exceeds limit {d}", unknownLocation, .{ max_push, self.options.max_push_size });
                }
                is_standard = false;
            }
        }
        return is_standard;
    }
};

const unknownLocation: SourceLocation = .{ .line = 0, .column = 0, .offset = 0, .length = 0 };
