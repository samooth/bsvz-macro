const std = @import("std");
const bsvz_macro = @import("bsvz-macro");
const bsvz = @import("bsvz");
const testing = std.testing;

// Test helpers to reduce boilerplate in test files.
// These provide common patterns for compilation, assertion, and cleanup.

/// Compile a script with default options and return the result.
/// Caller is responsible for deinit.
pub fn compileDefault(allocator: std.mem.Allocator, source: []const u8) !bsvz_macro.MacroExpansion {
    return bsvz_macro.compile(allocator, source, .{});
}

/// Compile a script with custom options.
pub fn compileWith(allocator: std.mem.Allocator, source: []const u8, options: bsvz_macro.CompileOptions) !bsvz_macro.MacroExpansion {
    return bsvz_macro.compile(allocator, source, options);
}

/// Compile a script and expect success.
/// Returns the expansion for further assertions.
pub fn compileExpectOk(allocator: std.mem.Allocator, source: []const u8) !bsvz_macro.MacroExpansion {
    return compileDefault(allocator, source);
}

/// Compile a script and expect a specific error.
pub fn compileExpectError(allocator: std.mem.Allocator, source: []const u8, expected: anyerror) !void {
    if (compileDefault(allocator, source)) |_| {
        return error.TestExpectedError;
    } else |err| {
        if (err != expected) {
            std.debug.print("Expected {s}, got {s}\n", .{ @errorName(expected), @errorName(err) });
            return error.TestWrongError;
        }
    }
}

/// Assert that a script compiles to bytecode of expected length.
pub fn expectBytecodeLength(allocator: std.mem.Allocator, source: []const u8, expected_length: u32) !void {
    const result = try compileDefault(allocator, source);
    defer result.deinit(allocator);
    if (result.byte_length != expected_length) {
        std.debug.print("Expected bytecode length {d}, got {d}\n", .{ expected_length, result.byte_length });
        return error.TestExpectedEqual;
    }
}

/// Assert that a script compiles to non-empty bytecode.
pub fn expectNonEmptyBytecode(allocator: std.mem.Allocator, source: []const u8) !void {
    const result = try compileDefault(allocator, source);
    defer result.deinit(allocator);
    if (result.bytecode.len == 0) {
        return error.TestExpectedNonEmpty;
    }
}

/// Assert that max stack height matches expected value.
pub fn expectMaxStack(allocator: std.mem.Allocator, source: []const u8, expected: u16) !void {
    const result = try compileDefault(allocator, source);
    defer result.deinit(allocator);
    if (result.max_stack_height != expected) {
        std.debug.print("Expected max stack {d}, got {d}\n", .{ expected, result.max_stack_height });
        return error.TestExpectedEqual;
    }
}

/// Assert that script is standard.
pub fn expectStandard(allocator: std.mem.Allocator, source: []const u8) !void {
    const result = try compileDefault(allocator, source);
    defer result.deinit(allocator);
    if (!result.is_standard) {
        return error.TestExpectedStandard;
    }
}

/// Run a test with a scoped allocator that checks for leaks.
pub fn runWithLeakCheck(comptime test_fn: fn (std.mem.Allocator) anyerror!void) void {
    const allocator = testing.allocator;
    test_fn(allocator) catch |err| {
        // If the test failed, re-raise the error
        std.debug.panic("Test failed: {s}\n", .{@errorName(err)});
    };
}

/// Generate a string of n repetitions of a character.
pub fn repeatChar(allocator: std.mem.Allocator, char: u8, n: usize) ![]u8 {
    const buf = try allocator.alloc(u8, n);
    for (buf) |*b| b.* = char;
    return buf;
}

/// Assert that two byte slices are equal.
pub fn expectBytesEqual(expected: []const u8, actual: []const u8) !void {
    if (expected.len != actual.len) {
        std.debug.print("Length mismatch: expected {d}, got {d}\n", .{ expected.len, actual.len });
        return error.TestExpectedEqual;
    }
    if (!std.mem.eql(u8, expected, actual)) {
        return error.TestExpectedEqual;
    }
}

/// Assert that compilation produces a specific hash (for determinism testing).
pub fn expectDeterministicHash(allocator: std.mem.Allocator, source: []const u8) !void {
    const result1 = try compileDefault(allocator, source);
    defer result1.deinit(allocator);
    const result2 = try compileDefault(allocator, source);
    defer result2.deinit(allocator);
    if (!std.mem.eql(u8, &result1.hash, &result2.hash)) {
        return error.TestExpectedDeterministic;
    }
}

