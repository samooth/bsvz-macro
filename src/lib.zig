const std = @import("std");
const bsvz = @import("bsvz");

pub const lexer = @import("lexer/scanner.zig");
pub const parser = @import("parser/parser.zig");
pub const expander = @import("expander/expander.zig");
pub const prelude = @import("prelude.zig");
pub const simulator = @import("simulator/engine.zig");
pub const validator = @import("validator/bounds.zig");
pub const encoder = @import("encoder/hex.zig");

pub const Target = enum {
    bsv_mainnet,
    bsv_testnet,
    btc_strict,
};

pub const CompileOptions = struct {
    target: Target = .bsv_mainnet,
    enforce_standardness: bool = true,
    max_script_size: u32 = 10_000,
    max_stack_elements: u16 = 1_000,
    max_push_size: u16 = 520,
    emit_asm: bool = false,
};

pub const MacroExpansion = struct {
    bytecode: []const u8,
    asm_text: ?[]const u8,
    hash: [32]u8,
    opcode_count: u32,
    byte_length: u32,
    max_stack_height: u16,
    is_standard: bool,

    pub fn deinit(self: *const MacroExpansion, allocator: std.mem.Allocator) void {
        allocator.free(self.bytecode);
        if (self.asm_text) |t| allocator.free(t);
    }
};

pub const MacroError = error{
    LexError,
    ParseError,
    ExpandError,
    SimError,
    ValError,
    OutOfMemory,
};

pub fn compile(
    allocator: std.mem.Allocator,
    source: []const u8,
    options: CompileOptions,
) MacroError!MacroExpansion {
    // Phase 1: Lex
    var scanner = lexer.Scanner.init(source);
    const tokens = scanner.scanAll(allocator) catch return MacroError.LexError;
    defer {
        for (tokens) |t| {
            switch (t.token) {
                .macro_name, .string, .iterator_var => |v| allocator.free(v),
                else => {},
            }
        }
        allocator.free(tokens);
    }

    // Phase 2: Parse
    var p = parser.Parser.init(tokens, allocator);
    const ast_nodes = p.parse() catch return MacroError.ParseError;
    defer {
        for (ast_nodes) |node| deinitAstNode(allocator, node);
        allocator.free(ast_nodes);
    }

    // Phase 3: Setup macro table
    const MacroTable = @import("expander/table.zig").MacroTable;
    var table = MacroTable.init(allocator);
    defer table.deinit();
    prelude.registerCanonicalMacros(&table) catch return MacroError.ExpandError;

    // Phase 4: Expand
    const Expander = @import("expander/expander.zig").Expander;
    var expander_inst = Expander.init(&table, options);
    const bytecode = expander_inst.expand(allocator, ast_nodes) catch return MacroError.ExpandError;

    // Phase 5: Simulate
    const SymbolicEngine = simulator.SymbolicEngine;
    const StackType = @import("simulator/stack.zig").StackType;
    var engine = SymbolicEngine.init(allocator);
    defer engine.deinit();

    // Pre-populate stack with dummy items for macro expansion simulation
    // Macros are meant to be used with existing stack items.
    // We use .integer so subsequent arithmetic ops don't trigger type errors.
    const pre_populated: u16 = 4;
    for (0..pre_populated) |_| {
        try engine.main_stack.push(allocator, .{ .type = StackType.integer });
    }

    const sim_report = engine.simulate(bytecode, options.max_stack_elements) catch |e| {
        allocator.free(bytecode);
        return switch (e) {
            error.StackUnderflow, error.StackOverflow, error.TypeMismatch, error.PushTooLarge => MacroError.SimError,
            else => MacroError.OutOfMemory,
        };
    };
    defer allocator.free(sim_report.final_stack);

    // Phase 6: Validate
    const BoundsValidator = @import("validator/bounds.zig").BoundsValidator;
    var bv = BoundsValidator.init(options);
    const is_standard = bv.validate(bytecode, sim_report.max_stack_height) catch |e| {
        allocator.free(bytecode);
        return switch (e) {
            error.ScriptTooLarge, error.StackTooDeep, error.PushTooLarge, error.NonStandard => MacroError.ValError,
            else => MacroError.OutOfMemory,
        };
    };

// Phase 7: ASM (optional)
     var asm_text: ?[]const u8 = null;
     if (options.emit_asm) {
         asm_text = @import("encoder/asm.zig").toAsm(allocator, bytecode) catch |e| {
             allocator.free(bytecode);
             return switch (e) {
                 else => MacroError.OutOfMemory,
             };
         };
     }

     // Hash
     var hash: [32]u8 = undefined;
     var hasher = std.crypto.hash.sha2.Sha256.init(.{});
     hasher.update(source);
     hasher.update(std.mem.asBytes(&options));
     hasher.final(&hash);

     return .{
         .bytecode = bytecode,
         .asm_text = asm_text,
         .hash = hash,
         .opcode_count = @intCast(bytecode.len),
         .byte_length = @intCast(bytecode.len),
         .max_stack_height = if (sim_report.max_stack_height > pre_populated)
            sim_report.max_stack_height - pre_populated
        else
            0,
         .is_standard = is_standard,
     };
}

