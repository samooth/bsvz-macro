# Testing Guide

This document describes how to run, cover, and benchmark the `bsvz-macro` test
suite, plus recommendations for keeping the suite healthy as the project grows.

## Running the tests

All tests are wired into a single `zig build` step:

```sh
zig build test
```

This compiles and runs every test module in `tests/` plus the in-source test
block in `src/lib.zig`. Each module is a separate test root so failures are
isolated per file. As of this writing the suite contains **320 passing tests**
across:

- `tests/lexer_tests.zig`, `tests/parser_tests.zig`, `tests/expander_tests.zig`,
  `tests/simulator_tests.zig`, `tests/validator_tests.zig` — unit + negative +
  edge-case coverage per module.
- `tests/flags_tests.zig` — conditional-compilation flag system (eras,
  `@has`, `@limit`, `@network`, `@standardness`, `@compileError`,
  legacy compatibility, era→feature derivation table).
- `tests/negative_tests.zig` — error-condition coverage (lexer/parser/expander/
  simulator/validator).
- `tests/property_tests.zig` — **property-based invariants** (determinism,
  loop unrolling, composition, conditional flag selection, randomized inputs).
- `tests/benchmark_tests.zig` — performance smoke + stress tests.
- `tests/helpers.zig`, `tests/test_data.zig` — self-tests for the test
  utilities themselves (builders + assertion helpers).
- `tests/examples_tests.zig`, `tests/canonical.zig`, `tests/macro_e2e.zig`,
  `tests/stack_sim.zig` — example / end-to-end coverage.

### Sanitizers / release mode

```sh
zig build test -Doptimize=ReleaseSafe   # enables safety checks + stack traces
```

## Test structure & conventions

- **Helpers** live in `tests/helpers.zig`: `compileDefault`, `compileWith`,
  `compileExpectError`, `expectBytecodeLength`, `expectDeterministicBytecode`,
  `expectBytecodeEquals`, `expectHashChangesWithOptions`, plus a small
  deterministic PRNG (`helpers.Prng`) for property-based inputs.
- **Builders** live in `tests/test_data.zig` (`ScriptBuilder`) for constructing
  script sources without string concatenation.
- **Given/When/Then** naming is used where it improves readability, e.g.
  `"property: LOOP[n]{ OP_DUP } peak stack height equals n"`.
- When adding a test that compiles a source, prefer the helpers over re-inlining
  `bsvz_macro.compile` + `defer deinit` so leaks stay checked and failures read
  clearly.

## Coverage reporting

Zig supports instrumentation-based coverage. To enable it for this project,
flip the coverage flag on the test compile steps in `build.zig`, for example:

```zig
const main_tests = b.addTest(.{ .root_module = macro_mod });
main_tests.coverage = true; // Zig 0.16: emits a raw profile next to the binary
```

Then run and post-process with `llvm-cov` (shipped with Zig):

```sh
zig build test
# produces ./zig-cache/.../test (with embedded coverage)
llvm-cov report \
  ./.zig-cache/o/*/test \
  --instr-profile ./.zig-cache/o/*/test.profdata \
  --object ./.zig-cache/o/*/test
```

Alternatively, for a one-off module, run `zig build test` (dependencies are
fetched automatically) and point `llvm-cov` at the generated test binary under
`.zig-cache/o/*/`. Manual `zig test` invocations must reference the cached
package sources from the Zig global cache rather than local sibling paths.

Coverage is **not** wired on by default. See `build.zig.zon` (dependencies are
fetched automatically from GitHub) and `.github/workflows/ci.yml` for the setup.
The Zig package manager downloads and caches `bsvz`/`zig-wallet-toolbox` on
first build, so no manual checkout is required for coverage either.

## Performance benchmarks & baselines

`tests/benchmark_tests.zig` is intentionally lightweight: each `bench:`/`stress:`
test runs a hot path many times and only fails on **correctness** or **timeout**,
not on absolute timing. This keeps CI fast and portable.

To catch performance regressions, run the suite and record timings locally:

```sh
time zig build test
```

Recommended baseline workflow:

1. After a meaningful change, run `time zig build test` on a quiet machine.
2. Record the `bench:`/`stress:` timings in a short note (or a CI artifact).
3. If a `bench:` test regresses by a noticeable margin, bisect the change
   before merging.

Do **not** assert hard latency thresholds in-tree — CI machines vary too much.
Keep the stress tests as smoke tests (they exercise deep loops / large inputs)
and treat absolute numbers as out-of-band baselines.

## CI

See `.github/workflows/ci.yml`. It checks out `bsvz-macro` and runs
`zig build test` in both debug and `ReleaseSafe` modes. Dependencies are fetched
automatically from GitHub by the Zig package manager, so no sibling checkout of
`bsvz`/`zig-wallet-toolbox` is needed.
