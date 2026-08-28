const std = @import("std");
const Opcode = @import("bsvz").script.opcode.Opcode;
const builder = @import("bsvz").script.builder;

pub fn encodeMinimalPush(value: i64, buf: []u8) u8 {
    if (value == 0) {
        buf[0] = Opcode.OP_0.toByte();
        return 1;
    }
    if (value >= 1 and value <= 16) {
        buf[0] = @intCast(0x50 + value);
        return 1;
    }
    if (value == -1) {
        buf[0] = Opcode.OP_1NEGATE.toByte();
        return 1;
    }
    // ScriptNum
    const negative = value < 0;
    var abs_val = if (negative) -value else value;
    var i: usize = 0;
    while (abs_val > 0) : (i += 1) {
        buf[i + 1] = @truncate(abs_val);
        abs_val >>= 8;
    }
    if (i > 0 and (buf[i] & 0x80) != 0) {
        i += 1;
        buf[i] = if (negative) 0x80 else 0x00;
    } else if (negative and i > 0) {
        buf[i] |= 0x80;
    }
    buf[0] = @intCast(i);
    @memcpy(buf[1..][0..i], buf[1..][0..i]);
    return @intCast(1 + i);
}
