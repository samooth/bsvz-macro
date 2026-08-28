# Lessons Learned Working with Zig on bsvz-macro

## Local‑Path Dependencies Require Sibling Checkouts
The project declares dependencies via relative paths in `build.zig.zon`:
```zig
.bsvz = { .path = "../bsvz" },
.zig_wallet_toolbox = { .path = "../zig-wallet-toolbox" },
```
CI workflows must therefore check out these repositories as siblings (e.g. `../bsvz` and `../zig-wallet-toolbox` relative to the macro repo) so the compiler can resolve them. See `.github/workflows/ci.yml`.

## Each Test File Is a Separate Root
In `build.zig`, the `test_step` depends on many `addTest`/`addRunArtifact` pairs, each with its own `root_module`. Consequently:
- Test helpers (`helpers.zig`, `test_data.zig`) must be `pub` and imported explicitly in each test file.
- There is no implicit sharing of test utilities across test roots; duplication is avoided only by importing the helper modules.

## Compile Options Are Hashed Verbatim
The `CompileOptions` struct (in `src/lib.zig`) is hashed via:
```zig
hasher.update(std.mem.asBytes(&options))
```
Changing any field—even ones that do not affect emitted bytecode like `.emit_asm`—alters the final hash. Property‑tests that assert hash stability must either fix all options or explicitly expect a change when an option toggles.

## Simulator Depth‑Argument Bug
In `src/simulator/engine.zig`, `OP_PICK` and `OP_ROLL` pop the depth value but then hard‑code `n = 0`:
```zig
.OP_PICK => {
    const n_item = try self.main_stack.pop();
    // … type check …
    const n: usize = 0;                 // BUG: ignores popped depth!
    const item = try self.main_stack.peek(n);
    try self.main_stack.push(a, item);
},
.OP_ROLL => {
    const n_item = try self.main_stack.pop();
    // … type check …
    const n: usize = 0;                 // BUG: ignores popped depth!
    const item = try self.main_stack.removeAt(a, n);
    try self.main_stack.push(a, item);
},
```
This bug caused property‑tests for looped `OP_XDROP[2]` to fail with stack underflow, because the depth argument is consumed by the `pop()` but the operation always uses depth 0.

## Stack Consumption of `OP_XDROP[2]`
The macro expands to:
```zig
emitMinimalPushInt(n - 1);   // push depth argument
emitOpcode(.OP_ROLL);        // consumes the depth value (pops it)
emitOpcode(.OP_DROP);        // drops another item
```
With the engine pre‑populating four integers, each iteration has net **-1**:
- `+1` from `push(n - 1)`,
- `-1` from `OP_ROLL` (it removes the depth we just pushed),
- `-1` from `OP_DROP`.
Looping five or more times therefore underflows the stack.

## Helper Utilities Reduce Boilerplate
Adding small, focused helpers to `tests/helpers.zig` keeps property tests readable:
- `expectDeterministicBytecode(allocator, source)` – compiles twice and compares bytecode.
- `expectBytecodeEquals(allocator, a, b)` – compares bytecode of two sources.
- `expectHashChangesWithOptions(allocator, source, base, variant)` – asserts that changing options changes the hash.
- `helpers.Prng` – a simple xorshift32 PRNG for reproducible random inputs in property tests.

Each new test in `tests/property_tests.zig` now reads as a one‑ or two‑line assertion instead of repeating compile/deinit/compare logic.

## Deterministic PRNG for Property Tests
External crates or non‑deterministic sources like `std.rand` are unnecessary for property‑based testing in Zig. A tiny xorshift32 PRNG (`helpers.Prng`) provides:
- Reproducible streams from a fixed seed.
- Uniform integer generation via `.range(max)`.
- Zero dependencies and no runtime overhead beyond a few integer operations.

It powers the "randomized compilable sources are deterministic" test, which generates 200 random scripts from a safe opcode alphabet and asserts that any source which compiles does so deterministically.

## Note on Iterator Substitution (`<i>`)
The lexer emits `.iterator_var` tokens for `<i>`. The parser now accepts these as
both a statement (`AstNode.iterator_ref`) and inside macro argument lists
(`parseArg`). The expander's `substituteIterator` replaces each `iterator_ref`
whose name matches the loop's `iterator_var` with an `integer_literal` of the
current index (0..n-1) before expansion. As a result, `LOOP[n]{ RANGE_CHECK[<i>,100] }`
expands to the concatenation of `RANGE_CHECK[0,100]`, `RANGE_CHECK[1,100]`, … .

Caveats:
- `<i>` is only meaningful inside a `LOOP` body; outside one it remains an
  `iterator_ref` and the expander returns `TypeMismatch`.
- The index runs `0..n-1`, so macros requiring `arg >= 1` (e.g. `OP_XSWAP[<i>]`)
  fail on the first iteration (`i=0`).

## Zig Language Gotchas (learned this session)
Specific Zig semantics that tripped up the implementation and are easy to forget:

### `@intCast` needs an inferable destination type
Inside a binary expression, `@intCast` cannot infer its result type:
```zig
// ERROR: @intCast must have a known result type
const len = @intCast(n) * single.byte_length;
// OK: bind to a typed variable first
const n_u32: u32 = @intCast(n);
const len: u32 = n_u32 * single.byte_length;
```
The cast’s destination type must be recoverable from context; a bare `@intCast(x)` in an arithmetic expression is not enough.

### `std.fmt.bufPrint` requires `{s}` for slices
A `[]const u8` argument must use the `{s}` specifier, not `{}`:
```zig
// ERROR: cannot format slice without a specifier (i.e. {s}, {x}, {b64}, or {any})
const s = try std.fmt.bufPrint(&buf, "LOOP[{}]{{ {} }}", .{ n, macro });
// OK
const s = try std.fmt.bufPrint(&buf, "LOOP[{}]{{ {s} }}", .{ n, macro });
```

### `compileComptime` returns dangling slices at runtime
`bsvz_macro.compileComptime` runs `compile` against a `std.heap.FixedBufferAllocator` backed by a **stack‑local** `buf: [4096]u8`. The returned `bytecode`/`asm_text` therefore point into memory that is freed when the function returns. Comparing those slices at runtime (e.g. `comptime bsvz_macro.compileComptime(...)` then reading `.bytecode`) is a use‑after‑free hazard. Use runtime `compile` for any assertion that inspects the result beyond the function boundary.

### `zig build test` hides success counts
When all tests pass, `zig build test` exits 0 and prints **no per‑test summary**—only failures are surfaced. Confirm pass/fail via the process exit code, not an "N passed" line. To see counts, force a failure or run a module directly.

### Manual `zig test` module flags
Assembling `zig test` module flags by hand fails with *"main module provided both by '-M…' and by positional argument"* if a `-Mname=path` also collides with the root. The working shape is:
```sh
zig test -ODebug --dep bsvz-macro --dep bsvz \
  -Mroot=tests/property_tests.zig \
  -Mbsvz-macro=src/lib.zig -Mbsvz=../bsvz/src/lib.zig \
  -Mzig-wallet-toolbox=../zig-wallet-toolbox/src/lib.zig --dep bsvz-macro
```
i.e. give the root via `-Mroot=` and declare dependency edges with `--dep`, rather than passing the test file as a positional argument.

---
*Generated during the test‑improvements session on 2026-08-28.*
