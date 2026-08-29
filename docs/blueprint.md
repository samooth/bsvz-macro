# Blueprint: bsvz-macro
## Sistema de Macro Expansion Wallet-Side para Bitcoin Script (BSV)

> **Version:** 1.0-draft  
> **Fecha:** 2026-08-28  
> **Autor:** Blueprint generado para el ecosistema `bsvz` / `zig-wallet-toolbox`  
> **Filosofia:** *"You write the loop once, but emit it many times"* -- determinismo total, zero-cost abstraction, consenso inmutable.

---

## 1. Vision y Principios de Diseno

### 1.1 Proposito

`bsvz-macro` es un compilador wallet-side de macro expansion para Bitcoin Script (BSV). Transforma un lenguaje simbolico de alto nivel (macros parametrizados) en secuencias de opcodes legacy compatibles con el protocolo Bitcoin original (2009). El nodo nunca ve un macro; solo ve bytecode plano, aciclico y determinista.

### 1.2 Principios arquitectonicos

| Principio | Descripcion | Implicacion en Zig |
|---|---|---|
| **Totality** | Toda expansion es finita, acotada y termina. | `comptime` evaluacion forzada; loops desenrollados estaticamente. |
| **Higiene** | Cada macro opera en scope aislado. Sin fugas, sin shadowing. | Cada invocacion es una funcion `comptime` independiente. |
| **Zero-cost** | Los macros no anaden overhead en runtime. | Expansion en `comptime` o single-pass con allocators de stack. |
| **Compatibilidad** | El output es indistinguible de Script escrito a mano. | Emite solo opcodes del set legacy; validado contra `bsvz` ScriptEngine. |
| **Auditabilidad** | Source macro + parametros -> bytecode reproducible bit-a-bit. | Builds deterministas; hash del source y del output publicables. |
| **Seguridad** | Fail-fast. Mejor no emitir que emitir invalido. | Validacion estructural antes de emision; nunca bytecode parcial. |

### 1.3 Relacion con el ecosistema

```
+-------------------------------------------------------------+
|  Autor de contrato (DSL macro)                              |
|  OP_XSWAP 3; LOOP[5]{ OP_<i> OP_DUP OP_MUL }; OP_HASHCAT  |
+----------------------+--------------------------------------+
                       |
                       v
+-------------------------------------------------------------+
|  bsvz-macro (wallet-side compiler)                          |
|  +---------+ +---------+ +----------+ +----------+          |
|  |  Lexer  | |  Parser | | Expander | | Validator |          |
|  +---------+ +---------+ +----------+ +----------+          |
+----------------------+--------------------------------------+
                       |
                       v
+-------------------------------------------------------------+
|  bsvz (script interpreter + crypto)                         |
|  +--------------+ +--------------+ +--------------+          |
|  | ScriptEngine | |   Hashing    | |  Serializer  |          |
|  +--------------+ +--------------+ +--------------+          |
+----------------------+--------------------------------------+
                       |
                       v
+-------------------------------------------------------------+
|  zig-wallet-toolbox (signing + tx building)                 |
|  +--------------+ +--------------+ +--------------+          |
|  |  KeyManager  | |  TxBuilder   | |   Signer     |          |
|  +--------------+ +--------------+ +--------------+          |
+----------------------+--------------------------------------+
                       |
                       v
+-------------------------------------------------------------+
|  Red BSV (nodo)                                             |
|  Script plano, aciclico, legacy-only. Sin macros.           |
+-------------------------------------------------------------+
```

---

## 2. Arquitectura de Modulos

### 2.1 Estructura de directorios

```
bsvz-macro/
  build.zig
  build.zig.zon          # Dependencia: bsvz, zig-wallet-toolbox
  src/
    lib.zig              # API publica (root)
    prelude.zig          # Macros predefinidos (M canonica)
    lexer/
      token.zig          # Definicion de tokens
      scanner.zig        # Analisis lexico (single-pass)
      error.zig          # LexError: UnrecognizedToken, InvalidLiteral
    parser/
      ast.zig            # Nodos: OpcodeLiteral, MacroInvocation, Block, Loop
      parser.zig         # Recursive descent / Pratt
      error.zig          # ParseError: UnexpectedToken, ArityMismatch
    expander/
      table.zig          # M: MacroTable (comptime + runtime)
      expander.zig       # Single-pass expander
      comptime_exp.zig   # Expansion comptime de Zig (meta-macros)
      error.zig          # ExpandError: UnboundMacro, Overflow
    simulator/
      stack.zig          # Modelo simbolico del stack (S, A)
      engine.zig         # Ejecutor simbolico de opcodes
      algebra.zig        # Precondicion P -> Postcondicion Q
      error.zig          # SimError: StackUnderflow, TypeMismatch
    encoder/
      push.zig           # Minimal push encoding (OP_0..OP_16, PUSHDATA1..4)
      asm.zig            # Emision a ASM (human-readable)
      hex.zig            # Emision a hex (wire-format)
    validator/
      bounds.zig         # Limites: 10k bytes, 1k stack, 520B push
      policy.zig         # Reglas de policy (standardness)
      error.zig          # ValError: ScriptTooLarge, StackTooDeep
  tests/
    macro_e2e.zig        # Tests end-to-end: source -> bytecode
    canonical.zig        # Tests de la familia canonica (XSWAP, XDROP, etc.)
    stack_sim.zig        # Tests del ejecutor simbolico
    fixtures/
      xswap_cases.zig
      loop_cases.zig
      covenant_cases.zig
  docs/
    blueprint.md         # Este documento
    macro_reference.md   # Documentacion de cada macro predefinido
    dsl_grammar.md       # Gramatica formal del DSL
```

