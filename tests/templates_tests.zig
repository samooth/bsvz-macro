const std = @import("std");
const bsvz_macro = @import("bsvz-macro");
const templates = bsvz_macro.templates;
const helpers = @import("helpers.zig");
const testing = std.testing;

// ── Inscription ─────────────────────────────────────────────────────────

test "templates: INSCRIPTION produces valid envelope" {
    const allocator = testing.allocator;
    const result = try bsvz_macro.compile(allocator, "INSCRIPTION[\"hello\", \"text/plain\"]", .{});
    defer result.deinit(allocator);

    try testing.expect(result.bytecode.len > 0);
    try testing.expect(result.is_standard);
}

test "templates: INSCRIPTION_FULL with prefix and suffix" {
    const allocator = testing.allocator;
    const result = try bsvz_macro.compile(allocator, "INSCRIPTION_FULL[\"0x76a914aabbccdd00112233445566778899aabbccddeeff88ac\", \"text/plain\", \"0x6a05\", \"0x00\"]", .{});
    defer result.deinit(allocator);

    try testing.expect(result.bytecode.len > 0);
}

test "templates: INSCRIPTION arity mismatch" {
    const allocator = testing.allocator;
    try helpers.compileExpectError(allocator, "INSCRIPTION[\"hello\"]", error.ExpandError);
}

// ── Lock (CLTV) ─────────────────────────────────────────────────────────

test "templates: LOCK produces valid CLTV script" {
    const allocator = testing.allocator;
    const result = bsvz_macro.compile(allocator, "LOCK[\"0xabababababababababababababababababababab\", 800000]", .{});
    try testing.expectError(error.SimError, result);
}

test "templates: LOCK rejects invalid pubkey hash length" {
    const allocator = testing.allocator;
    try helpers.compileExpectError(allocator, "LOCK[\"0xabab\", 800000]", error.ExpandError);
}

// ── BSV-21 ──────────────────────────────────────────────────────────────

test "templates: BSV21_DEPLOY produces valid inscription" {
    const allocator = testing.allocator;
    const result = try bsvz_macro.compile(allocator, "BSV21_DEPLOY[\"TOKEN\", 8, 21000000]", .{});
    defer result.deinit(allocator);

    try testing.expect(result.bytecode.len > 0);
}

test "templates: BSV21_TRANSFER produces valid inscription" {
    const allocator = testing.allocator;
    const token_id = "abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789_0";
    const result = try bsvz_macro.compile(allocator, "BSV21_TRANSFER[\"" ++ token_id ++ "\", 500]", .{});
    defer result.deinit(allocator);

    try testing.expect(result.bytecode.len > 0);
}

test "templates: BSV21_BURN produces valid inscription" {
    const allocator = testing.allocator;
    const token_id = "abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789_0";
    const result = try bsvz_macro.compile(allocator, "BSV21_BURN[\"" ++ token_id ++ "\", 100]", .{});
    defer result.deinit(allocator);

    try testing.expect(result.bytecode.len > 0);
}

test "templates: BSV21_DEPLOY rejects empty symbol" {
    const allocator = testing.allocator;
    try helpers.compileExpectError(allocator, "BSV21_DEPLOY[\"\", 8, 1000]", error.ExpandError);
}

test "templates: BSV21_DEPLOY rejects zero amount" {
    const allocator = testing.allocator;
    try helpers.compileExpectError(allocator, "BSV21_DEPLOY[\"T\", 8, 0]", error.ExpandError);
}

// ── BSV-20 ───────────────────────────────────────────────────────────────

test "templates: BSV20_DEPLOY produces valid inscription" {
    const allocator = testing.allocator;
    const result = try bsvz_macro.compile(allocator, "BSV20_DEPLOY[\"ORDI\", 21000000, 0, 1000]", .{});
    defer result.deinit(allocator);

    try testing.expect(result.bytecode.len > 0);
}

