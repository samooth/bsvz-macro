const std = @import("std");
const bsvz = @import("bsvz");

pub const XswapCase = struct {
    source: []const u8,
    expected_asm_text: []const u8,
    expected_hex: []const u8,
};

pub const cases = &[_]XswapCase{
    .{
        .source = "OP_XSWAP[3]",
        .expected_asm_text = "OP_2 OP_PICK OP_2 OP_ROLL OP_SWAP OP_DROP",
        .expected_hex = "5279527a7c75",
    },
    .{
        .source = "OP_XDROP[2]",
        .expected_asm_text = "OP_1 OP_ROLL OP_DROP",
        .expected_hex = "517a75",
    },
    .{
        .source = "OP_HASHCAT",
        .expected_asm_text = "OP_DUP OP_SHA256 OP_SWAP OP_CAT",
        .expected_hex = "76a87c7e",
    },
};
