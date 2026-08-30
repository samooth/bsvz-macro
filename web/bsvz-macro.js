const ERROR_NAMES = {
  [-1]: "LexError",
  [-2]: "ParseError",
  [-3]: "ExpandError",
  [-4]: "SimError",
  [-5]: "ValError",
  [-6]: "OutOfMemory",
  [-7]: "InvalidInput",
  [-8]: "InvalidOption",
};

export class CompileError extends Error {
  constructor(code, diagnostics = []) {
    const name = ERROR_NAMES[code] ?? `UnknownError(${code})`;
    super(`bsvz-macro: ${name}`);
    this.name = "CompileError";
    this.code = code;
    this.errorName = name;
    this.diagnostics = diagnostics;
  }
}

const PHASES = ["lex", "parse", "expand", "simulate", "validate"];
const SEVERITIES = ["error", "warning", "note"];

// Integer values MUST match the Zig enums in src/options.zig.
export const Target = Object.freeze({
  bsv_mainnet: 0,
  bsv_testnet: 1,
  btc_strict: 2,
});

export const Network = Object.freeze({
  btc_mainnet: 0,
  btc_testnet: 1,
  bch_mainnet: 2,
  bch_testnet: 3,
  bsv_mainnet: 4,
  bsv_testnet: 5,
  bsv_regtest: 6,
});

export const Era = Object.freeze({
  satoshi: 0,
  bip: 1,
  bch: 2,
  bsv_pre_genesis: 3,
  genesis: 4,
  chronicle: 5,
});

// Feature names MUST match the Zig FeatureSet field names in src/options.zig.
export const FEATURES = Object.freeze([
  "era_satoshi", "era_bip", "era_bch", "era_bsv_pre_genesis", "era_genesis",
  "era_chronicle", "cat", "split", "and_op", "or_op", "xor_op", "div", "mod",
  "num2bin", "bin2num", "mul", "invert", "lshift", "rshift", "lshiftnum",
  "rshiftnum", "2mul", "2div", "substr", "left", "right", "ver", "verif",
  "cltv", "csv", "p2sh", "dersig", "otda", "codesep_sigsig", "bigpush",
  "bigscript", "malleability_fixes", "forkid", "low_s", "nulldummy",
  "sigpushonly", "cleanstack", "minimaldata", "minimalif", "bsv", "btc_strict",
]);

// Standardness flag names MUST match the Zig StandardnessFlags field names
// in src/options.zig. When standardness is provided, ONLY the listed flags are
// enabled (the rest are disabled).
export const STANDARDNESS = Object.freeze([
  "dersig", "low_s", "forkid", "cleanstack", "nulldummy", "sigpushonly",
  "minimaldata", "minimalif",
]);

const MAX_U32 = 4294967295;

export const DEFAULT_OPTIONS = Object.freeze({
  target: Target.bsv_mainnet,
  network: undefined,
  era: undefined,
  blockHeight: undefined,
  protocolVersion: 1,
  txVersion: 1,
  features: [],
  standardness: undefined,
  enforceStandardness: true,
  maxScriptSize: 10_000,
  maxStackElements: 1_000,
  maxPushSize: 520,
  emitAsm: false,
});

function normalizeOptions(options) {
  const o = { ...DEFAULT_OPTIONS, ...options };
  if (!Number.isInteger(o.target) || o.target < 0 || o.target > 2) {
    throw new TypeError("options.target must be one of Target values");
  }
  if (o.network !== undefined) {
    if (!Number.isInteger(o.network) || o.network < 0 || o.network > 6) {
      throw new TypeError("options.network must be one of Network values");
    }
  }
  if (o.era !== undefined) {
    if (!Number.isInteger(o.era) || o.era < 0 || o.era > 5) {
      throw new TypeError("options.era must be one of Era values");
    }
  }
  if (o.blockHeight !== undefined) {
    if (!Number.isInteger(o.blockHeight) || o.blockHeight < 0) {
      throw new TypeError("options.blockHeight must be a non-negative integer");
    }
  }
  for (const key of ["protocolVersion", "txVersion"]) {
    if (!Number.isInteger(o[key]) || o[key] < 0) {
      throw new TypeError(`options.${key} must be a non-negative integer`);
    }
  }
  if (!Array.isArray(o.features)) {
    throw new TypeError("options.features must be an array of feature names");
  }
  for (const f of o.features) {
    if (!FEATURES.includes(f)) {
      throw new TypeError(`options.features contains unknown feature: ${f}`);
    }
  }
  if (o.standardness !== undefined) {
    if (!Array.isArray(o.standardness)) {
      throw new TypeError("options.standardness must be an array of flag names");
    }
    for (const s of o.standardness) {
      if (!STANDARDNESS.includes(s)) {
        throw new TypeError(`options.standardness contains unknown flag: ${s}`);
      }
    }
  }
  for (const key of ["maxScriptSize", "maxStackElements", "maxPushSize"]) {
    if (!Number.isInteger(o[key]) || o[key] < 0) {
      throw new TypeError(`options.${key} must be a non-negative integer`);
    }
  }
  return o;
}

export async function load(source) {
  let bytes;
  if (source instanceof WebAssembly.Module) {
    bytes = source;
  } else if (source instanceof ArrayBuffer || ArrayBuffer.isView(source)) {
    bytes = source;
  } else {
    bytes = await (await fetch(source)).arrayBuffer();
  }
  const { instance } = await WebAssembly.instantiate(bytes, {});
  return new BsvzMacro(instance);
}

