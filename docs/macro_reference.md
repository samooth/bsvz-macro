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

## BOLT (b017) Contract Macros

Ported from the [b017](https://github.com/BOLT-Association/b017) Bitcoin
Original Layer-1 Token templates. A b017 token is a 1-satoshi UTXO whose
locking script is N leading data pushes (the token state) followed by a
static covenant suffix. The four embedded suffixes are byte-faithful to the
b017 `0.0.0-b2+` templates — each is golden-tested against the sha256
fingerprints published in the b017 `REGISTRY`:

| Suffix | Bytes | sha256 (b017 REGISTRY golden) |
|---|---|---|
| `SimpleMultiBOLT` lock | 5103 | `368c45fdf92164e4e0869c9062be84621ea8ef040e8591399bf6ff3b8c819b11` |
| `SimpleMultiBOLT` unlock | 414 | `1b826327a9c9f8b7098047d3f3b6c996a01ad3474796f2d1d33faf0c0fed290d` |
| `MinSimpleBOLT` lock | 1113 | `2892679d85ef021d754036094ecd77e14f0c3934a23a48e09e7da337e50f823d` |
| `MinSimpleBOLT` unlock (shared with SMB) | 414 | `1b826327a9c9f8b7098047d3f3b6c996a01ad3474796f2d1d33faf0c0fed290d` |

### BOLT_SMB_LOCK_SUFFIX
Emit the static `SimpleMultiBOLT` fungible-token covenant suffix (5103 bytes).
- Arity: 0
- Stack: n/a (emits the lock suffix; prepend the 11 data-push args yourself, or use `BOLT_SMB_LOCK`)

### BOLT_SMB_UNLOCK_SUFFIX
Emit the static `SimpleMultiBOLT` unlock suffix (414 bytes).
- Arity: 0
- Stack: n/a (the ~198 unlock data args — ancestor pieces, interop args, sig preimage parts — are runtime-supplied by the spender and must be pushed before this suffix)

### BOLT_MS_LOCK_SUFFIX
Emit the static `MinSimpleBOLT` identity-NFT covenant suffix (1113 bytes).
- Arity: 0
- Stack: n/a

### BOLT_SMB_LOCK[balance, balanceCommit, pubKeyHash, pubKeyHashCommit, pubKeyHashCommit2, otherGrandparentOutpoint, txoType, outputIndexN, parentOutpoint, grandparentOutpoint, issuerPubKey]
Assemble a complete `SimpleMultiBOLT` locking script: 11 hex data pushes
(field sizes 16/16/20/20/20/36/1/1/36/36/33 bytes) followed by the golden
covenant suffix — the byte layout `SimpleMultiTemplate.lock()` produces in
b017.
- Arity: 11 (string, all hex; args must be exact-length fields)
- Example (genesis): `BOLT_SMB_LOCK[0x<16B balance>, 0x<16B>, 0x<20B>, 0x<20B>, 0x<20B>, 0x<36B>, 0x20, 0x00, 0x<36B>, 0x<36B>, 0x02<32B issuer>]`

### BOLT_MS_LOCK[pubKeyHash, issuerPubKey, pubKeyHashCommitment, txoType, parentOutpoint, grandparentOutpoint]
Assemble a complete `MinSimpleBOLT` locking script: 6 hex data pushes
(20/33/20/1/36/36 bytes) followed by the golden covenant suffix.
- Arity: 6 (string, all hex)

### BOLT_P2P_LOCK[pkh]
The b017 `pay2Proof` marker-proof UTXO: `<02b017> OP_EQUALVERIFY OP_DUP OP_HASH160 <pkh> OP_EQUALVERIFY OP_CHECKSIG`. The unlock carries its own `02b017` marker push, so the lock's marker EQUALVERIFY proves the marker was supplied.
- Arity: 1 (string, 20-byte hex pkh)
- Expansion: `0x02b017 OP_EQUALVERIFY OP_DUP OP_HASH160 <pkh> OP_EQUALVERIFY OP_CHECKSIG`

### BOLT_P2P_UNLOCK[sig, pubkey]
The `pay2Proof` unlocking script: signature, compressed pubkey, then the b017 marker push.
- Arity: 2 (string: DER sig hex, 33-byte compressed pubkey hex)
- Expansion: `<sig> <pubkey> 0x02b017`

Note: the covenant suffixes use deliberately non-minimal pushes (bare
`OP_BIN2NUM`-guarded data pushes, sX style) — they are consensus-valid but
not `minimaldata`-clean; compile with `enforce_standardness = false` if
policy validation rejects them.

## Template Macros

High-level protocol macros that emit standard BSV inscription and data-push
bytecode. These encode application-layer protocols (ordinals, tokens, name
services, large-file concatenation) inside data pushes and are **not** part of
the canonical stack-machine layer.

### INSCRIPTION[content, content_type]
Standard 1Sat ordinal inscription envelope.
- Arity: 2 (string, string)
- Expansion: `OP_0 OP_IF "ord" OP_1 <content_type> OP_0 <content> OP_ENDIF`

### INSCRIPTION_FULL[prefix_hex, content_type, suffix_hex, marker_hex]
Custom inscription with explicit prefix/suffix/marker bytes.
- Arity: 4 (string, string, string, string) — all even-length hex
- Expansion: `<prefix> OP_0 OP_IF "ord" OP_1 <content_type> OP_0 OP_RETURN <suffix> <marker>`

### LOCK[pkh_hex, block_height]
CLTV time-locked pay-to-pubkey-hash lock.
- Arity: 2 (string 20-byte hex, integer)
- Expansion: `<block_height> OP_CHECKLOCKTIMEVERIFY OP_DROP OP_DUP OP_HASH160 <20B-pkh> OP_EQUALVERIFY OP_CHECKSIG`

### BSV21_DEPLOY[symbol, decimals, max_supply]
Deploy a BSV-21 token with deploy+mint inscription.
- Arity: 3 (string ≤32 chars, integer 0-18, integer >0)
- Expansion: `OP_0 OP_IF "ord" OP_1 {"p":"bsv-20","op":"deploy+mint","sym":"<symbol>","amt":"<max_supply>","dec":"<decimals>"} OP_ENDIF`

### BSV21_TRANSFER[token_id, amount]
Transfer a BSV-21 token balance.
- Arity: 2 (string, integer >0)
- Expansion: `OP_0 OP_IF "ord" OP_1 {"p":"bsv-20","op":"transfer","id":"<token_id>","amt":"<amount>"} OP_ENDIF`

### BSV21_BURN[token_id, amount]
Burn a BSV-21 token balance.
- Arity: 2 (string, integer >0)
- Expansion: `OP_0 OP_IF "ord" OP_1 {"p":"bsv-20","op":"burn","id":"<token_id>","amt":"<amount>"} OP_ENDIF`

### BSV20_DEPLOY[tick, max_supply, decimals, mint_limit]
Deploy a BSV-20 token (deprecated; use BSV-21 for new tokens).
- Arity: 4 (string, integer >0, integer 0-18, integer ≥0)
- Expansion: `OP_0 OP_IF "ord" OP_1 {"p":"bsv-20","op":"deploy","tick":"<tick>","max":"<max_supply>","lim":"<mint_limit>","dec":"<decimals>"} OP_ENDIF`

### BSV20_MINT[tick, amount]
Mint BSV-20 tokens (deprecated).
- Arity: 2 (string, integer >0)

### BSV20_TRANSFER[tick, amount]
Transfer BSV-20 tokens (deprecated).
- Arity: 2 (string, integer >0)

### MAP_SET[key, value]
Write a key-value pair to the MAP protocol (OP_RETURN).
- Arity: 2 (string, string)
- Expansion: `OP_RETURN <MAP_PREFIX> "SET" <key> <value>`

### MAP_DEL[key]
Delete a key from the MAP protocol (OP_RETURN).
- Arity: 1 (string)
- Expansion: `OP_RETURN <MAP_PREFIX> "DEL" <key>`

### ORDLOCK[seller_pkh_hex, pay_pkh_hex, price_sats]
Ordinal Lock covenant (timelocked refund + atomic swap payload).
- Arity: 3 (string 20-byte hex, string 20-byte hex, integer)
- Expansion: `<ORDLOCK_PREFIX> <seller_pkh> <payout_script> <ORDLOCK_SUFFIX>`

### B_ENCODE[content_hex, content_type, encoding, filename]
B:// protocol data embedding (OP_RETURN).
- Arity: 4 (string, string, string, string)
- Expansion: `OP_RETURN <B_PREFIX> <content> <content_type> <encoding> <filename>`

### OPNS_LOCK[claimed_hex, domain, pow_hex]
OpNS name-claim covenant (mine-tree contract with embedded bytecode).
- Arity: 3 (string, string, string) — claimed and pow are even-length hex
- Expansion: `<OPNS_CONTRACT> OP_RETURN OP_0 <genesis_outpoint> <claimed> <domain> <pow> <state_len>`

### OPNS_INSCRIBE[name, owner_script_hex]
OpNS 1Sat ordinal name inscription.
- Arity: 2 (string, string)
- Expansion: `<owner_script> OP_0 OP_IF "ord" OP_1 "application/op-ns" OP_0 <name> OP_ENDIF OP_RETURN "1opNS..." <genesis_outpoint>`

### BCAT_HEADER[info, mime, charset, filename, flag, txids_hex]
Bcat header transaction (concatenation index).
- Arity: 6 (string ≤128, string ≤128, string ≤16, string ≤256, string ≤16, string) — txids_hex is 64×N chars
- Expansion: `OP_RETURN <BCAT_NAMESPACE> <info> <mime> <charset> <filename> <flag> <TX1> <TX2> ...`

### BCAT_PART[data_hex]
Bcat part transaction (raw file chunk).
- Arity: 1 (string, even-length hex)
- Expansion: `OP_RETURN <BCAT_PART_NAMESPACE> <raw_data>`

### SIGIL_NFT[project_hash_hex, p2pkh_hash_hex, metadata_json]
Sigil NFT locking script with project hash, pay-to-pubkey-hash, and metadata.
- Arity: 3 (string 20-byte hex, string 20-byte hex, string JSON)
- Expansion: `OP_HASH160 <project_hash> OP_EQUALVERIFY OP_DUP OP_HASH160 <p2pkh_hash> OP_EQUALVERIFY OP_CHECKSIG OP_RETURN <metadata_json>`

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
  protocol era, auto-derived from `block_height` when set (network-aware:
  BTC caps at `bip`, BCH at `bch`; the bsv_pre_genesis/genesis/chronicle
  boundaries are BSV history), else from the network's default. `@era(X)`
  implicitly enables every `@has(...)` feature of that era.
- **Features**: `@has(cat)`, `@has(mul)`, `@has(lshiftnum)`, `@has(otda)`,
  `@has(substr)`, `@has(left)`, `@has(right)`, `@has(2mul)`, `@has(2div)`,
  `@has(ver)`, `@has(verif)`, `@has(p2sh)`, `@has(cltv)`, `@has(forkid)`,
  `@has(bigscript)`, ... — the era-derived feature set (see `src/options.zig`
  for the full table). The Chronicle string opcodes (`substr`/`left`/`right`),
  `2mul`/`2div`, `ver`/`verif` are chronicle-era only. Unknown names warn and
  evaluate false.
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