### 2.2 Dependencias externas

| Dependencia | Version | Uso |
|---|---|---|
| `bsvz` | `^0.x` | ScriptEngine para validacion simbolica; opcodes; hashing |
| `zig-wallet-toolbox` | `^0.x` | Integracion wallet: KeyManager, TxBuilder, Signer |

No hay dependencias de red, I/O, ni allocators de heap obligatorios. El core puede correr con `std.heap.stackFallback` o `std.heap.FixedBufferAllocator`.

---

## 3. API Publica (lib.zig)

### 3.1 Tipos principales

```zig
// lib.zig

const std = @import("std");
const bsvz = @import("bsvz");

/// Resultado de una expansion: bytecode + metadatos de auditoria
pub const MacroExpansion = struct {
    bytecode: []const u8,           // Owned por el allocator pasado
    asm: []const u8,                // Representacion ASM (opcional, owned)
    hash: [32]u8,                  // hash256(source + params) para reproducibilidad
    opcode_count: u32,             // Numero de opcodes emitidos
    byte_length: u32,              // Longitud en bytes
    max_stack_height: u16,         // Altura maxima del stack simulado
    is_standard: bool,             // Cumple reglas de policy (<=201 opcodes, etc.)
};

/// Configuracion del compilador
pub const CompileOptions = struct {
    target: Target = .bsv_mainnet,  // .bsv_mainnet, .bsv_testnet, .btc_strict
    enforce_standardness: bool = true,
    max_script_size: u32 = 10_000,  // Consenso BSV: 10KB; policy: 10MB configurable
    max_stack_elements: u16 = 1_000,
    max_push_size: u16 = 520,       // Policy limit; BSV consenso: ilimitado (32MB Chronicle)
    emit_asm: bool = false,         // Generar representacion ASM ademas de bytecode
};

/// Errores globales del compilador
pub const MacroError = error{
    LexError,
    ParseError,
    ExpandError,
    SimError,
    ValError,
    OutOfMemory,
};
```

### 3.2 Funciones principales

```zig
/// Expande un script fuente con macros a bytecode legacy.
/// El caller es responsable de liberar `MacroExpansion.bytecode` y `.asm`.
pub fn compile(
    allocator: std.mem.Allocator,
    source: []const u8,
    options: CompileOptions,
) MacroError!MacroExpansion;

/// Expande un script fuente usando solo macros comptime (sin allocator).
/// El source debe ser conocido en compile-time de Zig.
pub fn compileComptime(comptime source: []const u8, comptime options: CompileOptions) MacroError!MacroExpansion;

/// Verifica simbolicamente que el bytecode tiene efecto de stack valido.
/// Util para validar scripts generados externamente.
pub fn validateStack(
    allocator: std.mem.Allocator,
    bytecode: []const u8,
    expected_pre: []const StackType,
    expected_post: []const StackType,
) MacroError!void;

/// Convierte bytecode a ASM human-readable.
pub fn toAsm(allocator: std.mem.Allocator, bytecode: []const u8) std.mem.Allocator.Error![]const u8;

/// Convierte ASM a bytecode.
pub fn fromAsm(allocator: std.mem.Allocator, asm_source: []const u8) MacroError![]const u8;
```

### 3.3 Integracion con bsvz Script

```zig
/// Convierte un MacroExpansion a un bsvz.Script para ejecucion/validacion.
pub fn toBsvzScript(
    expansion: MacroExpansion,
    engine: *bsvz.script.Engine,
) bsvz.script.Error!bsvz.Script;

/// Ejecuta el bytecode expandido en el bsvz ScriptEngine con un stack dado.
/// Util para testing y debugging paso a paso.
pub fn executeInBsvz(
    allocator: std.mem.Allocator,
    bytecode: []const u8,
    initial_stack: []const bsvz.script.StackItem,
    engine: *bsvz.script.Engine,
) bsvz.script.Error!bsvz.script.ExecutionResult;
```

### 3.4 Integracion con zig-wallet-toolbox

```zig
/// Construye un scriptPubKey desde un source macro y lo anade a un TxBuilder.
pub fn addMacroOutput(
    builder: *zig_wallet_toolbox.TxBuilder,
    source: []const u8,
    satoshis: u64,
    options: CompileOptions,
) MacroError!void;

/// Construye un scriptSig desde un source macro para un input especifico.
pub fn addMacroInput(
    builder: *zig_wallet_toolbox.TxBuilder,
    input_index: u32,
    source: []const u8,
    options: CompileOptions,
) MacroError!void;
```

