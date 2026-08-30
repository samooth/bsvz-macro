# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-08-30

### Added

- **Conditional compilation (4-layer flag system):** eras (`@era`), features
  (`@has`), limits (`@limit`, with `K`/`M`/`G` suffixes), networks
  (`@network`), `@standardness(...)` predicates, `@compileError("msg")`, plus
  legacy `@bsv` / `@chronicle` / `@btc_strict` / `@version[N]` flags with
  fixed semantics (`@chronicle` requires the chronicle era; `@version[N]`
  reads `protocol_version`).
- **Diagnostics:** `CompileDiagnostic` + `SourceLocation` threaded through
  lexer/parser/expander/simulator/validator; `compileWithDiagnostics()` API;
  WASM getters + JS `err.diagnostics`.
- **User-defined macros:** `MacroTable` + `registerMacro` exported from
  `lib.zig`; `compileWithTable()` / `compileWithTableAndDiagnostics()` APIs.
- **Bridge helpers:** `bridge` namespace (P2PKH/P2SH/PELS output helpers).
- **PUSHTX `_FAST` alt-stack variants:** `PUSHTX_SIGN_FAST`,
  `PUSHTX_TODER_FAST`, `PUSHTX_TOCANONICAL_FAST`,
  `PUSHTX_CONCATENATIONS_FAST`, `PUSHTX_OUTPUTS_REQUEST_FAST`,
  `PELS_LOCKING_SCRIPT_FAST` (WP1605 1.4 alt-stack optimization).
- **`compileWithUnlockingScript()`:** compile entry point that injects
  unlocking-script items onto the simulator stack so PELS scripts simulate
  end-to-end; `StackItem` re-exported.
- **WASM FFI surface tests:** Node test (`web/wasm_api.test.mjs`) covering
  status enums, result getters, diagnostic getters, ASM flag, and reset
  safety.

### Changed

- **Performance — LOOP fast path:** bodies that never reference `<i>` expand
  once and repeat the bytecode instead of cloning + expanding the AST per
  iteration.
- **Performance — scratch arena:** `compileInternal` routes lexer tokens,
  parser AST, and statement locations through a single `ArenaAllocator`,
  freed in one shot, replacing per-phase manual cleanup.
- **Bench timing output:** `bench:` tests in `tests/benchmark_tests.zig` print
  elapsed ms (no in-tree thresholds).

### Fixed

- Error-path memory leaks in `lexer/scanner.zig` and `parser/parser.zig`
  exposed by new fuzz tests.
- Property-based test harness extended with ASM round-trip (ASM-text
  idempotence), lex fuzz (random bytes), and mutation fuzz (mutated valid
  sources).

[Unreleased]: https://github.com/samooth/bsvz-macro/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/samooth/bsvz-macro/releases/tag/v0.1.0
