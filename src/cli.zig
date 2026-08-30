//! Command-line interface for bsvz-macro.
//!
//! Compile a source file (or stdin) with the full set of CompileOptions and
//! emit bytecode (hex), optional ASM, and diagnostics. See README.md "CLI".
//!
//! The core logic lives in runCliFromArgs so it is unit-testable without
//! spawning a process; main() is a thin wrapper over std.process.args.

const std = @import("std");
const bsvz_macro = @import("bsvz-macro");
const CompileOptions = bsvz_macro.CompileOptions;
const DiagnosticList = bsvz_macro.DiagnosticList;

pub const CliResult = struct {
    exit_code: u8,
    expansion: ?bsvz_macro.MacroExpansion,
};

/// Parsed, validated CLI configuration. Caller owns all owned slices; pass an
/// allocator that outlives the CliConfig only until runCliFromArgs completes
/// (which frees everything it allocates).
pub const CliConfig = struct {
    source: []const u8,

    target: bsvz_macro.Target = .bsv_mainnet,
    network: ?bsvz_macro.Network = null,
    era: ?bsvz_macro.Era = null,
    block_height: ?u32 = null,
    protocol_version: u32 = 1,
    tx_version: u32 = 1,
    features: bsvz_macro.FeatureSet = .{},
    standardness: ?bsvz_macro.StandardnessFlags = null,
    max_script_size: ?u32 = null,
    max_stack_elements: ?u16 = null,
    max_push_size: ?u16 = null,
    max_opcodes: ?u32 = null,
    enforce_standardness: ?bool = null,
    emit_asm: bool = false,

    verbose: bool = false,
    json: bool = false,
    output_path: ?[]const u8 = null,
    asm_out_path: ?[]const u8 = null,
};

// 1) Read the CLI into a CliConfig (argument parsing + source reading).
fn readConfig(allocator: std.mem.Allocator, io: std.Io, args: []const []const u8) !CliConfig {
    var cfg = CliConfig{ .source = &.{ } };
    var i: usize = 1; // skip argv[0]
    var positional: ?[]const u8 = null;

    while (i < args.len) : (i += 1) {
        const arg = args[i];
        var body: []const u8 = undefined;
        if (std.mem.startsWith(u8, arg, "--")) {
            body = arg[2..];
        } else if (arg.len == 2 and arg[0] == '-' and arg[1] != '-') {
            if (positional != null) {
                std.debug.print("bsvz-macro: unexpected argument '{s}' (source already given)\n", .{arg});
                return error.InvalidArgument;
            }
            if (arg[1] == 'o') {
                cfg.output_path = try parseNextValue(args, &i, "output");
                continue;
            }
            if (arg[1] == 'v') {
                cfg.verbose = true;
                continue;
            }
            std.debug.print("bsvz-macro: unknown flag '{s}'\n", .{arg});
            return error.InvalidArgument;
        } else if (std.mem.eql(u8, arg, "-")) {
            if (positional != null) {
                std.debug.print("bsvz-macro: unexpected argument '{s}' (source already given)\n", .{arg});
                return error.InvalidArgument;
            }
            positional = arg;
            continue;
        } else {
            if (positional != null) {
                std.debug.print("bsvz-macro: unexpected argument '{s}' (source already given)\n", .{arg});
                return error.InvalidArgument;
            }
            positional = arg;
            continue;
        }

        if (std.mem.eql(u8, body, "target")) {
            cfg.target = try parseNextEnum(args, &i, bsvz_macro.Target, "target");
        } else if (std.mem.eql(u8, body, "network")) {
            cfg.network = try parseNextEnum(args, &i, bsvz_macro.Network, "network");
        } else if (std.mem.eql(u8, body, "era")) {
            cfg.era = try parseNextEnum(args, &i, bsvz_macro.Era, "era");
        } else if (std.mem.eql(u8, body, "block-height")) {
            cfg.block_height = try parseNextU32(args, &i, "block-height");
        } else if (std.mem.eql(u8, body, "protocol-version")) {
            cfg.protocol_version = try parseNextU32(args, &i, "protocol-version");
        } else if (std.mem.eql(u8, body, "tx-version")) {
            cfg.tx_version = try parseNextU32(args, &i, "tx-version");
        } else if (std.mem.eql(u8, body, "features")) {
            cfg.features = try parseNextFeatures(args, &i);
        } else if (std.mem.eql(u8, body, "standardness")) {
            cfg.standardness = try parseNextStandardness(args, &i);
        } else if (std.mem.eql(u8, body, "max-script-size")) {
            cfg.max_script_size = try parseNextU32(args, &i, "max-script-size");
        } else if (std.mem.eql(u8, body, "max-stack-elements")) {
            cfg.max_stack_elements = try parseNextU16(args, &i, "max-stack-elements");
        } else if (std.mem.eql(u8, body, "max-push-size")) {
            cfg.max_push_size = try parseNextU16(args, &i, "max-push-size");
        } else if (std.mem.eql(u8, body, "max-opcodes")) {
            cfg.max_opcodes = try parseNextU32(args, &i, "max-opcodes");
        } else if (std.mem.eql(u8, body, "enforce-standardness")) {
            cfg.enforce_standardness = true;
        } else if (std.mem.eql(u8, body, "no-enforce-standardness")) {
            cfg.enforce_standardness = false;
        } else if (std.mem.eql(u8, body, "emit-asm")) {
            cfg.emit_asm = true;
        } else if (std.mem.eql(u8, body, "no-emit-asm")) {
            cfg.emit_asm = false;
        } else if (std.mem.eql(u8, body, "verbose")) {
            cfg.verbose = true;
        } else if (std.mem.eql(u8, body, "json")) {
            cfg.json = true;
        } else if (std.mem.eql(u8, body, "output")) {
            cfg.output_path = try parseNextValue(args, &i, "output");
        } else if (std.mem.eql(u8, body, "asm-out")) {
            cfg.asm_out_path = try parseNextValue(args, &i, "asm-out");
        } else {
            std.debug.print("bsvz-macro: unknown flag '--{s}'\n", .{body});
            return error.InvalidArgument;
        }
    }

    const source_name = positional orelse "-";
    cfg.source = if (std.mem.eql(u8, source_name, "-"))
        try readAllStdin(allocator, io)
    else
        try std.Io.Dir.cwd().readFileAlloc(io, source_name, allocator, .limited(1 << 20));

    if (cfg.source.len == 0) {
        std.debug.print("bsvz-macro: source is empty\n", .{});
        return error.EmptySource;
    }

    return cfg;
}