---

## 4. Pipeline de Compilacion (Detalle)

### 4.1 Fase 1: Lexical Analysis (lexer/scanner.zig)

**Entrada:** `[]const u8` (source DSL)  
**Salida:** `[]Token` (stream de tokens)

```zig
pub const Token = union(enum) {
    opcode: Opcode,              // OP_DUP, OP_HASH160, etc.
    macro_name: []const u8,     // "OP_XSWAP", "LOOP", "HASHCAT"
    integer: i64,               // 3, 5, -1, 1000
    string: []const u8,         // "deadbeef..." (hex literals)
    l_bracket, r_bracket,      // [ ]
    l_brace, r_brace,          // { }
    semicolon, comma,          // ; ,
    eof,
};
```

**Reglas de tokenizacion:**
- `OP_[A-Z][A-Z0-9_]*` -> opcode o macro_name (resolucion en parser)
- `[0-9]+` -> integer (decimal)
- `0x[0-9a-fA-F]+` -> string (bytes hex)
- `"[^"]*"` -> string (literal)
- `<i>` -> token especial de iteracion (solo dentro de LOOP bodies)
- Whitespace y newlines son delimitadores, no significativos
- Comentarios: `//` hasta newline, `/* */` multilinea

**Errores:**
- `UnrecognizedToken`: secuencia que no casa con ninguna regla
- `InvalidLiteral`: hex malformado, integer overflow (> i64)
- `UnclosedBlock`: `{` sin `}`

### 4.2 Fase 2: Parsing (parser/parser.zig)

**Entrada:** `[]Token`  
**Salida:** `AST` (arbol de sintaxis abstracta)

```zig
pub const AstNode = union(enum) {
    opcode_literal: Opcode,
    macro_invocation: struct {
        name: []const u8,
        args: []const AstNode,     // Solo literales (int, string, opcode)
    },
    loop_block: struct {
        bound: u64,               // Debe ser literal entero positivo
        iterator_var: ?[]const u8, // "i", "j", etc. o null
        body: []const AstNode,
    },
    conditional: struct {
        condition: Condition,
        then_branch: []const AstNode,
        else_branch: ?[]const AstNode,
    },
    block: []const AstNode,       // Secuencia plana
};

pub const Condition = union(enum) {
    feature_flag: FeatureFlag,    // @bsv, @chronicle, @cat_enabled
    version_check: u32,           // @version(2)
};
```

**Gramatica (simplificada):**
```
script      ::= statement_list
statement_list ::= statement ( ";" statement )* ";"?
statement   ::= opcode_literal
              | macro_invocation
              | loop_block
              | conditional
              | block

opcode_literal ::= "OP_" IDENT
macro_invocation ::= IDENT ( "[" arg_list "]" )? ( "{" body "}" )?
loop_block  ::= "LOOP" "[" INTEGER "]" "{" body "}"
conditional ::= "@" IDENT ( "(" INTEGER ")" )? "{" body "}" ( "else" "{" body "}" )?
arg_list    ::= arg ( "," arg )*
arg         ::= INTEGER | STRING | opcode_literal
body        ::= statement_list
```

**Errores:**
- `UnexpectedToken`: token donde no se esperaba
- `ArityMismatch`: macro espera N args, recibio M
- `InvalidLoopBound`: LOOP requiere literal entero positivo
- `ReservedKeyword`: uso de palabras reservadas como identificador

### 4.3 Fase 3: Macro Expansion (expander/expander.zig)

**Entrada:** `AST` + `MacroTable`  
**Salida:** `[]u8` (bytecode plano)

#### 4.3.1 MacroTable (M)

```zig
pub const MacroTable = struct {
    entries: std.StringHashMap(MacroDefinition),

    pub const MacroDefinition = struct {
        arity: u8,                    // Numero de argumentos formales
        param_types: []const ParamType,
        expand_fn: *const fn (
            allocator: std.mem.Allocator,
            args: []const AstNode,
            table: *const MacroTable,
        ) ExpandError![]const u8,
        // Para comptime macros (definidos en Zig, no en DSL)
        comptime_expand: ?*const fn (comptime args: anytype) []const u8,
    };

    pub const ParamType = enum {
        integer,      // 0, 1, 2...
        string,       // hex bytes, "literal"
        opcode,       // OP_DUP, OP_HASH160...
        block,        // body de loop/conditional
    };
};
```

#### 4.3.2 Familia canonica predefinida (prelude.zig)

