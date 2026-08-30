pub const LoopCase = struct {
    source: []const u8,
    expected_opcodes: u32,
};

pub const cases = &[_]LoopCase{
    .{
        .source = "LOOP[3]{ OP_DUP OP_MUL }",
        .expected_opcodes = 6,
    },
    .{
        .source = "LOOP[5]{ <i> OP_ADD }",
        .expected_opcodes = 10,
    },
    .{
        .source = "LOOP[4]{ OP_HASHCAT }",
        .expected_opcodes = 16,
    },
};
