# bsvz-macro

> **Zero-Cost Macro Assembler for Bitcoin Script (BSV)**  
> *"You write the loop once, but emit it many times"*

[![Zig](https://img.shields.io/badge/Zig-0.16.0-orange.svg)](https://ziglang.org)
[![BSV](https://img.shields.io/badge/BSV-Chronicle%20ready-green.svg)](https://bsvblockchain.org)
[![License](https://img.shields.io/badge/License-Open%20BSV-blue.svg)](LICENSE)

`bsvz-macro` is a **wallet-side macro expansion compiler** for Bitcoin Script (BSV). It transforms a high-level symbolic language (parameterized macros) into legacy opcode sequences compatible with the original Bitcoin protocol (2009). The node never sees a macro; it only sees flat, acyclic, deterministic bytecode.

## Philosophy

| Principle | Description |
|---|---|
| **Totality** | Every expansion is finite, bounded, and terminates |
| **Hygiene** | Each macro operates in isolated scope — no leaks, no shadowing |
| **Zero-Cost** | Macros add zero runtime overhead |
| **Consensus Compatible** | Output is bit-for-bit identical to hand-written Script |
| **Auditability** | Source macro + params → reproducible bytecode |
| **Fail-Fast** | Better not to emit than to emit invalid bytecode |

## Inspiration

This project is a direct implementation of the ideas presented in the article [**"Macro Expansion in Bitcoin Script"**](https://singulargrit.substack.com/p/macro-expansion-in-bitcoin-script) published on Substack. The article formalizes Bitcoin Script as a two-stack pushdown automaton (2PDA) — computationally equivalent to a Turing machine when all control flow is statically bounded and unrolled at compile time — and proposes a wallet-side macro expansion compiler that transforms high-level symbolic macros into flat, acyclic, deterministic legacy opcode sequences.

> *"You write the loop once, but emit it many times — fully expanded, and verifiable by the node interpreter as a static script."*

The article establishes the theoretical foundation (stack algebra, pre/postconditions, macro hygiene, boundedness) that `bsvz-macro` implements in Zig. For a detailed analysis of the original article, see [`docs/article_analysis.md`](docs/article_analysis.md).

## Features

- **11 canonical macros**: `OP_XSWAP`, `OP_XDROP`, `OP_XROT`, `OP_HASHCAT`, `IFDUP`, `SAFE_DIV`, `RANGE_CHECK`, `P2PKH_FROM_PUBKEY`, `VERIFY_ALL`, `VERIFY_ANY`, `PUSHTX_FRAGMENT`
- **Loop unrolling**: `LOOP[n]{ body }` with iterator substitution `<i>`
- **Conditional compilation**: `@bsv`, `@chronicle`, `@btc_strict`, `@version(n)`
- **Symbolic stack simulator**: Validates stack transitions before emission
- **Bounds & policy validation**: Enforces consensus and standardness rules
- **Dual mode**: `compile()` (runtime) and `compileComptime()` (zero-cost at build time)
- **Real bsvz integration**: Uses `bsvz` ScriptEngine, ASM encoder, and transaction builder directly — **no mocks, no stubs**

## Quick Start

```zig
const bsvz_macro = @import("bsvz-macro");

// Runtime compilation
const result = try bsvz_macro.compile(allocator, "OP_XSWAP[3]", .{});
defer result.deinit(allocator);

// Comptime compilation — zero runtime cost
const contract = comptime bsvz_macro.compileComptime(
    "LOOP[5]{ OP_<i> OP_DUP OP_MUL }",
    .{ .target = .bsv_mainnet },
) catch unreachable;
```

## Installation

### Prerequisites

- [Zig 0.16.0+](https://ziglang.org/download/)
- Network access (dependencies are fetched automatically by the Zig package manager)

### Dependencies

`bsvz` and `zig-wallet-toolbox` are fetched from GitHub as pinned Git archives
(see `build.zig.zon`). No manual checkout or sibling-directory layout is
required — `zig build` downloads them on first use and caches them.

### Build

```bash
zig build
zig build test
```

## Usage

### Compile a Macro

```zig
const std = @import("std");
const bsvz_macro = @import("bsvz-macro");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const result = try bsvz_macro.compile(allocator, "OP_HASHCAT", .{
        .emit_asm = true,
    });
    defer result.deinit(allocator);

    std.debug.print("Bytecode: ", .{});
    for (result.bytecode) |b| std.debug.print("{x:0>2}", .{b});
    std.debug.print("\nASM: {s}\n", .{result.asm.?});
    std.debug.print("Max stack: {}\n", .{result.max_stack_height});
    std.debug.print("Standard: {}\n", .{result.is_standard});
}
```

### Loop Unrolling

```zig
const result = try bsvz_macro.compile(allocator,
    "LOOP[3]{ OP_<i> OP_ADD }", .{});
// Expands to: OP_0 OP_ADD OP_1 OP_ADD OP_2 OP_ADD
```

### Conditional Compilation

```zig
const result = try bsvz_macro.compile(allocator,
    "@bsv{ OP_CAT } else { OP_NOP }", .{});
```

### Integration with bsvz ScriptEngine

```zig
const bsvz = @import("bsvz");
const expansion = try bsvz_macro.compile(allocator, source, .{});
const script = bsvz.script.Script.init(expansion.bytecode);

var engine = bsvz.script.engine.ScriptEngine.init(allocator);
const exec_result = try engine.execute(script);
```

### Integration with zig-wallet-toolbox

```zig
const bsvz_macro = @import("bsvz-macro");

// Add a macro-generated output to a transaction
var builder = bsvz.transaction.Builder.init(allocator);
try bsvz_macro.bridge.wallet.addMacroOutput(
    &builder,
    "OP_HASH160 0x0000...0000 OP_EQUALVERIFY OP_CHECKSIG",
    1000,
    .{},
);
```

## Architecture

```
Source DSL
    |
    v
[Lexer]     → Tokens
    |
    v
[Parser]    → AST
    |
    v
[Expander]  → Bytecode (via MacroTable)
    |
    v
[Simulator] → Stack transitions (symbolic)
    |
    v
[Validator] → Bounds + Policy checks
    |
    v
[Encoder]   → Hex / ASM
```

## Available Macros

| Macro | Arity | Stack Effect | Expansion |
|---|---|---|---|
| `OP_XSWAP[n]` | 1 | `[..., x0, xn]` → `[..., xn, x0]` | `PUSH(n-1) PICK PUSH(n-1) ROLL SWAP DROP` |
| `OP_XDROP[n]` | 1 | `[..., x0, xn]` → `[...]` | `PUSH(n-1) ROLL DROP` |
| `OP_XROT[n]` | 1 | `[..., x0, xn]` → `[xn, ..., x0]` | `PUSH(n-1) ROLL` |
| `OP_HASHCAT` | 0 | `[x]` → `[x \|\| SHA256(x)]` | `DUP SHA256 SWAP CAT` |
| `IFDUP` | 0 | `[x]` → `[x]` or `[x, x]` | `DUP IF { DUP } ENDIF` |
| `SAFE_DIV` | 0 | `[a, b]` → `[a / b]` | `SWAP DUP 0NOTEQUAL VERIFY DIV` |
| `RANGE_CHECK[min,max]` | 2 | `[x]` → `[]` | `DUP min GE SWAP max LE BOOLAND VERIFY` |
| `P2PKH_FROM_PUBKEY` | 0 | `[sig, pubkey]` → `[]` | `DUP HASH160 <20b> EQUALVERIFY CHECKSIG` |
| `VERIFY_ALL[n]` | 1 | `[b1...bn]` → `[]` | `BOOLAND...VERIFY` |
| `VERIFY_ANY[n]` | 1 | `[b1...bn]` → `[]` | `BOOLOR...VERIFY` |
| `PUSHTX_FRAGMENT[n]` | 1 | `[..., xn]` → `[..., xn, xn \|\| HASH256(xn)]` | `PICK DUP HASH256 CAT` |
| `PUSHTX_TOCANONICAL` | 0 | `[s]` → `[s' ∈ [0, n/2]]` | `DUP n/2 GT IF n SWAP SUB ENDIF` |
| `PUSHTX_TOCANONICAL_FAST` | 0 | `[s]` → `[s' ∈ [0, n/2]]` | `DUP n/2 GT IF n SWAP SUB ENDIF` (byte-identical; `n` literal) |
| `PUSHTX_CONCATENATIONS` | 0 | `[r, s]` → `[DER(r,s)]` | `SIZE DUP 0x24 ADD 0x30 SWAP CAT 0x0220\|\|Gx\|\|02 CAT SWAP CAT SWAP CAT` |
| `PUSHTX_CONCATENATIONS_FAST` | 0 | `[r, s]` → `[DER(r,s)]` | same, but `0x0220\|\|Gx\|\|02` is built from `Gx` on the alt stack |
| `PUSHTX_TODER` | 0 | `[r, s]` → `[DER(r,s)]` | `PUSHTX_TOCANONICAL PUSHTX_CONCATENATIONS` |
| `PUSHTX_TODER_FAST` | 0 | `[r, s]` → `[DER(r,s)]` | `PUSHTX_TOCANONICAL_FAST` + reverse + `PUSHTX_CONCATENATIONS_FAST` |
| `PUSHTX_SIGN[sighash]` | 1 | `[z]` → `[sig\|\|sighash\|\|Gcomp]` | `HASH256 Gx ADD n MOD PUSHTX_TODER <sighash> CAT Gcomp CAT` |
| `PUSHTX_SIGN_FAST[sighash]` | 1 | `[z]` → `[sig\|\|sighash\|\|Gcomp]` | `HASH256 Gx DUP TOALTSTACK ADD n MOD PUSHTX_TODER_FAST <sighash> CAT Gcomp CAT` (byte-identical to `PUSHTX_SIGN`) |
| `PUSHTX_OUTPUTS_REQUEST[item8, items10_11]` | 2 | `[..., H, F]` → `[..., F, H, HASH256(H), ...]` | `2DUP HASH256 SWAP <item8> CAT SWAP CAT <items10_11> CAT` |
| `PUSHTX_SIGN_BIT_SHIFT[security, sighash]` | 2 | `[..., z]` → `[..., z, <sig>]` | `push security OP_RSHIFT push <prefix‖R‖0x0220> SWAP CAT push sighash CAT push P CHECKSIG` |
| `PELS_LOCKING_SCRIPT[sighash, item8, items10_11, pk_b_hash160]` | 4 | (full PELS script) | `[outputsRequest] [sign] OP_CHECKSIGVERIFY OP_SWAP 0x68 SPLIT NIP SWAP 0x8 SPLIT SWAP CAT EQUALVERIFY DUP HASH160 <H(PK_B)> EQUALVERIFY OP_CHECKSIG` |
| `PELS_LOCKING_SCRIPT_BIT_SHIFT[security, sighash, item8, items10_11, pk_b_hash160]` | 5 | (full PELS script, bit-shift) | `[outputsRequest] [sign_bit_shift] OP_CHECKSIGVERIFY OP_SWAP 0x68 SPLIT NIP SWAP 0x8 SPLIT SWAP CAT EQUALVERIFY DUP HASH160 <H(PK_B)> EQUALVERIFY OP_CHECKSIG` |

## DSL Grammar

```ebnf
script      ::= statement (";" statement)* ";"?
statement   ::= opcode
              | macro "[" args "]" ["{" body "}"]
              | "LOOP" "[" integer "]" "{" body "}"
              | "@" flag ["(" integer ")"] "{" body "}" ["else" "{" body "}"]

opcode      ::= "OP_" IDENT
args        ::= arg ("," arg)*
arg         ::= integer | string | opcode
body        ::= statement (";" statement)* ";"?
flag        ::= "bsv" | "chronicle" | "btc_strict" | "version"
```

## Safety Limits

| Limit | Value |
|---|---|
| Max tokens per source | 10,000 |
| Max opcodes post-expansion | 1,000,000 |
| Macro recursion depth | 32 |
| Max loop bound | 1,000 |
| Script size (consensus) | 1 GB |
| Script size (policy) | 10 MB |
| Stack elements | 1,000 |
| Push size (policy) | 520 B |
| Push size (Chronicle) | 32 MB |

## API Reference

```zig
/// Compile source macro to bytecode (runtime)
pub fn compile(allocator, source, options) MacroError!MacroExpansion;

/// Compile source macro to bytecode (comptime — zero runtime cost)
pub fn compileComptime(source, options) MacroError!MacroExpansion;

/// Validate stack transitions symbolically
pub fn validateStack(allocator, bytecode, expected_pre, expected_post) MacroError!void;

/// Bytecode → ASM
pub fn toAsm(allocator, bytecode) ![]const u8;

/// ASM → Bytecode
pub fn fromAsm(allocator, asm_source) MacroError![]const u8;
```

## Testing

```bash
# All tests
zig build test

# Specific test suites
zig test src/lib.zig
zig test tests/macro_e2e.zig
zig test tests/canonical.zig
zig test tests/stack_sim.zig
```

## WASM Target

The core is pure Zig with no network or I/O dependencies, so it compiles to a
self-contained wasm32-freestanding module (~70 KB, zero imports, no libc).

```bash
zig build wasm
# -> zig-out/wasm/bsvz_macro.wasm
```

JS bindings live in `web/` (ESM + TypeScript types):

```js
import { load } from "./web/bsvz-macro.js";

const m = await load("./zig-out/wasm/bsvz_macro.wasm");
const result = m.compile("SAFE_DIV", { emitAsm: true });
// result: { bytecode: Uint8Array, asmText, hash, opcodeCount,
//           byteLength, maxStackHeight, isStandard }
```

Run the Node smoke test against the built artifact:

```bash
zig build wasm && node web/test/smoke.mjs
```

The wasm module graph intentionally excludes `zig-wallet-toolbox` (it is not
referenced by the macro compiler); only `bsvz` is imported.

## Related Projects

| Project | Description |
|---|---|
| [bsvz](https://github.com/samooth/bsvz) | BSV foundation library for Zig |
| [zig-wallet-toolbox](https://github.com/samooth/zig-wallet-toolbox) | Wallet toolkit for BSV |
| [ts-sdk](https://github.com/bsv-blockchain/ts-sdk) | TypeScript BSV SDK |
| [go-sdk](https://github.com/bsv-blockchain/go-sdk) | Go BSV SDK |

## License

This project is licensed under the **Open BSV License**.

The Open BSV License is a modified form of the MIT license that grants full rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell the software, with the following conditions:

1. The copyright notice and license text must be included in all copies or substantial portions.
2. **The software, and any software derived from it, must only be used on the BSV Blockchains** (mainnet and testnets).

This license is inherited from the upstream [`bsvz`](https://github.com/opldotdev/bsvz) dependency, which is released under the Open BSV License. See [LICENSE](LICENSE) for the full text.

> **Note:** The Open BSV License is not OSI-approved. It is a blockchain-specific license designed to prevent unauthorized use on competing blockchains while maintaining open-source accessibility within the BSV ecosystem.