| Macro | Arity | Expansion | Stack P->Q |
|---|---|---|---|
| `OP_XSWAP[n]` | 1 (int) | `PUSH(n-1) PICK PUSH(n-1) ROLL SWAP DROP` | `[..., x0, xn]` -> `[..., xn, x0]` |
| `OP_XDROP[n]` | 1 (int) | `PUSH(n-1) ROLL DROP` | `[..., x0, xn]` -> `[...]` |
| `OP_XROT[n]` | 1 (int) | `PUSH(n-1) ROLL` | `[..., x0, xn]` -> `[xn, ..., x0]` |
| `OP_HASHCAT` | 0 | `DUP SHA256 SWAP CAT` (o fallback si CAT disabled) | `[x]` -> `[x || SHA256(x)]` |
| `LOOP[n]{body}` | 1 (int) + 1 (block) | `body(0) body(1) ... body(n-1)` | Segun body |
| `IFDUP` | 0 | `DUP IF { DUP }` (nativo, pero como ejemplo) | `[x]` -> `[x]` o `[x, x]` |
| `VERIFY_ALL` | 0+ (var) | `BOOLAND...VERIFY` | `[b1,b2,...]` -> `[]` |
| `VERIFY_ANY` | 0+ (var) | `BOOLOR...VERIFY` | `[b1,b2,...]` -> `[]` |
| `RANGE_CHECK[min,max]` | 2 (int) + 1 (value) | `DUP min GE SWAP max LE BOOLAND VERIFY` | `[x]` -> `[]` |
| `SAFE_DIV` | 0 | `DUP 0NOTEQUAL VERIFY DIV` | `[a,b]` -> `[a/b]` |
| `P2PKH_FROM_PUBKEY` | 0 | `DUP HASH160 <push20> EQUALVERIFY CHECKSIG` | `[sig,pubkey]` -> `[]` |

#### 4.3.3 Algoritmo de expansion (single-pass)

```
function expand(node, table, output_buffer):
    if node is OpcodeLiteral:
        encode_opcode(node.opcode, output_buffer)

    else if node is MacroInvocation:
        def = table.lookup(node.name)
        if def is null: raise UnboundMacro
        if len(node.args) != def.arity: raise ArityMismatch
        for arg in node.args:
            if not typecheck(arg, def.param_types[i]): raise TypeError
        bytes = def.expand_fn(allocator, node.args, table)
        output_buffer.append(bytes)

    else if node is LoopBlock:
        for i in 0..node.bound:
            substituted = substitute_iterator(node.body, i)
            expand(substituted, table, output_buffer)

    else if node is Conditional:
        if evaluate_condition(node.condition, options):
            expand(node.then_branch, table, output_buffer)
        else if node.else_branch:
            expand(node.else_branch, table, output_buffer)

    else if node is Block:
        for child in node:
            expand(child, table, output_buffer)
```

**Higiene:**
- Cada macro invoca `expand_fn` con un sub-allocator o buffer temporal
- No hay variables globales; cada invocacion es stateless
- Los argumentos se evaluan antes de pasarse al macro (eager evaluation)
- No hay recursion: la tabla M es un DAG; ciclos se detectan en `init()`

### 4.4 Fase 4: Stack Simulation (simulator/engine.zig)

**Entrada:** Bytecode expandido  
**Salida:** `SimulationReport` o `SimError`

```zig
pub const StackType = union(enum) {
    unknown,           // Valor de input no tipado
    bool,              // Resultado de EQUAL, CHECKSIG, etc.
    integer,           // ScriptNum
    bytes: u32,        // Buffer de longitud conocida (o max)
    hash160,           // 20 bytes
    hash256,           // 32 bytes
    pubkey,            // 33 o 65 bytes
    signature,         // DER + sighash byte
};

pub const SimulationReport = struct {
    max_stack_height: u16,
    max_altstack_height: u16,
    final_stack: []const StackType,
    stack_transitions: []const StackTransition,  // Para debugging
    is_valid: bool,
};

pub const StackTransition = struct {
    pc: u32,
    opcode: Opcode,
    pre_stack: []const StackType,
    post_stack: []const StackType,
    alt_stack: []const StackType,
};
```

**Algoritmo:**
- Ejecutar simbolicamente opcode por opcode
- Cada opcode tiene una firma de tipo: `fn(opcode, &main_stack, &alt_stack) SimError!void`
- `OP_ADD`: pop integer, pop integer, push integer
- `OP_DUP`: peek top, push duplicate
- `OP_PICK`: pop integer n, push copy of element at depth n
- `OP_CAT`: pop bytes(a), pop bytes(b), push bytes(a+b) -- verificar a+b <= max_push_size
- `OP_CHECKSIG`: pop pubkey, pop sig, push bool

**Errores:**
- `StackUnderflow`: opcode requiere N elementos, hay M < N
- `StackOverflow`: altura excede max_stack_elements
- `TypeMismatch`: OP_ADD sobre bool, CHECKSIG sobre integer, etc.
- `PushTooLarge`: resultado de CAT excede 520B (policy) o 32MB (Chronicle)

### 4.5 Fase 5: Validation (validator/bounds.zig)

**Comprobaciones post-simulacion:**

| Limite | Consenso BSV | Policy (default) | Accion |
|---|---|---|---|
| Script size | 1 GB | 10 MB (node config) | Rechazar si excede target |
| Opcode count | Ilimitado | 201 (standard relay) | Marcar `is_standard = false` |
| Stack elements | 1,000 | 1,000 | Rechazar si excede |
| Push size | 32 MB (Chronicle) | 520 B | Rechazar si excede policy |
| Alt stack | 1,000 | 1,000 | Rechazar si excede |
| OP_RETURN size | Ilimitado | 100 KB | Warning si > 100KB |

