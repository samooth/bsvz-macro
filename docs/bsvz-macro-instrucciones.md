# Instrucciones de bsvz-macro

## Que es bsvz-macro

`bsvz-macro` es un compilador wallet-side de macro expansion para Bitcoin Script (BSV). Transforma un lenguaje simbolico de alto nivel (macros parametrizados) en secuencias de opcodes legacy compatibles con el protocolo Bitcoin original (2009).

**Filosofia:** *"You write the loop once, but emit it many times"* — determinismo total, zero-cost abstraction, consenso inmutable.

## Requisitos

- **Zig 0.16.0** o superior
- Acceso a red (las dependencias se descargan automaticamente mediante el gestor de paquetes de Zig desde GitHub: `bsvz` y `zig-wallet-toolbox`, fijadas por commit en `build.zig.zon`). No se requiere clonar repositorios hermanos ni configurar un layout de directorios especial.

## Estructura del proyecto

```
bsvz-macro/
  build.zig
  build.zig.zon
  src/
    lib.zig              # API publica
    prelude.zig          # Macros predefinidos (11 macros)
    lexer/
      token.zig          # Definicion de tokens
      scanner.zig        # Analisis lexico
      error.zig          # Errores del lexer
    parser/
      ast.zig            # Arbol de sintaxis abstracta
      parser.zig         # Parser recursive descent
      error.zig          # Errores del parser
    expander/
      table.zig          # Tabla de macros
      expander.zig       # Expansor single-pass
      comptime_exp.zig   # Expansion comptime
      error.zig          # Errores de expansion
    simulator/
      stack.zig          # Modelo simbolico del stack
      engine.zig         # Ejecutor simbolico
      error.zig          # Errores de simulacion
    encoder/
      push.zig           # Minimal push encoding
      asm.zig            # Emision a ASM
      hex.zig            # Emision a hex
    validator/
      bounds.zig         # Limites de consenso/policy
      policy.zig         # Reglas de policy
      error.zig          # Errores de validacion
    bridge/
      bsvz.zig           # Integracion con bsvz ScriptEngine
      wallet.zig         # Integracion con zig-wallet-toolbox
  tests/
    macro_e2e.zig        # Tests end-to-end
    canonical.zig        # Tests de macros canonicas
    stack_sim.zig        # Tests del simulador
    fixtures/
      xswap_cases.zig
      loop_cases.zig
      covenant_cases.zig
  docs/
    blueprint.md         # Especificacion completa
    macro_reference.md   # Referencia de macros
    dsl_grammar.md       # Gramatica formal EBNF
```

## Instalacion

### 1. Clonar el repositorio

```bash
git clone https://github.com/tu-usuario/bsvz-macro
```

Las dependencias (`bsvz`, `zig-wallet-toolbox`) se obtienen automaticamente al
ejecutar `zig build` la primera vez, gracias al gestor de paquetes de Zig.

### 2. Compilar

```bash
cd bsvz-macro
zig build
```

### 3. Ejecutar tests

```bash
zig build test
```

## Uso basico

### Compilacion en runtime

```zig
const std = @import("std");
const bsvz_macro = @import("bsvz-macro");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const result = try bsvz_macro.compile(allocator, "OP_XSWAP[3]", .{});
    defer result.deinit(allocator);

    std.debug.print("Bytecode: ", .{});
    for (result.bytecode) |b| {
        std.debug.print("{x:0>2}", .{b});
    }
    std.debug.print("\n", .{});
}
```

### Compilacion en comptime

```zig
const contract = comptime bsvz_macro.compileComptime(
    "OP_XSWAP 3; LOOP[5]{ OP_<i> OP_DUP OP_MUL }",
    .{ .target = .bsv_mainnet },
) catch unreachable;

// contract.bytecode es un slice comptime, zero-cost en runtime
```

### Con ASM de salida

