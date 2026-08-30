// Tests for the WP1605 §1.4 alt-stack optimized PUSHTX_OUTPUTS_REQUEST_FAST and
// PELS_LOCKING_SCRIPT_FAST macros, plus the compileWithUnlockingScript entry
// point that lets PELS scripts simulate end-to-end (the symbolic simulator does
// not model the unlocking script's pubkey by default).

const std = @import("std");
const testing = std.testing;
const bsvz_macro = @import("bsvz-macro");
const StackItem = bsvz_macro.StackItem;

test "expander: PUSHTX_OUTPUTS_REQUEST_FAST emits alt-stack opcodes" {
    const allocator = testing.allocator;
    const slow = try bsvz_macro.compile(allocator, "PUSHTX_OUTPUTS_REQUEST[0xffffffff, 0x0000000001000000]", .{});
    defer slow.deinit(allocator);
    const fast = try bsvz_macro.compile(allocator, "PUSHTX_OUTPUTS_REQUEST_FAST[0xffffffff, 0x0000000001000000]", .{});
    defer fast.deinit(allocator);

    // The FAST variant must use the alt stack.
    const has_alt_stack = blk: {
        for (fast.bytecode) |b| {
            if (b == 0x6b or b == 0x6c) break :blk true; // OP_TOALTSTACK / OP_FROMALTSTACK
        }
        break :blk false;
    };
    try testing.expect(has_alt_stack);

    // The non-FAST variant must NOT use the alt stack.
    const slow_has_alt = blk: {
        for (slow.bytecode) |b| {
            if (b == 0x6b or b == 0x6c) break :blk true;
        }
        break :blk false;
    };
    try testing.expect(!slow_has_alt);
}

test "expander: PELS_LOCKING_SCRIPT_FAST uses the optimised outputsRequest" {
    const allocator = testing.allocator;
    // PELS needs a pubkey on the stack to simulate; use compileWithUnlockingScript
    // with dummy unlocking items for both. The FAST variant needs a deeper
    // stack (8 items) than the non-FAST PELS (5 items) because its alt-stack
    // outputsRequest consumes items differently.
    const src_args = "1, 0xffffffff, 0x0000000001000000, 0x0102030405060708090a0b0c0d0e0f1011121314]";
    const slow = try bsvz_macro.compileWithUnlockingScript(
        allocator,
        "PELS_LOCKING_SCRIPT[" ++ src_args,
        .{},
        &[_]StackItem{
            .{ .type = .{ .bytes = 96 } },
            .{ .type = .{ .bytes = 33 } },
            .{ .type = .{ .bytes = 128 } },
            .{ .type = .{ .bytes = 64 } },
            .{ .type = .{ .bytes = 4 } },
        },
    );
    defer slow.deinit(allocator);
    const fast = try bsvz_macro.compileWithUnlockingScript(
        allocator,
        "PELS_LOCKING_SCRIPT_FAST[" ++ src_args,
        .{},
        &[_]StackItem{
            .{ .type = .{ .bytes = 96 } },
            .{ .type = .{ .bytes = 33 } },
            .{ .type = .{ .bytes = 128 } },
            .{ .type = .{ .bytes = 64 } },
            .{ .type = .{ .bytes = 4 } },
            .{ .type = .{ .bytes = 32 } },
            .{ .type = .{ .bytes = 32 } },
            .{ .type = .{ .bytes = 32 } },
        },
    );
    defer fast.deinit(allocator);

    // The FAST variant's outputsRequest uses the alt stack (the §1.4
    // optimisation), so its bytecode contains OP_TOALTSTACK/OP_FROMALTSTACK
    // whereas the non-FAST variant does not.
    const fast_has_alt = blk: {
        for (fast.bytecode) |b| {
            if (b == 0x6b or b == 0x6c) break :blk true;
        }
        break :blk false;
    };
    const slow_has_alt = blk: {
        for (slow.bytecode) |b| {
            if (b == 0x6b or b == 0x6c) break :blk true;
        }
        break :blk false;
    };
    try testing.expect(fast_has_alt);
    try testing.expect(!slow_has_alt);
}

test "simulator: PELS_LOCKING_SCRIPT fails with SimError under plain compile" {
    const allocator = testing.allocator;
    // Plain compile() pre-populates the stack with .integer items only; PELS
    // needs a pubkey/bytes item for OP_CHECKSIGVERIFY, so simulation fails.
    const err = bsvz_macro.compile(
        allocator,
        "PELS_LOCKING_SCRIPT[1, 0xffffffff, 0x0000000001000000, 0x0102030405060708090a0b0c0d0e0f1011121314]",
        .{},
    ) catch |e| e;
    try testing.expectEqual(bsvz_macro.MacroError.SimError, err);
}

test "simulator: PELS_LOCKING_SCRIPT simulates with compileWithUnlockingScript" {
    const allocator = testing.allocator;
    // Model the unlocking script's stack contribution per WP1605 Table 4:
    // <SigB> <PKB> <Data1> <Data2> <Data3> — five .bytes items that the
    // PELS locking script consumes. (Plain compile() only pre-populates
    // .integer items, which fail OP_CHECKSIGVERIFY's type check.)
    const unlocking = [_]StackItem{
        .{ .type = .{ .bytes = 96 } },  // SigB placeholder
        .{ .type = .{ .bytes = 33 } },  // PKB (compressed pubkey)
        .{ .type = .{ .bytes = 128 } }, // Data1
        .{ .type = .{ .bytes = 64 } },  // Data2
        .{ .type = .{ .bytes = 4 } },   // Data3
    };

    const result = try bsvz_macro.compileWithUnlockingScript(
        allocator,
        "PELS_LOCKING_SCRIPT[1, 0xffffffff, 0x0000000001000000, 0x0102030405060708090a0b0c0d0e0f1011121314]",
        .{},
        &unlocking,
    );
    defer result.deinit(allocator);
    try testing.expect(result.is_standard);
    try testing.expect(result.byte_length > 0);
}

test "simulator: PELS_LOCKING_SCRIPT_FAST simulates with compileWithUnlockingScript" {
    const allocator = testing.allocator;
    // The alt-stack outputsRequest in the FAST variant consumes stack items
    // differently, so it needs a deeper unlocking-script stack (8 items) than
    // the non-FAST PELS (5 items).
    const unlocking = [_]StackItem{
        .{ .type = .{ .bytes = 96 } },
        .{ .type = .{ .bytes = 33 } },
        .{ .type = .{ .bytes = 128 } },
        .{ .type = .{ .bytes = 64 } },
        .{ .type = .{ .bytes = 4 } },
        .{ .type = .{ .bytes = 32 } },
        .{ .type = .{ .bytes = 32 } },
        .{ .type = .{ .bytes = 32 } },
    };

    const result = try bsvz_macro.compileWithUnlockingScript(
        allocator,
        "PELS_LOCKING_SCRIPT_FAST[1, 0xffffffff, 0x0000000001000000, 0x0102030405060708090a0b0c0d0e0f1011121314]",
        .{},
        &unlocking,
    );
    defer result.deinit(allocator);
    try testing.expect(result.is_standard);
    try testing.expect(result.byte_length > 0);
}