**Feature flags (para target multi-chain):**
- `@bsv`: habilita OP_CAT, OP_SPLIT, OP_NUM2BIN, etc.
- `@chronicle`: habilita OP_SUBSTR, OP_LSHIFTNUM, 32MB numbers
- `@btc_strict`: deshabilita OP_CAT, OP_MUL, etc.; emite error si se usan

### 4.6 Fase 6: Encoding (encoder/*.zig)

**Minimal Push Encoding:**
```zig
pub fn encodeMinimalPush(value: i64, buf: []u8) u8 {
    if (value == 0) { buf[0] = 0x00; return 1; }           // OP_0
    if (1 <= value and value <= 16) { 
        buf[0] = 0x50 + @as(u8, @intCast(value)); return 1; // OP_1..OP_16
    }
    if (value == -1) { buf[0] = 0x4f; return 1; }          // OP_1NEGATE
    // ScriptNum serialization
    const bytes = scriptNumEncode(value, buf[1..]);
    const len = bytes.len;
    if (len <= 75) { buf[0] = len; @memcpy(buf[1..][0..len], bytes); return 1 + len; }
    if (len <= 255) { buf[0] = 0x4c; buf[1] = len; @memcpy(buf[2..][0..len], bytes); return 2 + len; }
    // PUSHDATA2, PUSHDATA4...
}
```

**ASM Emission:**
- `0x76` -> `"OP_DUP"`
- `0x01 0x04` -> `"0x04"`
- `0x4c 0x20 <32 bytes>` -> `"PUSHDATA1 0x20 0xabcd..."`


---

## 5. Comptime vs Runtime: Estrategia Dual

### 5.1 Macros comptime (Zig-native)

Para contratos donde los parametros son **conocidos en compile-time de Zig** (hardcoded en el codigo fuente de la aplicacion):

```zig
const contract = comptime bsvz_macro.compileComptime(
    "OP_XSWAP 3; LOOP[5]{ OP_<i> OP_DUP OP_MUL }",
    .{ .target = .bsv_mainnet },
) catch unreachable;

// `contract.bytecode` es un slice comptime, zero-cost en runtime
// Se incrusta directamente en el binario
```

**Ventajas:**
- Zero allocation en runtime
- Validacion simbolica en compile-time de Zig
- Bytecode incrustado en `.rodata`; sin parsing ni expansion en runtime
- Ideal para contratos template (tokens PELS, covenants fijos)

### 5.2 Macros runtime (DSL dinamico)

Para contratos donde los parametros vienen de **input del usuario** o **datos on-chain**:

```zig
pub fn buildDynamicScript(allocator: std.mem.Allocator, n_swaps: u8, loop_bound: u8) !MacroExpansion {
    var source_buf: [256]u8 = undefined;
    const source = try std.fmt.bufPrint(&source_buf, 
        "OP_XSWAP {d}; LOOP[{d}]{{ OP_<i> OP_DUP OP_MUL }}", 
        .{ n_swaps, loop_bound });

    return bsvz_macro.compile(allocator, source, .{});
}
```

**Ventajas:**
- Flexibilidad total
- Puede leerse de archivo, red, o input de usuario
- El mismo lexer/parser/expander sirve para ambos modos

### 5.3 Macros hibridos (comptime + runtime)

```zig
// Parte fija en comptime
const base_script = comptime bsvz_macro.compileComptime(
    "OP_HASH160 <expected_hash> OP_EQUALVERIFY",
    .{},
) catch unreachable;

// Parte dinamica en runtime
pub fn buildVaultScript(allocator: std.mem.Allocator, pubkey: []const u8) !bsvz.Script {
    var full_source: [512]u8 = undefined;
    const source = try std.fmt.bufPrint(&full_source,
        "{s} {s} OP_CHECKSIG",
        .{ base_script.asm, pubkey });

    const expanded = try bsvz_macro.compile(allocator, source, .{});
    return bsvz_macro.toBsvzScript(expanded, engine);
}
```

---

## 6. Integracion Detallada con Ecosistema

### 6.1 Con bsvz (ScriptEngine)

```zig
// bsvz-macro/src/bridge/bsvz.zig

const bsvz = @import("bsvz");

pub fn executeExpanded(
    expansion: MacroExpansion,
    engine: *bsvz.script.Engine,
    initial_stack: []const bsvz.script.StackItem,
) !bsvz.script.ExecutionResult {
    // El bytecode expandido se carga directamente en el engine
    try engine.loadScript(expansion.bytecode);
    try engine.pushAll(initial_stack);
    return engine.execute();
}

pub fn verifyAgainstBsvz(
    allocator: std.mem.Allocator,
    source: []const u8,
    engine: *bsvz.script.Engine,
) !bool {
    const expanded = try compile(allocator, source, .{});
    defer expanded.deinit(allocator);

    // Ejecutar en bsvz ScriptEngine
    const result = try executeExpanded(expanded, engine, &.{});
    return result.success;
}
```

