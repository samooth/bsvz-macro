// Raw-export tests for the bsvz-macro wasm FFI (src/wasm.zig).
//
// These exercise the C-ABI exports directly (no JS wrapper) so that regressions
// in either wasm.zig or the JS glue in web/bsvz-macro.js are caught. The module
// holds single-shot global state (one compile at a time), so every case calls
// bsvz_free() before the next.
//
// Run: node --test web/wasm_api.test.mjs --wasm=zig-out/wasm/<file>.wasm
//      (or set WASM_PATH env; the test auto-discovers zig-out/wasm/*.wasm).

import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

function findWasm() {
  if (process.env.WASM_PATH) return process.env.WASM_PATH;
  const flag = process.argv.findIndex((a) => a.startsWith("--wasm="));
  if (flag !== -1) return process.argv[flag].slice("--wasm=".length);
  const dir = path.join(__dirname, "..", "zig-out", "wasm");
  if (fs.existsSync(dir)) {
    const files = fs.readdirSync(dir).filter((f) => f.endsWith(".wasm"));
    if (files.length > 0) return path.join(dir, files[0]);
  }
  throw new Error("could not locate .wasm artifact; pass --wasm=<path>");
}

const wasmPath = findWasm();
const encoder = new TextEncoder();
const decoder = new TextDecoder();

/** Instantiate the module and return { instance, memory }. */
async function instantiate() {
  const bytes = fs.readFileSync(wasmPath);
  const { instance } = await WebAssembly.instantiate(bytes, {});
  const mem = instance.exports.memory;
  if (!mem) throw new Error("wasm module has no exported memory");
  return { instance, e: instance.exports, mem };
}

/** Copy `src` into a freshly allocated wasm buffer and return [ptr, len]. */
function allocSource(e, mem, text) {
  const encoded = encoder.encode(text);
  const ptr = e.bsvz_compile_alloc(encoded.length);
  assert.notStrictEqual(ptr, 0, "bsvz_compile_alloc returned null");
  new Uint8Array(mem.buffer, ptr, encoded.length).set(encoded);
  return [ptr, encoded.length];
}

/** Read a wasm string (ptr, len) into a JS string. */
function readString(mem, ptr, len) {
  return decoder.decode(new Uint8Array(mem.buffer, ptr, len));
}

// Extended compile helper that exercises the full 16-param signature,
// forwarding conditional-compilation options (era, features, standardness, ...).
function compileWithOptions(e, mem, src, opts) {
  const encoded = encoder.encode(src);
  const srcPtr = e.bsvz_compile_alloc(encoded.length);
  assert.notStrictEqual(srcPtr, 0, "source alloc non-null");
  new Uint8Array(mem.buffer, srcPtr, encoded.length).set(encoded);

  // Features as comma-separated names.
  const features = (opts.features ?? []).join(",");
  const featEnc = encoder.encode(features);
  const featPtr = featEnc.length > 0 ? e.bsvz_scratch_alloc(featEnc.length) : 0;
  if (featPtr !== 0) {
    new Uint8Array(mem.buffer, featPtr, featEnc.length).set(featEnc);
  }

  // Standardness as comma-separated flag names (undefined = use defaults).
  const stdStr = opts.standardness ? opts.standardness.join(",") : "";
  const stdEnc = encoder.encode(stdStr);
  const stdPtr = stdEnc.length > 0 ? e.bsvz_scratch_alloc(stdEnc.length) : 0;
  if (stdPtr !== 0) {
    new Uint8Array(mem.buffer, stdPtr, stdEnc.length).set(stdEnc);
  }

  const UNSET = 4294967295; // maxInt(u32) sentinel = "use default"
  const status = e.bsvz_compile(
    srcPtr,
    encoded.length,
    opts.target ?? 0,
    opts.enforceStandardness ?? 1,
    opts.maxScriptSize ?? 10_000,
    opts.maxStackElements ?? 1_000,
    opts.maxPushSize ?? 520,
    opts.emitAsm ?? 0,
    opts.network ?? UNSET,
    opts.era ?? UNSET,
    opts.blockHeight ?? UNSET,
    opts.protocolVersion ?? 1,
    opts.txVersion ?? 1,
    featPtr,
    featEnc.length,
    stdPtr,
    stdEnc.length,
  );

  if (featPtr !== 0) e.bsvz_scratch_free(featPtr, featEnc.length);
  if (stdPtr !== 0) e.bsvz_scratch_free(stdPtr, stdEnc.length);

  return status;
}

