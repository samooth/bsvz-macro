# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **CLI executable** (`zig-out/bin/bsvz-macro`, `zig build run -- <args>`):
  positional source file or `-` for stdin, full `CompileOptions` flag surface
  (`--target/--network/--era/--block-height/--protocol-version/--tx-version/
  --features/--standardness/--max-*/--enforce-standardness`), hex bytecode to
  stdout or `--output`/`-o`, `--asm-out`, structured `--json` output,
  diagnostics to stderr; exit 0/1/2 semantics.
- **bsvz 0.2.0 Chronicle opcodes.** `OP_SUBSTR`, `OP_LEFT`, `OP_RIGHT`,
  `OP_LSHIFTNUM`, `OP_RSHIFTNUM`, `OP_2MUL`, `OP_2DIV` lex as first-class
  opcodes (legacy `OP_NOP4`–`OP_NOP8` names still work via bsvz aliases);
  the simulator models their stack effects (net −1 for the string/numeric
  shifts, neutral for 2mul/2div) so `max_stack_height` is correct for
  Chronicle scripts. Corresponding `@has` features: `substr`, `left`,
  `right`, `2mul`, `2div`, `ver`, `verif` (chronicle-era only).
- **WASM/JS API: full `CompileOptions` forwarding.** The `bsvz_compile` export and
  `BsvzMacro.compile()` now accept the options that were previously silent
  defaults: `era`, `network`, `blockHeight`, `protocolVersion`, `txVersion`,
  `features` (array of feature names), and `standardness` (array of flag names).
  JS enum maps (`Network`, `Era`, `FEATURES`, `STANDARDNESS`) are exported so
  consumers can validate values; integer codes match the Zig enums in
  `src/options.zig`.
- New WASM exports: `bsvz_scratch_alloc` / `bsvz_scratch_free` (temporary
  string buffers for feature/standardness names).
- WASM FFI tests extended with conditional-compilation cases: feature flags and
  era select different branches, and out-of-range network/era returns
  `invalid_option`.

### Changed

- **Network-aware era derivation.** `block_height` → era resolution
  (`eraFromBlockHeightForNetwork`) now respects the network family: BTC
  heights cap at `bip`, BCH at `bch`; only BSV reaches
  `bsv_pre_genesis`/`genesis`/`chronicle`. Previously
  `block_height=620000` with `network=btc_mainnet` derived `.genesis`
  (BSV history).
- **Expander option caching.** `effectiveFeatures()`/`effectiveLimits()` are
  resolved once at `Expander.init` instead of per conditional evaluation.
- Dependency `bsvz` bumped 0.1.0 → **0.2.0** (Chronicle support tag).

### Fixed

- `docs/TESTING.md` coverage section: the `Step.Compile.coverage` field is not
  present in this Zig 0.16.0-dev build; documented as a future wiring task instead
  of wiring a non-functional flag.
- `tests/user_macros_tests.zig` used the old `ArrayListUnmanaged(u8){}`
  struct-literal init, which official Zig 0.16.0 rejects (the local dev build
  accepted it); migrated to `.empty` (CI failure).

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