**Flujo de test:**
1. Escribir source macro
2. Expandir con bsvz-macro
3. Ejecutar en bsvz ScriptEngine con stack simulado
4. Comparar resultado con la simulacion simbolica de bsvz-macro
5. Si difieren: bug en el expander o en el engine

### 6.2 Con zig-wallet-toolbox

```zig
// bsvz-macro/src/bridge/wallet.zig

const wallet = @import("zig-wallet-toolbox");

pub fn addContractOutput(
    builder: *wallet.TxBuilder,
    source: []const u8,
    satoshis: u64,
    options: CompileOptions,
) !void {
    const expanded = try compile(builder.allocator, source, options);
    defer expanded.deinit(builder.allocator);

    const script = try wallet.Script.fromBytes(expanded.bytecode);
    try builder.addOutput(script, satoshis);
}

pub fn signMacroInput(
    signer: *wallet.Signer,
    tx: *wallet.Transaction,
    input_index: u32,
    macro_source: []const u8,
    sighash_type: u8,
) !wallet.Signature {
    // 1. Expandir el macro para obtener el scriptSig
    const expanded = try compile(signer.allocator, macro_source, .{});
    defer expanded.deinit(signer.allocator);

    // 2. Calcular sighash con el scriptPubKey correspondiente
    const sighash = try signer.calculateSighash(tx, input_index, sighash_type);

    // 3. Firmar
    return try signer.sign(sighash);
}
```

### 6.3 Con PUSHTX / Covenants

Para PUSHTX (firma in-script que "ve" la transaccion), bsvz-macro puede generar el **script de construccion del preimage** como una secuencia macro:

```zig
const pushtx_template = 
    // Construir hashPrevouts
    "OP_XSWAP 2; OP_CAT; OP_HASH256;"
    // Construir hashSequence
    "OP_XSWAP 2; OP_CAT; OP_HASH256;"
    // ... etc
;
```

El expander emite el bytecode que, cuando se ejecuta en el ScriptEngine de bsvz, construye byte-a-byte el preimage. Esto permite **automatizar la generacion de scripts PUSHTX** desde templates de alto nivel.

---

## 7. Seguridad y Limites

### 7.1 Fail-fast en todas las fases

| Fase | Error critico | Respuesta |
|---|---|---|
| Lex | Token no reconocido | Abortar, no emitir bytecode parcial |
| Parse | Arity mismatch | Abortar, diagnosticar esperado vs recibido |
| Expand | Macro no definido | Abortar, sugerir macros similares (fuzzy match) |
| Expand | Loop bound > max | Abortar, reportar limite excedido |
| Simulate | Stack underflow | Abortar, reportar opcode y profundidad actual |
| Validate | Script > 10KB | Abortar (consenso) o marcar non-standard (policy) |
| Validate | Push > 520B | Abortar (policy) o warning (Chronicle 32MB) |

### 7.2 Prevencion de DoS en compilacion

- **Budget de tokens:** max 10,000 tokens por source
- **Budget de expansion:** max 1,000,000 opcodes post-expansion
- **Timeout:** Si la expansion toma > 1s, abortar (proteccion contra pathological input)
- **Recursion depth:** Max 32 niveles de anidamiento de macros

### 7.3 Determinismo y reproducibilidad

```zig
/// Hash del source + options para verificacion de builds reproducibles
pub fn computeBuildHash(source: []const u8, options: CompileOptions) [32]u8 {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update(source);
    hasher.update(std.mem.asBytes(&options));
    var hash: [32]u8 = undefined;
    hasher.final(&hash);
    return hash;
}
```

Dos compilaciones del mismo source con las mismas options deben producir el **mismo bytecode bit-a-bit**.

---

## 8. Testing Strategy

### 8.1 Niveles de test

| Nivel | Que testea | Herramienta |
|---|---|---|
| Unit | Cada opcode en el simulador simbolico | `zig test` |
| Unit | Cada macro de la familia canonica | `zig test` |
| Integration | Lexer -> Parser -> Expander -> Encoder | `zig test` |
| Integration | Expander -> bsvz ScriptEngine | `zig test` + bsvz |
| E2E | Source macro -> Tx firmada -> Validacion | `zig test` + wallet-toolbox |
| Property | Fuzzing de stack transitions | `std.testing.fuzz` |
| Regression | Fixtures de scripts conocidos | `tests/fixtures/` |

### 8.2 Fixtures de referencia

```zig
// tests/fixtures/xswap_cases.zig
pub const xswap3_case = MacroTestCase{
    .source = "OP_XSWAP 3",
    .expected_asm = "OP_2 OP_PICK OP_2 OP_ROLL OP_SWAP OP_DROP",
    .expected_hex = "5279527a7c75",
    .pre_stack = &.{ .{ .bytes = 4 }, .{ .bytes = 4 }, .{ .bytes = 4 }, .{ .bytes = 4 } },
    .post_stack = &.{ .{ .bytes = 4 }, .{ .bytes = 4 }, .{ .bytes = 4 } },
};
```