```zig
const result = try bsvz_macro.compile(allocator, "OP_HASHCAT", .{
    .emit_asm = true,
});
if (result.asm) |asm_str| {
    std.debug.print("ASM: {s}\n", .{asm_str});
}
```

## Macros disponibles

### OP_XSWAP[n]
Swap el tope con el elemento a profundidad n.
```
OP_XSWAP[3]
```
Expansion: `PUSH(2) PICK PUSH(2) ROLL SWAP DROP`

### OP_XDROP[n]
Elimina el elemento a profundidad n.
```
OP_XDROP[2]
```
Expansion: `PUSH(1) ROLL DROP`

### OP_XROT[n]
Rota el elemento a profundidad n al tope.
```
OP_XROT[3]
```
Expansion: `PUSH(2) ROLL`

### OP_HASHCAT
Concatena el tope con su SHA256.
```
OP_HASHCAT
```
Expansion: `DUP SHA256 SWAP CAT`

### IFDUP
Duplica si el tope es truthy.
```
IFDUP
```

### SAFE_DIV
Division segura (chequea divisor != 0).
```
SAFE_DIV
```
Expansion: `SWAP DUP 0NOTEQUAL VERIFY DIV`

### RANGE_CHECK[min, max]
Verifica que el tope esta en rango.
```
RANGE_CHECK[0, 100]
```

### P2PKH_FROM_PUBKEY
P2PKH estandar (con hash placeholder).
```
P2PKH_FROM_PUBKEY
```

### VERIFY_ALL[n]
Verifica que n booleans son todos true.
```
VERIFY_ALL[3]
```

### VERIFY_ANY[n]
Verifica que al menos uno de n booleans es true.
```
VERIFY_ANY[2]
```

### PUSHTX_FRAGMENT[n]
Helper para construir PUSHTX según WP1605 (nChain, 2021) sección 1.2: pick a profundidad n, duplicar, hashear la copia, y concatenar el original con el hash.
```
PUSHTX_FRAGMENT[3]
```

### PUSHTX_TOCANONICAL
Bloque [toCanonical] de WP1605 §1.1: fuerza s al rango [0, n/2] reemplazando s con n-s cuando s > n/2.

### PUSHTX_CONCATENATIONS
Bloque [concatenations] de WP1605 §1.1: construye la estructura DER para (r, s).

### PUSHTX_TODER
Bloque [toDER] de WP1605 §1.1: canonicaliza s y construye la estructura DER.

### PUSHTX_SIGN[sighash_flag]
Bloque [sign] de WP1605 §1.1 con la optimización k = a = 1. El parámetro `sighash_flag` es la bandera sighash en formato little-endian (1 para SIGHASH_ALL, 0x83 para SINGLE|ANYONECANPAY, etc.).
```
PUSHTX_SIGN[1]
```

### PUSHTX_OUTPUTS_REQUEST[item8_hex, items10_11_hex]
Bloque [outputsRequest] de WP1605 §1.3. Ambos argumentos son strings hexadecimales (con o sin prefijo `0x`, longitud par) que se empujan como bytes crudos. `item8_hex` es la secuencia de 4 bytes del item 8 (sequence number), e `items10_11_hex` es la concatenación de los items 10 y 11 (locktime y sighash, 8 bytes en total).
```
PUSHTX_OUTPUTS_REQUEST[0xffffffff, 0x0000000001000000]
```

## Sintaxis del DSL

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

### Bucles con iterador

```
LOOP[5]{ OP_<i> OP_ADD }
```

`<i>` se sustituye por 0, 1, 2, 3, 4 en cada iteracion.

### Flags condicionales

```
@bsv{ OP_CAT } else { OP_NOP }
```

```
@version(2){ OP_LSHIFTNUM }
```

## Opciones de compilacion

