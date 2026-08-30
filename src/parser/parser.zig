const std = @import("std");
const TokenWithLoc = @import("../lexer/token.zig").TokenWithLoc;
const Token = @import("../lexer/token.zig").Token;
const AstNode = @import("ast.zig").AstNode;
const Condition = @import("ast.zig").Condition;
const FeatureFlag = @import("ast.zig").FeatureFlag;
const ParseError = @import("error.zig").ParseError;
const DiagnosticList = @import("../diagnostics.zig").DiagnosticList;
const SourceLocation = @import("../diagnostics.zig").SourceLocation;

pub const Parser = struct {
    tokens: []const TokenWithLoc,
    pos: usize = 0,
    allocator: std.mem.Allocator,
    diagnostics: ?*DiagnosticList = null,
    recovery_depth: u32 = 0,
    /// When true, parse errors are recorded as diagnostics and parsing
    /// continues at the next statement boundary to accumulate more errors
    /// before failing with the first error seen. When false, the first
    /// error propagates immediately (fail-fast).
    recover: bool = false,

    pub fn init(tokens: []const TokenWithLoc, allocator: std.mem.Allocator) Parser {
        return .{
            .tokens = tokens,
            .allocator = allocator,
        };
    }

    pub fn parse(self: *Parser) ParseError![]const AstNode {
        var statements: std.ArrayList(AstNode) = .empty;
        defer statements.deinit(self.allocator);

        while (!self.isAtEnd()) {
            const stmt = self.parseStatement() catch |e| {
                if (!self.recover) return e;
                self.report(e, self.locAtCurrent());
                if (!self.recoverToStatementBoundary()) return e;
                continue;
            };
            try statements.append(self.allocator, stmt);

            // Optional semicolon between statements
            if (self.match(.semicolon)) {
                continue;
            }
        }

        return statements.toOwnedSlice(self.allocator);
    }

    /// Parse and also return per-statement source locations (parallel to the
    /// returned slice, one entry per successfully parsed statement).
    /// With `recover` enabled, all parse errors are accumulated into
    /// `diagnostics` before failing with the first error seen.
    pub fn parseWithLocations(self: *Parser, out_locs: *std.ArrayListUnmanaged(SourceLocation)) ParseError![]const AstNode {
        var statements: std.ArrayList(AstNode) = .empty;
        defer statements.deinit(self.allocator);

        var first_error: ?ParseError = null;

        while (!self.isAtEnd()) {
            const stmt_start = self.locAtCurrent();
            const stmt = self.parseStatement() catch |e| {
                if (!self.recover) return e;
                if (first_error == null) first_error = e;
                self.report(e, self.locAtCurrent());
                if (!self.recoverToStatementBoundary()) return first_error.?;
                continue;
            };
            try statements.append(self.allocator, stmt);
            try out_locs.append(self.allocator, stmt_start);

            if (self.match(.semicolon)) {
                continue;
            }
        }

        if (first_error != null) return first_error.?;
        return statements.toOwnedSlice(self.allocator);
    }

    fn report(self: *Parser, err: anyerror, location: SourceLocation) void {
        const diags = self.diagnostics orelse return;
        diags.append(.parse, .@"error", "parse error: {s}", location, .{@errorName(err)});
    }

    fn locAtCurrent(self: *Parser) SourceLocation {
        if (self.pos < self.tokens.len) {
            const t = self.tokens[self.pos];
            return .{ .line = t.line, .column = t.column, .offset = t.offset, .length = t.length };
        }
        return .{ .line = 0, .column = 0, .offset = 0, .length = 0 };
    }

    fn recoverToStatementBoundary(self: *Parser) bool {
        if (self.recovery_depth >= 16) return false;
        self.recovery_depth += 1;
        defer self.recovery_depth -= 1;

        // Skip tokens until a plausible statement start after a ';' or '}'.
        var depth: i32 = 0;
        while (!self.isAtEnd()) {
            const tag = std.meta.activeTag(self.peek().token);
            if (depth == 0) {
                if (tag == .semicolon) {
                    _ = self.advance();
                    return true;
                }
                if (tag == .r_brace) {
                    // Consume the closing brace so the caller does not
                    // immediately fail on it again.
                    _ = self.advance();
                    return true;
                }
            }
            if (tag == .l_brace) depth += 1;
            if (tag == .r_brace) depth -= 1;
            _ = self.advance();
        }
        return false;
    }

    fn parseStatement(self: *Parser) ParseError!AstNode {
        if (self.check(.opcode)) {
            return self.parseOpcodeLiteral();
        }
        if (self.check(.macro_name)) {
            const name = self.peek().token.macro_name;
            if (std.mem.eql(u8, name, "LOOP")) {
                return self.parseLoopBlock();
            }
            return self.parseMacroInvocation();
        }
        if (self.check(.at)) {
            return self.parseConditional();
        }
        if (self.check(.iterator_var)) {
            return self.parseIteratorRef();
        }
        if (self.check(.l_brace)) {
            return self.parseBlock();
        }
        return ParseError.UnexpectedToken;
    }

    fn parseIteratorRef(self: *Parser) ParseError!AstNode {
        const tok = self.advance();
        return .{ .iterator_ref = try self.allocator.dupe(u8, tok.token.iterator_var) };
    }

    fn parseOpcodeLiteral(self: *Parser) AstNode {
        const tok = self.advance();
        return .{ .opcode_literal = tok.token.opcode };
    }

    fn parseMacroInvocation(self: *Parser) ParseError!AstNode {
        const name_tok = self.advance();
        const name = try self.allocator.dupe(u8, name_tok.token.macro_name);
        errdefer self.allocator.free(name);

        var args: std.ArrayList(AstNode) = .empty;
        defer args.deinit(self.allocator);

        // Optional argument list: [arg1, arg2, ...]
        if (self.match(.l_bracket)) {
            while (!self.check(.r_bracket) and !self.isAtEnd()) {
                const arg = try self.parseArg();
                try args.append(self.allocator, arg);
                if (!self.match(.comma)) break;
            }
            if (!self.match(.r_bracket)) return ParseError.UnexpectedToken;
        }

        // Optional body: { ... }
        var body: ?[]const AstNode = null;
        if (self.match(.l_brace)) {
            body = try self.parseBody();
            if (!self.match(.r_brace)) return ParseError.UnexpectedToken;
        }

        return .{
            .macro_invocation = .{
                .name = name,
                .args = try args.toOwnedSlice(self.allocator),
                .body = body,
            },
        };
    }

    fn parseLoopBlock(self: *Parser) ParseError!AstNode {
        _ = self.advance(); // consume LOOP

        if (!self.match(.l_bracket)) return ParseError.UnexpectedToken;
        if (!self.check(.integer)) return ParseError.InvalidLoopBound;
        const bound_tok = self.advance();
        const bound = bound_tok.token.integer;
        if (bound < 0) return ParseError.InvalidLoopBound;
        if (!self.match(.r_bracket)) return ParseError.UnexpectedToken;

        if (!self.match(.l_brace)) return ParseError.UnexpectedToken;
        const body = try self.parseBody();
        if (!self.match(.r_brace)) return ParseError.UnexpectedToken;

        return .{
            .loop_block = .{
                .bound = @intCast(bound),
                .iterator_var = try self.allocator.dupe(u8, "i"),
                .body = body,
            },
        };
    }

    fn parseConditional(self: *Parser) ParseError!AstNode {
        _ = self.advance(); // consume @
        if (!self.check(.macro_name)) return ParseError.InvalidCondition;
        const flag_tok = self.advance();
        const flag_name = flag_tok.token.macro_name;

        var condition: Condition = undefined;
        if (std.mem.eql(u8, flag_name, "bsv")) {
            condition = .{ .feature_flag = .bsv };
        } else if (std.mem.eql(u8, flag_name, "chronicle")) {
            condition = .{ .feature_flag = .chronicle };
        } else if (std.mem.eql(u8, flag_name, "btc_strict")) {
            condition = .{ .feature_flag = .btc_strict };
        } else if (std.mem.eql(u8, flag_name, "version")) {
            if (!self.match(.l_bracket)) return ParseError.InvalidCondition;
            if (!self.check(.integer)) return ParseError.InvalidCondition;
            const ver_tok = self.advance();
            condition = .{ .version_check = @intCast(ver_tok.token.integer) };
            if (!self.match(.r_bracket)) return ParseError.InvalidCondition;
        } else {
            return ParseError.InvalidCondition;
        }

        if (!self.match(.l_brace)) return ParseError.UnexpectedToken;
        const then_branch = try self.parseBody();
        if (!self.match(.r_brace)) return ParseError.UnexpectedToken;

        var else_branch: ?[]const AstNode = null;
        if (self.match(.else_keyword)) {
            if (!self.match(.l_brace)) return ParseError.UnexpectedToken;
            else_branch = try self.parseBody();
            if (!self.match(.r_brace)) return ParseError.UnexpectedToken;
        }

        return .{
            .conditional = .{
                .condition = condition,
                .then_branch = then_branch,
                .else_branch = else_branch,
            },
        };
    }

    fn parseBlock(self: *Parser) ParseError!AstNode {
        _ = self.advance(); // consume {
        const body = try self.parseBody();
        if (!self.match(.r_brace)) return ParseError.UnexpectedToken;
        return .{ .block = body };
    }

    fn parseBody(self: *Parser) ParseError![]const AstNode {
        var statements: std.ArrayList(AstNode) = .empty;
        defer statements.deinit(self.allocator);

        while (!self.check(.r_brace) and !self.isAtEnd()) {
            const stmt = try self.parseStatement();
            try statements.append(self.allocator, stmt);
            if (self.match(.semicolon)) continue;
        }

        return statements.toOwnedSlice(self.allocator);
    }

    fn parseArg(self: *Parser) ParseError!AstNode {
        if (self.check(.iterator_var)) {
            const tok = self.advance();
            return .{ .iterator_ref = try self.allocator.dupe(u8, tok.token.iterator_var) };
        }
        if (self.check(.integer)) {
            const tok = self.advance();
            return .{ .integer_literal = tok.token.integer };
        }
        if (self.check(.string)) {
            const tok = self.advance();
            return .{ .string_literal = try self.allocator.dupe(u8, tok.token.string) };
        }
        if (self.check(.opcode)) {
            const tok = self.advance();
            return .{ .opcode_literal = tok.token.opcode };
        }
        return ParseError.UnexpectedToken;
    }

    fn match(self: *Parser, tag: std.meta.Tag(Token)) bool {
        if (self.check(tag)) {
            _ = self.advance();
            return true;
        }
        return false;
    }

    fn check(self: *Parser, tag: std.meta.Tag(Token)) bool {
        if (self.isAtEnd()) return false;
        return std.meta.activeTag(self.peek().token) == tag;
    }

    fn advance(self: *Parser) TokenWithLoc {
        if (!self.isAtEnd()) self.pos += 1;
        return self.tokens[self.pos - 1];
    }

    fn isAtEnd(self: *Parser) bool {
        return self.pos >= self.tokens.len or self.peek().token == .eof;
    }

    fn peek(self: *Parser) TokenWithLoc {
        return self.tokens[self.pos];
    }
};

