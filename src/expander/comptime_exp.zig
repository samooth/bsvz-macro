const std = @import("std");
const Opcode = @import("bsvz").script.opcode.Opcode;
const builder = @import("bsvz").script.builder;
const AstNode = @import("../parser/ast.zig").AstNode;
const ExpandError = @import("error.zig").ExpandError;
const MacroTable = @import("table.zig").MacroTable;
const MacroDefinition = @import("table.zig").MacroDefinition;
const ParamType = @import("table.zig").ParamType;
const CompileOptions = @import("../lib.zig").CompileOptions;

/// Comptime expansion uses a fixed-size buffer and no allocator.
/// This is for macros where all parameters are comptime-known.
pub const ComptimeExpander = struct {
    pub const max_size = 4096;

    pub fn expandComptime(
        comptime source: []const u8,
        comptime options: CompileOptions,
    ) ExpandError![]const u8 {
        // At comptime, we parse and expand using a fixed buffer
        var buf: [max_size]u8 = undefined;
        var fba = std.heap.FixedBufferAllocator.init(&buf);
        const allocator = fba.allocator();

        // Tokenize
        const Scanner = @import("../lexer/scanner.zig").Scanner;
        var scanner = Scanner.init(source);
        const tokens = try scanner.scanAll(allocator);

        // Parse
        const Parser = @import("../parser/parser.zig").Parser;
        var parser = Parser.init(tokens, allocator);
        const ast = try parser.parse();

        // Setup macro table
        var table = MacroTable.init(allocator);
        const prelude = @import("../prelude.zig");
        try prelude.registerCanonicalMacros(&table);

        // Expand
        const Expander = @import("expander.zig").Expander;
        var expander = Expander.init(&table, options);
        const result = try expander.expand(allocator, ast);

        return result;
    }
};
