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

export const Target = Object.freeze({
  bsv_mainnet: 0,
  bsv_testnet: 1,
  btc_strict: 2,
});

export const DEFAULT_OPTIONS = Object.freeze({
  target: Target.bsv_mainnet,
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

    const status = this.#e.bsvz_compile(
      ptr,
      encoded.length,
      o.target,
      o.enforceStandardness ? 1 : 0,
      o.maxScriptSize,
      o.maxStackElements,
      o.maxPushSize,
      o.emitAsm ? 1 : 0,
    );
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
