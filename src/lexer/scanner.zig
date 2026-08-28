const std = @import("std");
const Opcode = @import("bsvz").script.opcode.Opcode;
const Token = @import("token.zig").Token;
const TokenWithLoc = @import("token.zig").TokenWithLoc;
const LexError = @import("error.zig").LexError;

pub const Scanner = struct {
    source: []const u8,
    pos: usize = 0,
    line: u32 = 1,
    column: u32 = 1,
    in_loop_body: bool = false,

    pub fn init(source: []const u8) Scanner {
        return .{ .source = source };
    }

    pub fn scanAll(self: *Scanner, allocator: std.mem.Allocator) LexError![]TokenWithLoc {
        var tokens: std.ArrayList(TokenWithLoc) = .empty;
        defer tokens.deinit(allocator);

        while (true) {
            const tok = try self.nextToken(allocator);
            try tokens.append(tok);
            if (tok.token == .eof) break;
        }

        return tokens.toOwnedSlice();
    }

    fn nextToken(self: *Scanner, allocator: std.mem.Allocator) LexError!TokenWithLoc {
        self.skipWhitespaceAndComments();

        const start_line = self.line;
        const start_col = self.column;
        const start_offset = self.pos;

        if (self.pos >= self.source.len) {
            return .{
                .token = .eof,
                .line = start_line,
                .column = start_col,
                .offset = start_offset,
                .length = 0,
            };
        }

        const c = self.source[self.pos];

        // Single-char tokens
        switch (c) {
            '[' => { self.advance(); return self.makeTok(.l_bracket, start_line, start_col, start_offset, 1); },
            ']' => { self.advance(); return self.makeTok(.r_bracket, start_line, start_col, start_offset, 1); },
            '{' => { self.advance(); return self.makeTok(.l_brace, start_line, start_col, start_offset, 1); },
            '}' => { self.advance(); return self.makeTok(.r_brace, start_line, start_col, start_offset, 1); },
            ';' => { self.advance(); return self.makeTok(.semicolon, start_line, start_col, start_offset, 1); },
            ',' => { self.advance(); return self.makeTok(.comma, start_line, start_col, start_offset, 1); },
            '@' => { self.advance(); return self.makeTok(.at, start_line, start_col, start_offset, 1); },
            '<' => return self.scanIteratorVar(start_line, start_col, start_offset),
            '"' => return self.scanQuotedString(allocator, start_line, start_col, start_offset),
            '0'...'9', '-' => return self.scanNumber(start_line, start_col, start_offset),
            'A'...'Z', 'a'...'z', '_' => return self.scanIdentifier(allocator, start_line, start_col, start_offset),
            else => return LexError.UnrecognizedToken,
        }
    }

    fn makeTok(self: *Scanner, token: Token, line: u32, col: u32, offset: u32, length: u32) TokenWithLoc {
        _ = self;
        return .{
            .token = token,
            .line = line,
            .column = col,
            .offset = offset,
            .length = length,
        };
    }

    fn advance(self: *Scanner) void {
        if (self.pos >= self.source.len) return;
        if (self.source[self.pos] == '\n') {
            self.line += 1;
            self.column = 1;
        } else {
            self.column += 1;
        }
        self.pos += 1;
    }

    fn peek(self: *Scanner) ?u8 {
        if (self.pos + 1 >= self.source.len) return null;
        return self.source[self.pos + 1];
    }

    fn skipWhitespaceAndComments(self: *Scanner) void {
        while (self.pos < self.source.len) {
            const c = self.source[self.pos];
            if (c == ' ' or c == '\t' or c == '\r' or c == '\n') {
                self.advance();
            } else if (c == '/' and self.peek() == '/') {
                // Line comment
                self.advance(); self.advance();
                while (self.pos < self.source.len and self.source[self.pos] != '\n') {
                    self.advance();
                }
            } else if (c == '/' and self.peek() == '*') {
                // Block comment
                self.advance(); self.advance();
                var depth: u32 = 1;
                while (self.pos < self.source.len and depth > 0) {
                    if (self.source[self.pos] == '*' and self.peek() == '/') {
                        self.advance(); self.advance();
                        depth -= 1;
                    } else if (self.source[self.pos] == '/' and self.peek() == '*') {
                        self.advance(); self.advance();
                        depth += 1;
                    } else {
                        self.advance();
                    }
                }
                if (depth > 0) return; // Let caller handle as error if needed
            } else {
                break;
            }
        }
    }

    fn scanNumber(self: *Scanner, line: u32, col: u32, offset: u32) LexError!TokenWithLoc {
        const start = self.pos;
        var negative = false;
        if (self.source[self.pos] == '-') {
            negative = true;
            self.advance();
        }

        // Check for hex literal
        if (!negative and self.source[self.pos] == '0' and self.peek() == 'x') {
            self.advance(); self.advance(); // skip 0x
            const hex_start = self.pos;
            while (self.pos < self.source.len) {
                const c = self.source[self.pos];
                if ((c >= '0' and c <= '9') or (c >= 'a' and c <= 'f') or (c >= 'A' and c <= 'F')) {
                    self.advance();
                } else break;
            }
            if (self.pos == hex_start) return LexError.InvalidHexLiteral;
            const hex_str = self.source[hex_start..self.pos];
            // Validate even length
            if (hex_str.len % 2 != 0) return LexError.InvalidHexLiteral;
            const len = self.pos - start;
            return self.makeTok(.{ .string = self.source[start..self.pos] }, line, col, offset, @intCast(len));
        }

        var has_digits = false;
        while (self.pos < self.source.len) {
            const c = self.source[self.pos];
            if (c >= '0' and c <= '9') {
                has_digits = true;
                self.advance();
            } else break;
        }

        if (!has_digits) return LexError.InvalidLiteral;

        const num_str = self.source[start..self.pos];
        const value = std.fmt.parseInt(i64, num_str, 10) catch return LexError.IntegerOverflow;
        const len = self.pos - start;
        return self.makeTok(.{ .integer = value }, line, col, offset, @intCast(len));
    }

    fn scanQuotedString(self: *Scanner, allocator: std.mem.Allocator, line: u32, col: u32, offset: u32) LexError!TokenWithLoc {
        _ = allocator;
        self.advance(); // skip opening "
        const start = self.pos;
        while (self.pos < self.source.len and self.source[self.pos] != '"') {
            self.advance();
        }
        if (self.pos >= self.source.len) return LexError.UnclosedString;
        const str_content = self.source[start..self.pos];
        self.advance(); // skip closing "
        const len = self.pos - offset;
        return self.makeTok(.{ .string = str_content }, line, col, offset, @intCast(len));
    }

    fn scanIteratorVar(self: *Scanner, line: u32, col: u32, offset: u32) LexError!TokenWithLoc {
        self.advance(); // skip <
        const start = self.pos;
        while (self.pos < self.source.len and self.source[self.pos] != '>') {
            self.advance();
        }
        if (self.pos >= self.source.len) return LexError.UnrecognizedToken;
        const var_name = self.source[start..self.pos];
        self.advance(); // skip >
        const len = self.pos - offset;
        return self.makeTok(.{ .iterator_var = var_name }, line, col, offset, @intCast(len));
    }

    fn scanIdentifier(self: *Scanner, allocator: std.mem.Allocator, line: u32, col: u32, offset: u32) LexError!TokenWithLoc {
        const start = self.pos;
        while (self.pos < self.source.len) {
            const c = self.source[self.pos];
            if ((c >= 'A' and c <= 'Z') or (c >= 'a' and c <= 'z') or (c >= '0' and c <= '9') or c == '_') {
                self.advance();
            } else break;
        }
        const ident = self.source[start..self.pos];
        const len = self.pos - start;

        // Check for "else" keyword
        if (std.mem.eql(u8, ident, "else")) {
            return self.makeTok(.else_keyword, line, col, offset, @intCast(len));
        }

        // Check for OP_ prefix -> opcode or macro_name
        if (std.mem.startsWith(u8, ident, "OP_")) {
            // Try to match as opcode first
            const op = opcodeFromName(ident);
            if (op) |opcode| {
                return self.makeTok(.{ .opcode = opcode }, line, col, offset, @intCast(len));
            }
            // Otherwise it's a macro name
            return self.makeTok(.{ .macro_name = try allocator.dupe(u8, ident) }, line, col, offset, @intCast(len));
        }

        // Regular identifier -> macro name
        return self.makeTok(.{ .macro_name = try allocator.dupe(u8, ident) }, line, col, offset, @intCast(len));
    }
};