export class BsvzMacro {
  constructor(instance) {
    this.#instance = instance;
    this.#e = instance.exports;
    this.#memory = this.#e.memory;
    if (!this.#e.bsvz_compile) {
      throw new TypeError("not a bsvz-macro wasm instance");
    }
  }

  #instance;
  #e;
  #memory;

  compile(source, options = {}) {
    const o = normalizeOptions(options);
    let text = source;
    if (typeof text !== "string") {
      throw new TypeError("source must be a string");
    }
    const encoded = new TextEncoder().encode(text);
    if (encoded.length === 0) {
      throw new CompileError(-7);
    }
    const ptr = this.#e.bsvz_compile_alloc(encoded.length);
    if (ptr === 0) {
      throw new CompileError(-6);
    }
    new Uint8Array(this.#memory.buffer, ptr, encoded.length).set(encoded);

    // Encode features / standardness as comma-separated name strings via the
    // scratch allocator (does not disturb the source buffer).
    const featuresStr = o.features.join(",");
    const standardnessStr = o.standardness ? o.standardness.join(",") : "";
    const featEncoded = new TextEncoder().encode(featuresStr);
    const stdEncoded = new TextEncoder().encode(standardnessStr);
    const featPtr = featEncoded.length > 0
      ? this.#e.bsvz_scratch_alloc(featEncoded.length)
      : 0;
    if (featPtr !== 0) {
      new Uint8Array(this.#memory.buffer, featPtr, featEncoded.length).set(featEncoded);
    }
    const stdPtr = stdEncoded.length > 0
      ? this.#e.bsvz_scratch_alloc(stdEncoded.length)
      : 0;
    if (stdPtr !== 0) {
      new Uint8Array(this.#memory.buffer, stdPtr, stdEncoded.length).set(stdEncoded);
    }

    // maxInt(u32) sentinel means "use default" for nullable enums.
    const network = o.network === undefined ? MAX_U32 : o.network;
    const era = o.era === undefined ? MAX_U32 : o.era;
    const blockHeight = o.blockHeight === undefined ? MAX_U32 : o.blockHeight;

    const status = this.#e.bsvz_compile(
      ptr,
      encoded.length,
      o.target,
      o.enforceStandardness ? 1 : 0,
      o.maxScriptSize,
      o.maxStackElements,
      o.maxPushSize,
      o.emitAsm ? 1 : 0,
      network,
      era,
      blockHeight,
      o.protocolVersion,
      o.txVersion,
      featPtr,
      featEncoded.length,
      stdPtr,
      stdEncoded.length,
    );

    // Free the temporary feature/standardness scratch buffers.
    if (featPtr !== 0) this.#e.bsvz_scratch_free(featPtr, featEncoded.length);
    if (stdPtr !== 0) this.#e.bsvz_scratch_free(stdPtr, stdEncoded.length);

    if (status !== 0) {
      const diagnostics = this.#readDiagnostics();
      this.#e.bsvz_free();
      throw new CompileError(status, diagnostics);
    }

    const mem = new Uint8Array(this.#memory.buffer);
    const bytecodePtr = this.#e.bsvz_bytecode_ptr();
    const bytecodeLen = this.#e.bsvz_bytecode_len();
    const bytecode = mem.slice(bytecodePtr, bytecodePtr + bytecodeLen);

    let asmText = null;
    const asmPtr = this.#e.bsvz_asm_ptr();
    if (asmPtr !== 0) {
      const asmLen = this.#e.bsvz_asm_len();
      asmText = new TextDecoder().decode(mem.slice(asmPtr, asmPtr + asmLen));
    }

    const hashPtr = this.#e.bsvz_hash_ptr();
    const hash = mem.slice(hashPtr, hashPtr + 32);

    const result = {
      bytecode,
      asmText,
      hash,
      opcodeCount: this.#e.bsvz_opcode_count(),
      byteLength: this.#e.bsvz_byte_length(),
      maxStackHeight: this.#e.bsvz_max_stack_height(),
      isStandard: this.#e.bsvz_is_standard() === 1,
      diagnostics: this.#readDiagnostics(),
    };

    this.#e.bsvz_free();
    return result;
  }

  #readDiagnostics() {
    const count = this.#e.bsvz_diag_count();
    const out = [];
    const mem = new Uint8Array(this.#memory.buffer);
    const decoder = new TextDecoder();
    for (let i = 0; i < count; i++) {
      const mptr = this.#e.bsvz_diag_message_ptr(i);
      if (mptr === 0) continue;
      const mlen = this.#e.bsvz_diag_message_len(i);
      const phaseIdx = this.#e.bsvz_diag_phase(i) - 1;
      const sevIdx = this.#e.bsvz_diag_severity(i) - 1;
      out.push({
        phase: PHASES[phaseIdx] ?? `phase(${phaseIdx + 1})`,
        severity: SEVERITIES[sevIdx] ?? `severity(${sevIdx + 1})`,
        line: this.#e.bsvz_diag_line(i),
        column: this.#e.bsvz_diag_column(i),
        offset: this.#e.bsvz_diag_offset(i),
        message: decoder.decode(mem.slice(mptr, mptr + mlen)),
      });
    }
    return out;
  }

  free() {
    this.#e.bsvz_free();
  }
}
