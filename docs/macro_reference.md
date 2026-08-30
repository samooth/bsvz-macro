# bsvz-macro Reference

## Canonical Macros

### OP_XSWAP[n]
Swap the top stack item with the item at depth n.
- Arity: 1 (integer)
- Stack: [..., x0, xn] -> [..., xn, x0]
- Expansion: PUSH(n-1) PICK PUSH(n-1) ROLL SWAP DROP

### OP_XDROP[n]
Drop the item at depth n.
- Arity: 1 (integer)
- Stack: [..., x0, xn] -> [...]
- Expansion: PUSH(n-1) ROLL DROP

### OP_XROT[n]
Rotate the item at depth n to the top.
- Arity: 1 (integer)
- Stack: [..., x0, xn] -> [xn, ..., x0]
- Expansion: PUSH(n-1) ROLL

### OP_HASHCAT
Concatenate top item with its SHA256 hash.
- Arity: 0
- Stack: [x] -> [x || SHA256(x)]
- Expansion: DUP SHA256 SWAP CAT

### IFDUP
Duplicate top item if it is truthy.
- Arity: 0
- Stack: [x] -> [x] or [x, x]
- Expansion: DUP IF { DUP } ENDIF

### SAFE_DIV
Safe division with zero-check.
- Arity: 0
- Stack: [a, b] -> [a / b]
- Expansion: SWAP DUP 0NOTEQUAL VERIFY DIV

### RANGE_CHECK[min, max]
Verify top item is within range [min, max].
- Arity: 2 (integers)
- Stack: [x] -> []
- Expansion: DUP min GE SWAP max LE BOOLAND VERIFY

### P2PKH_FROM_PUBKEY
Standard P2PKH from pubkey (with placeholder hash).
- Arity: 0
- Stack: [sig, pubkey] -> []
- Expansion: DUP HASH160 <20-zero-bytes> EQUALVERIFY CHECKSIG

### VERIFY_ALL[n]
Verify that n boolean items on stack are all true.
- Arity: 1 (integer count)
- Stack: [b1, b2, ..., bn] -> []
- Expansion: BOOLAND...VERIFY

### VERIFY_ANY[n]
Verify that at least one of n boolean items is true.
- Arity: 1 (integer count)
- Stack: [b1, b2, ..., bn] -> []
- Expansion: BOOLOR...VERIFY

### PUSHTX_FRAGMENT[n]
PUSHTX helper per WP1605 (nChain, 2021) section 1.2: pick element at depth n, duplicate it, hash the copy, and concatenate the original with the hash to form a preimage fragment.
- Arity: 1 (integer depth 1-10)
- Stack: [..., xn] -> [..., xn, xn || HASH256(xn)]
- Expansion: PICK DUP HASH256 CAT

### PUSHTX_TOCANONICAL
PUSHTX [toCanonical] block per WP1605 §1.1: forces s into the range [0, n/2] by replacing s with n-s when s > n/2.
- Arity: 0
- Stack: [s] -> [s' where s' = s if s <= n/2 else n-s]
- Expansion: DUP <n/2> GREATERTHAN IF <n> SWAP SUB ENDIF

### PUSHTX_TOCANONICAL_FAST
Alt-stack variant of `PUSHTX_TOCANONICAL` (WP1605 §1.4 white-paper errata corrected: the comparison is against `n/2`, not `Gx/2`). Produces byte-identical canonical s. The curve order `n` is pushed literally here (the alt stack is reserved for `Gx` in `PUSHTX_CONCATENATIONS_FAST` so the symbolic simulator — which executes both conditional branches linearly — does not underflow the alt stack).
- Arity: 0
- Stack: [s] -> [s' where s' = s if s <= n/2 else n-s]
- Expansion: DUP <n/2> GREATERTHAN IF <n> SWAP SUB ENDIF

### PUSHTX_CONCATENATIONS
PUSHTX [concatenations] block per WP1605 §1.1: builds the DER-encoded (r, s) byte string from r (below) and s (on top).
- Arity: 0
- Stack: [r, s] -> [DER(r, s)]
- Expansion: SIZE DUP <0x24> ADD <0x30> SWAP CAT <02 20||Gx||02> CAT SWAP CAT SWAP CAT

### PUSHTX_CONCATENATIONS_FAST
Alt-stack variant of `PUSHTX_CONCATENATIONS` (WP1605 §1.4). Byte-identical DER output, but the `02 20 || Gx || 02` tag is assembled inline from the `Gx` held on the alt stack instead of re-pushing a 35-byte literal.
- Arity: 0
- Stack: [r, s] -> [DER(r, s)]
- Expansion: SIZE DUP <0x24> ADD <0x30> SWAP CAT <02 20> FROMALTSTACK CAT <02> CAT CAT SWAP CAT SWAP CAT

### PUSHTX_TODER
PUSHTX [toDER] block per WP1605 §1.1: canonicalises s and builds the DER structure.
- Arity: 0
- Stack: [r, s] -> [DER(r, s)]
- Expansion: PUSHTX_TOCANONICAL PUSHTX_CONCATENATIONS (inlined)