fn opcodeFromName(name: []const u8) ?Opcode {
    // Map common opcode names to enum values
    const map = .{
        .{ "OP_0", Opcode.OP_0 },
        .{ "OP_FALSE", Opcode.OP_0 },
        .{ "OP_PUSHDATA1", Opcode.OP_PUSHDATA1 },
        .{ "OP_PUSHDATA2", Opcode.OP_PUSHDATA2 },
        .{ "OP_PUSHDATA4", Opcode.OP_PUSHDATA4 },
        .{ "OP_1NEGATE", Opcode.OP_1NEGATE },
        .{ "OP_RESERVED", Opcode.OP_RESERVED },
        .{ "OP_1", Opcode.OP_1 },
        .{ "OP_TRUE", Opcode.OP_1 },
        .{ "OP_2", Opcode.OP_2 },
        .{ "OP_3", Opcode.OP_3 },
        .{ "OP_4", Opcode.OP_4 },
        .{ "OP_5", Opcode.OP_5 },
        .{ "OP_6", Opcode.OP_6 },
        .{ "OP_7", Opcode.OP_7 },
        .{ "OP_8", Opcode.OP_8 },
        .{ "OP_9", Opcode.OP_9 },
        .{ "OP_10", Opcode.OP_10 },
        .{ "OP_11", Opcode.OP_11 },
        .{ "OP_12", Opcode.OP_12 },
        .{ "OP_13", Opcode.OP_13 },
        .{ "OP_14", Opcode.OP_14 },
        .{ "OP_15", Opcode.OP_15 },
        .{ "OP_16", Opcode.OP_16 },
        .{ "OP_NOP", Opcode.OP_NOP },
        .{ "OP_VER", Opcode.OP_VER },
        .{ "OP_IF", Opcode.OP_IF },
        .{ "OP_NOTIF", Opcode.OP_NOTIF },
        .{ "OP_VERIF", Opcode.OP_VERIF },
        .{ "OP_VERNOTIF", Opcode.OP_VERNOTIF },
        .{ "OP_ELSE", Opcode.OP_ELSE },
        .{ "OP_ENDIF", Opcode.OP_ENDIF },
        .{ "OP_VERIFY", Opcode.OP_VERIFY },
        .{ "OP_RETURN", Opcode.OP_RETURN },
        .{ "OP_TOALTSTACK", Opcode.OP_TOALTSTACK },
        .{ "OP_FROMALTSTACK", Opcode.OP_FROMALTSTACK },
        .{ "OP_2DROP", Opcode.OP_2DROP },
        .{ "OP_2DUP", Opcode.OP_2DUP },
        .{ "OP_3DUP", Opcode.OP_3DUP },
        .{ "OP_2OVER", Opcode.OP_2OVER },
        .{ "OP_2ROT", Opcode.OP_2ROT },
        .{ "OP_2SWAP", Opcode.OP_2SWAP },
        .{ "OP_IFDUP", Opcode.OP_IFDUP },
        .{ "OP_DEPTH", Opcode.OP_DEPTH },
        .{ "OP_DROP", Opcode.OP_DROP },
        .{ "OP_DUP", Opcode.OP_DUP },
        .{ "OP_NIP", Opcode.OP_NIP },
        .{ "OP_OVER", Opcode.OP_OVER },
        .{ "OP_PICK", Opcode.OP_PICK },
        .{ "OP_ROLL", Opcode.OP_ROLL },
        .{ "OP_ROT", Opcode.OP_ROT },
        .{ "OP_SWAP", Opcode.OP_SWAP },
        .{ "OP_TUCK", Opcode.OP_TUCK },
        .{ "OP_CAT", Opcode.OP_CAT },
        .{ "OP_SPLIT", Opcode.OP_SPLIT },
        .{ "OP_NUM2BIN", Opcode.OP_NUM2BIN },
        .{ "OP_BIN2NUM", Opcode.OP_BIN2NUM },
        .{ "OP_SIZE", Opcode.OP_SIZE },
        .{ "OP_INVERT", Opcode.OP_INVERT },
        .{ "OP_AND", Opcode.OP_AND },
        .{ "OP_OR", Opcode.OP_OR },
        .{ "OP_XOR", Opcode.OP_XOR },
        .{ "OP_EQUAL", Opcode.OP_EQUAL },
        .{ "OP_EQUALVERIFY", Opcode.OP_EQUALVERIFY },
        .{ "OP_RESERVED1", Opcode.OP_RESERVED1 },
        .{ "OP_RESERVED2", Opcode.OP_RESERVED2 },
        .{ "OP_1ADD", Opcode.OP_1ADD },
        .{ "OP_1SUB", Opcode.OP_1SUB },
        .{ "OP_2MUL", Opcode.OP_2MUL },
        .{ "OP_2DIV", Opcode.OP_2DIV },
        .{ "OP_NEGATE", Opcode.OP_NEGATE },
        .{ "OP_ABS", Opcode.OP_ABS },
        .{ "OP_NOT", Opcode.OP_NOT },
        .{ "OP_0NOTEQUAL", Opcode.OP_0NOTEQUAL },
        .{ "OP_ADD", Opcode.OP_ADD },
        .{ "OP_SUB", Opcode.OP_SUB },
        .{ "OP_MUL", Opcode.OP_MUL },
        .{ "OP_DIV", Opcode.OP_DIV },
        .{ "OP_MOD", Opcode.OP_MOD },
        .{ "OP_LSHIFT", Opcode.OP_LSHIFT },
        .{ "OP_RSHIFT", Opcode.OP_RSHIFT },
        .{ "OP_BOOLAND", Opcode.OP_BOOLAND },
        .{ "OP_BOOLOR", Opcode.OP_BOOLOR },
        .{ "OP_NUMEQUAL", Opcode.OP_NUMEQUAL },
        .{ "OP_NUMEQUALVERIFY", Opcode.OP_NUMEQUALVERIFY },
        .{ "OP_NUMNOTEQUAL", Opcode.OP_NUMNOTEQUAL },
        .{ "OP_LESSTHAN", Opcode.OP_LESSTHAN },
        .{ "OP_GREATERTHAN", Opcode.OP_GREATERTHAN },
        .{ "OP_LESSTHANOREQUAL", Opcode.OP_LESSTHANOREQUAL },
        .{ "OP_GREATERTHANOREQUAL", Opcode.OP_GREATERTHANOREQUAL },
        .{ "OP_MIN", Opcode.OP_MIN },
        .{ "OP_MAX", Opcode.OP_MAX },
        .{ "OP_WITHIN", Opcode.OP_WITHIN },
        .{ "OP_RIPEMD160", Opcode.OP_RIPEMD160 },
        .{ "OP_SHA1", Opcode.OP_SHA1 },
        .{ "OP_SHA256", Opcode.OP_SHA256 },
        .{ "OP_HASH160", Opcode.OP_HASH160 },
        .{ "OP_HASH256", Opcode.OP_HASH256 },
        .{ "OP_CODESEPARATOR", Opcode.OP_CODESEPARATOR },
        .{ "OP_CHECKSIG", Opcode.OP_CHECKSIG },
        .{ "OP_CHECKSIGVERIFY", Opcode.OP_CHECKSIGVERIFY },
        .{ "OP_CHECKMULTISIG", Opcode.OP_CHECKMULTISIG },
        .{ "OP_CHECKMULTISIGVERIFY", Opcode.OP_CHECKMULTISIGVERIFY },
        .{ "OP_NOP1", Opcode.OP_NOP1 },
        .{ "OP_CHECKLOCKTIMEVERIFY", Opcode.OP_CHECKLOCKTIMEVERIFY },
        .{ "OP_CHECKSEQUENCEVERIFY", Opcode.OP_CHECKSEQUENCEVERIFY },
        .{ "OP_NOP4", Opcode.OP_NOP4 },
        .{ "OP_NOP5", Opcode.OP_NOP5 },
        .{ "OP_NOP6", Opcode.OP_NOP6 },
        .{ "OP_NOP7", Opcode.OP_NOP7 },
        .{ "OP_NOP8", Opcode.OP_NOP8 },
        .{ "OP_NOP9", Opcode.OP_NOP9 },
        .{ "OP_NOP10", Opcode.OP_NOP10 },
        .{ "OP_LSHIFTNUM", Opcode.OP_LSHIFTNUM },
        .{ "OP_RSHIFTNUM", Opcode.OP_RSHIFTNUM },
        .{ "OP_SUBSTR", Opcode.OP_SUBSTR },
        .{ "OP_LEFT", Opcode.OP_LEFT },
        .{ "OP_RIGHT", Opcode.OP_RIGHT },
    };

    inline for (map) |entry| {
        if (std.mem.eql(u8, name, entry[0])) return entry[1];
    }
    return null;
}