// Tests
const testing = std.testing;
const Scanner = @import("../lexer/scanner.zig").Scanner;

fn parseSource(allocator: std.mem.Allocator, source: []const u8) ![]const AstNode {
    var scanner = Scanner.init(source);
    const tokens = try scanner.scanAll(allocator);
    defer {
        for (tokens) |t| {
            switch (t.token) {
                .macro_name, .string, .iterator_var => |v| allocator.free(v),
                else => {},
            }
        }
        allocator.free(tokens);
    }
    var parser = Parser.init(tokens, allocator);
    return try parser.parse();
}

fn freeAst(allocator: std.mem.Allocator, nodes: []const AstNode) void {
    for (nodes) |node| {
        switch (node) {
            .macro_invocation => |m| {
                allocator.free(m.name);
                for (m.args) |arg| {
                    switch (arg) {
                        .string_literal => |s| allocator.free(s),
                        else => {},
                    }
                }
                allocator.free(m.args);
                if (m.body) |body| {
                    freeAst(allocator, body);
                    allocator.free(body);
                }
            },
            .loop_block => |l| {
                allocator.free(l.iterator_var);
                freeAst(allocator, l.body);
                allocator.free(l.body);
            },
            .conditional => |c| {
                freeAst(allocator, c.then_branch);
                allocator.free(c.then_branch);
                if (c.else_branch) |eb| {
                    freeAst(allocator, eb);
                    allocator.free(eb);
                }
            },
            .block => |b| {
                freeAst(allocator, b);
                allocator.free(b);
            },
            .string_literal => |s| allocator.free(s),
            else => {},
        }
    }
}