### PUSHTX_TODER_FAST
Alt-stack variant of `PUSHTX_TODER` (WP1605 §1.4): `PUSHTX_TOCANONICAL_FAST` + reverse-endianness + `PUSHTX_CONCATENATIONS_FAST`, byte-identical to `PUSHTX_TODER`.
- Arity: 0
- Stack: [r, s] -> [DER(r, s)]
- Expansion: PUSHTX_TOCANONICAL_FAST (inlined reverse) PUSHTX_CONCATENATIONS_FAST (inlined)

### PUSHTX_SIGN[sighash_flag]
PUSHTX [sign] block per WP1605 §1.1, using the k = a = 1 optimisation. Computes a deterministic signature over the message hash z on top of the stack. The sighash flag is appended to the DER signature together with the compressed public key (0x02 || Gx), ready for OP_CHECKSIG.
- Arity: 1 (integer sighash flag, e.g. 1 for SIGHASH_ALL, 0x83 for SINGLE|ANYONECANPAY)
- Stack: [z] -> [DER(r,s) || sighash || Gcomp]
- Expansion: HASH256 <Gx> ADD <n> MOD PUSHTX_TODER <sighash> CAT <0x02||Gx> CAT

### PUSHTX_SIGN_FAST[sighash_flag]
Alt-stack variant of `PUSHTX_SIGN` (WP1605 §1.4 white-paper errata corrected). Produces a byte-identical signature but pushes `Gx` to the alt stack once (consumed in the concatenations step), avoiding the 35-byte `Gx` literal re-push. A `bsvz` ScriptEngine parity test verifies it matches `PUSHTX_SIGN` byte-for-byte over several message preimages.
- Arity: 1 (integer sighash flag)
- Stack: [z] -> [DER(r,s) || sighash || Gcomp]
- Expansion: HASH256 <Gx> DUP TOALTSTACK ADD <n> MOD PUSHTX_TODER_FAST <sighash> CAT <0x02||Gx> CAT

### PUSHTX_OUTPUTS_REQUEST[item8_hex, items10_11_hex]
PUSHTX [outputsRequest] block per WP1605 §1.3. Constructs the message fragment for the outputs section (item 9 plus item 8 and items 10/11). Both arguments are hex strings (with or without the `0x` prefix, even length) that are pushed as raw bytes.
- Arity: 2 (string, string) — 4-byte item 8 and 8-byte concatenated items 10+11
- Stack: [..., item1..7, serialised_outputs] -> [..., item1..7, serialised_outputs, item9, item8, items10||11]
- Expansion: 2DUP HASH256 SWAP <item8> CAT SWAP CAT <items10||11> CAT

### PUSHTX_OUTPUTS_REQUEST_FAST[item8_hex, items10_11_hex]
Alt-stack variant of `PUSHTX_OUTPUTS_REQUEST` (WP1605 §1.4 optimisation). Byte-identical output, but caches the intermediate `Data2` on the alt stack to avoid re-deriving it.
- Arity: 2 (string, string)
- Expansion: 2DUP CAT TOALTSTACK SWAP CAT HASH256 <item8> SWAP CAT FROMALTSTACK SWAP CAT CAT <items10||11> CAT

### PELS_LOCKING_SCRIPT[sighash_flag, item8_hex, items10_11_hex, pk_b_hash160_hex]
Full Perpetually Enforcing Locking Script from WP1605 §1.3 (Figure 1). Composes `PUSHTX_OUTPUTS_REQUEST` + `PUSHTX_SIGN` + the fixed OP_SWAP / OP_SPLIT / OP_EQUALVERIFY / OP_HASH160 / OP_CHECKSIG tail. The `pk_b_hash160_hex` argument must decode to exactly 20 bytes. Note: the PELS script assumes the spenders pubkey is already on the stack (from the unlocking script); the symbolic simulator does not model a pre-existing pubkey and will return `error.SimError` under plain `compile()`. Use `compileWithUnlockingScript()` with a dummy pubkey item to simulate PELS end-to-end.
- Arity: 4 (integer, string, string, string)
- Expansion: `[outputsRequest] [sign] OP_CHECKSIGVERIFY OP_SWAP <0x68> OP_SPLIT OP_NIP OP_SWAP <0x8> OP_SPLIT OP_SWAP OP_CAT OP_EQUALVERIFY OP_DUP OP_HASH160 <H(PK_B)> OP_EQUALVERIFY OP_CHECKSIG`

### PELS_LOCKING_SCRIPT_FAST[sighash_flag, item8_hex, items10_11_hex, pk_b_hash160_hex]
Alt-stack variant of `PELS_LOCKING_SCRIPT` (WP1605 §1.4). Composes `PUSHTX_OUTPUTS_REQUEST_FAST` + `PUSHTX_SIGN` + the same PELS tail. Because the alt-stack `outputsRequest` changes stack consumption, simulating this variant via `compileWithUnlockingScript()` requires a deeper unlocking-script stack (8 items) than the non-FAST PELS (5 items).
- Arity: 4 (integer, string, string, string)
- Expansion: `[outputsRequest_FAST] [sign] OP_CHECKSIGVERIFY OP_SWAP <0x68> OP_SPLIT OP_NIP OP_SWAP <0x8> OP_SPLIT OP_SWAP OP_CAT OP_EQUALVERIFY OP_DUP OP_HASH160 <H(PK_B)> OP_EQUALVERIFY OP_CHECKSIG`

