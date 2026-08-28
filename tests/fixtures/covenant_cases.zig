pub const CovenantCase = struct {
    source: []const u8,
    description: []const u8,
};

pub const cases = &[_]CovenantCase{
    .{
        .source = "OP_XSWAP 2; OP_CAT; OP_HASH256",
        .description = "hashPrevouts builder fragment",
    },
};