test "parse simple opcodes" {
    const allocator = testing.allocator;
    const ast = try parseSource(allocator, "OP_DUP OP_HASH160");
    defer {
        freeAst(allocator, ast);
        allocator.free(ast);
    }

    try testing.expectEqual(@as(usize, 2), ast.len);
    try testing.expect(ast[0] == .opcode_literal);
    try testing.expect(ast[1] == .opcode_literal);
}

test "parse macro invocation with args" {
    const allocator = testing.allocator;
    const ast = try parseSource(allocator, "OP_XSWAP[3]");
    defer {
        freeAst(allocator, ast);
        allocator.free(ast);
    }

    try testing.expectEqual(@as(usize, 1), ast.len);
    try testing.expect(ast[0] == .macro_invocation);
    try testing.expectEqualStrings("OP_XSWAP", ast[0].macro_invocation.name);
    try testing.expectEqual(@as(usize, 1), ast[0].macro_invocation.args.len);
    try testing.expect(ast[0].macro_invocation.args[0] == .integer_literal);
    try testing.expectEqual(@as(i64, 3), ast[0].macro_invocation.args[0].integer_literal);
}

test "parse loop block" {
    const allocator = testing.allocator;
    const ast = try parseSource(allocator, "LOOP[3]{ OP_DUP OP_MUL }");
    defer {
        freeAst(allocator, ast);
        allocator.free(ast);
    }

    try testing.expectEqual(@as(usize, 1), ast.len);
    try testing.expect(ast[0] == .loop_block);
    try testing.expectEqual(@as(u64, 3), ast[0].loop_block.bound);
    try testing.expectEqual(@as(usize, 2), ast[0].loop_block.body.len);
}

test "parse conditional" {
    const allocator = testing.allocator;
    const ast = try parseSource(allocator, "@bsv{ OP_CAT } else { OP_NOP }");
    defer {
        freeAst(allocator, ast);
        allocator.free(ast);
    }

    try testing.expectEqual(@as(usize, 1), ast.len);
    try testing.expect(ast[0] == .conditional);
    try testing.expect(ast[0].conditional.else_branch != null);
}
