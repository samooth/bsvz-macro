const std = @import("std");
const Opcode = @import("bsvz").script.opcode.Opcode;
const StackType = @import("stack.zig").StackType;
const StackItem = @import("stack.zig").StackItem;
const SymbolicStack = @import("stack.zig").SymbolicStack;
const SimError = @import("error.zig").SimError;
const DiagnosticList = @import("../diagnostics.zig").DiagnosticList;

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

fn decodeScriptNum(data: []const u8) ?i64 {
    if (data.len == 0) return 0;
    if (data.len > 8) return null;
    var magnitude: u64 = 0;
    for (data, 0..) |b, i| {
        const shift: u6 = @intCast(8 * i);
        magnitude |= @as(u64, b) << shift;
    }
    const sign_shift: u6 = @intCast(8 * (data.len - 1) + 7);
    const sign_mask = @as(u64, 1) << sign_shift;
    if (magnitude & sign_mask != 0) {
        const abs_value: i64 = @intCast(magnitude & ~sign_mask);
        return -abs_value;
    }
    return @intCast(magnitude);
}

fn pushedValue(bytecode: []const u8, start: usize, len: usize) ?i64 {
    if (len > 8) return null;
    if (start + len > bytecode.len) return null;
    return decodeScriptNum(bytecode[start .. start + len]);
}

fn depthFromValue(value: i64, max_stack: u16) SimError!usize {
    if (value < 0) return SimError.InvalidStackIndex;
    if (value >= @as(i64, max_stack)) return SimError.InvalidStackIndex;
    return @intCast(value);
}