/// Assert that compiling a source twice yields identical bytecode (determinism).
pub fn expectDeterministicBytecode(allocator: std.mem.Allocator, source: []const u8) !void {
    const result1 = try compileDefault(allocator, source);
    defer result1.deinit(allocator);
    const result2 = try compileDefault(allocator, source);
    defer result2.deinit(allocator);
    try expectBytesEqual(result1.bytecode, result2.bytecode);
}

/// Assert that two sources compile to identical bytecode.
pub fn expectBytecodeEquals(allocator: std.mem.Allocator, a: []const u8, b: []const u8) !void {
    const ra = try compileDefault(allocator, a);
    defer ra.deinit(allocator);
    const rb = try compileDefault(allocator, b);
    defer rb.deinit(allocator);
    try expectBytesEqual(ra.bytecode, rb.bytecode);
}

/// Assert that the hash of a source changes when compile options change.
pub fn expectHashChangesWithOptions(
    allocator: std.mem.Allocator,
    source: []const u8,
    base: bsvz_macro.CompileOptions,
    variant: bsvz_macro.CompileOptions,
) !void {
    const rb = try compileWith(allocator, source, base);
    defer rb.deinit(allocator);
    const rv = try compileWith(allocator, source, variant);
    defer rv.deinit(allocator);
    if (std.mem.eql(u8, &rb.hash, &rv.hash)) {
        return error.TestExpectedNonEqual;
    }
}

/// Lightweight deterministic PRNG (xorshift32) for property-based test inputs.
pub const Prng = struct {
    state: u32,

    pub fn init(seed: u32) Prng {
        return .{ .state = if (seed == 0) 0x9e3779b9 else seed };
    }

    pub fn next(self: *Prng) u32 {
        var x = self.state;
        x ^= x << 13;
        x ^= x >> 17;
        x ^= x << 5;
        self.state = x;
        return x;
    }

    /// Return a value in [0, max).
    pub fn range(self: *Prng, max: u32) u32 {
        return self.next() % max;
    }
};

// Tests for the helpers themselves
test "helpers: compileDefault works" {
    const allocator = testing.allocator;
    const result = try compileDefault(allocator, "OP_DUP");
    defer result.deinit(allocator);
    try testing.expect(result.byte_length > 0);
}

test "helpers: compileWith respects options" {
    const allocator = testing.allocator;
    const result = try compileWith(allocator, "OP_DUP", .{ .emit_asm = true });
    defer result.deinit(allocator);
    try testing.expect(result.asm_text != null);
}

test "helpers: expectBytecodeLength works" {
    const allocator = testing.allocator;
    try expectBytecodeLength(allocator, "OP_DUP OP_DROP", 2);
}

test "helpers: expectNonEmptyBytecode works" {
    const allocator = testing.allocator;
    try expectNonEmptyBytecode(allocator, "OP_HASH160");
}

test "helpers: repeatChar works" {
    const allocator = testing.allocator;
    const buf = try repeatChar(allocator, 'a', 5);
    defer allocator.free(buf);
    try testing.expectEqualSlices(u8, "aaaaa", buf);
}

test "helpers: expectBytesEqual works" {
    try expectBytesEqual("hello", "hello");
}

test "helpers: expectDeterministicBytecode works" {
    const allocator = testing.allocator;
    try expectDeterministicBytecode(allocator, "OP_DUP OP_HASH160 OP_EQUAL");
}

test "helpers: expectBytecodeEquals works" {
    const allocator = testing.allocator;
    try expectBytecodeEquals(allocator, "OP_DUP OP_DROP", "OP_DUP; OP_DROP");
}

test "helpers: expectHashChangesWithOptions works" {
    const allocator = testing.allocator;
    try expectHashChangesWithOptions(allocator, "OP_DUP", .{}, .{ .emit_asm = true });
}

test "helpers: Prng is deterministic" {
    var a = Prng.init(0x1234);
    var b = Prng.init(0x1234);
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        try testing.expectEqual(a.next(), b.next());
    }
    // Different seed -> different stream (with overwhelming probability).
    var c = Prng.init(0x5678);
    try testing.expect(a.next() != c.next());
}
