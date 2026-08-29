import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { load } from "../bsvz-macro.js";

const here = dirname(fileURLToPath(import.meta.url));
const wasmPath = join(here, "..", "..", "zig-out", "wasm", "bsvz_macro.wasm");

let passed = 0;
let failed = 0;

function check(name, cond, detail) {
  if (cond) {
    passed++;
    console.log(`ok - ${name}`);
  } else {
    failed++;
    console.log(`FAIL - ${name}${detail ? `: ${detail}` : ""}`);
  }
}

const hex = (u8) => Buffer.from(u8).toString("hex");

const m = await load(readFileSync(wasmPath));

{
  const r = m.compile("SAFE_DIV");
  check("SAFE_DIV length", r.byteLength === 5, `got ${r.byteLength}`);
  check("SAFE_DIV bytecode", hex(r.bytecode) === "7c76926996", hex(r.bytecode));
  check("SAFE_DIV isStandard", r.isStandard === true);
  check("SAFE_DIV hash", r.hash.length === 32);
  check("SAFE_DIV asmText null without emitAsm", r.asmText === null);
}

{
  const r = m.compile("RANGE_CHECK[0,100]");
  check("RANGE_CHECK length", r.byteLength === 9, `got ${r.byteLength}`);
  check("RANGE_CHECK bytecode", hex(r.bytecode) === "7600a27c0164a19a69", hex(r.bytecode));
}

{
  const r = m.compile("OP_DUP OP_HASH160", { emitAsm: true });
  check("HASH160 asm emitted", typeof r.asmText === "string" && r.asmText.length > 0, String(r.asmText));
}

{
  const r = m.compile("OP_1 OP_2 OP_ADD OP_DROP");
  check("simple opcodes length", r.byteLength === 4, `got ${r.byteLength}`);
}

{
  let threw = null;
  try {
    m.compile("LOOP[100]{OP_HASHCAT}");
  } catch (e) {
    threw = e;
  }
  check("LOOP[100]{OP_HASHCAT} throws", threw !== null);
  check("error name is SimError", threw?.errorName === "SimError", threw?.errorName);
}

{
  let threw = null;
  try {
    m.compile("RANGE_CHECK[<0x9c>,100]");
  } catch (e) {
    threw = e;
  }
  check("bad hex arg throws", threw !== null);
  check("error name is ExpandError", threw?.errorName === "ExpandError", threw?.errorName);
}

{
  const a = m.compile("OP_XSWAP[2] LOOP[3]{OP_HASHCAT}", { emitAsm: true });
  const b = m.compile("OP_XSWAP[2] LOOP[3]{OP_HASHCAT}", { emitAsm: true });
  check("deterministic bytecode", hex(a.bytecode) === hex(b.bytecode));
  check("deterministic hash", hex(a.hash) === hex(b.hash));
  check("hash changes with options", (() => {
    const c = m.compile("OP_XSWAP[2] LOOP[3]{OP_HASHCAT}", { emitAsm: true, enforceStandardness: false });
    return hex(a.hash) !== hex(c.hash);
  })());
}

{
  const before = m.compile("SAFE_DIV").byteLength;
  for (let i = 0; i < 2000; i++) {
    m.compile("SAFE_DIV");
  }
  const after = m.compile("SAFE_DIV").byteLength;
  check("2000-iteration soak stable", before === 5 && after === 5, `after ${after}`);
}

console.log(`\n${passed} passed, ${failed} failed`);
process.exit(failed === 0 ? 0 : 1);
