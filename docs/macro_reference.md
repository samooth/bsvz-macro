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

## DSL Syntax

```
script      ::= statement (";" statement)* ";"?
statement   ::= opcode | macro "[" args "]" "{" body "}"
              | "@" flag "{" body "}" ["else" "{" body "}"]
```

## Feature Flags

- @bsv -- BSV mainnet/testnet features (enables OP_CAT, OP_MUL, etc.)
- @chronicle -- Chronicle upgrade features (32MB numbers, restored opcodes)
- @btc_strict -- Bitcoin Core compatibility mode (disables re-enabled opcodes)
- @version(N) -- Minimum protocol version check

## Loop Syntax

```
LOOP[n]{ body }
```

The body can reference the loop index with `<i>`:
```
LOOP[5]{ OP_<i> OP_ADD }
```
This expands to: OP_0 OP_ADD OP_1 OP_ADD OP_2 OP_ADD OP_3 OP_ADD OP_4 OP_ADD