pub fn compileComptime(
    comptime source: []const u8,
    comptime options: CompileOptions,
) MacroError!MacroExpansion {
    var buf: [4096]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buf);
    const allocator = fba.allocator();
    return compile(allocator, source, options) catch unreachable;
}

pub fn validateStack(
    allocator: std.mem.Allocator,
    bytecode: []const u8,
    expected_pre: []const @import("simulator/stack.zig").StackType,
    expected_post: []const @import("simulator/stack.zig").StackType,
) MacroError!void {
    const SymbolicEngine = simulator.SymbolicEngine;
    var engine = SymbolicEngine.init(allocator);
    defer engine.deinit();

    for (expected_pre) |t| {
        try engine.main_stack.push(.{ .type = t });
    }

    const report = engine.simulate(bytecode, 1000) catch return MacroError.SimError;
    defer allocator.free(report.final_stack);

    if (report.final_stack.len != expected_post.len) return MacroError.SimError;
    for (report.final_stack, expected_post) |actual, expected| {
        if (@intFromEnum(actual) != @intFromEnum(expected)) return MacroError.SimError;
    }
}

pub fn toAsm(allocator: std.mem.Allocator, bytecode: []const u8) @import("encoder/asm.zig").Error![]const u8 {
    return @import("encoder/asm.zig").toAsm(allocator, bytecode);
}

pub fn fromAsm(allocator: std.mem.Allocator, asm_source: []const u8) MacroError![]const u8 {
    return @import("encoder/asm.zig").fromAsm(allocator, asm_source) catch |e| switch (e) {
        error.InvalidOpcode, error.InvalidHex, error.InvalidPushData => return MacroError.ParseError,
        else => return MacroError.OutOfMemory,
    };
}

fn deinitAstNode(allocator: std.mem.Allocator, node: @import("parser/ast.zig").AstNode) void {
    switch (node) {
        .macro_invocation => |m| {
            allocator.free(m.name);
            for (m.args) |arg| deinitAstNode(allocator, arg);
            allocator.free(m.args);
            if (m.body) |body| {
                for (body) |n| deinitAstNode(allocator, n);
                allocator.free(body);
            }
        },
        .loop_block => |l| {
            allocator.free(l.iterator_var);
            for (l.body) |n| deinitAstNode(allocator, n);
            allocator.free(l.body);
        },
        .conditional => |c| {
            for (c.then_branch) |n| deinitAstNode(allocator, n);
            allocator.free(c.then_branch);
            if (c.else_branch) |eb| {
                for (eb) |n| deinitAstNode(allocator, n);
                allocator.free(eb);
            }
        },
        .block => |b| {
            for (b) |n| deinitAstNode(allocator, n);
            allocator.free(b);
        },
        .string_literal => |s| allocator.free(s),
        .iterator_ref => |s| allocator.free(s),
        else => {},
    }
}

test {
    _ = lexer;
    _ = parser;
    _ = expander;
    _ = prelude;
    _ = simulator;
    _ = validator;
    _ = encoder;
}
