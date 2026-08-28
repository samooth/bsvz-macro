const std = @import("std");
const bsvz_macro = @import("bsvz-macro");
const bsvz = @import("bsvz");
const testing = std.testing;
const Opcode = bsvz.script.opcode.Opcode;

// Test data builders for creating script sources.
// These work with the public API and don't require access to internal AST types.

// Builder for creating a script source string from opcodes and values.
pub const ScriptBuilder = struct {
    allocator: std.mem.Allocator,
    source: std.ArrayList(u8),

    pub fn init(allocator: std.mem.Allocator) ScriptBuilder {
        return .{
            .allocator = allocator,
            .source = .empty,
        };
    }

    pub fn deinit(self: *ScriptBuilder) void {
        self.source.deinit(self.allocator);
    }

    /// Add an opcode to the script.
    pub fn addOpcode(self: *ScriptBuilder, op: Opcode) !void {
        const name = @tagName(op);
        try self.source.appendSlice(self.allocator, name);
        try self.source.append(self.allocator, ' ');
    }

    /// Add raw text to the script.
    pub fn addRaw(self: *ScriptBuilder, text: []const u8) !void {
        try self.source.appendSlice(self.allocator, text);
        try self.source.append(self.allocator, ' ');
    }

    /// Build and return the source string.
    pub fn build(self: *ScriptBuilder) ![]const u8 {
        // Remove trailing space
        if (self.source.items.len > 0 and self.source.items[self.source.items.len - 1] == ' ') {
            _ = self.source.pop();
        }
        return try self.source.toOwnedSlice(self.allocator);
    }
};

/// Convenience function to get an opcode's name.
pub fn opcodeName(op: Opcode) []const u8 {
    return @tagName(op);
}

// Tests for the builders
test "builders: ScriptBuilder creates simple script" {
    const allocator = testing.allocator;
    var builder = ScriptBuilder.init(allocator);
    defer builder.deinit();

    try builder.addOpcode(Opcode.OP_DUP);
    try builder.addOpcode(Opcode.OP_DROP);

    const source = try builder.build();
    defer allocator.free(source);
    try testing.expectEqualStrings("OP_DUP OP_DROP", source);
}

test "builders: ScriptBuilder with multiple opcodes" {
    const allocator = testing.allocator;
    var builder = ScriptBuilder.init(allocator);
    defer builder.deinit();

    try builder.addOpcode(Opcode.OP_1);
    try builder.addOpcode(Opcode.OP_2);
    try builder.addOpcode(Opcode.OP_ADD);

    const source = try builder.build();
    defer allocator.free(source);
    try testing.expectEqualStrings("OP_1 OP_2 OP_ADD", source);
}

test "builders: ScriptBuilder with raw text" {
    const allocator = testing.allocator;
    var builder = ScriptBuilder.init(allocator);
    defer builder.deinit();

    try builder.addOpcode(Opcode.OP_DUP);
    try builder.addRaw("OP_DROP");
    try builder.addOpcode(Opcode.OP_HASH160);

    const source = try builder.build();
    defer allocator.free(source);
    try testing.expectEqualStrings("OP_DUP OP_DROP OP_HASH160", source);
}

test "builders: opcodeName returns correct name" {
    try testing.expectEqualStrings("OP_DUP", opcodeName(Opcode.OP_DUP));
    try testing.expectEqualStrings("OP_HASH160", opcodeName(Opcode.OP_HASH160));
}
