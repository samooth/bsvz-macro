const std = @import("std");
const bsvz = @import("bsvz");

pub const lexer = @import("lexer/scanner.zig");
pub const parser = @import("parser/parser.zig");
pub const expander = @import("expander/expander.zig");
pub const prelude = @import("prelude.zig");
pub const simulator = @import("simulator/engine.zig");
pub const validator = @import("validator/bounds.zig");
pub const encoder = @import("encoder/hex.zig");

pub const MacroTable = @import("expander/table.zig").MacroTable;
pub const MacroDefinition = @import("expander/table.zig").MacroDefinition;
pub const ParamType = @import("expander/table.zig").ParamType;
pub const AstNode = @import("parser/ast.zig").AstNode;
pub const ExpandError = @import("expander/error.zig").ExpandError;

pub const bridge = struct {
    pub const bsvz_bridge = @import("bridge/bsvz.zig");
    pub const wallet = @import("bridge/wallet.zig");
};

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
    return compileInternal(allocator, source, options, null, null);
}

pub const diagnostics_mod = @import("diagnostics.zig");
pub const CompileDiagnostic = diagnostics_mod.CompileDiagnostic;
pub const DiagnosticList = diagnostics_mod.DiagnosticList;
pub const SourceLocation = diagnostics_mod.SourceLocation;
pub const Phase = diagnostics_mod.Phase;
pub const Severity = diagnostics_mod.Severity;

/// Compile while accumulating diagnostics with source locations. On failure
/// the returned MacroError matches what `compile` would return; `diagnostics`
/// holds every diagnostic collected up to (and including) the failure.
/// On success `diagnostics` may still hold warnings/notes from validation.
/// The diagnostic list must be deinit'd by the caller.
pub fn compileWithDiagnostics(
    allocator: std.mem.Allocator,
    source: []const u8,
    options: CompileOptions,
    diagnostics: *DiagnosticList,
) MacroError!MacroExpansion {
    return compileInternal(allocator, source, options, diagnostics, null);
}

/// Compile against a caller-owned macro table. The table must already contain
/// the canonical macros (call `prelude.registerCanonicalMacros(&table)` first,
/// or use `registerMacro` on top of it) and stays owned by the caller.
pub fn compileWithTable(
    allocator: std.mem.Allocator,
    source: []const u8,
    options: CompileOptions,
    table: *MacroTable,
) MacroError!MacroExpansion {
    return compileInternal(allocator, source, options, null, table);
}

/// Compile against a caller-owned macro table, accumulating diagnostics.
pub fn compileWithTableAndDiagnostics(
    allocator: std.mem.Allocator,
    source: []const u8,
    options: CompileOptions,
    table: *MacroTable,
    diagnostics: *DiagnosticList,
) MacroError!MacroExpansion {
    return compileInternal(allocator, source, options, diagnostics, table);
}

/// Register a user-defined macro into `table`. The name and param types are
/// copied into the table's allocator.
pub fn registerMacro(
    table: *MacroTable,
    name: []const u8,
    definition: MacroDefinition,
) MacroError!void {
    table.register(name, definition) catch return MacroError.OutOfMemory;
}

fn compileInternal(
    allocator: std.mem.Allocator,
    source: []const u8,
    options: CompileOptions,
    diagnostics: ?*DiagnosticList,
    custom_table: ?*@import("expander/table.zig").MacroTable,
) MacroError!MacroExpansion {
    // Phase 1: Lex
    var scanner = lexer.Scanner.init(source);
    scanner.diagnostics = diagnostics;
    const tokens = scanner.scanAll(allocator) catch return MacroError.LexError;
    defer {
        for (tokens) |t| {
            switch (t.token) {
                .macro_name, .iterator_var => |v| allocator.free(v),
                .string => {},
                else => {},
            }
        }
        allocator.free(tokens);
    }

    // Phase 2: Parse
    var p = parser.Parser.init(tokens, allocator);
    p.diagnostics = diagnostics;
    p.recover = diagnostics != null;
    var stmt_locs: std.ArrayListUnmanaged(SourceLocation) = .empty;
    const ast_nodes = p.parseWithLocations(&stmt_locs) catch {
        stmt_locs.deinit(allocator);
        return MacroError.ParseError;
    };
    defer stmt_locs.deinit(allocator);
    defer {
        for (ast_nodes) |node| deinitAstNode(allocator, node);
        allocator.free(ast_nodes);
    }

    // Phase 3: Setup macro table
    var table: MacroTable = undefined;
    if (custom_table) |ct| {
        table = ct.*;
    } else {
        table = MacroTable.init(allocator);
    }
    const table_owned = custom_table == null;
    defer if (table_owned) table.deinit();

    if (custom_table == null) {
        prelude.registerCanonicalMacros(&table) catch return MacroError.ExpandError;
    }

    // Phase 4: Expand
    const Expander = @import("expander/expander.zig").Expander;
    var expander_inst = Expander.init(&table, options);
    expander_inst.diagnostics = diagnostics;
    expander_inst.stmt_locs = stmt_locs.items;
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

    const sim_report = engine.simulateWithDiagnostics(bytecode, options.max_stack_elements, diagnostics) catch |e| {
        allocator.free(bytecode);
        return switch (e) {
            error.OutOfMemory => MacroError.OutOfMemory,
            else => MacroError.SimError,
        };
    };
    defer allocator.free(sim_report.final_stack);

    // Phase 6: Validate
    const BoundsValidator = @import("validator/bounds.zig").BoundsValidator;
    var bv = BoundsValidator.init(options);
    const is_standard = bv.validateWithDiagnostics(bytecode, sim_report.max_stack_height, diagnostics) catch |e| {
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
        .opcode_count = countOpcodes(bytecode),
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
        try engine.main_stack.push(allocator, .{ .type = t });
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

pub fn countOpcodes(bytecode: []const u8) u32 {
    const Opcode = bsvz.script.opcode.Opcode;
    var count: u32 = 0;
    var i: usize = 0;
    while (i < bytecode.len) {
        const op: Opcode = Opcode.fromByte(bytecode[i]);
        count += 1;
        var data_len: usize = 0;
        var header_len: usize = 1;
        switch (op) {
            .OP_PUSHDATA1 => {
                if (i + 1 >= bytecode.len) return count;
                data_len = bytecode[i + 1];
                header_len = 2;
            },
            .OP_PUSHDATA2 => {
                if (i + 2 >= bytecode.len) return count;
                data_len = std.mem.readInt(u16, bytecode[i + 1..][0..2], .little);
                header_len = 3;
            },
            .OP_PUSHDATA4 => {
                if (i + 5 >= bytecode.len) return count;
                data_len = std.mem.readInt(u32, bytecode[i + 1..][0..4], .little);
                header_len = 5;
            },
            else => {
                const b = bytecode[i];
                if (b > 0 and b <= 0x4b) data_len = b;
            },
        }
        i += header_len + data_len;
        if (i > bytecode.len) break;
    }
    return count;
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
