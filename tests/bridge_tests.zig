const std = @import("std");
const bsvz_macro = @import("bsvz-macro");
const bsvz = @import("bsvz");
const testing = std.testing;

test "bridge: addP2pkhOutput produces 25-byte locking script" {
    const allocator = testing.allocator;
    var builder = bsvz.transaction.Builder.init(allocator);
    defer builder.deinit();

    const hash = [_]u8{0x01} ** 20;
    try bsvz_macro.bridge.wallet.addP2pkhOutput(&builder, &hash, 1000, .{});
    try testing.expectEqual(@as(usize, 1), builder.outputs.items.len);
    const out = builder.outputs.items[0];
    try testing.expectEqual(@as(usize, 25), out.locking_script.bytes.len);
    try testing.expectEqual(@as(u8, 0x76), out.locking_script.bytes[0]);
    try testing.expectEqual(@as(u8, 0xa9), out.locking_script.bytes[1]);
    try testing.expectEqual(@as(u8, 0x14), out.locking_script.bytes[2]);
    try testing.expectEqual(@as(u8, 0x88), out.locking_script.bytes[23]);
    try testing.expectEqual(@as(u8, 0xac), out.locking_script.bytes[24]);
}

test "bridge: addP2pkhOutput rejects wrong-length hash" {
    const allocator = testing.allocator;
    var builder = bsvz.transaction.Builder.init(allocator);
    defer builder.deinit();
    const bad_hash = [_]u8{0x02} ** 19;
    try testing.expectError(error.ValError, bsvz_macro.bridge.wallet.addP2pkhOutput(&builder, &bad_hash, 1000, .{}));
}

test "bridge: addP2shOutput produces 23-byte locking script" {
    const allocator = testing.allocator;
    var builder = bsvz.transaction.Builder.init(allocator);
    defer builder.deinit();

    const hash = [_]u8{0x03} ** 20;
    try bsvz_macro.bridge.wallet.addP2shOutput(&builder, &hash, 2000, .{});
    try testing.expectEqual(@as(usize, 1), builder.outputs.items.len);
    const out = builder.outputs.items[0];
    try testing.expectEqual(@as(usize, 23), out.locking_script.bytes.len);
    try testing.expectEqual(@as(u8, 0xa9), out.locking_script.bytes[0]);
    try testing.expectEqual(@as(u8, 0x14), out.locking_script.bytes[1]);
    try testing.expectEqual(@as(u8, 0x87), out.locking_script.bytes[22]);
}

test "bridge: addMacroOutput compiles source and adds output" {
    const allocator = testing.allocator;
    var builder = bsvz.transaction.Builder.init(allocator);
    defer builder.deinit();

    try bsvz_macro.bridge.wallet.addMacroOutput(&builder, "OP_1 OP_DROP", 500, .{});
    try testing.expectEqual(@as(usize, 1), builder.outputs.items.len);
    const out = builder.outputs.items[0];
    try testing.expectEqual(@as(i64, 500), out.satoshis);
    // OP_1 = 0x51, OP_DROP = 0x75
    try testing.expectEqualSlices(u8, &.{ 0x51, 0x75 }, out.locking_script.bytes);
}

test "bridge: toBsvzScript wraps expansion bytecode" {
    const allocator = testing.allocator;
    const result = try bsvz_macro.compile(allocator, "OP_1 OP_DROP", .{});
    defer result.deinit(allocator);
    const script = bsvz_macro.bridge.bsvz_bridge.toBsvzScript(result);
    try testing.expectEqualSlices(u8, &.{ 0x51, 0x75 }, script.bytes);
}

test "bridge: bsvz_bridge executeInBsvz runs a simple script" {
    const allocator = testing.allocator;
    // OP_1 OP_1 OP_EQUAL leaves true on the stack
    const bytecode = [_]u8{ 0x51, 0x51, 0x87 };
    var exec = try bsvz_macro.bridge.bsvz_bridge.executeInBsvz(allocator, &bytecode);
    defer exec.deinit(allocator);
    try testing.expect(exec.success);
}

test "bridge: addPelsOutput delegates to addMacroOutput" {
    const allocator = testing.allocator;
    var builder = bsvz.transaction.Builder.init(allocator);
    defer builder.deinit();
    try bsvz_macro.bridge.wallet.addPelsOutput(&builder, "OP_1 OP_DROP", 1234, .{});
    try testing.expectEqual(@as(usize, 1), builder.outputs.items.len);
    try testing.expectEqual(@as(i64, 1234), builder.outputs.items[0].satoshis);
}