// Tests
const testing = std.testing;

test "scan simple opcodes" {
    var s = Scanner.init("OP_DUP OP_HASH160 OP_EQUALVERIFY");
    const tokens = try s.scanAll(testing.allocator);
    defer {
        for (tokens) |t| {
            switch (t.token) {
                .macro_name, .string, .iterator_var => |v| testing.allocator.free(v),
                else => {},
            }
        }
        testing.allocator.free(tokens);
    }

    try testing.expectEqual(@as(usize, 4), tokens.len); // 3 opcodes + eof
    try testing.expect(tokens[0].token == .opcode);
    try testing.expect(tokens[1].token == .opcode);
    try testing.expect(tokens[2].token == .opcode);
}

test "scan integer and macro" {
    var s = Scanner.init("OP_XSWAP 3");
    const tokens = try s.scanAll(testing.allocator);
    defer {
        for (tokens) |t| {
            switch (t.token) {
                .macro_name, .string, .iterator_var => |v| testing.allocator.free(v),
                else => {},
            }
        }
        testing.allocator.free(tokens);
    }

    try testing.expectEqual(@as(usize, 3), tokens.len);
    try testing.expect(tokens[0].token == .macro_name);
    try testing.expect(tokens[1].token == .integer);
    try testing.expectEqual(@as(i64, 3), tokens[1].token.integer);
}

