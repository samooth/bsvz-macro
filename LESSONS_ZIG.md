# Lessons Learned Working with Zig on bsvz-macro

## Dependencies Are Fetched From GitHub
The project declares dependencies as pinned Git archives in `build.zig.zon`
(fetched by the Zig package manager — no sibling checkout needed):
```zig
.bsvz = .{
    .url = "https://github.com/samooth/bsvz/archive/<commit>.tar.gz",
    .hash = "bsvz-0.1.0-wvsL-dviFQDU2Al1QQBlT1s8lDJPmNDXLWdg1-1Q4fBw",
},
.zig_wallet_toolbox = .{
    .url = "https://github.com/samooth/zig-wallet-toolbox/archive/<commit>.tar.gz",
    .hash = "zig_wallet_toolbox-0.1.0-yWfVolP1BADleEjqRBsj38XcHaWp2LnYkw7RzsHS0-hG",
},
```
To update or pin a dependency, use `zig fetch --save <tarball-or-git-url>`; it
writes the correct `.url` + `.hash` into `build.zig.zon` automatically. CI does
not need to check out the dependencies as siblings.

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

## Simulator Depth‑Argument Bug (fixed)
`src/simulator/engine.zig` used to pop the `OP_PICK`/`OP_ROLL` depth value and then
hard‑code `n = 0`, ignoring the real depth. The fix required two changes:
- **Track literal values**: `StackItem` gained a `value: ?i64` field, populated by
  `OP_0`/`OP_1..OP_16`/`OP_1NEGATE`, direct `push`/`PUSHDATA*` opcodes (decoded via
  `decodeScriptNum`, capped at 8 bytes), and `pushedValue`. `OP_PICK`/`OP_ROLL` now
  read `n_item.value` and use it as the depth.
- **Model the caller's stack as unbounded**: a macro is a *fragment*, so the four
  pre‑populated items are not the whole story. `SymbolicStack.ensureDepth` lazily
  materializes the missing items at the bottom of the stack (as `.integer`, matching
  the existing pre‑population convention). This lets `OP_XSWAP[100]` and
  `PUSHTX_FRAGMENT[10]` compile; their reported `max_stack_height` counts how deep
  the fragment reaches. Depth errors still fire for a negative depth, a depth
  `>= max_stack_elements`, or a non‑integer depth argument.

A depth that is not a statically known literal (e.g. `OP_DEPTH OP_PICK`) keeps stack
heights correct but yields an `.unknown`‑typed item at the top, so the simulator stays
conservative instead of guessing.

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
  -Mbsvz-macro=src/lib.zig -Mbsvz=$(zig env ZIG_GLOBAL_CACHE_DIR)/.../bsvz/lib.zig \
  -Mzig-wallet-toolbox=$(zig env ZIG_GLOBAL_CACHE_DIR)/.../zig-wallet-toolbox/lib.zig --dep bsvz-macro
```
i.e. give the root via `-Mroot=` and declare dependency edges with `--dep`, rather than passing the test file as a positional argument. When dependencies are fetched (not local siblings), point `-Mbsvz`/`-Mzig-wallet-toolbox` at the cached package sources under the Zig global cache, or simply run the suites via `zig build test`.

---
*Generated during the test‑improvements session on 2026-08-28.*

### Hard-coded flag thresholds rot
The original conditional-flag implementation compared `@version[N]` against a hard-coded `ver <= 2` and treated `@chronicle` as an alias of `@bsv` (both fired on any BSV target). The redesign replaces both with data-driven evaluation: `@version[N]` reads `options.protocol_version`, and `@chronicle` reads the effective era. Lesson: never encode protocol constants in the expander — put them in `src/options.zig` (single source of truth) and derive everything else.

### `packed struct` + `inline for` gives free string-keyed lookup
`FeatureSet.hasByName(name)` / `isKnownFeature(name)` use `inline for (@typeInfo(...).@"struct".fields)` over a packed struct — a comptime-unrolled name match that doubles as a registry. Adding a feature means adding one field; no parser or expander changes. Same pattern works for enums (`Era.fromString`).

### Conditional payloads need deep copy in iterator substitution
`substituteIterator` clones the AST per loop iteration. When a union payload carries heap slices (`Condition.has_feature: []const u8`), a shallow copy aliases the original. The `.conditional` case must dupe the string payloads (see `substituteNode`) or the substituted node frees memory it does not own. If a future Condition variant gains a slice payload, extend that switch.

### Downstream opcode-name gaps: version-gate the workaround
When a dependency lags the spec (bsvz 0.1.0 lacked `OP_LSHIFTNUM`/`OP_RSHIFTNUM`), resist forking names into the DSL permanently. Keep a documented stand-in (`OP_NOP7`), file upstream, and swap to the real names the release lands — bsvz 0.2.0 added `OP_SUBSTR`/`OP_LEFT`/`OP_RIGHT`/`OP_LSHIFTNUM`/`OP_RSHIFTNUM`/`OP_2MUL`/`OP_2DIV` as first-class variants with `OP_NOP4`–`OP_NOP8` kept as aliases, so both old and new scripts keep lexing.

### Simulator must learn new opcode stack shapes
Adding a name to the lexer map is not enough. Each new opcode needs its net stack effect in `src/simulator/engine.zig` (`substr/left/right` are −1, `lshiftnum/rshiftnum` are −1, `2mul/2div` are neutral), otherwise `max_stack_height` silently misreports and net-negative ops hide stack underflow. When bsvz renames an opcode family, prune the old names from the simulator's do-nothing branches (`.OP_NOP4`–`.OP_NOP8` had to leave the NOP case) or both branches will claim the same byte.

---
*Appended during the flags-system redesign session on 2026-08-30.*
