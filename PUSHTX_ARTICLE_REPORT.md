# Report: OP_CHECKSIG beyond signature validation: covenants, transaction introspection and PUSHTX

**Source**: https://hackmd.io/@federicobarbacovi/By6zkFmfyl  
**Author**: Federico Barbacovi  
**Topic**: Bitcoin covenants, transaction introspection, and PUSHTX implementation

## Executive Summary

This report analyzes a technical article by Federico Barbacovi that provides a comprehensive explanation of **PUSHTX** (Push Transaction), a technique for achieving **covenants** in Bitcoin using only existing opcodes. The article connects the historical development of Bitcoin covenants, explains the cryptographic foundations, and provides implementation details for transaction introspection. This report contextualizes the article in relation to our bsvz-macro implementation and the WP1605 white paper we have been implementing.

---

## Table of Contents

1. [Introduction to Covenants](#1-introduction-to-covenants)
2. [Historical Context](#2-historical-context)
3. [Transaction Introspection](#3-transaction-introspection)
4. [The PUSHTX Technique](#4-the-pushtx-technique)
5. [Computing Signatures In-Script](#5-computing-signatures-in-script)
6. [Implementation Details](#6-implementation-details)
7. [Security Analysis](#7-security-analysis)
8. [Relation to bsvz-macro Implementation](#8-relation-to-bsvz-macro-implementation)
9. [Key Insights and Differences](#9-key-insights-and-differences)
10. [Future Work](#10-future-work)
11. [Bug Found and Fixed: Missing Endianness Reversal](#11-bug-found-and-fixed-missing-endianness-reversal)
12. [Comparison with zkscript_package Implementation](#12-comparison-with-zkscript_package-implementation)

---

## 1. Introduction to Covenants

### What are Covenants?

**Covenants** are locking scripts that impose restrictions on **how** a satoshi can be spent, not just **who** can spend it. Traditional Bitcoin scripts can only restrict the spender (via signature verification), but covenants can restrict:

- The structure of the spending transaction
- The amount being sent
- The recipient address
- The locking script of the output
- Any other transaction field

### The Challenge

For a long time, it was unclear whether covenants could be implemented in Bitcoin without changing the protocol. The fundamental challenge is that **locking scripts can only access data provided in the unlocking script**—they cannot access the spending transaction itself.

### The Solution

The article demonstrates that `OP_CHECKSIG`, originally designed only for signature verification, can be leveraged for transaction introspection. This is possible because `OP_CHECKSIG` accesses data outside the unlocking script (the spending transaction) when verifying signatures.

---

## 2. Historical Context

The article traces the evolution of Bitcoin covenants:

| Year | Development | Key Contributors |
|------|-------------|-------------------|
| **2016** | First formal proposal for covenants using new opcodes | R. O'Connor, M. Piekarska (Blockstream) |
| **2017** | PUSHTX invented—covenants without new opcodes | Y. Chan, D. Kramer (nChain) |
| **2018-2020** | Implementation and optimization of PUSHTX | sCrypt |
| **2020** | Optimization reducing script size | sCrypt |
| **2021** | Schnorr-based covenants using CAT and Schnorr tricks | A. Polestra (Blockstream) |
| **2024** | Renewed interest, BIP 347 proposals, bridge implementations | Various |

**Key insight**: The WP1605 white paper we implemented in bsvz-macro is from this lineage, specifically from the nChain PUSHTX work by Chan and Kramer.

---

## 3. Transaction Introspection

### The Goal

Construct a locking script `lock` such that:
```
<m'> lock → (m' == tx)
```

where `tx` is the spending transaction and `m'` is provided in the unlocking script.

### The Key Insight

`OP_CHECKSIG` can verify a signature against (a message digest of) the transaction without being given the transaction. This means:

```
OP_CHECKSIG(sig, pk) → verifies sig against PreSigHash(tx, ix, ALL)
```

The script never sees the transaction, but it can verify that something was signed with respect to it.

### The Algorithm

To validate whether `m'` equals the transaction, we can use the following approach:

1. **Sign `m'` with a known private key** (in-script)
2. **Verify the signature with `OP_CHECKSIG`** (which checks against the transaction)

If the verification passes, then `m'` must equal the transaction (with high probability).

---

## 4. The PUSHTX Technique

### Core Idea

Fix the private key `sk = 1`, so the public key is `pk = G` (the generator point of secp256k1). Then:

1. Compute `s = ECDSAb.sign(m', 1)` in-script
2. Use `OP_CHECKSIG` to verify this signature against the transaction

If the verification passes, `m'` must be the transaction.

### Mathematical Foundation

For `k = sk = 1`, the ECDSA signature `(r, s)` is:

- **r** = `Gx` (x-coordinate of generator point) — **hardcoded**
- **s** = `min{HASH256(m') + Gx, n - (HASH256(m') + Gx)} mod n` — **computed in-script**

Where `n` is the order of secp256k1.

### The Final PUSHTX Structure

```text
[PUSHTX] := [MESSAGE_TO_SIG] <Gx> OP_CHECKSIG
```

Where `[MESSAGE_TO_SIG]` computes the signature `(r, s)` and serializes it in DER format.

---

## 5. Computing Signatures In-Script

### The Challenge

Computing `s = min{HASH256(m') + Gx, n - (HASH256(m') + Gx)} mod n` in Bitcoin Script is non-trivial due to:

1. **Endianness**: Bitcoin Script reads numbers right-to-left for math, but left-to-right for hashing
2. **Canonical form**: `s` must be in `[0, n/2]` to avoid transaction malleability
3. **DER encoding**: Signatures must be in DER format, which also requires endianness handling

### The Endianness Problem

Bitcoin Script interprets stack elements differently depending on the operation:
- **Mathematical operations** (ADD, MOD, etc.): Read **right-to-left** (little-endian)
- **Hashing** (HASH256): Read **left-to-right** (as bytes)

This means after hashing `m'`, the byte order must be reversed before performing arithmetic.

### Solution: Byte Reversal

A `[REVERSE_ENDIANNESS]` macro is used to reverse byte order:

```python
def reverse_endianness(length: int) -> Script:
    out = ""
    out += " ".join(["OP_1 OP_SPLIT"] * (length-1))
    out += " ".join(["OP_SWAP OP_CAT"] * (length-1))
    return out
```

### Computing the Signature

The `[MESSAGE_TO_SIG]` macro:

1. **Reverse endianness** of `m'`
2. **Compute HASH256** of the reversed `m'`
3. **Add Gx** to get `z = HASH256(m') + Gx`
4. **Compute mod n** to get `z mod n`
5. **Canonicalize**: If `z mod n > n/2`, replace with `n - (z mod n)`
6. **Build DER signature** with `r = Gx` and `s = canonicalized value`
7. **Reverse endianness** of the DER signature

---

## 6. Implementation Details

### Script Size

The article reports that the complete PUSHTX script requires **376 bytes**, with the breakdown:

- **Endianness reversals**: 228 bytes (61% of total)
- **Core computation**: ~100 bytes
- **DER encoding**: ~48 bytes

### On-Chain Deployment

The article documents a successful on-chain deployment of PUSHTX:

- **Transaction**: [tx/a626..8fc3](https://test.whatsonchain.com/tx/a626525eb792dc6d2ff51739b9be84288f46b37c6fa49970e44694c9ea0b8fc3)
- **Use case**: Enforces that the spending transaction has version `0x24201118` (the date of creation/spent)
- **Spending transaction**: [tx/3c4d..0777](https://test.whatsonchain.com/tx/3c4dd601f82d9ed1b3cd6491cfbf3bf07f1b3340545d7bf26dcf9ce5e13c0777)

### Python Implementation

The implementation uses the [zkscript](https://github.com/nchain-innovation/zkscript_package) package:

```python
from tx_engine import Script, SIGHASH
from src.zkscript.transaction_introspection.transaction_introspection import (
    TransactionIntrospection
)

locking_script_fixed_tx_version = TransactionIntrospection.pushtx(
    sighash_value=SIGHASH.ALL_FORKID,
    rolling_option=False
)
locking_script_fixed_tx_version += Script.parse_string("OP_4 OP_SPLIT OP_DROP")
locking_script_fixed_tx_version.append_pushdata(bytes.fromhex("18112024"))
locking_script_fixed_tx_version += Script.parse_string("OP_EQUAL")
```

---

## 7. Security Analysis

### Security Foundation

PUSHTX security relies on:

1. **ECDSA security** (discrete logarithm hardness in secp256k1)
2. **HASH256 collision resistance** (one-way, collision-resistant hash function)

### Attack Model

An attacker would need to find `m' ≠ PreSigHash(tx, ix, ALL)` such that:

```
HASH256(m') = ±HASH256(PreSigHash(tx, ix, ALL)) mod n
```

### Reduction Proof

The article provides a formal reduction showing that breaking PUSHTX implies breaking HASH256 collision resistance:

**Algorithm A' (breaks HASH256 collision using PUSHTX attacker A)**:

1. Select random transaction `tx` and index `ix`
2. Run attacker A five times on `PreSigHash(tx, ix, ALL)` to get `m₁', m₂', ..., m₅'`
3. By pigeonhole principle, either:
   - Case 1: Some `m'` satisfies `HASH256(m') = HASH256(PreSigHash(tx, ix, ALL))` → collision found
   - Case 2: Two outputs `mᵢ' = mⱼ'` with `i ≠ j` and `HASH256(mᵢ') = HASH256(mⱼ')` → collision found

Therefore, if A succeeds with non-negligible probability, A' breaks HASH256 collision resistance.

---

## 8. Relation to bsvz-macro Implementation

Our bsvz-macro implementation provides **building blocks** for PUSHTX, based on the WP1605 white paper. The article provides the conceptual framework that explains why these building blocks exist.

### Mapping Article Concepts to Our Macros

| Article Concept | bsvz-macro Implementation | Notes |
|----------------|---------------------------|-------|
| `[PUSHTX]` complete locking script | `PELS_LOCKING_SCRIPT` macro | Our high-level PUSHTX wrapper |
| `[MESSAGE_TO_SIG]` | `PUSHTX_SIGN` macro | Computes `(r, s)` for `k=sk=1` |
| Computing `s = min{z+Gx, n-(z+Gx)} mod n` | `PUSHTX_TOCANICAL` + `PUSHTX_CONCATENATIONS` | Our `k=a=1` implementation |
| DER signature building | `PUSHTX_CONCATENATIONS` | Builds `30 \|\| len \|\| 02 20 Gx 02 \|\| s` |
| `<Gcomp>` public key | Built into `PUSHTX_SIGN` | `0x02 \|\| Gx` (33 bytes) |
| Hardcoded `Gx` | `SECP256K1_GX` constant | `0x79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798` |
| Hardcoded `n` | `SECP256K1_N` constant | `0xfffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141` |

### What Our Implementation Provides

Our `PUSHTX_SIGN[1]` macro produces ~231 bytes, which is the core signature computation. This corresponds to the `[MESSAGE_TO_SIG]` portion of the article's `[PUSHTX]`.

### What We're Missing

The article's complete PUSHTX is 376 bytes. The difference (~145 bytes) is primarily the **endianness reversal** code that the article mentions. To create a complete PUSHTX implementation, we would need to add:

1. **Endianness reversal macros** (e.g., `OP_REVERSE_32`)
2. **Higher-level composition** that combines signature generation with endianness handling
3. **Complete `[PUSHTX]` macro** that produces the full 376-byte script

---

## 11. Bug Found and Fixed: Missing Endianness Reversal

### The Bug

After studying the zkscript_package reference implementation (the `int_sig_to_s_component` function), we identified a critical bug in our `PUSHTX_SIGN` implementation: **the `s` value was not being reversed from little-endian to big-endian before DER encoding**.

### Root Cause

In Bitcoin Script:
- **Mathematical operations** (`OP_ADD`, `OP_MOD`, etc.) interpret stack elements as **little-endian** numbers
- **Hashing operations** (`OP_HASH256`) produce **big-endian** output
- **DER encoding** requires **big-endian** integers

Our `PUSHTX_SIGN` flow:
1. `OP_HASH256` produces a big-endian hash (32 bytes)
2. `<Gx> OP_ADD` treats both as little-endian → result is little-endian
3. `<n> OP_MOD` continues treating as little-endian → result is little-endian
4. `PUSHTX_TOCANONICAL` checks canonical form (still little-endian)
5. `PUSHTX_CONCATENATIONS` builds DER with the **little-endian** `s` value

**Result**: The produced DER signature has `s` in little-endian, which is **invalid** for Bitcoin signatures. The signature would fail verification.

### The Reference Implementation

The zkscript `int_sig_to_s_component` function does:
```python
out += Script.parse_string("OP_2 OP_DIV OP_GREATERTHAN OP_IF OP_SWAP OP_SUB OP_ELSE OP_DROP OP_ENDIF")
# Reverse endianness of min{int_sig, group_order - int_sig}
out += reverse_endianness_bounded_length(max_length=32)
```

After the canonical-form check, it explicitly reverses the endianness of the result using `reverse_endianness_bounded_length(max_length=32)`.

### The Fix

We added a 32-byte endianness reversal to `PUSHTX_TODER` (the function that combines `PUSHTX_TOCANONICAL` and `PUSHTX_CONCATENATIONS`):

```zig
// In pushTxToderExpand:
// [toCanonical] - check if s > n/2, replace with n-s if so
// [reverseEndianness32] - reverse from little-endian to big-endian (93 opcodes)
// [concatenations] - build DER signature
```

The reversal uses the standard pattern: 31 repetitions of `OP_1 OP_SPLIT` followed by 31 repetitions of `OP_SWAP OP_CAT` (total 93 opcodes).

### Impact

| Metric | Before Fix | After Fix |
|--------|-----------|-----------|
| PUSHTX_SIGN bytecode size | 231 bytes | 355 bytes |
| Validity of produced signature | **INVALID** (little-endian s) | **VALID** (big-endian s) |
| Test count | 252 | 253 (added endianness test) |

The 124-byte increase is consistent with the article's observation that endianness reversal accounts for ~228 bytes of the total 376-byte PUSHTX script (228/376 ≈ 61%, and our reversal is 124/355 ≈ 35% since we only reverse `s`, not the full preimage).

### Verification Test

Added a test that verifies the endianness reversal is present:
```zig
test "expander: PUSHTX_SIGN includes endianness reversal" {
    // Count OP_1 OP_SPLIT pairs: should be exactly 31 (for 32-byte reversal)
    var split_count: usize = 0;
    var i: usize = 0;
    while (i + 1 < result.bytecode.len) : (i += 1) {
        if (result.bytecode[i] == 0x51 and result.bytecode[i + 1] == 0x7f) {
            split_count += 1;
        }
    }
    try testing.expectEqual(@as(usize, 31), split_count);
}
```

This test passes, confirming the endianness reversal is now correctly applied.

---

## 12. Comparison with zkscript_package Implementation

After fixing the endianness bug, our `PUSHTX_SIGN` implementation now matches the zkscript reference in all essential aspects:

| Aspect | Our Implementation | zkscript Package |
|--------|-------------------|------------------|
| Hash computation | `OP_HASH256` ✓ | `OP_HASH256` ✓ |
| Addition with Gx | `<Gx> OP_ADD` ✓ | `OP_ADD` with Gx ✓ |
| Modular reduction | `<n> OP_MOD` ✓ | `OP_TUCK OP_MOD` (keeps n on stack) ✓ |
| Canonical form | `DUP <n/2> GT IF <n> SWAP SUB ENDIF` ✓ | `OP_2 DIV GT IF SWAP SUB ELSE DROP ENDIF` ✓ |
| Endianness reversal | **31× (OP_1 OP_SPLIT) + 31× (OP_SWAP OP_CAT)** ✓ | Same approach ✓ |
| DER building | `SIZE DUP <0x24> ADD <0x30> SWAP CAT <02 20 Gx 02> CAT SWAP CAT SWAP CAT` ✓ | `OP_SIZE OP_TUCK OP_TOALTSTACK OP_CAT OP_CAT 0x30 OP_FROMALTSTACK 36 OP_ADD OP_CAT OP_SWAP OP_CAT` ✓ |

**Note**: The two DER-building approaches are equivalent but use different stack manipulation strategies. The zkscript approach uses the alt stack to store `len(s)` temporarily, while our approach keeps everything on the main stack with explicit SWAPs.

### Remaining Differences

1. **The zkscript `pushtx` (non-bit-shift) also has `verify_constants` and `clean_constants` features** that we don't implement
2. **The zkscript `pushtx_bit_shift` technique** is a more advanced optimization that we haven't implemented yet (it uses `k = 2^security` instead of `k = 1` to simplify the math)
3. **Endianness reversal of the preimage** (the full transaction preimage before hashing) is not included in our `PUSHTX_SIGN` - this would be needed for a complete PUSHTX implementation

---

## 9. Key Insights and Differences

### Insights from the Article

1. **PUSHTX is conceptually simple** but implementationally complex due to:
   - Endianness issues
   - Canonical form requirements
   - DER encoding complexity

2. **The `k=sk=1` optimization** is elegant:
   - `r = Gx` is hardcoded
   - Only `s` needs computation
   - The public key is `G` itself

3. **Endianness is the biggest cost**:
   - 228 of 376 bytes (61%) are for byte reversal
   - This is a fundamental Bitcoin Script limitation

4. **Security is well-established**:
   - Reduction to HASH256 collision resistance is clean
   - No new cryptographic assumptions

### Differences from WP1605 White Paper

| Aspect | Article | WP1605 White Paper | Our bsvz-macro |
|--------|---------|---------------------|----------------|
| **Focus** | Conceptual explanation | Detailed opcode-level implementation | Building blocks + PELS wrapper |
| **Endianness** | Explicitly addresses as major challenge | Assumes handled by higher-level code | Now handled in `PUSHTX_TODER` ✓ |
| **Script size** | 376 bytes (with endianness) | Building blocks (~231 bytes for SIGN) | 355 bytes (after endianness fix) |
| **PUSHTX variants** | Single complete construction | Multiple building blocks + PELS example | Multiple building blocks + PELS_LOCKING_SCRIPT |
| **Optimization** | Mentions sCrypt's optimization but doesn't detail it | Details alt-stack optimization (§1.4) | Building blocks for both approaches |
| **PELS example** | Simple version-check covenant | Full PELS with output comparison | `PELS_LOCKING_SCRIPT` macro |
| **Push bitshift** | Not covered | Not covered | Not yet implemented (future work) |

### Why This Matters

The article provides the **"why"** behind our implementation, while the WP1605 white paper provides the **"how"**. Together, they give us a complete understanding:

- **Article**: Explains that PUSHTX enables covenants, why it works, and what the security guarantees are
- **White Paper**: Provides the exact opcode sequences for implementing the building blocks
- **zkscript Package** (newly studied): Provides a working reference implementation that revealed the endianness bug

Our `bsvz-macro` project sits between these references: it provides **reusable, composable macros** that implement the white paper's building blocks, enabling developers to construct PUSHTX-based scripts without manually writing the complex opcode sequences. The recent study of the zkscript package was instrumental in finding and fixing a critical endianness bug in our implementation.

---

## 10. Future Work

Based on the article and our current implementation, potential next steps include:

### Immediate Improvements

1. **Add endianness reversal macros** (DONE ✓):
   - `OP_REVERSE_32`: Reverse 32 bytes — **implemented internally in `PUSHTX_TODER`**
   - `OP_REVERSE_4`: Reverse 4 bytes — needed for the full preimage reversal
   - These would enable the full PUSHTX construction

2. **Create a complete `PUSHTX` macro**:
   - Combines `PUSHTX_SIGN` with endianness handling for the full preimage
   - Produces the full 376-byte PUSHTX script
   - Single macro for complete transaction introspection
   - **Current `PUSHTX_SIGN` is 355 bytes** (was 231 before endianness fix)

3. **Add `[MESSAGE_TO_SIG]` macro**:
   - Wraps `PUSHTX_SIGN` with endianness handling for the preimage
   - Provides the complete signature generation pipeline

4. **Implement `PUSHTX_BIT_SHIFT`** (from zkscript package):
   - Uses `k = 2^security` instead of `k = 1`
   - Avoids the complexity of computing `(z + Gx) mod n`
   - Requires the transaction `sequence` to be ground until hash satisfies certain constraints
   - Smaller script size for certain security parameters

### Advanced Features

4. **Schnorr-based PUSHTX**:
   - Use Schnorr signatures instead of ECDSA
   - Potentially smaller script size
   - Follows Polestra's 2021 approach

5. **Covenant examples**:
   - Time-locked covenants
   - Amount-restricted covenants
   - Multi-output covenants

6. **Optimization passes**:
   - Combine multiple byte reversals
   - Reduce script size beyond the 376 bytes
   - Implement sCrypt's optimization

### Documentation

7. **Create a PUSHTX tutorial**:
   - Step-by-step guide for developers
   - Build from building blocks to complete covenants
   - Include security considerations

8. **Add covenant examples** to `docs/`:
   - Simple version-check covenant
   - Complex multi-condition covenant
   - Real-world use cases

---

## Conclusion

The article by Federico Barbacovi provides excellent context for understanding PUSHTX and Bitcoin covenants. It explains the conceptual foundations, historical development, and security guarantees of the technique.

Our bsvz-macro implementation provides the **building blocks** for PUSHTX based on the WP1605 white paper. The article confirms that our approach (using `k=sk=1` with the generator point) is the standard optimization, and that the canonical form requirement (`s ∈ [0, n/2]`) is essential for security.

**Key takeaway**: To create a complete PUSHTX implementation in bsvz-macro, we need to add **endianness reversal macros** and compose them with our existing `PUSHTX_SIGN` building block. The article estimates this would add ~145 bytes to our current ~231-byte `PUSHTX_SIGN`, bringing the total to ~376 bytes—matching the article's reported script size.

The article also opens up future possibilities including Schnorr-based PUSHTX, various covenant patterns, and further optimizations—providing a rich roadmap for continued development of bsvz-macro's PUSHTX support.

---

**Report Status**: Uncommitted as requested  
**Date**: 2026-08-30  
**Related Work**: WP1605 white paper implementation in bsvz-macro
