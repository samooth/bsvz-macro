const std = @import("std");
const macro = @import("bsvz-macro");

const alloc = std.heap.wasm_allocator;

const max_source_bytes: usize = 1 << 20;
const max_diagnostics: usize = 64;

pub const Status = enum(i32) {
    ok = 0,
    lex_error = -1,
    parse_error = -2,
    expand_error = -3,
    sim_error = -4,
    validation_error = -5,
    out_of_memory = -6,
    invalid_input = -7,
    invalid_option = -8,
};

var last_result: ?macro.MacroExpansion = null;
var src_buf: ?[]u8 = null;
var last_status: Status = .ok;
var diag_list: macro.DiagnosticList = undefined;
var diag_initialized = false;

fn ensureDiagList() *macro.DiagnosticList {
    if (!diag_initialized) {
        diag_list = macro.DiagnosticList.init(alloc);
        diag_initialized = true;
    }
    return &diag_list;
}

fn resetDiagnostics() void {
    if (diag_initialized) {
        diag_list.deinit();
        diag_list = macro.DiagnosticList.init(alloc);
    }
}

fn releaseResult() void {
    if (last_result) |*r| {
        r.deinit(alloc);
        last_result = null;
    }
}

fn releaseSource() void {
    if (src_buf) |s| {
        alloc.free(s);
        src_buf = null;
    }
}

export fn bsvz_compile_alloc(len: usize) ?[*]u8 {
    if (len == 0 or len > max_source_bytes) return null;
    releaseSource();
    const buf = alloc.alloc(u8, len) catch return null;
    src_buf = buf;
    return buf.ptr;
}

// Scratch allocation for temporary buffers (e.g. feature/standardness name
// strings passed from JS). Not tracked globally — caller frees via
// bsvz_scratch_free.
export fn bsvz_scratch_alloc(len: usize) ?[*]u8 {
    if (len == 0 or len > max_source_bytes) return null;
    const buf = alloc.alloc(u8, len) catch return null;
    return buf.ptr;
}

export fn bsvz_scratch_free(ptr: [*]u8, len: usize) void {
    alloc.free(ptr[0..len]);
}

fn parseFeatureSet(names: []const u8) macro.FeatureSet {
    var fs = macro.FeatureSet{};
    if (names.len == 0) return fs;
    var it = std.mem.splitScalar(u8, names, ',');
    while (it.next()) |name| {
        if (name.len == 0) continue;
        inline for (@typeInfo(macro.FeatureSet).@"struct".fields) |f| {
            if (std.mem.eql(u8, name, f.name)) {
                @field(fs, f.name) = true;
                break;
            }
        }
    }
    return fs;
}

fn parseStandardness(names: []const u8) macro.StandardnessFlags {
    var sf = macro.StandardnessFlags{};
    if (names.len == 0) return sf;
    // When names are provided, enable only the named flags (start from all-false).
    sf = .{};
    var it = std.mem.splitScalar(u8, names, ',');
    while (it.next()) |name| {
        if (name.len == 0) continue;
        inline for (@typeInfo(macro.StandardnessFlags).@"struct".fields) |f| {
            if (std.mem.eql(u8, name, f.name)) {
                @field(sf, f.name) = true;
                break;
            }
        }
    }
    return sf;
}