fn parseNextValue(args: []const []const u8, i: *usize, flag: []const u8) ![]const u8 {
    const idx = i.* + 1;
    if (idx >= args.len) {
        std.debug.print("bsvz-macro: '--{s}' requires a value\n", .{flag});
        return error.MissingValue;
    }
    i.* = idx;
    return args[idx];
}

fn parseNextU32(args: []const []const u8, i: *usize, flag: []const u8) !u32 {
    const raw = try parseNextValue(args, i, flag);
    return std.fmt.parseInt(u32, raw, 10) catch {
        std.debug.print("bsvz-macro: '--{s}' expects a non-negative integer, got '{s}'\n", .{ flag, raw });
        return error.InvalidValue;
    };
}

fn parseNextU16(args: []const []const u8, i: *usize, flag: []const u8) !u16 {
    const v = try parseNextU32(args, i, flag);
    if (v > std.math.maxInt(u16)) {
        std.debug.print("bsvz-macro: '--{s}' value {d} out of range\n", .{ flag, v });
        return error.InvalidValue;
    }
    return @intCast(v);
}

fn parseNextEnum(args: []const []const u8, i: *usize, comptime T: type, flag: []const u8) !T {
    const raw = try parseNextValue(args, i, flag);
    inline for (@typeInfo(T).@"enum".fields) |f| {
        if (std.mem.eql(u8, raw, f.name)) return @enumFromInt(f.value);
    }
    std.debug.print("bsvz-macro: '--{s}' unknown value '{s}'\n", .{ flag, raw });
    return error.InvalidValue;
}

/// Parse `--features cat,-split,...` into a FeatureSet. Leading '+' or no prefix
/// enables; leading '-' disables.
fn parseNextFeatures(args: []const []const u8, i: *usize) !bsvz_macro.FeatureSet {
    const raw = try parseNextValue(args, i, "features");
    var fs = bsvz_macro.FeatureSet{};
    var it = std.mem.splitScalar(u8, raw, ',');
    while (it.next()) |tok| {
        if (tok.len == 0) continue;
        const signed = tok[0] == '-' or tok[0] == '+';
        const name = if (signed) tok[1..] else tok;
        if (name.len == 0) {
            std.debug.print("bsvz-macro: '--features' has an empty entry\n", .{});
            return error.InvalidValue;
        }
        var found = false;
        inline for (@typeInfo(bsvz_macro.FeatureSet).@"struct".fields) |f| {
            if (std.mem.eql(u8, name, f.name)) {
                @field(fs, f.name) = tok[0] != '-';
                found = true;
            }
        }
        if (!found) {
            std.debug.print("bsvz-macro: '--features' unknown feature '{s}'\n", .{name});
            return error.InvalidValue;
        }
    }
    return fs;
}