### 8.3 Fuzzing targets

- **Lexer fuzz:** Input aleatorio de bytes -> no debe crashar, debe retornar error controlado
- **Stack sim fuzz:** Secuencia aleatoria de opcodes validos -> verificar que la simulacion coincide con bsvz ScriptEngine
- **Macro expansion fuzz:** AST aleatoria con macros validos -> verificar que el output es valido segun policy

---

## 9. Roadmap de Implementacion

### Fase 1: Foundation (Semana 1-2)
- [ ] Estructura de modulos y `build.zig`
- [ ] Definicion de tipos base (`Token`, `AstNode`, `MacroTable`)
- [ ] Lexer completo con todas las reglas de tokenizacion
- [ ] Parser recursive descent para gramatica base
- [ ] Encoder minimal push (OP_0..OP_16, PUSHDATA1..4)
- [ ] 100% cobertura de test para lexer + parser + encoder

### Fase 2: Expander Core (Semana 3-4)
- [ ] MacroTable con familia canonica: XSWAP, XDROP, XROT, HASHCAT
- [ ] Single-pass expander con single allocator
- [ ] LOOP[n]{body} con substitute_iterator
- [ ] Feature flags (@bsv, @chronicle, @btc_strict)
- [ ] Tests de integracion expander -> hex

### Fase 3: Stack Simulator (Semana 5-6)
- [ ] Modelo simbolico de stack (main + alt)
- [ ] Firma de tipo para cada opcode legacy (~100 opcodes)
- [ ] Ejecutor simbolico paso a paso
- [ ] Deteccion de StackUnderflow, TypeMismatch, PushTooLarge
- [ ] Tests contra bsvz ScriptEngine (deben coincidir 100%)

### Fase 4: Validator + Policy (Semana 7)
- [ ] Bounds checker (size, stack, push)
- [ ] Policy checker (standardness rules)
- [ ] Chronicle support (32MB numbers, nuevos opcodes)
- [ ] Error reporting con ubicacion exacta (linea:columna)

### Fase 5: Comptime Bridge (Semana 8)
- [ ] `compileComptime()` usando `comptime` de Zig
- [ ] Macros definidos como funciones `comptime` en `prelude.zig`
- [ ] Integracion con `std.testing` para tests comptime
- [ ] Benchmark: comptime vs runtime expansion

### Fase 6: Wallet Integration (Semana 9-10)
- [ ] Bridge `bsvz-macro` -> `bsvz` ScriptEngine
- [ ] Bridge `bsvz-macro` -> `zig-wallet-toolbox` TxBuilder/Signer
- [ ] Helpers para P2PKH, P2SH (legacy), PELS, Covenants
- [ ] Documentacion de API publica (`lib.zig`)
- [ ] Ejemplos: Token PELS, Vault, Dutch Auction, Payment Channel

### Fase 7: Optimizacion + Polish (Semana 11-12)
- [ ] Fuzzing con `std.testing.fuzz`
- [ ] Profile-guided optimization del expander
- [x] WASM target: `zig build wasm` produce `zig-out/wasm/bsvz_macro.wasm` (wasm32-freestanding, ~70 KB, sin imports, sin libc; excluye `zig-wallet-toolbox` del grafo)
- [x] JS bindings para consumo desde wallets web (`web/bsvz-macro.js` + `web/bsvz-macro.d.ts`; smoke test `node web/test/smoke.mjs`)
- [ ] Release v0.1.0

---

## 10. Consideraciones de Diseno Avanzadas

### 10.1 Allocators

El core de bsvz-macro debe ser **allocator-agnostic**:

```zig
pub fn compile(
    allocator: std.mem.Allocator,  // Puede ser FBA, GPA, Arena, stackFallback
    source: []const u8,
    options: CompileOptions,
) MacroError!MacroExpansion {
    // Usar allocator para tokens, AST, bytecode, ASM
    // El caller decide la estrategia de memoria
}
```

Para uso en wallet con muchas compilaciones pequenas, recomendar `std.heap.ArenaAllocator`. Para un solo script grande, `std.heap.page_allocator`.

### 10.2 Error Reporting

```zig
pub const CompileDiagnostic = struct {
    phase: Phase,           // .lex, .parse, .expand, .simulate, .validate
    severity: Severity,     // .error, .warning, .note
    message: []const u8,
    location: SourceLocation,
    suggestion: ?[]const u8,
};

pub const SourceLocation = struct {
    line: u32,
    column: u32,
    offset: u32,
    length: u32,
};
```

El compilador debe acumular **todos** los diagnosticos (no solo fail-fast) en modo debug, pero en modo produccion (wallet) es fail-fast en el primer error.

### 10.3 Extensibilidad: Macros definidos por el usuario

