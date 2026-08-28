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
- **Dependencies are fetched, not local paths**: `bsvz` and
  `zig-wallet-toolbox` are pulled from GitHub as pinned Git archives in
  `build.zig.zon` (`.url` + `.hash`). Do not replace them with local
  `../` paths — the Zig package manager downloads and caches them on first
  build. A network connection is required for the initial fetch.
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
- **`OP_PICK`/`OP_ROLL` depth model**: the simulator honors the popped depth
  (it tracks literal push values in `StackItem.value`). Because a macro is a
  *fragment*, the caller's stack is modeled as unbounded: reaching a depth below
  the modeled items lazily materializes `.integer` items at the bottom
  (`SymbolicStack.ensureDepth`), so `OP_XSWAP[100]` and `PUSHTX_FRAGMENT[10]`
  compile and their reported `max_stack_height` includes the depth they reach.
  Errors are raised for a negative depth, a depth `>= max_stack_elements`, and a
  non‑integer depth. A depth that is not a statically known literal (e.g.
  `OP_DEPTH OP_PICK`) keeps heights correct and yields an `.unknown`‑typed item.
- **Net‑negative macros can still underflow in loops**: macros that only pop
  (`SAFE_DIV`, `RANGE_CHECK`) underflow the 4 pre‑populated items when looped
  (e.g. `LOOP[10]{ SAFE_DIV }` → `SimError`). `OP_XDROP[n]` no longer underflows,
  because `OP_ROLL` materializes the caller items it reaches for. Prefer
  stack‑neutral / stack‑growing macros (`OP_XSWAP`, `OP_XROT`, `OP_HASHCAT`) in
  loop properties.
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
`.github/workflows/ci.yml` checks out this repo and runs `zig build test` in
Debug and ReleaseSafe. Dependencies are fetched automatically from GitHub by
the Zig package manager (see `build.zig.zon`), so no sibling checkout is
needed. Keep it in sync if dependency URLs/hashes or Zig version change.

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
