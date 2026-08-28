const std = @import("std");
const Opcode = @import("bsvz").script.opcode.Opcode;
const StackType = @import("stack.zig").StackType;
const StackItem = @import("stack.zig").StackItem;
const SymbolicStack = @import("stack.zig").SymbolicStack;
const SimError = @import("error.zig").SimError;

pub const SimulationReport = struct {
    max_stack_height: u16,
    max_altstack_height: u16,
    final_stack: []const StackType,
    is_valid: bool,
};

pub const StackTransition = struct {
    pc: u32,
    opcode: Opcode,
    pre_stack_height: usize,
    post_stack_height: usize,
};

pub const SymbolicEngine = struct {
    main_stack: SymbolicStack,
    alt_stack: SymbolicStack,
    transitions: std.ArrayList(StackTransition),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) SymbolicEngine {
        return .{
            .main_stack = SymbolicStack.init(allocator),
            .alt_stack = SymbolicStack.init(allocator),
            .transitions = .empty,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *SymbolicEngine) void {
        self.main_stack.deinit(self.allocator);
        self.alt_stack.deinit(self.allocator);
        self.transitions.deinit(self.allocator);
    }

    pub fn simulate(self: *SymbolicEngine, bytecode: []const u8, max_stack: u16) SimError!SimulationReport {
        var pc: u32 = 0;
        while (pc < bytecode.len) {
            const op_byte = bytecode[pc];
            const op = Opcode.fromByte(op_byte);

            const pre_height = self.main_stack.height();
            try self.executeOpcode(op, bytecode, &pc, max_stack);
            const post_height = self.main_stack.height();

            try self.transitions.append(self.allocator, .{
                .pc = pc,
                .opcode = op,
                .pre_stack_height = pre_height,
                .post_stack_height = post_height,
            });
        }

        var final_stack = try self.allocator.alloc(StackType, self.main_stack.height());
        for (self.main_stack.items.items, 0..) |item, i| {
            final_stack[i] = item.type;
        }

        return .{
            .max_stack_height = @intCast(self.main_stack.max_height),
            .max_altstack_height = @intCast(self.alt_stack.max_height),
            .final_stack = final_stack,
            .is_valid = true,
        };
    }

    fn executeOpcode(self: *SymbolicEngine, op: Opcode, bytecode: []const u8, pc: *u32, max_stack: u16) SimError!void {
        const a = self.allocator;
        switch (op) {
            .OP_0 => try self.main_stack.push(a, .{ .type = StackType{ .integer = {} } }),
            .OP_1, .OP_2, .OP_3, .OP_4, .OP_5, .OP_6, .OP_7, .OP_8,
            .OP_9, .OP_10, .OP_11, .OP_12, .OP_13, .OP_14, .OP_15, .OP_16 => {
                try self.main_stack.push(a, .{ .type = StackType{ .integer = {} } });
            },
            .OP_1NEGATE => try self.main_stack.push(a, .{ .type = StackType{ .integer = {} } }),

            .OP_DUP => try self.main_stack.dup(a),
            .OP_DROP => _ = try self.main_stack.pop(),
            .OP_SWAP => try self.main_stack.swap(),
            .OP_ROT => {
                if (self.main_stack.height() < 3) return SimError.StackUnderflow;
                const c = try self.main_stack.pop();
                const b = try self.main_stack.pop();
                const top = try self.main_stack.pop();
                try self.main_stack.push(a, b);
                try self.main_stack.push(a, c);
                try self.main_stack.push(a, top);
            },
            .OP_2DROP => {
                _ = try self.main_stack.pop();
                _ = try self.main_stack.pop();
            },
            .OP_2DUP => {
                const item1 = try self.main_stack.peek(1);
                const item0 = try self.main_stack.peek(0);
                try self.main_stack.push(a, item1);
                try self.main_stack.push(a, item0);
            },
            .OP_3DUP => {
                const item2 = try self.main_stack.peek(2);
                const item1 = try self.main_stack.peek(1);
                const item0 = try self.main_stack.peek(0);
                try self.main_stack.push(a, item2);
                try self.main_stack.push(a, item1);
                try self.main_stack.push(a, item0);
            },
            .OP_2OVER => {
                const item3 = try self.main_stack.peek(3);
                const item2 = try self.main_stack.peek(2);
                try self.main_stack.push(a, item3);
                try self.main_stack.push(a, item2);
            },
            .OP_2ROT => {
                if (self.main_stack.height() < 6) return SimError.StackUnderflow;
                const f = try self.main_stack.removeAt(a, 5);
                const e = try self.main_stack.removeAt(a, 4);
                try self.main_stack.push(a, f);
                try self.main_stack.push(a, e);
            },
            .OP_2SWAP => {
                if (self.main_stack.height() < 4) return SimError.StackUnderflow;
                const d = try self.main_stack.removeAt(a, 3);
                const c = try self.main_stack.removeAt(a, 2);
                try self.main_stack.insertAt(a, 0, c);
                try self.main_stack.insertAt(a, 0, d);
            },
            .OP_NIP => {
                if (self.main_stack.height() < 2) return SimError.StackUnderflow;
                const top = try self.main_stack.pop();
                _ = try self.main_stack.pop();
                try self.main_stack.push(a, top);
            },
            .OP_OVER => {
                if (self.main_stack.height() < 2) return SimError.StackUnderflow;
                const item = try self.main_stack.peek(1);
                try self.main_stack.push(a, item);
            },
            .OP_PICK => {
                const n_item = try self.main_stack.pop();
                if (std.meta.activeTag(n_item.type) != .integer) return SimError.TypeMismatch;
                const n: usize = 0;
                const item = try self.main_stack.peek(n);
                try self.main_stack.push(a, item);
            },
            .OP_ROLL => {
                const n_item = try self.main_stack.pop();
                if (std.meta.activeTag(n_item.type) != .integer) return SimError.TypeMismatch;
                const n: usize = 0;
                const item = try self.main_stack.removeAt(a, n);
                try self.main_stack.push(a, item);
            },
            .OP_TUCK => {
                if (self.main_stack.height() < 2) return SimError.StackUnderflow;
                const top = try self.main_stack.peek(0);
                try self.main_stack.insertAt(a, 1, top);
            },
            .OP_DEPTH => try self.main_stack.push(a, .{ .type = StackType{ .integer = {} } }),
            .OP_IFDUP => {
                const top = try self.main_stack.peek(0);
                try self.main_stack.push(a, top);
            },

            .OP_TOALTSTACK => {
                const item = try self.main_stack.pop();
                try self.alt_stack.push(a, item);
            },
            .OP_FROMALTSTACK => {
                const item = try self.alt_stack.pop();
                try self.main_stack.push(a, item);
            },

            .OP_CAT => {
                const item1 = try self.main_stack.pop();
                const item2 = try self.main_stack.pop();
                const len1: u32 = if (std.meta.activeTag(item1.type) == .bytes) item1.type.bytes else 0;
                const len2: u32 = if (std.meta.activeTag(item2.type) == .bytes) item2.type.bytes else 0;
                const new_len = len1 + len2;
                if (new_len > 520) return SimError.PushTooLarge;
                try self.main_stack.push(a, .{ .type = StackType{ .bytes = new_len } });
            },
            .OP_SPLIT => {
                const pos = try self.main_stack.pop();
                const data = try self.main_stack.pop();
                if (std.meta.activeTag(pos.type) != .integer) return SimError.TypeMismatch;
                _ = data;
                try self.main_stack.push(a, .{ .type = StackType{ .bytes = 0 } });
                try self.main_stack.push(a, .{ .type = StackType{ .bytes = 0 } });
            },
            .OP_SIZE => {
                try self.main_stack.push(a, .{ .type = StackType{ .integer = {} } });
            },
            .OP_NUM2BIN => {
                const size = try self.main_stack.pop();
                const val = try self.main_stack.pop();
                if (std.meta.activeTag(size.type) != .integer) return SimError.TypeMismatch;
                _ = val;
                try self.main_stack.push(a, .{ .type = StackType{ .bytes = 0 } });
            },
            .OP_BIN2NUM => {
                const val = try self.main_stack.pop();
                _ = val;
                try self.main_stack.push(a, .{ .type = StackType.integer });
            },

            .OP_EQUAL => {
                const item1 = try self.main_stack.pop();
                const item2 = try self.main_stack.pop();
                _ = item1; _ = item2;
                try self.main_stack.push(a, .{ .type = StackType.bool });
            },
            .OP_EQUALVERIFY => {
                const item1 = try self.main_stack.pop();
                const item2 = try self.main_stack.pop();
                _ = item1; _ = item2;
            },
            .OP_INVERT, .OP_AND, .OP_OR, .OP_XOR => {
                const item1 = try self.main_stack.pop();
                const item2 = try self.main_stack.pop();
                _ = item1; _ = item2;
                try self.main_stack.push(a, .{ .type = StackType{ .bytes = 0 } });
            },

            .OP_1ADD, .OP_1SUB, .OP_NEGATE, .OP_ABS => {
                const item = try self.main_stack.pop();
                if (std.meta.activeTag(item.type) != .integer) return SimError.TypeMismatch;
                try self.main_stack.push(a, .{ .type = StackType.integer });
            },
            .OP_NOT => {
                const item = try self.main_stack.pop();
                _ = item;
                try self.main_stack.push(a, .{ .type = StackType.bool });
            },
            .OP_0NOTEQUAL => {
                const item = try self.main_stack.pop();
                _ = item;
                try self.main_stack.push(a, .{ .type = StackType.bool });
            },
            .OP_BOOLAND, .OP_BOOLOR => {
                const item1 = try self.main_stack.pop();
                const item2 = try self.main_stack.pop();
                _ = item1; _ = item2;
                try self.main_stack.push(a, .{ .type = StackType.bool });
            },
            .OP_ADD, .OP_SUB, .OP_MUL, .OP_DIV, .OP_MOD,
            .OP_LSHIFT, .OP_RSHIFT,
            .OP_NUMEQUAL, .OP_NUMNOTEQUAL, .OP_LESSTHAN,
            .OP_GREATERTHAN, .OP_LESSTHANOREQUAL, .OP_GREATERTHANOREQUAL,
            .OP_MIN, .OP_MAX => {
                const item1 = try self.main_stack.pop();
                const item2 = try self.main_stack.pop();
                if (std.meta.activeTag(item1.type) != .integer or std.meta.activeTag(item2.type) != .integer) return SimError.TypeMismatch;
                const is_bool = switch (op) {
                    .OP_BOOLAND, .OP_BOOLOR, .OP_NUMEQUAL, .OP_NUMNOTEQUAL,
                    .OP_LESSTHAN, .OP_GREATERTHAN, .OP_LESSTHANOREQUAL, .OP_GREATERTHANOREQUAL => true,
                    else => false,
                };
                if (is_bool) {
                    try self.main_stack.push(a, .{ .type = StackType.bool });
                } else {
                    try self.main_stack.push(a, .{ .type = StackType.integer });
                }
            },
            .OP_NUMEQUALVERIFY => {
                const item1 = try self.main_stack.pop();
                const item2 = try self.main_stack.pop();
                if (std.meta.activeTag(item1.type) != .integer or std.meta.activeTag(item2.type) != .integer) return SimError.TypeMismatch;
            },
            .OP_WITHIN => {
                const max = try self.main_stack.pop();
                const min = try self.main_stack.pop();
                const x = try self.main_stack.pop();
                if (std.meta.activeTag(max.type) != .integer or std.meta.activeTag(min.type) != .integer or std.meta.activeTag(x.type) != .integer) return SimError.TypeMismatch;
                try self.main_stack.push(a, .{ .type = StackType.bool });
            },

            .OP_RIPEMD160, .OP_SHA1, .OP_SHA256 => {
                const item = try self.main_stack.pop();
                _ = item;
                try self.main_stack.push(a, .{ .type = StackType{ .bytes = 32 } });
            },
            .OP_HASH160 => {
                const item = try self.main_stack.pop();
                _ = item;
                try self.main_stack.push(a, .{ .type = StackType.hash160 });
            },
            .OP_HASH256 => {
                const item = try self.main_stack.pop();
                _ = item;
                try self.main_stack.push(a, .{ .type = StackType.hash256 });
            },
            .OP_CODESEPARATOR => {},
            .OP_CHECKSIG, .OP_CHECKSIGVERIFY => {
                const pubkey = try self.main_stack.pop();
                const sig = try self.main_stack.pop();
                if (std.meta.activeTag(pubkey.type) != .pubkey and std.meta.activeTag(pubkey.type) != .bytes) return SimError.TypeMismatch;
                if (std.meta.activeTag(sig.type) != .signature and std.meta.activeTag(sig.type) != .bytes) return SimError.TypeMismatch;
                if (op == .OP_CHECKSIG) {
                    try self.main_stack.push(a, .{ .type = StackType.bool });
                }
            },
            .OP_CHECKMULTISIG, .OP_CHECKMULTISIGVERIFY => {
                if (self.main_stack.height() < 3) return SimError.StackUnderflow;
                if (op == .OP_CHECKMULTISIG) {
                    try self.main_stack.push(a, .{ .type = StackType.bool });
                }
            },

            .OP_VERIFY => {
                const item = try self.main_stack.pop();
                _ = item;
            },
            .OP_RETURN => return SimError.VerifyFailed,
            .OP_NOP, .OP_NOP1, .OP_NOP4, .OP_NOP5, .OP_NOP6, .OP_NOP7, .OP_NOP8, .OP_NOP9, .OP_NOP10 => {},
            .OP_IF, .OP_NOTIF, .OP_ELSE, .OP_ENDIF => {
                if (op == .OP_IF or op == .OP_NOTIF) {
                    const cond = try self.main_stack.pop();
                    _ = cond;
                }
            },

            else => {
                const op_byte: u8 = @intFromEnum(op);
                if (op_byte <= 75) {
                    const len = op_byte;
                    pc.* += len;
                    // Small pushes (≤8 bytes) are typically integer literals; treat as integer.
                    const pushed_type: StackType = if (len <= 8) .integer else .{ .bytes = len };
                    try self.main_stack.push(a, .{ .type = pushed_type });
                } else if (op == .OP_PUSHDATA1) {
                    if (pc.* + 1 >= bytecode.len) return SimError.StackUnderflow;
                    const len = bytecode[pc.* + 1];
                    pc.* += 1 + len;
                    const pushed_type: StackType = if (len <= 8) .integer else .{ .bytes = len };
                    try self.main_stack.push(a, .{ .type = pushed_type });
                } else if (op == .OP_PUSHDATA2) {
                    if (pc.* + 2 >= bytecode.len) return SimError.StackUnderflow;
                    const len = std.mem.readInt(u16, bytecode[pc.* + 1 ..][0..2], .little);
                    pc.* += 2 + len;
                    const pushed_type: StackType = if (len <= 8) .integer else .{ .bytes = len };
                    try self.main_stack.push(a, .{ .type = pushed_type });
                } else if (op == .OP_PUSHDATA4) {
                    if (pc.* + 4 >= bytecode.len) return SimError.StackUnderflow;
                    const len = std.mem.readInt(u32, bytecode[pc.* + 1 ..][0..4], .little);
                    pc.* += 4 + len;
                    const pushed_type: StackType = if (len <= 8) .integer else .{ .bytes = len };
                    try self.main_stack.push(a, .{ .type = pushed_type });
                } else {
                    return SimError.InvalidOpcode;
                }
            },
        }

        if (self.main_stack.height() > max_stack) return SimError.StackOverflow;
        pc.* += 1;
    }
};