export fn bsvz_compile(
    src: [*]const u8,
    src_len: usize,
    target: u32,
    enforce_standardness: u32,
    max_script_size: u32,
    max_stack_elements: u32,
    max_push_size: u32,
    emit_asm: u32,
    network: u32,
    era: u32,
    block_height: u32,
    protocol_version: u32,
    tx_version: u32,
    features_ptr: [*]const u8,
    features_len: usize,
    standardness_ptr: [*]const u8,
    standardness_len: usize,
) i32 {
    if (src_len == 0 or src_len > max_source_bytes) {
        last_status = .invalid_input;
        return @intFromEnum(last_status);
    }
    if (target > @intFromEnum(macro.Target.btc_strict)) {
        last_status = .invalid_option;
        return @intFromEnum(last_status);
    }
    if (network != std.math.maxInt(u32) and network > @intFromEnum(macro.Network.bsv_regtest)) {
        last_status = .invalid_option;
        return @intFromEnum(last_status);
    }
    if (era != std.math.maxInt(u32) and era > @intFromEnum(macro.Era.chronicle)) {
        last_status = .invalid_option;
        return @intFromEnum(last_status);
    }

    if (src_buf == null or src_buf.?.ptr != src or src_buf.?.len != src_len) {
        releaseSource();
        const copy = alloc.dupe(u8, src[0..src_len]) catch {
            last_status = .out_of_memory;
            return @intFromEnum(last_status);
        };
        src_buf = copy;
    }

    const features = parseFeatureSet(features_ptr[0..features_len]);
    const standardness = parseStandardness(standardness_ptr[0..standardness_len]);

    last_status = .ok;
    const options = macro.CompileOptions{
        .target = @enumFromInt(target),
        .network = if (network == std.math.maxInt(u32)) null else @enumFromInt(network),
        .era = if (era == std.math.maxInt(u32)) null else @enumFromInt(era),
        .block_height = if (block_height == std.math.maxInt(u32)) null else block_height,
        .protocol_version = protocol_version,
        .tx_version = tx_version,
        .features = features,
        .standardness = standardness,
        .enforce_standardness = enforce_standardness != 0,
        .max_script_size = max_script_size,
        .max_stack_elements = @intCast(@min(max_stack_elements, std.math.maxInt(u16))),
        .max_push_size = @intCast(@min(max_push_size, std.math.maxInt(u16))),
        .emit_asm = emit_asm != 0,
    };

    releaseResult();
    resetDiagnostics();
    const result = macro.compileWithDiagnostics(alloc, src_buf.?, options, ensureDiagList()) catch |e| {
        last_status = switch (e) {
            error.LexError => .lex_error,
            error.ParseError => .parse_error,
            error.ExpandError => .expand_error,
            error.SimError => .sim_error,
            error.ValError => .validation_error,
            error.OutOfMemory => .out_of_memory,
        };
        return @intFromEnum(last_status);
    };
    last_result = result;
    last_status = .ok;
    return @intFromEnum(Status.ok);
}

export fn bsvz_bytecode_ptr() ?[*]const u8 {
    const r = last_result orelse return null;
    return r.bytecode.ptr;
}

export fn bsvz_bytecode_len() usize {
    const r = last_result orelse return 0;
    return r.bytecode.len;
}

export fn bsvz_asm_ptr() ?[*]const u8 {
    const r = last_result orelse return null;
    const t = r.asm_text orelse return null;
    return t.ptr;
}

export fn bsvz_asm_len() usize {
    const r = last_result orelse return 0;
    const t = r.asm_text orelse return 0;
    return t.len;
}

export fn bsvz_hash_ptr() ?[*]const u8 {
    if (last_result == null) return null;
    return &last_result.?.hash;
}

export fn bsvz_opcode_count() u32 {
    const r = last_result orelse return 0;
    return r.opcode_count;
}

export fn bsvz_byte_length() u32 {
    const r = last_result orelse return 0;
    return r.byte_length;
}

export fn bsvz_max_stack_height() u32 {
    const r = last_result orelse return 0;
    return r.max_stack_height;
}

export fn bsvz_is_standard() u32 {
    const r = last_result orelse return 0;
    return if (r.is_standard) 1 else 0;
}

export fn bsvz_last_error() i32 {
    return @intFromEnum(last_status);
}

export fn bsvz_diag_count() usize {
    if (!diag_initialized) return 0;
    return @min(diag_list.len(), max_diagnostics);
}

export fn bsvz_diag_phase(index: usize) u32 {
    const d = getDiag(index) orelse return 0;
    return @intFromEnum(d.phase) + 1;
}

export fn bsvz_diag_severity(index: usize) u32 {
    const d = getDiag(index) orelse return 0;
    return @intFromEnum(d.severity) + 1;
}

export fn bsvz_diag_line(index: usize) u32 {
    const d = getDiag(index) orelse return 0;
    return d.location.line;
}

export fn bsvz_diag_column(index: usize) u32 {
    const d = getDiag(index) orelse return 0;
    return d.location.column;
}

export fn bsvz_diag_offset(index: usize) u32 {
    const d = getDiag(index) orelse return 0;
    return d.location.offset;
}

export fn bsvz_diag_message_ptr(index: usize) ?[*]const u8 {
    const d = getDiag(index) orelse return null;
    return d.message.ptr;
}

export fn bsvz_diag_message_len(index: usize) usize {
    const d = getDiag(index) orelse return 0;
    return d.message.len;
}

fn getDiag(index: usize) ?macro.CompileDiagnostic {
    if (!diag_initialized) return null;
    if (index >= max_diagnostics) return null;
    return diag_list.get(index);
}

export fn bsvz_free() void {
    releaseResult();
    releaseSource();
    if (diag_initialized) {
        diag_list.deinit();
        diag_initialized = false;
    }
}
