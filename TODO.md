# TODO — Current Roadmap

## Done (this round)
- [x] Diagnostics: `CompileDiagnostic` + `SourceLocation` threaded through
      lexer/parser/expander/simulator/validator; `compileWithDiagnostics()` API;
      wasm getters + JS `err.diagnostics` (`src/diagnostics.zig`, tests,
      `docs/`). WASM binding complete (all `bsvz_diag_*` exports + JS
      `#readDiagnostics`).
- [x] User-defined macros: `MacroTable` + `registerMacro` exported from
      `lib.zig`; `compileWithTable()` / `compileWithTableAndDiagnostics()`
      (`src/expander/table.zig`, `tests/user_macros_tests.zig`).
- [x] Bridge Phase 6: `bridge` namespace exported from `lib.zig`; P2PKH/P2SH/
      PELS output helpers; `tests/bridge_tests.zig`
      (`src/bridge/wallet.zig`, `src/bridge/bsvz.zig`).
- [x] Robustness: `fromAsm(toAsm(x))` ASM-idempotence property; lex + mutation
      fuzz using a local xorshift (`tests/property_tests.zig`); fixed
      error-path memory leaks in `lexer/scanner.zig` and `parser/parser.zig`
      exposed by the fuzz tests.
- [x] PUSHTX_SIGN_FAST / _FAST variants (WP1605 §1.4 alt-stack optimization)
      in `src/prelude.zig`; bsvz ScriptEngine parity test; documented in
      `macro_reference.md` / `PUSHTX.md` / `README.md`.
- [x] Performance trinity:
      - LOOP fast path in `src/expander/expander.zig` — when the body never
        references `<i>`, expand once and repeat the bytecode instead of
        cloning + expanding the AST per iteration.
      - Scratch `ArenaAllocator` in `compileInternal` (`src/lib.zig`) backing
        lexer tokens, parser AST, and statement locations; one-shot
        `arena.deinit()` replaces per-phase manual cleanup.
      - Bench timing output: each `bench:` test in
        `tests/benchmark_tests.zig` prints elapsed ms (no in-tree thresholds,
        per `docs/TESTING.md`); libc linked for the bench module
        (`build.zig`).

## In progress (user WIP, do not touch)
— none —

- [x] PUSHTX leftovers: §1.4 alt-stack `outputsRequest` optimisation
      (`PUSHTX_OUTPUTS_REQUEST_FAST` in `src/prelude.zig`) paired with
      `PELS_LOCKING_SCRIPT_FAST`; `compileWithUnlockingScript()` entry point in
      `src/lib.zig` lets PELS scripts simulate end-to-end (the symbolic
      simulator does not model the unlocking script's pubkey). Documented in
      `macro_reference.md` / `PUSHTX.md` / `README.md`; tested in
      `tests/pushtx_fast_tests.zig`.

## Next steps
— none —

## Notes / risks
- Blueprint Phase 1–6 checkboxes are verified this round.
- The symbolic simulator executes both `OP_IF`/`OP_ELSE` branches linearly, so
  a conditional `OP_FROMALTSTACK` underflows the alt stack — the `_FAST`
  signing macros keep `Gx` on the alt stack but push `n` literally for the
  canonical step to stay simulator-safe.
- wasm module graph intentionally excludes `zig-wallet-toolbox`; keep it that
  way until the bridge actually needs it.
- `std.time.Timer`/`Instant`/`nanoTimestamp` are absent in this Zig 0.16.0-dev
  build; bench timing uses `std.c.clock_gettime(CLOCK_MONOTONIC)`.