test("valid compile returns ok and getters report results", async () => {
  const { instance, e, mem } = await instantiate();
  const [ptr, len] = allocSource(e, mem, "OP_DUP");

  const status = e.bsvz_compile(ptr, len, 0, 1, 10_000, 1_000, 520, 0);
  assert.strictEqual(status, 0, "expected ok (0)");

  const bcLen = e.bsvz_bytecode_len();
  assert.ok(bcLen > 0, "bytecode length should be > 0");
  assert.notStrictEqual(e.bsvz_bytecode_ptr(), 0, "bytecode ptr non-null");

  assert.notStrictEqual(e.bsvz_hash_ptr(), 0, "hash ptr non-null");
  assert.ok(e.bsvz_opcode_count() > 0, "opcode count > 0");
  assert.ok(e.bsvz_byte_length() > 0, "byte length > 0");
  assert.ok(e.bsvz_max_stack_height() > 0, "max stack height > 0");

  const std = e.bsvz_is_standard();
  assert.ok(std === 0 || std === 1, "is_standard is 0 or 1");

  // Success may produce zero or more diagnostics; just assert the getter works.
  assert.ok(e.bsvz_diag_count() >= 0);

  e.bsvz_free();
});

test("invalid target returns invalid_option (-8)", async () => {
  const { instance, e, mem } = await instantiate();
  const [ptr, len] = allocSource(e, mem, "OP_DUP");

  const status = e.bsvz_compile(ptr, len, 99, 1, 10_000, 1_000, 520, 0);
  assert.strictEqual(status, -8, "expected invalid_option (-8)");
  assert.strictEqual(e.bsvz_last_error(), -8, "last_error reflects -8");

  e.bsvz_free();
});

test("empty source returns invalid_input (-7)", async () => {
  const { instance, e, mem } = await instantiate();

  // alloc(0) must refuse.
  assert.strictEqual(e.bsvz_compile_alloc(0), 0, "alloc(0) returns null");

  // compile with len 0 also yields invalid_input.
  const status = e.bsvz_compile(0, 0, 0, 1, 10_000, 1_000, 520, 0);
  assert.strictEqual(status, -7, "expected invalid_input (-7)");

  e.bsvz_free();
});

test("invalid script returns non-ok status with diagnostics", async () => {
  const { instance, e, mem } = await instantiate();
  const [ptr, len] = allocSource(e, mem, "OP_DUP !");

  const status = e.bsvz_compile(ptr, len, 0, 1, 10_000, 1_000, 520, 0);
  assert.ok(status < 0, "expected a non-ok status");

  const count = e.bsvz_diag_count();
  assert.ok(count >= 1, "expected at least one diagnostic");

  // Diagnostic 0 getters.
  const phase = e.bsvz_diag_phase(0);
  assert.ok(phase >= 1 && phase <= 5, "phase in 1..5");
  const severity = e.bsvz_diag_severity(0);
  assert.ok(severity >= 1 && severity <= 3, "severity in 1..3");
  assert.strictEqual(typeof e.bsvz_diag_line(0), "number");
  assert.strictEqual(typeof e.bsvz_diag_column(0), "number");
  assert.strictEqual(typeof e.bsvz_diag_offset(0), "number");

  const mptr = e.bsvz_diag_message_ptr(0);
  assert.notStrictEqual(mptr, 0, "message ptr non-null");
  const mlen = e.bsvz_diag_message_len(0);
  assert.ok(mlen > 0, "message length > 0");
  const msg = readString(mem, mptr, mlen);
  assert.ok(msg.length > 0, "message decodes to non-empty string");

  // Out-of-range diagnostic index yields 0/null safely.
  assert.strictEqual(e.bsvz_diag_message_ptr(999), 0, "oob diag message ptr null");

  e.bsvz_free();
});

test("emit_asm flag controls asm output", async () => {
  const { instance, e, mem } = await instantiate();
  const src = "OP_DUP OP_DROP";

  // With asm emission.
  {
    const [ptr, len] = allocSource(e, mem, src);
    const status = e.bsvz_compile(ptr, len, 0, 1, 10_000, 1_000, 520, 1);
    assert.strictEqual(status, 0, "compile with asm ok");
    assert.notStrictEqual(e.bsvz_asm_ptr(), 0, "asm ptr non-null when emit_asm=1");
    const asmLen = e.bsvz_asm_len();
    assert.ok(asmLen > 0, "asm len > 0");
    const text = readString(mem, e.bsvz_asm_ptr(), asmLen);
    assert.ok(text.includes("OP_"), "asm text contains OP_");
    e.bsvz_free();
  }

  // Without asm emission.
  {
    const [ptr, len] = allocSource(e, mem, src);
    const status = e.bsvz_compile(ptr, len, 0, 1, 10_000, 1_000, 520, 0);
    assert.strictEqual(status, 0, "compile without asm ok");
    assert.strictEqual(e.bsvz_asm_ptr(), 0, "asm ptr null when emit_asm=0");
    e.bsvz_free();
  }
});