### PUSHTX_SIGN_BIT_SHIFT[security, sighash_flag]
PUSHTX [sign] block per zkscript_package (WP1605 §1.4 / sCrypt optimisation). Uses `k = 2^security` instead of `k = 1`, avoiding the expensive `(z + Gx) mod n` computation. The signature is built inline using a precomputed `R = 2^security * G` and a "public key" `P = a * G` such that `a * R_x ≡ -1 mod n`. The unlocking key must grind `tx_in.sequence` until `HASH256(z) % 2^security == 1` and `HASH256(z) >> security >= 2^248`.
- Arity: 2 (integer, integer) — `security ∈ {2, 3}`, `sighash_flag` (e.g. 1 for SIGHASH_ALL)
- Stack: `[.., z, ..]` → `[.., z, .., <DER(R,s) || sighash || P>]` (verified by OP_CHECKSIG)
- Expansion: `push security OP_RSHIFT push <prefix || R || 0x0220> OP_SWAP OP_CAT push <sighash_flag> OP_CAT push P OP_CHECKSIG`
- Size: ~85 bytes (vs ~355 bytes for `PUSHTX_SIGN`)

### PELS_LOCKING_SCRIPT_BIT_SHIFT[security, sighash_flag, item8_hex, items10_11_hex, pk_b_hash160_hex]
PELS locking script using the bit-shift `PUSHTX_SIGN_BIT_SHIFT` instead of `PUSHTX_SIGN`. Same structure as `PELS_LOCKING_SCRIPT` but with the much smaller signature block. The unlocking key must grind `tx_in.sequence` (typically ~4-8 iterations) until the hash satisfies the bit-shift constraints.
- Arity: 5 (integer, integer, string, string, string)
- Expansion: `[outputsRequest] [sign_bit_shift] OP_CHECKSIGVERIFY OP_SWAP <0x68> OP_SPLIT OP_NIP OP_SWAP <0x8> OP_SPLIT OP_SWAP OP_CAT OP_EQUALVERIFY OP_DUP OP_HASH160 <H(PK_B)> OP_EQUALVERIFY OP_CHECKSIG`

## DSL Syntax

```
script      ::= statement (";" statement)* ";"?
statement   ::= opcode | macro "[" args "]" "{" body "}"
              | "@" flag ["(" args ")"] "{" body "}" ["else" "{" body "}"]
              | "@compileError" "(" string ")"
```

## Conditional Flags

Four orthogonal layers, all evaluated against `CompileOptions`:

- **Era**: `@era(satoshi|bip|bch|bsv_pre_genesis|genesis|chronicle)` —
  protocol era, auto-derived from `block_height` when set, else from the
  network's default. `@era(X)` implicitly enables every `@has(...)` feature
  of that era.
- **Features**: `@has(cat)`, `@has(mul)`, `@has(lshiftnum)`, `@has(otda)`,
  `@has(p2sh)`, `@has(cltv)`, `@has(forkid)`, `@has(bigscript)`, ... — the
  era-derived feature set (see `src/options.zig` for the full table). Unknown
  names warn and evaluate false.
- **Limits**: `@limit(push, 32MB)`, `@limit(script, 10MB)`,
  `@limit(opcodes, 1M)`, `@limit(stack, 1000)` — true when the effective
  limit is at least the requested magnitude. Suffixes `K`/`M`/`G`
  (decimal) are optional.
- **Network**: `@network(bsv_mainnet)`, `@network(btc_mainnet)`, ... — any
  of the seven supported networks.
- **Standardness**: `@standardness(cleanstack)`, `@standardness(dersig)`,
  `@standardness(low_s)`, `@standardness(nulldummy)`,
  `@standardness(sigpushonly)`, `@standardness(minimaldata)`,
  `@standardness(minimalif)`, `@standardness(forkid)` — predicates over
  `CompileOptions.standardness` (no structural validation).
- `@compileError("message")` — statement that always fails expansion with
  `ExpandError.CompileError` when its branch is selected; inert in dead
  branches.

Legacy flags, still supported: `@bsv`, `@chronicle`, `@btc_strict`,
`@version[N]`. Note that `@chronicle` now requires the chronicle era (it is
no longer an alias of `@bsv`), and `@version[N]` compares against
`options.protocol_version` instead of a hard-coded threshold.

## Loop Syntax

```
LOOP[n]{ body }
```

The body can reference the loop index with `<i>`:
```
LOOP[5]{ OP_<i> OP_ADD }
```
This expands to: OP_0 OP_ADD OP_1 OP_ADD OP_2 OP_ADD OP_3 OP_ADD OP_4 OP_ADD