test "scan loop block" {
    var s = Scanner.init("LOOP[5]{ OP_DUP OP_MUL }");
    const tokens = try s.scanAll(testing.allocator);
    defer {
        for (tokens) |t| {
            switch (t.token) {
                .macro_name, .string, .iterator_var => |v| testing.allocator.free(v),
                else => {},
            }
        }
        testing.allocator.free(tokens);
    }

    try testing.expect(tokens[0].token == .macro_name);
    try testing.expect(tokens[1].token == .l_bracket);
    try testing.expect(tokens[2].token == .integer);
    try testing.expect(tokens[3].token == .r_bracket);
    try testing.expect(tokens[4].token == .l_brace);
    try testing.expect(tokens[5].token == .opcode);
    try testing.expect(tokens[6].token == .opcode);
    try testing.expect(tokens[7].token == .r_brace);
}

test "scan comments" {
    var s = Scanner.init("OP_DUP // duplicate\nOP_DROP /* remove */");
    const tokens = try s.scanAll(testing.allocator);
    defer {
        for (tokens) |t| {
            switch (t.token) {
                .macro_name, .string, .iterator_var => |v| testing.allocator.free(v),
                else => {},
            }
        }
        testing.allocator.free(tokens);
    }

    try testing.expectEqual(@as(usize, 3), tokens.len);
    try testing.expect(tokens[0].token == .opcode);
    try testing.expect(tokens[1].token == .opcode);
}
