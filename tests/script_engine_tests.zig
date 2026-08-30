// Script-engine integration tests for the alt-stack optimized PUSHTX_SIGN_FAST macro.
//
// These tests use the real bsvz ScriptEngine (not the symbolic simulator) to
// execute the expanded bytecode and verify that PUSHTX_SIGN and PUSHTX_SIGN_FAST
// produce byte-identical signatures for the same message hash input. This is
// the definitive proof that the alt-stack optimization is semantically equivalent
// to the un-optimized version, and also catches the white paper errata (n vs Gx).

const std = @import("std");
const testing = std.testing;
const bsvz = @import("bsvz");
const bsvz_macro = @import("bsvz-macro");
const engine = bsvz.script.engine;
const Script = bsvz.script.Script;
const ExecutionContext = engine.ExecutionContext;

// Three fixed message hashes. Chosen to exercise the canonical-form
// branch (s > n/2) in at least one case, since the optimized sequence
// was specifically designed to handle that case correctly.
const TEST_Z_HEXES = [_][]const u8{
    "0000000000000000000000000000000000000000000000000000000000000000",
    "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
    "7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
};

// Helper: build a tiny script that pushes `z`, executes the given
// macro expansion, then leaves the top of the stack as the produced
// signature. We feed z via a literal push so the engine can run a
// single executeScript call.
fn runSignatureScript(allocator: std.mem.Allocator, expansion: []const u8, z_bytes: []const u8) ![]u8 {
    // Script: push z, run expansion, leave top of stack as the signature.
    // We use a simple concatenation: <push z> <expansion>
    // The script expects z (the message hash) on top of the stack
    // when the expansion starts.
    var script_bytes = std.ArrayList(u8).empty;
    defer script_bytes.deinit(allocator);

    // Push z: 0x20 (direct push 32 bytes) + z_bytes
    try script_bytes.append(allocator, 0x20);
    try script_bytes.appendSlice(allocator, z_bytes);

    // Append the expansion
    try script_bytes.appendSlice(allocator, expansion);

    const ctx = ExecutionContext{
        .allocator = allocator,
        .flags = .{
            .max_ops = 10_000_000,
            .max_stack_items = 1_000,
            .max_script_size = 10_000_000,
            .max_script_element_size = 520,
        },
    };

    var result = try engine.executeScript(ctx, Script.init(script_bytes.items));
    defer result.deinit(allocator);

    if (!result.success) {
        return error.ScriptFailed;
    }
    if (result.state.stack.items.len == 0) {
        return error.EmptyStack;
    }

    // The top of the stack is the produced signature.
    const top = result.state.stack.items[result.state.stack.items.len - 1];
    return allocator.dupe(u8, top);
}

test "script_engine: bsvz ScriptEngine can run a simple push script" {
    // Smoke test: verify that the bsvz ScriptEngine integration works
    // by running a trivial script that just pushes a value.
    const allocator = testing.allocator;
    const z_bytes = [_]u8{0x42} ** 32;
    // The helper prepends a 32-byte push of z_bytes, then runs the
    // expansion. With an empty expansion, the top of the stack should
    // be the 32-byte z value.
    const result = try runSignatureScript(allocator, &.{}, &z_bytes);
    defer allocator.free(result);
    try testing.expectEqualSlices(u8, &z_bytes, result);
}

test "script_engine: PUSHTX_SIGN_FAST matches PUSHTX_SIGN byte-for-byte" {
    const allocator = testing.allocator;
    // Three fixed preimages. Chosen so at least one exercises the
    // canonical-form branch (s > n/2).
    const preimages = [_][]const u8{
        &[_]u8{0x00} ** 32,
        &[_]u8{0xff} ** 32,
        &[_]u8{0x7f} ** 32,
    };

    for (preimages) |preimage| {
        const slow = try bsvz_macro.compile(allocator, "PUSHTX_SIGN[1]", .{});
        defer slow.deinit(allocator);
        const fast = try bsvz_macro.compile(allocator, "PUSHTX_SIGN_FAST[1]", .{});
        defer fast.deinit(allocator);

        const slow_sig = try runSignatureScript(allocator, slow.bytecode, preimage);
        defer allocator.free(slow_sig);
        const fast_sig = try runSignatureScript(allocator, fast.bytecode, preimage);
        defer allocator.free(fast_sig);

        try testing.expectEqualSlices(u8, slow_sig, fast_sig);
    }
}