```zig
const options = bsvz_macro.CompileOptions{
    .target = .bsv_mainnet,           // .bsv_mainnet, .bsv_testnet, .btc_strict
    .enforce_standardness = true,     // Aplicar reglas de policy
    .max_script_size = 10_000,       // Limite de tamano (consenso: 1GB, policy: 10MB)
    .max_stack_elements = 1_000,     // Max elementos en stack
    .max_push_size = 520,            // Max push (policy; Chronicle: 32MB)
    .emit_asm = false,               // Generar salida ASM
};
```

## Integracion con bsvz

```zig
const bsvz = @import("bsvz");
const bsvz_macro = @import("bsvz-macro");

const expansion = try bsvz_macro.compile(allocator, source, .{});
const script = bsvz.script.Script.init(expansion.bytecode);

// Ejecutar en ScriptEngine
var engine = bsvz.script.engine.ScriptEngine.init(allocator);
const result = try engine.execute(script);
```

## Integracion con zig-wallet-toolbox

```zig
const wallet = @import("zig-wallet-toolbox");
const bsvz_macro = @import("bsvz-macro");

// Anadir output con macro
var builder = bsvz.transaction.builder.Builder.init(allocator);
try bsvz_macro.bridge.wallet.addMacroOutput(
    &builder,
    "OP_HASH160 0x0000000000000000000000000000000000000000 OP_EQUALVERIFY OP_CHECKSIG",
    1000,
    .{},
);
```

## Pipeline de compilacion

```
Source DSL
    |
    v
[1] Lexer  -> Tokens
    |
    v
[2] Parser -> AST
    |
    v
[3] Expander -> Bytecode plano (con MacroTable)
    |
    v
[4] Simulator -> Stack transitions (validacion simbolica)
    |
    v
[5] Validator -> Bounds + Policy checks
    |
    v
[6] Encoder -> Hex / ASM
```

## Limites y seguridad

| Limite | Valor | Accion |
|---|---|---|
| Max tokens por source | 10,000 | Abortar |
| Max opcodes post-expansion | 1,000,000 | Abortar |
| Profundidad de recursion de macros | 32 | Abortar |
| Bound maximo de LOOP | 1,000 | Abortar |
| Tamano maximo de script (consenso) | 1 GB | Rechazar |
| Tamano maximo de script (policy) | 10 MB | Marcar non-standard |
| Elementos max en stack | 1,000 | Rechazar |
| Push max (policy) | 520 bytes | Rechazar |
| Push max (Chronicle) | 32 MB | Warning |

## Errores

| Fase | Error | Causa |
|---|---|---|
| Lex | `UnrecognizedToken` | Token no reconocido |
| Lex | `InvalidLiteral` | Literal malformado |
| Parse | `UnexpectedToken` | Token inesperado |
| Parse | `ArityMismatch` | Numero incorrecto de argumentos |
| Parse | `InvalidLoopBound` | LOOP requiere entero positivo |
| Expand | `UnboundMacro` | Macro no definido |
| Expand | `MacroRecursionDepthExceeded` | Recursion > 32 |
| Expand | `LoopBoundTooLarge` | LOOP[n] con n > 1000 |
| Simulate | `StackUnderflow` | Opcode requiere mas elementos |
| Simulate | `StackOverflow` | Stack excede limite |
| Simulate | `TypeMismatch` | Tipos incompatibles |
| Validate | `ScriptTooLarge` | Script excede max_script_size |
| Validate | `StackTooDeep` | Stack excede max_stack_elements |
| Validate | `NonStandard` | No cumple reglas de policy |

## Tests

```bash
# Todos los tests
zig build test

# Tests especificos
zig test src/lib.zig
zig test tests/macro_e2e.zig
zig test tests/canonical.zig
zig test tests/stack_sim.zig
```

## Target WASM

```bash
zig build -Dtarget=wasm32-freestanding
```

El core es puro Zig sin dependencias de red ni I/O, compatible con WASM.

## Licencia

MIT — parte del ecosistema bsvz / zig-wallet-toolbox.
