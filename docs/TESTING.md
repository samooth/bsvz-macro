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

### CLI

The CLI executable is built by `zig build` (installed to
`zig-out/bin/bsvz-macro`). Smoke it directly:

```sh
echo 'OP_DUP OP_DROP' | zig-out/bin/bsvz-macro -        # -> 7675, exit 0
echo 'UNKNOWN' | zig-out/bin/bsvz-macro -               # diagnostics, exit 1
zig-out/bin/bsvz-macro --era nada - < /dev/null         # usage error, exit 2
```

The pure logic (`runCliFromArgs`) is designed to stay unit-testable without
spawning a process; a `tests/cli_tests.zig` registration is the natural next
wiring step if the surface grows.

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

Zig supports instrumentation-based coverage. Enabling it for this project would
require wiring the coverage flag onto each test compile step in `build.zig`,
then post-processing the run with `llvm-cov` (shipped with Zig):

```sh
zig build test -Dcoverage
llvm-cov report ./.zig-cache/o/*/test \
  --instr-profile ./.zig-cache/o/*/test.profdata \
  --object ./.zig-cache/o/*/test
```

> **Status:** the `Step.Compile.coverage` field that earlier Zig 0.16 builds
> exposed is **not present** in this Zig 0.16.0-dev build, so the flag is not yet
> wired. Coverage reporting is documented as a future wiring task; until then
> the test suite is verified for correctness and leaks only (see "Validation"
> above). To add it, each `addTest(...)` step in `build.zig` needs the
> instrumentation enabled via whatever mechanism the installed Zig build system
> exposes (check `std.Build.Step.Compile` fields for the current version), and a
> `-Dcoverage` option threaded through.

`zig build test` produces the test binary under `.zig-cache/o/*/`. Manual `zig
test` invocations must reference the cached package sources from the Zig global
cache rather than local sibling paths.

See `build.zig.zon` (dependencies are fetched automatically) and
`.github/workflows/ci.yml` for the CI setup. The Zig package manager downloads
and caches `bsvz` on first build, so no manual checkout is needed for coverage
either.

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