/// Parse `--standardness dersig,low_s,...`: enable ONLY the named flags.
fn parseNextStandardness(args: []const []const u8, i: *usize) !bsvz_macro.StandardnessFlags {
    const raw = try parseNextValue(args, i, "standardness");
    var sf = bsvz_macro.StandardnessFlags{}; // all false, then enable named
    var it = std.mem.splitScalar(u8, raw, ',');
    while (it.next()) |tok| {
        if (tok.len == 0) continue;
        var found = false;
        inline for (@typeInfo(bsvz_macro.StandardnessFlags).@"struct".fields) |f| {
            if (std.mem.eql(u8, tok, f.name)) {
                @field(sf, f.name) = true;
                found = true;
            }
        }
        if (!found) {
            std.debug.print("bsvz-macro: '--standardness' unknown flag '{s}'\n", .{tok});
            return error.InvalidValue;
        }
    }
    return sf;
}

fn readAllStdin(allocator: std.mem.Allocator, io: std.Io) ![]u8 {
    const Io = std.Io;
    var stdin_buffer: [4096]u8 = undefined;
    var stdin_reader = Io.File.stdin().reader(io, &stdin_buffer);
    var list = std.ArrayList(u8).empty;
    defer list.deinit(allocator);
    try stdin_reader.interface.appendRemainingUnlimited(allocator, &list);
    return list.toOwnedSlice(allocator);
}

fn buildOptions(cfg: CliConfig) CompileOptions {
    var o = CompileOptions{
        .target = cfg.target,
        .network = cfg.network,
        .era = cfg.era,
        .block_height = cfg.block_height,
        .protocol_version = cfg.protocol_version,
        .tx_version = cfg.tx_version,
        .features = cfg.features,
        .standardness = cfg.standardness orelse .{},
        .enforce_standardness = cfg.enforce_standardness orelse true,
        .emit_asm = cfg.emit_asm,
    };
    if (cfg.max_script_size) |v| o.max_script_size = v;
    if (cfg.max_stack_elements) |v| o.max_stack_elements = v;
    if (cfg.max_push_size) |v| o.max_push_size = v;
    if (cfg.max_opcodes) |v| o.limits.opcodes = v;
    return o;
}

fn writeHex(out: anytype, bytes: []const u8) !void {
    for (bytes) |b| {
        const hex = "0123456789abcdef";
        try out.writeAll(&.{ hex[b >> 4], hex[b & 0x0f] });
    }
}

fn writeDiagnostics(err: anytype, diags: DiagnosticList) !void {
    var idx: usize = 0;
    while (idx < diags.len()) : (idx += 1) {
        const d = diags.get(idx).?;
        try err.print("{s}:{d}:{d}: {s}: {s}\n", .{
            @tagName(d.phase),
            d.location.line,
            d.location.column,
            @tagName(d.severity),
            d.message,
        });
    }
}

fn writeJson(out: anytype, expansion: bsvz_macro.MacroExpansion, diags: DiagnosticList) !void {
    try out.writeAll("{\n");
    try out.print("  \"bytecode\": \"", .{});
    try writeHex(out, expansion.bytecode);
    try out.print("\",\n", .{});
    try out.print("  \"hash\": \"", .{});
    try writeHex(out, &expansion.hash);
    try out.print("\",\n", .{});
    if (expansion.asm_text) |asm_text| {
        try out.print("  \"asm\": \"", .{});
        // Escape quotes/backslashes minimally for the ASM text.
        for (asm_text) |c| {
            switch (c) {
                '"' => try out.writeAll("\\\""),
                '\\' => try out.writeAll("\\\\"),
                '\n' => try out.writeAll("\\n"),
                '\r' => try out.writeAll("\\r"),
                '\t' => try out.writeAll("\\t"),
                else => try out.writeAll(&.{c}),
            }
        }
        try out.print("\",\n", .{});
    } else {
        try out.print("  \"asm\": null,\n", .{});
    }
    try out.print("  \"opcodeCount\": {d},\n", .{expansion.opcode_count});
    try out.print("  \"byteLength\": {d},\n", .{expansion.byte_length});
    try out.print("  \"maxStackHeight\": {d},\n", .{@as(u32, expansion.max_stack_height)});
    try out.print("  \"isStandard\": {s},\n", .{if (expansion.is_standard) "true" else "false"});
    try out.print("  \"diagnostics\": [\n", .{});
    var idx: usize = 0;
    while (idx < diags.len()) : (idx += 1) {
        const d = diags.get(idx).?;
        try out.print("    {{\"phase\": \"{s}\", \"severity\": \"{s}\", \"line\": {d}, \"column\": {d}, \"offset\": {d}, \"message\": \"", .{
            @tagName(d.phase), @tagName(d.severity), d.location.line, d.location.column, d.location.offset,
        });
        for (d.message) |c| {
            switch (c) {
                '"' => try out.writeAll("\\\""),
                '\\' => try out.writeAll("\\\\"),
                '\n' => try out.writeAll("\\n"),
                else => try out.writeAll(&.{c}),
            }
        }
        try out.print("\"", .{});
        if (idx + 1 < diags.len()) try out.writeAll(",");
        try out.writeAll("\n");
    }
    try out.print("  ]\n", .{});
    try out.writeAll("}\n");
}

