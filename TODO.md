# TODO — Next Step: Enable iterator variable substitution (`<i>`)

## Goal
Make the `<i>` iterator variable usable as a statement and as a macro argument
inside `LOOP[n]{ ... }` bodies. Today the lexer emits an `.iterator_var` token
but the parser rejects it (`ParseError.UnexpectedToken`), so `<i>` cannot be used
at all. The expander already substitutes `iterator_ref` nodes (see
`src/expander/expander.zig` `substituteIterator`), so only the parser is missing.

## Why
- Unlocks macro/loop interaction: `LOOP[n]{ RANGE_CHECK[<i>,100] }` should expand
  to the concatenation of `RANGE_CHECK[0,100]`, `RANGE_CHECK[1,100]`, … .
- Enables stronger property-based tests (deterministic per-iteration expansion).
- Removes a documented known pitfall (`AGENTS.md`, `LESSONS_ZIG.md`).

## Tasks
- [x] 1. Parser: accept `.iterator_var` token as a top-level statement
        (`parseStatement` → `parseIteratorRef` → `AstNode.iterator_ref`).
- [x] 2. Parser: accept `.iterator_var` token inside macro argument lists
        (`parseArg`).
- [x] 3. Add parser unit tests for `<i>` as statement and macro argument
        (in `tests/parser_tests.zig`).
- [x] 4. Re-add property tests for iterator substitution in
        `tests/property_tests.zig` (e.g. `RANGE_CHECK[<i>,100]` and `LOOP[n]{ <i> }`).
- [x] 5. Update `AGENTS.md` / `LESSONS_ZIG.md` to note `<i>` is now supported.
- [x] 6. Run `zig build test` and confirm all tests pass (exit 0).

## Notes / risks
- `<i>` only has meaning inside a `LOOP` body; outside one it stays an
  `iterator_ref` and expander returns `TypeMismatch` (acceptable).
- Iterator `i` runs `0..n-1`. Macros requiring `arg >= 1` (e.g. `OP_XSWAP[<i>]`)
  will fail on the first iteration (`i=0`) — expected, do not write tests for it.
- The simulator `OP_PICK`/`OP_ROLL` depth bug is **out of scope** here; it does
  not block this change.