test("bsvz_free resets result and is idempotent", async () => {
  const { instance, e, mem } = await instantiate();
  const [ptr, len] = allocSource(e, mem, "OP_DUP");
  const status = e.bsvz_compile(ptr, len, 0, 1, 10_000, 1_000, 520, 0);
  assert.strictEqual(status, 0);

  e.bsvz_free();
  assert.strictEqual(e.bsvz_bytecode_ptr(), 0, "bytecode ptr null after free");
  assert.strictEqual(e.bsvz_bytecode_len(), 0, "bytecode len 0 after free");

  // Second free must not throw.
  assert.doesNotThrow(() => e.bsvz_free(), "double free is free is safe");
});

test("conditional feature flag controls emitted bytecode", async () => {
  const { instance, e, mem } = await instantiate();
  // lshiftnum is chronicle-only → disabled under the default (genesis) era.
  // Forwarding it via the features param must select the then-branch.
  const src = "@has(lshiftnum){ OP_DUP } else { OP_DROP }";

  // With lshiftnum forwarded, the then-branch (OP_DUP = 0x76) is emitted.
  const withFeat = compileWithOptions(e, mem, src, { features: ["lshiftnum"] });
  assert.strictEqual(withFeat, 0, "compile with lshiftnum forwarded ok");
  assert.strictEqual(e.bsvz_bytecode_len(), 1, "exactly one byte with feature");
  assert.strictEqual(new Uint8Array(mem.buffer, e.bsvz_bytecode_ptr(), 1)[0], 0x76,
    "emits OP_DUP (0x76) when feature forwarded");
  e.bsvz_free();

  // Without the feature, the default era lacks lshiftnum → else-branch
  // (OP_DROP = 0x75).
  const noFeat = compileWithOptions(e, mem, src, { features: [] });
  assert.strictEqual(noFeat, 0, "compile without feature ok");
  assert.strictEqual(e.bsvz_bytecode_len(), 1, "exactly one byte without feature");
  assert.strictEqual(new Uint8Array(mem.buffer, e.bsvz_bytecode_ptr(), 1)[0], 0x75,
    "emits OP_DROP (0x75) when feature absent");
  e.bsvz_free();
});

test("era option affects conditional compilation", async () => {
  const { instance, e, mem } = await instantiate();
  // cat is enabled in chronicle but not in bip era.
  const src = "@era(chronicle){ OP_DUP } else { OP_DROP }";

  // Chronicle era (5) → then-branch (OP_DUP = 0x76).
  const chronicle = compileWithOptions(e, mem, src, { era: 5 });
  assert.strictEqual(chronicle, 0, "compile under chronicle era ok");
  assert.strictEqual(new Uint8Array(mem.buffer, e.bsvz_bytecode_ptr(), 1)[0], 0x76,
    "emits OP_DUP under chronicle era");
  e.bsvz_free();

  // Bip era (1) lacks cat → else-branch (OP_DROP = 0x75).
  const bip = compileWithOptions(e, mem, src, { era: 1 });
  assert.strictEqual(bip, 0, "compile under bip era ok");
  assert.strictEqual(new Uint8Array(mem.buffer, e.bsvz_bytecode_ptr(), 1)[0], 0x75,
    "emits OP_DROP under bip era");
  e.bsvz_free();
});

test("invalid network or era returns invalid_option", async () => {
  const { instance, e, mem } = await instantiate();
  const [ptr, len] = allocSource(e, mem, "OP_DUP");

  // network = 99 is out of range.
  const badNetwork = e.bsvz_compile(
    ptr, len, 0, 1, 10_000, 1_000, 520, 0,
    99, 4294967295, 4294967295, 1, 1, 0, 0, 0, 0,
  );
  assert.strictEqual(badNetwork, -8, "invalid network → invalid_option");

  // era = 99 is out of range.
  const badEra = e.bsvz_compile(
    ptr, len, 0, 1, 10_000, 1_000, 520, 0,
    4294967295, 99, 4294967295, 1, 1, 0, 0, 0, 0,
  );
  assert.strictEqual(badEra, -8, "invalid era → invalid_option");

  e.bsvz_free();
});