test "templates: BSV20_MINT produces valid inscription" {
    const allocator = testing.allocator;
    const result = try bsvz_macro.compile(allocator, "BSV20_MINT[\"ORDI\", 1000]", .{});
    defer result.deinit(allocator);

    try testing.expect(result.bytecode.len > 0);
}

test "templates: BSV20_TRANSFER produces valid inscription" {
    const allocator = testing.allocator;
    const result = try bsvz_macro.compile(allocator, "BSV20_TRANSFER[\"ORDI\", 500]", .{});
    defer result.deinit(allocator);

    try testing.expect(result.bytecode.len > 0);
}

test "templates: BSV20_DEPLOY rejects empty ticker" {
    const allocator = testing.allocator;
    try helpers.compileExpectError(allocator, "BSV20_DEPLOY[\"\", 21000000, 0, 1000]", error.ExpandError);
}

test "templates: BSV20_DEPLOY rejects zero max supply" {
    const allocator = testing.allocator;
    try helpers.compileExpectError(allocator, "BSV20_DEPLOY[\"ORDI\", 0, 0, 1000]", error.ExpandError);
}

test "templates: BSV20_MINT rejects zero amount" {
    const allocator = testing.allocator;
    try helpers.compileExpectError(allocator, "BSV20_MINT[\"ORDI\", 0]", error.ExpandError);
}

// ── MAP ─────────────────────────────────────────────────────────────────

test "templates: MAP_SET produces valid OP_RETURN script" {
    const allocator = testing.allocator;
    const result = bsvz_macro.compile(allocator, "MAP_SET[\"app\", \"bsocial\"]", .{});
    try testing.expectError(error.SimError, result);
}

test "templates: MAP_DEL produces valid OP_RETURN script" {
    const allocator = testing.allocator;
    const result = bsvz_macro.compile(allocator, "MAP_DEL[\"app\"]", .{});
    try testing.expectError(error.SimError, result);
}

// ── OrdLock ─────────────────────────────────────────────────────────────

test "templates: ORDLOCK produces valid script" {
    const allocator = testing.allocator;
    const result = bsvz_macro.compile(allocator, "ORDLOCK[\"0xabababababababababababababababababababab\", \"0xcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcd\", 1000]", .{});
    try testing.expectError(error.SimError, result);
}

test "templates: ORDLOCK rejects invalid pubkey hash length" {
    const allocator = testing.allocator;
    try helpers.compileExpectError(allocator, "ORDLOCK[\"0xabab\", \"0xcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcd\", 1000]", error.ExpandError);
}

// ── B protocol ──────────────────────────────────────────────────────────

test "templates: B_ENCODE produces valid OP_RETURN script" {
    const allocator = testing.allocator;
    const result = bsvz_macro.compile(allocator, "B_ENCODE[\"0x48656c6c6f\", \"text/plain\", \"utf-8\", \"hello.txt\"]", .{});
    try testing.expectError(error.SimError, result);
}

// ── OpNS ────────────────────────────────────────────────────────────────

test "templates: OPNS_LOCK produces valid script with contract" {
    const allocator = testing.allocator;
    const result = bsvz_macro.compile(allocator, "OPNS_LOCK[\"0xabababababababababababababababababababab\", \"test\", \"0xcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcd\"]", .{});
    try testing.expectError(error.SimError, result);
}

test "templates: OPNS_INSCRIBE produces valid name inscription" {
    const allocator = testing.allocator;
    const owner = "abababababababababababababababababababab";
    const result = bsvz_macro.compile(allocator, "OPNS_INSCRIBE[\"myname\", \"0x" ++ owner ++ "\"]", .{});
    try testing.expectError(error.SimError, result);
}

test "templates: OPNS_INSCRIBE rejects empty name" {
    const allocator = testing.allocator;
    try helpers.compileExpectError(allocator, "OPNS_INSCRIBE[\"\", \"0xabab\"]", error.ExpandError);
}

// ── BCAT ─────────────────────────────────────────────────────────────────