/// Core CLI logic. Compiles cfg.source with the resolved options and writes
/// results to out/err. Returns a CliResult carrying the exit code and, on
/// success, the expansion (owned by caller via deinit). On failure, diagnostics
/// are written to err and expansion is null.
pub fn runCliFromArgs(
    allocator: std.mem.Allocator,
    io: std.Io,
    args: []const []const u8,
    out: anytype,
    err: anytype,
) !CliResult {
    const cfg = readConfig(allocator, io, args) catch |e| {
        if (e == error.InvalidArgument or e == error.MissingValue or
            e == error.InvalidValue or e == error.EmptySource)
        {
            try err.print("usage: bsvz-macro [options] <source | ->\n", .{});
            return CliResult{ .exit_code = 2, .expansion = null };
        }
        return e;
    };

    var diags = DiagnosticList.init(allocator);
    defer diags.deinit();

    const options = buildOptions(cfg);
    const expansion = bsvz_macro.compileWithDiagnostics(allocator, cfg.source, options, &diags) catch |e| {
        // Surface any diagnostics captured before the failure.
        if (diags.len() == 0) {
            try err.print("bsvz-macro: {s}\n", .{@errorName(e)});
        } else {
            try writeDiagnostics(err, diags);
        }
        return CliResult{ .exit_code = 1, .expansion = null };
    };

    if (cfg.json) {
        try writeJson(out, expansion, diags);
    } else {
        if (cfg.output_path) |path| {
            var wbuf: [4096]u8 = undefined;
            const file = try std.Io.Dir.cwd().createFile(io, path, .{});
            defer file.close(io);
            var fw = file.writer(io, &wbuf);
            try writeHex(&fw.interface, expansion.bytecode);
            try fw.interface.writeAll("\n");
            try fw.interface.flush();
        } else {
            try writeHex(out, expansion.bytecode);
            try out.writeAll("\n");
        }
        if (cfg.asm_out_path) |path| {
            if (expansion.asm_text) |asm_text| {
                var wbuf: [4096]u8 = undefined;
                const file = try std.Io.Dir.cwd().createFile(io, path, .{});
                defer file.close(io);
                var fw = file.writer(io, &wbuf);
                try fw.interface.writeAll(asm_text);
                if (asm_text.len == 0 or asm_text[asm_text.len - 1] != '\n') try fw.interface.writeAll("\n");
                try fw.interface.flush();
            }
        }
        if (cfg.verbose) {
            if (expansion.asm_text) |asm_text_val| {
                try err.print(";; ASM\n{s}\n", .{asm_text_val});
            }
            try err.print(";; opcodes={d} bytes={d} maxstack={d} standard={s}\n", .{
                expansion.opcode_count,
                expansion.byte_length,
                expansion.max_stack_height,
                if (expansion.is_standard) "yes" else "no",
            });
        }
        if (diags.len() > 0) {
            try writeDiagnostics(err, diags);
        }
    }

    return CliResult{ .exit_code = 0, .expansion = expansion };
}

pub fn main(init: std.process.Init) !u8 {
    const Io = std.Io;
    const arena = init.arena.allocator();

    const args = try init.minimal.args.toSlice(arena);

    var stdout_buffer: [0x1000]u8 = undefined;
    var stdout_writer = Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    var stderr_buffer: [0x1000]u8 = undefined;
    var stderr_writer = Io.File.stderr().writer(init.io, &stderr_buffer);
    const stderr = &stderr_writer.interface;

    const result = runCliFromArgs(arena, init.io, args, stdout, stderr) catch |e| {
        stderr.print("bsvz-macro: {s}\n", .{@errorName(e)}) catch {};
        stderr.flush() catch {};
        stdout.flush() catch {};
        return 1;
    };
    if (result.expansion) |*exp| exp.deinit(arena);

    stdout.flush() catch {};
    stderr.flush() catch {};
    return result.exit_code;
}
