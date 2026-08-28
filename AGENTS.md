# AGENTS.md — Developer Guide for bsvz-macro

Atemporal guidance for anyone (human or automated agent) working in this
repository. Assumes Zig 0.16 and the project layout described in `README.md`.

## What this project is
A zero‑cost macro‑assembler that compiles a high‑level symbolic Bitcoin Script
(BSV) macro language into flat, legacy opcode sequences. Pipeline:
`lex → parse → expand → simulate → validate → (optional ASM)`. Public entry
point: `bsvz_macro.compile(allocator, source, options)` in `src/lib.zig`.

## Hard rules (do not violate)
- **Zig version**: target `0.16.0` (`minimum_zig_version` in `build.zig.zon`).
  Do not bump without updating CI and the README badge.
- **Dependencies are local paths**, not network fetches:
  `../bsvz` and `../zig-wallet-toolbox` (see `build.zig.zon`). Never replace
  them with registry URLs in this repo. They must exist as siblings for any
  build/test to work.
- **No mocks/stubs for `bsvz`**: the codebase integrates the real `bsvz`
  ScriptEngine/encoder. Keep it that way.
- **Fail‑fast on invalid bytecode**: prefer returning an error over emitting
  questionable output (the project philosophy is "better not to emit than to
  emit invalid bytecode").
- **No comments in source unless explicitly requested.** Code should be
  self‑documenting; update docs in `docs/` instead.

## Build & test
```sh
zig build test                 # run the whole suite (exit 0 == all pass)
zig build test -Doptimize=ReleaseSafe   # safety checks + stack traces
```
- `zig build test` prints **no per‑test summary on success**—rely on the exit
  code, not an "N passed" line.
- Each file under `tests/` is its own test root. To add a test utility, put it
  in `tests/helpers.zig` or `tests/test_data.zig` as a `pub` declaration and
  `@import` it from the test file that needs it.
- After editing test files, run `zig build test` and confirm exit 0 before
  considering work done.

## Adding tests (preferred patterns)
- Use the helpers in `tests/helpers.zig`: `compileDefault`, `compileWith`,
  `compileExpectError`, `expectBytecodeLength`, `expectDeterministicBytecode`,
  `expectBytecodeEquals`, `expectHashChangesWithOptions`, and `helpers.Prng`
  (deterministic xorshift32) for randomized/property inputs.
- Use `tests/test_data.zig`'s `ScriptBuilder` to construct sources instead of
  hand‑concatenating strings.
- Name property/invariant tests `property: <what holds>` and prefer
  Given/When/Then phrasing for clarity.

## Known pitfalls (read before touching these areas)
- **Simulator `OP_PICK`/`OP_ROLL` bug**: in `src/simulator/engine.zig` both
  opcodes pop the depth value but then hard‑code `n = 0`, ignoring the real
  depth. Any correct depth‑dependent behavior is currently impossible through
  the simulator. See `LESSONS_ZIG.md`.
- **`OP_XDROP[2]` is net −1 per iteration** (depth push consumed by `OP_ROLL`,
  then `OP_DROP`). With the engine pre‑populating four integers, looping it
  ≥5× underflows the stack. The same applies to other net‑negative macros
  (`SAFE_DIV`, `RANGE_CHECK`). Keep loop bounds small or use stack‑neutral /
  stack‑growing macros (`OP_XSWAP`, `OP_XROT`, `OP_HASHCAT`) in loop
  properties.
- **Iterator `<i>` is now supported**: the parser accepts `<i>` both as a loop
  body statement and inside macro argument lists (e.g. `LOOP[n]{ RANGE_CHECK[<i>,100] }`).
  The index runs `0..n-1`; macros requiring `arg >= 1` (e.g. `OP_XSWAP[<i>]`) fail
  on the first iteration (`i=0`). Outside a `LOOP` body, `<i>` is still invalid.
- **`compileComptime` returns dangling slices**: its result lives in a
  stack‑local `FixedBufferAllocator` buffer; never retain/compare it at
  runtime. Use runtime `compile` for assertions.
- **`@intCast` needs an inferable destination type** in arithmetic; bind to a
  typed variable first. `std.fmt.bufPrint` needs `{s}` (not `{}`) for slices.
  See `LESSONS_ZIG.md` for all language gotchas.

## Compile options & hashing
`CompileOptions` (target, `enforce_standardness`, `max_script_size`,
`max_stack_elements`, `max_push_size`, `emit_asm`) is hashed verbatim into the
result hash. Changing any option changes the hash even when bytecode is
identical. Preserve this invariant.

## CI
`.github/workflows/ci.yml` checks out this repo plus its two sibling
dependencies as siblings, then runs `zig build test` in Debug and ReleaseSafe.
Keep it in sync if dependency layouts or Zig version change.

## Docs
- `README.md` — project overview, features, macros.
- `docs/` — `blueprint.md`, `dsl_grammar.md`, `macro_reference.md`,
  `article_analysis.md`, `bsvz-macro-instrucciones.md`, and `TESTING.md`
  (coverage + benchmark baselines).
- `LESSONS_ZIG.md` — Zig‑specific and project‑specific lessons (read it when
  something builds but shouldn't, or fails for non‑obvious reasons).

## Commit etiquette
- Keep the working tree clean; commit only intended files (`git status` first).
- Write concise, imperative commit messages matching the existing style
  (e.g. `test: …`, `fix: …`).
- Do not commit secrets or keys. Do not push unless explicitly asked.
