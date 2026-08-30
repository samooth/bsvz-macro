export type Target = "bsv_mainnet" | "bsv_testnet" | "btc_strict";

export type DiagnosticPhase = "lex" | "parse" | "expand" | "simulate" | "validate";

export type DiagnosticSeverity = "error" | "warning" | "note";

export interface Diagnostic {
  phase: DiagnosticPhase | string;
  severity: DiagnosticSeverity | string;
  line: number;
  column: number;
  offset: number;
  message: string;
}

export interface CompileOptions {
  target?: Target;
  enforceStandardness?: boolean;
  maxScriptSize?: number;
  maxStackElements?: number;
  maxPushSize?: number;
  emitAsm?: boolean;
}

export type MacroErrorName =
  | "LexError"
  | "ParseError"
  | "ExpandError"
  | "SimError"
  | "ValError"
  | "OutOfMemory"
  | "InvalidInput"
  | "InvalidOption";

export class CompileError extends Error {
  code: number;
  errorName: MacroErrorName;
  diagnostics: Diagnostic[];
}

export interface MacroExpansion {
  bytecode: Uint8Array;
  asmText: string | null;
  hash: Uint8Array;
  opcodeCount: number;
  byteLength: number;
  maxStackHeight: number;
  isStandard: boolean;
  diagnostics: Diagnostic[];
}

export interface MacroExpansion {
  bytecode: Uint8Array;
  asmText: string | null;
  hash: Uint8Array;
  opcodeCount: number;
  byteLength: number;
  maxStackHeight: number;
  isStandard: boolean;
}

export declare const Target: {
  readonly bsv_mainnet: 0;
  readonly bsv_testnet: 1;
  readonly btc_strict: 2;
};

export declare const DEFAULT_OPTIONS: Readonly<Required<CompileOptions>>;

export declare class BsvzMacro {
  constructor(instance: WebAssembly.Instance);
  compile(source: string, options?: CompileOptions): MacroExpansion;
  free(): void;
}

export declare function load(
  source: string | URL | WebAssembly.Module | ArrayBuffer | ArrayBufferView,
): Promise<BsvzMacro>;
