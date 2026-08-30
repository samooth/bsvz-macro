# TODO — Current Roadmap

## In progress (user WIP, do not touch)
- PUSHTX_SIGN_FAST / _FAST variants (WP1605 §1.4 alt-stack optimization)
  in `src/prelude.zig`; parity tests in `tests/script_engine_tests.zig` (untracked).
  Remaining: document `_FAST` macros in macro_reference.md / PUSHTX.md / README,
  then commit.

## Done this round
- [x] WASM target + JS bindings (`zig build wasm`, `web/`, CI wasm job)
- [x] `opcode_count` now counts real opcodes (walks push-data boundaries),
      not raw byte length (`countOpcodes` in `src/lib.zig`)
- [x] LOOP fixtures wired into canonical tests; dead `comptime_exp.zig`
      and invalid `covenant_cases.zig` fixture removed

## Next steps
1. Full-accumulation diagnostics: `CompileDiagnostic` + `SourceLocation`
   (blueprint §10.2) threaded through lexer/parser/expander/simulator/validator;
   `compileWithDiagnostics()` API + wasm getters + JS `err.diagnostics`.
2. User-defined macros: export `MacroTable` + `registerMacro` from `lib.zig`,
   add `compileWithTable()` (blueprint §10.3).
3. Bridge Phase 6: export `bridge` namespace from `lib.zig`, P2PKH/P2SH/PELS
   output helpers, `tests/bridge_tests.zig`, fix doc references to the
   non-existent `bridge.wallet` API.
4. Robustness: `std.testing.fuzz` for lexer/parser/expander;
   `fromAsm(toAsm(x)) == x` property over macro corpus; Zig-side tests for
   the wasm surface (options decode, status mapping).
5. Performance: LOOP fast path when body has no iterator (skip per-iteration
   AST clone); arena inside `compile()`; `zig build bench` printing timings
   (no in-tree thresholds per docs/TESTING.md policy).
6. PUSHTX leftovers: §1.4 optimized outputsRequest (no macro yet); PELS bare
   invocation SimError (simulator doesn't model pre-existing pubkey,
   see docs/PUSHTX.md).

## Notes / risks
- Blueprint Phase 1–5 checkboxes are ticked as verified this round; Phase 6
  (bridge) is in progress — see item 3 above.
- wasm module graph intentionally excludes `zig-wallet-toolbox`; keep it that
  way until the bridge actually needs it.