```zig
// API para registrar macros custom en runtime
pub fn registerMacro(
    table: *MacroTable,
    name: []const u8,
    definition: MacroDefinition,
) !void;

// Ejemplo: usuario define un macro "MY_DUP_DROP"
const my_macro = MacroDefinition{
    .arity = 0,
    .expand_fn = struct {
        fn f(a: std.mem.Allocator, args: []const AstNode, t: *const MacroTable) ![]const u8 {
            _ = .{ a, args, t };
            return &.{ 0x76, 0x75 }; // OP_DUP OP_DROP
        }
    }.f,
};
try macro_table.register("MY_DUP_DROP", my_macro);
```

### 10.4 Cache de expansion

Para macros comunes que se expanden frecuentemente con los mismos parametros:

```zig
pub const ExpansionCache = struct {
    map: std.HashMap(u64, []const u8, std.hash_map.default_ctx, 80),

    pub fn getOrExpand(
        self: *ExpansionCache,
        source_hash: u64,
        expand_fn: *const fn() []const u8,
    ) []const u8 {
        if (self.map.get(source_hash)) |cached| return cached;
        const result = expand_fn();
        self.map.put(source_hash, result) catch {};
        return result;
    }
};
```

---

## 11. Apendice: Gramatica Formal EBNF

```ebnf
script          = statement_list, EOF;
statement_list  = statement, { ";", statement }, [ ";" ];
statement       = opcode_literal
                | macro_invocation
                | loop_block
                | conditional
                | block;

opcode_literal  = "OP_", identifier;
macro_invocation= identifier, [ "[", arg_list, "]" ], [ "{", body, "}" ];
loop_block      = "LOOP", "[", integer, "]", "{", body, "}";
conditional     = "@", identifier, [ "(", integer, ")" ], "{", body, "}", [ "else", "{", body, "}" ];

arg_list        = arg, { ",", arg };
arg             = integer
                | string
                | opcode_literal;

body            = statement_list;

integer         = [ "-" ], digit, { digit };
string          = hex_string | quoted_string;
hex_string      = "0x", hex_digit, { hex_digit };
quoted_string   = '"', { character - '"' }, '"';
identifier      = letter, { letter | digit | "_" };

letter          = "A".."Z" | "a".."z";
digit           = "0".."9";
hex_digit       = digit | "A".."F" | "a".."f";
character       = any Unicode scalar except control;
```

---

## 12. Apendice: Tabla de Opcodes Soportados (v1.0)

Toda la familia de opcodes de Bitcoin Script (2009) mas los restaurados/habilitados en BSV/Chronicle:

| Categoria | Opcodes | Soporte v1.0 |
|---|---|---|
| Constantes | OP_0..OP_16, OP_1NEGATE | Si |
| Stack | OP_DUP, OP_DROP, OP_SWAP, OP_PICK, OP_ROLL, OP_ROT, OP_NIP, OP_OVER, OP_2DUP, OP_2DROP, OP_2OVER, OP_2ROT, OP_2SWAP, OP_TUCK, OP_DEPTH | Si |
| Alt Stack | OP_TOALTSTACK, OP_FROMALTSTACK | Si |
| Splice | OP_CAT, OP_SPLIT, OP_SIZE, OP_NUM2BIN, OP_BIN2NUM | Si |
| Bitwise | OP_EQUAL, OP_EQUALVERIFY, OP_AND, OP_OR, OP_XOR, OP_INVERT | Si |
| Aritmetica | OP_ADD, OP_SUB, OP_MUL, OP_DIV, OP_MOD, OP_NEGATE, OP_ABS, OP_NOT, OP_0NOTEQUAL, OP_LSHIFT, OP_RSHIFT, OP_BOOLAND, OP_BOOLOR, OP_NUMEQUAL, OP_NUMEQUALVERIFY, OP_NUMNOTEQUAL, OP_LESSTHAN, OP_GREATERTHAN, OP_LESSTHANOREQUAL, OP_GREATERTHANOREQUAL, OP_MIN, OP_MAX, OP_WITHIN | Si |
| Chronicle | OP_2MUL, OP_2DIV, OP_LSHIFTNUM, OP_RSHIFTNUM, OP_SUBSTR, OP_LEFT, OP_RIGHT, OP_VER, OP_VERIF, OP_VERNOTIF | Si (con flag @chronicle) |
| Crypto | OP_RIPEMD160, OP_SHA1, OP_SHA256, OP_HASH160, OP_HASH256, OP_CODESEPARATOR, OP_CHECKSIG, OP_CHECKSIGVERIFY, OP_CHECKMULTISIG, OP_CHECKMULTISIGVERIFY | Si |
| Control | OP_IF, OP_NOTIF, OP_ELSE, OP_ENDIF, OP_VERIFY, OP_RETURN, OP_NOP | Si |
| Push Data | OP_PUSHBYTES_1..75, OP_PUSHDATA1, OP_PUSHDATA2, OP_PUSHDATA4 | Si |

---

*Fin del Blueprint de bsvz-macro*
*Este documento es un especificacion viva. Las decisiones de implementacion deben alinearse con los principios de totality, hygiene, zero-cost, y consensus compatibility.*