fn isNumeric(t: StackType) bool {
    return switch (t) {
        .integer, .bytes, .hash160, .hash256 => true,
        else => false,
    };
}

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

    /// Pushes `items` onto the bottom of the main stack (in order), so they sit
    /// below the items a locking script expects to find. Used to model items
    /// left by the unlocking script (e.g. `<sig> <pubkey>`) before the locking
    /// script runs. Unlike the fixed pre-populated integers, these are opt-in
    /// via `compileWithUnlockingScript`.
    pub fn prependStackItems(self: *SymbolicEngine, items: []const StackItem) !void {
        // Insert at index 0 in reverse so the first item ends up deepest.
        var i: usize = items.len;
        while (i > 0) {
            i -= 1;
            try self.main_stack.items.insert(self.allocator, 0, items[i]);
        }
        if (self.main_stack.items.items.len > self.main_stack.max_height) {
            self.main_stack.max_height = self.main_stack.items.items.len;
        }
    }

    pub fn simulate(self: *SymbolicEngine, bytecode: []const u8, max_stack: u16) SimError!SimulationReport {
        return self.simulateWithDiagnostics(bytecode, max_stack, null);
    }

    pub fn simulateWithDiagnostics(self: *SymbolicEngine, bytecode: []const u8, max_stack: u16, diagnostics: ?*DiagnosticList) SimError!SimulationReport {
        var pc: u32 = 0;
        while (pc < bytecode.len) {
            const op_byte = bytecode[pc];
            const op = Opcode.fromByte(op_byte);

            const pre_height = self.main_stack.height();
            self.executeOpcode(op, bytecode, &pc, max_stack) catch |e| {
                if (diagnostics) |diags| {
                    diags.append(.simulate, .@"error", "simulation error: {s} at opcode {s} (byte offset {d})", .{
                        .line = 1,
                        .column = pc + 1,
                        .offset = pc,
                        .length = 1,
                    }, .{ @errorName(e), op.name(), pc });
                }
                return e;
            };
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
            .OP_0 => try self.main_stack.push(a, .{ .type = StackType{ .integer = {} }, .value = 0 }),
            .OP_1, .OP_2, .OP_3, .OP_4, .OP_5, .OP_6, .OP_7, .OP_8,
            .OP_9, .OP_10, .OP_11, .OP_12, .OP_13, .OP_14, .OP_15, .OP_16 => {
                const literal: i64 = @as(i64, @intFromEnum(op)) - @as(i64, @intFromEnum(Opcode.OP_1)) + 1;
                try self.main_stack.push(a, .{ .type = StackType{ .integer = {} }, .value = literal });
            },
            .OP_1NEGATE => try self.main_stack.push(a, .{ .type = StackType{ .integer = {} }, .value = -1 }),

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
                if (n_item.value) |raw_depth| {
                    const n = try depthFromValue(raw_depth, max_stack);
                    try self.main_stack.ensureDepth(a, n);
                    const item = try self.main_stack.peek(n);
                    try self.main_stack.push(a, item);
                } else {
                    try self.main_stack.push(a, .{ .type = StackType.unknown });
                }
            },
            .OP_ROLL => {
                const n_item = try self.main_stack.pop();
                if (std.meta.activeTag(n_item.type) != .integer) return SimError.TypeMismatch;
                if (n_item.value) |raw_depth| {
                    const n = try depthFromValue(raw_depth, max_stack);
                    try self.main_stack.ensureDepth(a, n);
                    const item = try self.main_stack.removeAt(a, n);
                    try self.main_stack.push(a, item);
                } else {
                    try self.main_stack.ensureDepth(a, 0);
                    _ = try self.main_stack.removeAt(a, 0);
                    try self.main_stack.push(a, .{ .type = StackType.unknown });
                }
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
                if (!isNumeric(item1.type) or !isNumeric(item2.type)) return SimError.TypeMismatch;
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
                if (!isNumeric(item1.type) or !isNumeric(item2.type)) return SimError.TypeMismatch;
            },
            .OP_WITHIN => {
                const max = try self.main_stack.pop();
                const min = try self.main_stack.pop();
                const x = try self.main_stack.pop();
                if (!isNumeric(max.type) or !isNumeric(min.type) or !isNumeric(x.type)) return SimError.TypeMismatch;
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
                    const data_start = pc.* + 1;
                    pc.* += len;
                    // Small pushes (≤8 bytes) are typically integer literals; treat as integer.
                    const pushed_type: StackType = if (len <= 8) .integer else .{ .bytes = len };
                    try self.main_stack.push(a, .{
                        .type = pushed_type,
                        .value = pushedValue(bytecode, data_start, len),
                    });
                } else if (op == .OP_PUSHDATA1) {
                    if (pc.* + 1 >= bytecode.len) return SimError.StackUnderflow;
                    const len = bytecode[pc.* + 1];
                    const data_start = pc.* + 2;
                    pc.* += 1 + len;
                    const pushed_type: StackType = if (len <= 8) .integer else .{ .bytes = len };
                    try self.main_stack.push(a, .{
                        .type = pushed_type,
                        .value = pushedValue(bytecode, data_start, len),
                    });
                } else if (op == .OP_PUSHDATA2) {
                    if (pc.* + 2 >= bytecode.len) return SimError.StackUnderflow;
                    const len = std.mem.readInt(u16, bytecode[pc.* + 1 ..][0..2], .little);
                    const data_start = pc.* + 3;
                    pc.* += 2 + len;
                    const pushed_type: StackType = if (len <= 8) .integer else .{ .bytes = len };
                    try self.main_stack.push(a, .{
                        .type = pushed_type,
                        .value = pushedValue(bytecode, data_start, len),
                    });
                } else if (op == .OP_PUSHDATA4) {
                    if (pc.* + 4 >= bytecode.len) return SimError.StackUnderflow;
                    const len = std.mem.readInt(u32, bytecode[pc.* + 1 ..][0..4], .little);
                    const data_start = pc.* + 5;
                    pc.* += 4 + len;
                    const pushed_type: StackType = if (len <= 8) .integer else .{ .bytes = len };
                    try self.main_stack.push(a, .{
                        .type = pushed_type,
                        .value = pushedValue(bytecode, data_start, len),
                    });
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

test "OP_PICK copies the item at the popped depth" {
    const allocator = testing.allocator;
    var engine = SymbolicEngine.init(allocator);
    defer engine.deinit();

    try engine.main_stack.push(allocator, .{ .type = StackType{ .bytes = 11 } });
    try engine.main_stack.push(allocator, .{ .type = StackType{ .bytes = 22 } });
    try engine.main_stack.push(allocator, .{ .type = StackType{ .bytes = 33 } });

    const bytecode = &[_]u8{ Opcode.OP_2.toByte(), Opcode.OP_PICK.toByte() };
    const report = try engine.simulate(bytecode, 1000);
    defer allocator.free(report.final_stack);

    try testing.expectEqual(@as(usize, 4), report.final_stack.len);
    try testing.expectEqual(@as(u32, 11), report.final_stack[0].bytes);
    try testing.expectEqual(@as(u32, 22), report.final_stack[1].bytes);
    try testing.expectEqual(@as(u32, 33), report.final_stack[2].bytes);
    try testing.expectEqual(@as(u32, 11), report.final_stack[3].bytes);
}

test "OP_ROLL moves the item at the popped depth to the top" {
    const allocator = testing.allocator;
    var engine = SymbolicEngine.init(allocator);
    defer engine.deinit();

    try engine.main_stack.push(allocator, .{ .type = StackType{ .bytes = 11 } });
    try engine.main_stack.push(allocator, .{ .type = StackType{ .bytes = 22 } });
    try engine.main_stack.push(allocator, .{ .type = StackType{ .bytes = 33 } });

    const bytecode = &[_]u8{ Opcode.OP_2.toByte(), Opcode.OP_ROLL.toByte() };
    const report = try engine.simulate(bytecode, 1000);
    defer allocator.free(report.final_stack);

    try testing.expectEqual(@as(usize, 3), report.final_stack.len);
    try testing.expectEqual(@as(u32, 22), report.final_stack[0].bytes);
    try testing.expectEqual(@as(u32, 33), report.final_stack[1].bytes);
    try testing.expectEqual(@as(u32, 11), report.final_stack[2].bytes);
}

test "OP_PICK depth 0 still copies the top item" {
    const allocator = testing.allocator;
    var engine = SymbolicEngine.init(allocator);
    defer engine.deinit();

    try engine.main_stack.push(allocator, .{ .type = StackType{ .bytes = 11 } });
    try engine.main_stack.push(allocator, .{ .type = StackType{ .bytes = 22 } });

    const bytecode = &[_]u8{ Opcode.OP_0.toByte(), Opcode.OP_PICK.toByte() };
    const report = try engine.simulate(bytecode, 1000);
    defer allocator.free(report.final_stack);

    try testing.expectEqual(@as(usize, 3), report.final_stack.len);
    try testing.expectEqual(@as(u32, 22), report.final_stack[2].bytes);
}

test "OP_PICK materializes caller-supplied items below the modeled stack" {
    const allocator = testing.allocator;
    var engine = SymbolicEngine.init(allocator);
    defer engine.deinit();

    try engine.main_stack.push(allocator, .{ .type = StackType{ .bytes = 7 } });

    const bytecode = &[_]u8{ Opcode.OP_3.toByte(), Opcode.OP_PICK.toByte() };
    const report = try engine.simulate(bytecode, 1000);
    defer allocator.free(report.final_stack);

    try testing.expectEqual(@as(usize, 5), report.final_stack.len);
    try testing.expect(report.final_stack[0] == .integer);
    try testing.expectEqual(@as(u32, 7), report.final_stack[3].bytes);
    try testing.expect(report.final_stack[4] == .integer);
    try testing.expectEqual(@as(u16, 5), report.max_stack_height);
}

test "OP_PICK honors a depth pushed as push data" {
    const allocator = testing.allocator;
    var engine = SymbolicEngine.init(allocator);
    defer engine.deinit();

    try engine.main_stack.push(allocator, .{ .type = StackType{ .bytes = 9 } });

    const bytecode = &[_]u8{ 0x01, 20, Opcode.OP_PICK.toByte() };
    const report = try engine.simulate(bytecode, 1000);
    defer allocator.free(report.final_stack);

    try testing.expectEqual(@as(usize, 22), report.final_stack.len);
    try testing.expectEqual(@as(u32, 9), report.final_stack[20].bytes);
    try testing.expect(report.final_stack[21] == .integer);
}

test "OP_PICK rejects a negative depth" {
    const allocator = testing.allocator;
    var engine = SymbolicEngine.init(allocator);
    defer engine.deinit();

    try engine.main_stack.push(allocator, .{ .type = StackType{ .bytes = 4 } });

    const bytecode = &[_]u8{ Opcode.OP_1NEGATE.toByte(), Opcode.OP_PICK.toByte() };
    try testing.expectError(SimError.InvalidStackIndex, engine.simulate(bytecode, 1000));
}

test "OP_ROLL rejects a negative depth encoded as push data" {
    const allocator = testing.allocator;
    var engine = SymbolicEngine.init(allocator);
    defer engine.deinit();

    try engine.main_stack.push(allocator, .{ .type = StackType{ .bytes = 4 } });

    const bytecode = &[_]u8{ 0x01, 0x81, Opcode.OP_ROLL.toByte() };
    try testing.expectError(SimError.InvalidStackIndex, engine.simulate(bytecode, 1000));
}

test "OP_PICK rejects a depth beyond the stack element limit" {
    const allocator = testing.allocator;
    var engine = SymbolicEngine.init(allocator);
    defer engine.deinit();

    try engine.main_stack.push(allocator, .{ .type = StackType{ .bytes = 4 } });

    const bytecode = &[_]u8{ Opcode.OP_16.toByte(), Opcode.OP_PICK.toByte() };
    try testing.expectError(SimError.InvalidStackIndex, engine.simulate(bytecode, 8));
}

test "OP_PICK with an unknown depth yields an unknown item" {
    const allocator = testing.allocator;
    var engine = SymbolicEngine.init(allocator);
    defer engine.deinit();

    try engine.main_stack.push(allocator, .{ .type = StackType{ .bytes = 11 } });
    try engine.main_stack.push(allocator, .{ .type = StackType{ .bytes = 22 } });

    const bytecode = &[_]u8{ Opcode.OP_DEPTH.toByte(), Opcode.OP_PICK.toByte() };
    const report = try engine.simulate(bytecode, 1000);
    defer allocator.free(report.final_stack);

    try testing.expectEqual(@as(usize, 3), report.final_stack.len);
    try testing.expect(report.final_stack[2] == .unknown);
}

test "OP_ROLL with an unknown depth preserves the stack height" {
    const allocator = testing.allocator;
    var engine = SymbolicEngine.init(allocator);
    defer engine.deinit();

    try engine.main_stack.push(allocator, .{ .type = StackType{ .bytes = 11 } });
    try engine.main_stack.push(allocator, .{ .type = StackType{ .bytes = 22 } });
    try engine.main_stack.push(allocator, .{ .type = StackType{ .bytes = 33 } });

    const bytecode = &[_]u8{ Opcode.OP_DEPTH.toByte(), Opcode.OP_ROLL.toByte() };
    const report = try engine.simulate(bytecode, 1000);
    defer allocator.free(report.final_stack);

    try testing.expectEqual(@as(usize, 3), report.final_stack.len);
    try testing.expect(report.final_stack[2] == .unknown);
}
