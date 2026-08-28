const std = @import("std");

pub fn encodeHex(allocator: std.mem.Allocator, bytes: []const u8) std.mem.Allocator.Error![]const u8 {
    const hex = "0123456789abcdef";
    const out = try allocator.alloc(u8, bytes.len * 2);
    for (bytes, 0..) |b, i| {
        out[i * 2] = hex[b >> 4];
        out[i * 2 + 1] = hex[b & 0xf];
    }
    return out;
}

pub fn decodeHex(allocator: std.mem.Allocator, hex_str: []const u8) (std.mem.Allocator.Error || error{InvalidHex})![]const u8 {
    if (hex_str.len % 2 != 0) return error.InvalidHex;
    const out = try allocator.alloc(u8, hex_str.len / 2);
    errdefer allocator.free(out);
    _ = std.fmt.hexToBytes(out, hex_str) catch return error.InvalidHex;
    return out;
}