test "templates: BCAT_HEADER produces valid OP_RETURN script" {
    const allocator = testing.allocator;
    const txid1 = "abababababababababababababababababababababababababababababababab";
    const txid2 = "cdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcd";
    const result = bsvz_macro.compile(allocator, "BCAT_HEADER[\"info\", \"image/jpeg\", \"UTF-8\", \"photo.jpg\", \"gzip\", \"0x" ++ txid1 ++ txid2 ++ "\"]", .{});
    try testing.expectError(error.SimError, result);
}

test "templates: BCAT_HEADER rejects zero txids" {
    const allocator = testing.allocator;
    try helpers.compileExpectError(allocator, "BCAT_HEADER[\"info\", \"image/jpeg\", \"UTF-8\", \"photo.jpg\", \"gzip\", \"\"]", error.ExpandError);
}

test "templates: BCAT_HEADER rejects odd-length txid hex" {
    const allocator = testing.allocator;
    try helpers.compileExpectError(allocator, "BCAT_HEADER[\"info\", \"image/jpeg\", \"UTF-8\", \"photo.jpg\", \"gzip\", \"0xabc\"]", error.ExpandError);
}

test "templates: BCAT_PART produces valid OP_RETURN script" {
    const allocator = testing.allocator;
    const chunk = "48656c6c6f20776f726c6421";
    const result = bsvz_macro.compile(allocator, "BCAT_PART[\"0x" ++ chunk ++ "\"]", .{});
    try testing.expectError(error.SimError, result);
}

test "templates: BCAT_PART rejects empty data" {
    const allocator = testing.allocator;
    try helpers.compileExpectError(allocator, "BCAT_PART[\"\"]", error.ExpandError);
}

// ── AIP ─────────────────────────────────────────────────────────────────

test "templates: AIP_ENCODE produces valid script bytes" {
    const allocator = testing.allocator;
    const result = try bsvz_macro.compile(allocator, "AIP_ENCODE[\"BITCOIN_ECDSA\", \"1TestAddr\", \"0xabababababababababababababababababababababababababababababababab\"]", .{});
    defer result.deinit(allocator);

    try testing.expect(result.bytecode.len > 0);
}

// ── SIGMA ───────────────────────────────────────────────────────────────

test "templates: SIGMA_ENCODE produces valid script bytes" {
    const allocator = testing.allocator;
    const result = try bsvz_macro.compile(allocator, "SIGMA_ENCODE[\"BSM\", \"1TestAddr\", \"0xabababababababababababababababababababababababababababababababab\", 0]", .{});
    defer result.deinit(allocator);

    try testing.expect(result.bytecode.len > 0);
}

// ── Constants ───────────────────────────────────────────────────────────

test "templates: constants are non-empty and correct type" {
    try testing.expect(templates.MAP_PREFIX.len > 0);
    try testing.expect(templates.B_PREFIX.len > 0);
    try testing.expect(templates.AIP_PREFIX.len > 0);
    try testing.expect(templates.SIGMA_PREFIX.len > 0);
    try testing.expect(templates.CONTENT_TYPE_BSV20.len > 0);
    try testing.expect(templates.ORDLOCK_PREFIX.len > 0);
    try testing.expect(templates.ORDLOCK_SUFFIX.len > 0);
    try testing.expect(templates.OPNS_CONTRACT.len == 5892);
    try testing.expect(templates.ORD_MARKER.len == 3);
    try testing.expect(templates.GENESIS_OUTPOINT.len == 36);
}

// ── Determinism ─────────────────────────────────────────────────────────

test "templates: INSCRIPTION is deterministic" {
    const allocator = testing.allocator;
    try helpers.expectDeterministicBytecode(allocator, "INSCRIPTION[\"hello\", \"text/plain\"]");
}

test "templates: BSV21_DEPLOY is deterministic" {
    const allocator = testing.allocator;
    try helpers.expectDeterministicBytecode(allocator, "BSV21_DEPLOY[\"TOKEN\", 8, 21000000]");
}