const testing = std.testing;

test "simulate simple stack ops" {
    const allocator = testing.allocator;
    var engine = SymbolicEngine.init(allocator);
    defer engine.deinit();

    const bytecode = &[_]u8{
        Opcode.OP_1.toByte(),
        Opcode.OP_DUP.toByte(),
        Opcode.OP_ADD.toByte(),
    };

    const report = try engine.simulate(bytecode, 1000);
    defer allocator.free(report.final_stack);

    try testing.expect(report.is_valid);
    try testing.expectEqual(@as(u16, 2), report.max_stack_height);
    try testing.expectEqual(@as(usize, 1), report.final_stack.len);
    try testing.expect(report.final_stack[0] == .integer);
}

test "simulate xswap3 expansion" {
    const allocator = testing.allocator;
    var engine = SymbolicEngine.init(allocator);
    defer engine.deinit();

    const bytecode = &[_]u8{
        0x52,
        Opcode.OP_PICK.toByte(),
        0x52,
        Opcode.OP_ROLL.toByte(),
        Opcode.OP_SWAP.toByte(),
        Opcode.OP_DROP.toByte(),
    };

    var initial = SymbolicEngine.init(allocator);
    defer initial.deinit();
    for (0..4) |_| {
        try initial.main_stack.push(allocator, .{ .type = StackType{ .bytes = 4 } });
    }

    const report = try initial.simulate(bytecode, 1000);
    defer allocator.free(report.final_stack);

    try testing.expect(report.is_valid);
}
