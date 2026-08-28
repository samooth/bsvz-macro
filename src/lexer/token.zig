const std = @import("std");
const Opcode = @import("bsvz").script.opcode.Opcode;

pub const Token = union(enum) {
    opcode: Opcode,
    macro_name: []const u8,
    integer: i64,
    string: []const u8,
    iterator_var: []const u8, // <i>, <j>, etc.
    l_bracket,    // [
    r_bracket,    // ]
    l_brace,      // {
    r_brace,      // }
    semicolon,    // ;
    comma,        // ,
    at,           // @
    else_keyword, // else
    eof,
};

pub const TokenWithLoc = struct {
    token: Token,
    line: u32,
    column: u32,
    offset: u32,
    length: u32,
};
