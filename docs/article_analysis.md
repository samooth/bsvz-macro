# Macro Expansion en Bitcoin Script
## Resumen y Analisis del articulo de Substack

> **Titulo original:** Macro Expansion in Bitcoin Script  
> **Autor:** Craig Wright (publicado en [Substack](https://singulargrit.substack.com/p/macro-expansion-in-bitcoin-script))  
> **Fecha de lectura:** Agosto 2026  
> **Enfoque:** Teoria de automatas, compiladores wallet-side, y computacion estatica en Bitcoin Script

---

## Tabla de Contenidos

1. [Resumen Ejecutivo](#1-resumen-ejecutivo)
2. [El Argumento Central: Script como 2PDA](#2-el-argumento-central-script-como-2pda)
3. [La Solucion: Wallet-Side Macro Expansion](#3-la-solucion-wallet-side-macro-expansion)
4. [Familia Canonica de Macros](#4-familia-canonica-de-macros)
5. [Formalismo Matematico](#5-formalismo-matematico)
6. [Algebra de Stack y Verificacion Simbolica](#6-algebra-de-stack-y-verificacion-simbolica)
7. [Arquitectura del Compilador](#7-arquitectura-del-compilador)
8. [Higiene y Boundedness](#8-higiene-y-boundedness)
9. [Manejo de Errores](#9-manejo-de-errores)
10. [Implicaciones para BSV](#10-implicaciones-para-bsv)
11. [Critica y Limitaciones](#11-critica-y-limitaciones)
12. [Conclusiones](#12-conclusiones)

---

## 1. Resumen Ejecutivo

El [articulo](https://singulargrit.substack.com/p/macro-expansion-in-bitcoin-script) presenta una vision formal de Bitcoin Script no como un lenguaje limitado, sino como un **autómata de pila de dos stacks (2PDA)** — computacionalmente equivalente a una maquina de Turing, siempre y cuando todo el control de flujo sea **estaticamente acotado y desenrollado en tiempo de compilacion**.

La tesis practica es: en lugar de modificar el protocolo para anadir loops, recursion o nuevos opcodes, se traslada toda la complejidad al **wallet**, que funciona como un compilador macro-expansor. El wallet transforma un lenguaje simbolico de alto nivel (macros parametrizados) en secuencias planas de opcodes legacy. El nodo nunca ve un macro; solo ejecuta bytecode estatico, aciclico y determinista.

> *"You write the loop once, but emit it many times — fully expanded, and verifiable by the node interpreter as a static script."*

---

## 2. El Argumento Central: Script como 2PDA

### 2.1 El modelo de dos pilas

Bitcoin Script maneja dos estructuras LIFO durante la ejecucion:

- **Main Stack (S):** La pila principal donde la mayoria de opcodes operan.
- **Alt Stack (A):** Pila secundaria accesible via `OP_TOALTSTACK` y `OP_FROMALTSTACK`.

Desde la teoria de lenguajes formales, esta configuracion constituye un **two-stack pushdown automaton (2PDA)**. Un 2PDA es conocido por ser equivalente en poder computacional a una **maquina de Turing universal**.

### 2.2 Por que es Turing-equivalente (condicionalmente)

La equivalencia funciona asi:
- Una pila simula el **lado izquierdo** de la cinta de Turing.
- La otra pila simula el **lado derecho** de la cinta.
- Los movimientos del cabezal se simulan haciendo pop de una pila y push en la otra.

**Pero hay una condicion critica:** esta equivalencia solo se mantiene si todo el control de flujo es **estaticamente acotado**. No puede haber loops dinamicos, recursion en runtime, ni memoria no acotada. El "programa" debe tener una trayectoria fija y finita para cualquier input.

### 2.3 La restriccion de Bitcoin: intencionalmente total

Bitcoin impone limites estrictos que hacen la computacion **total** (siempre termina):
- Tamano de script acotado (~10,000 bytes en BTC, 1GB en BSV consenso)
- Stack limitado (~1,000 elementos)
- Sin `OP_JUMP`, `OP_CALL`, `OP_LOOP`, `OP_RECURSE`
- Evaluacion no interactiva: un solo programa contra un input de transaccion

El articulo argumenta que Bitcoin no esta "subpotenciado" — esta **intencionalmente total** sobre un espacio simbolico finito. La complejidad no se elimina; se traslada al compilador.

### 2.4 Analogia con hardware

El autor compara este modelo con:
- **FPGAs:** donde el disenador escribe logica estructurada que se sintetiza en un circuito fisico estatico.
- **zk-SNARKs:** donde un programa se "desenrolla" en un circuito aritmetico aciclico.

En ambos casos, la expresividad se logra mediante **transformacion estatica**, no extension dinamica del runtime.

---

## 3. La Solucion: Wallet-Side Macro Expansion

### 3.1 Separacion de responsabilidades

| Componente | Rol | Complejidad |
|---|---|---|
| **Wallet / Compilador** | Macro expansion, verificacion simbolica, generacion de bytecode | Alta (abstraccion, estructura, logica) |
| **Nodo / ScriptEngine** | Ejecucion de opcodes legacy, validacion de consenso | Baja (determinista, aciclico, finito) |

El wallet es donde ocurre toda la "computacion simbolica". El nodo solo valida transiciones de estado finitas.

### 3.2 El loop como desenrollado estatico

En lugar de:
```
for i in 0..n:
    body(i)
```

El compilador emite:
```
body(0)
body(1)
body(2)
...
body(n-1)
```

Cada `body(i)` es una secuencia concreta de opcodes. El resultado es un **grafo aciclico de flujo de datos** (DAG), no un programa con control dinamico.

### 3.3 Propiedades del modelo

- **Inmutabilidad del protocolo:** No se necesitan forks, soft-forks ni nuevos opcodes.
- **Compatibilidad total:** El bytecode expandido es indistinguible de Script escrito a mano.
- **Verificabilidad:** Se puede publicar el source macro + parametros, y cualquiera puede reproducir el bytecode.
- **Determinismo:** Mismo source + mismos parametros = mismo bytecode, bit a bit.

---

## 4. Familia Canonica de Macros

El articulo define un conjunto minimo pero expresivo de macros que cubren las operaciones mas frecuentes en el diseno de contratos.

### 4.1 OP_XSWAP_n

**Proposito:** Intercambiar el elemento superior del stack con el n-esimo elemento desde arriba.

**Expansion:**
```
PUSH(n-1) OP_PICK       ; copia S[n-1] al top
PUSH(n-1) OP_ROLL       ; mueve S[0] a profundidad n-1
OP_SWAP
OP_DROP
```

**Transformacion de stack (n=3):**
```
[a, b, c] -> [c, b, a]
```

**Uso:** Reordenar operandos sin romper el determinismo del stack.

### 4.2 OP_XDROP_n

**Proposito:** Eliminar el n-esimo elemento desde arriba sin afectar el resto.

**Expansion:**
```
PUSH(n-1) OP_ROLL
OP_DROP
```

**Transformacion de stack (n=4):**
```
[a, b, c, d] -> [a, b, c]
```

**Uso:** Limpiar valores intermedios o de contexto.

### 4.3 OP_XROT_n

**Proposito:** Rotar el n-esimo elemento al tope, desplazando los elementos superiores hacia abajo.

**Expansion:**
```
PUSH(n-1) OP_ROLL
```

**Transformacion de stack (n=5):**
```
[a, b, c, d, e] -> [e, a, b, c, d]
```

**Uso:** Simular registros o slots de datos estructurados.

### 4.4 OP_HASHCAT

**Proposito:** Duplicar el elemento superior, calcular su hash, y concatenar el resultado al original.

**Expansion (BSV con OP_CAT habilitado):**
```
OP_DUP
OP_SHA256
OP_SWAP
OP_CAT
```

**Transformacion:**
```
[x] -> [x || SHA256(x)]
```

**Fallback (BTC donde OP_CAT esta deshabilitado):**
- El compilador calcula `SHA256(x)` off-chain y emite dos `PUSHDATA` literales.
- La concatenacion no es expresable en Script y debe manejarse estructuralmente.

**Uso:** Token locking, address-derived commitments, binding de identidad.

### 4.5 LOOP[n]{body(i)}

**Proposito:** Repetir una plantilla `body(i)` exactamente `n` veces con sustitucion de parametros.

**Ejemplo:**
```
LOOP[3]{ OP_<i> OP_DUP OP_MUL }
```

**Expansion:**
```
OP_0 OP_DUP OP_MUL
OP_1 OP_DUP OP_MUL
OP_2 OP_DUP OP_MUL
```

**Uso:** Iteracion estatica sobre estructuras tipo array, aritmetica por lotes, progresion de estado determinista.

### 4.6 Propiedades de la familia canonica

Cada macro es:
- **Pura sintactica:** sin interpretacion en runtime
- **Finita y aciclica:** termina sin condicionales ni jumps
- **Parametrica sobre N:** acepta solo literales enteros no negativos
- **Composable:** puede anidarse en cuerpos de loop u otros macros
- **Legacy-safe:** emite solo opcodes del set base de 2009

---

## 5. Formalismo Matematico

### 5.1 Definicion de macro

Un macro **M** se define formalmente como una tripleta:

> **M = <sigma, pi, rho>**
>
> donde:
> - **sigma** pertenece a Sigma: nombre simbolico (ej. "OP_XSWAP", "LOOP")
> - **pi = [p1, p2, ..., pk]:** lista ordenada de parametros formales (enteros)
> - **rho: Z^k -> Omega+:** funcion que mapea k-tuplas de enteros a secuencias finitas de opcodes

Omega es el conjunto de opcodes base de Bitcoin (2009). Omega+ es la clausura de Kleene (todas las secuencias finitas no vacias sobre Omega).

### 5.2 Restricciones de rho

Para que un macro sea valido, su funcion de expansion debe cumplir:

1. **Totalidad:** rho termina en pasos finitos para toda entrada valida.
2. **Expansion finita:** rho(n1,...,nk) devuelve una lista acotada por una constante estatica.
3. **Validez de opcodes:** todos los elementos de la salida pertenecen a Omega.
4. **Solidez de stack:** para precondicion P y postcondicion Q declaradas, la secuencia de opcodes transforma P en Q correctamente.
5. **No-interactividad:** la expansion es stateless, sin side-effects, e independiente del orden de invocacion.

### 5.3 Ejemplo: OP_XDROP

**M = OP_XDROP, pi = [n]**

```
rho(n) = [PUSH(n-1), OP_ROLL, OP_DROP]
```

**Expansion de OP_XDROP_4:**
```
OP_3
OP_ROLL
OP_DROP
```

Transforma `[a, b, c, d]` en `[a, b, c]`.

### 5.4 Encoding de parametros

Cuando un parametro entero se emite como push:

| Rango | Encoding |
|---|---|
| 0 | OP_0 (0x00) |
| 1-16 | OP_1..OP_16 (0x51..0x60) |
| -1 | OP_1NEGATE (0x4f) |
| 17-75 | [0x01, byte] |
| 76-255 | PUSHDATA1 + 1 byte length |
| 256-65535 | PUSHDATA2 + 2 bytes length |
| > 65535 | PUSHDATA4 + 4 bytes length |

El compilador selecciona siempre la representacion minimal.

---

## 6. Algebra de Stack y Verificacion Simbolica

### 6.1 Configuracion de ejecucion

El estado de ejecucion en cualquier paso es el par:

> **C = (S, A)**
>
> S = [s0, s1, ..., sn-1] (main stack, s0 = top)
> A = [a0, a1, ..., ak-1] (alt stack)

Cada opcode **op** es una funcion parcial:

> **f_op: C -> C'**

### 6.2 Ejemplos de reescritura simbolica

**OP_DUP:**
```
S = [x, ...]  =>  S' = [x, x, ...]
```

**OP_PICK:**
```
S = [n, s0, s1, ..., sn, ...]  =>  S' = [sn, s0, s1, ..., sn, ...]
```

**OP_ROLL:**
```
S = [n, s0, s1, ..., sn, ...]  =>  S' = [s1, ..., sn, s0]
```

**OP_SWAP:**
```
S = [x, y, ...]  =>  S' = [y, x, ...]
```

### 6.3 Composicion de funciones

Para un macro M(n) que expande a `[op1, op2, ..., opk]`:

> **f_M(n) = f_opk o f_op(k-1) o ... o f_op1**

El compilador simboliza f_M(n) para verificar:
- Que la profundidad del stack nunca sea insuficiente
- Que el estado final del stack coincida con la postcondicion Q declarada
- Que la altura maxima del stack no exceda limites de consenso

### 6.4 Ejemplo de simulacion: OP_XSWAP_3

**Stack simbolico inicial:**
```
S = [x0, x1, x2, x3, ..., xn]
```

**Paso a paso:**
```
OP_2            -> [2, x0, x1, x2, x3, ..., xn]
OP_PICK         -> [x2, x0, x1, x2, x3, ..., xn]
OP_2            -> [2, x2, x0, x1, x2, x3, ..., xn]
OP_ROLL         -> [x0, x1, x2, x3, ..., xn, x2]  (wait, correction)
```

**Correccion del articulo:**
```
OP_2 OP_PICK    -> [x2, x0, x1, x2, x3, ..., xn]
OP_2 OP_ROLL    -> [x0, x1, x2, x3, ..., xn]  (x2 movido al top)
OP_SWAP         -> [x2, x1, x0, x3, ..., xn]
OP_DROP         -> [x2, x1, x3, ..., xn]
```

El motor simbolico rastrea cada transformacion intermedia y verifica que cada stack intermedio este bien formado.

### 6.5 Metadatos de tipo por macro

Cada macro lleva una especificacion de tipo:

> **M : P -> Q**

Donde P es el stack simbolico esperado antes de la expansion y Q es el stack despues. Esto funciona como un sistema de tipos sobre el stack, donde cada macro es un morfismo entre "tipos de stack".

---

## 7. Arquitectura del Compilador

### 7.1 La tabla de macros (𝓜)

Es un mapeo determinista y de solo lectura:

> **𝓜: Sigma -> <pi, rho>**

Cada entrada define un esquema de expansion. Ejemplo de entrada:

```
M["OP_XSWAP"] = (
    ["n"],
    lambda n: [PUSH(n-1), OP_PICK, PUSH(n-1), OP_ROLL, OP_SWAP, OP_DROP]
)
```

### 7.2 Algoritmo del expander (single-pass)

```
Expand(S) -> Omega+

Input: S = [t0, t1, ..., tn] (token stream)
Output: O (opcode stream)

1. Inicializar O = [], i = 0
2. Mientras i < len(S):
   a. t = S[i]
   b. Si t pertenece a Omega (opcode base):
      - Append t a O
      - i += 1
   c. Si t pertenece a Sigma (macro):
      - Recuperar <pi, rho> = M[t]
      - Leer los siguientes |pi| tokens: args = [S[i+1], ..., S[i+|pi|]]
      - Evaluar W = rho(args)
      - Append W a O
      - i += |pi| + 1
   d. Si no: raise UnboundTokenError(t)
3. Retornar O
```

### 7.3 Propiedades del expander

- **One-pass:** sin backtracking ni lookahead mas alla de la aridad del macro.
- **Stateless:** no hay program counter, branching condicional, ni variables globales.
- **Puro:** dado el mismo S y M, Expand(S) siempre produce el mismo O.
- **Oblivious a semantica:** el expander no simula la maquina Script; solo hace sustitucion sintactica.

### 7.4 Feature flags para multi-chain

El compilador puede targetear diferentes redes mediante flags:

- **@bsv:** habilita OP_CAT, OP_SPLIT, OP_NUM2BIN, etc.
- **@chronicle:** habilita OP_SUBSTR, OP_LSHIFTNUM, numeros de 32MB.
- **@btc_strict:** deshabilita opcodes no presentes en BTC; emite error si se usan.

Esto permite que el mismo source macro compile a bytecode valido para diferentes redes sin cambios de protocolo.

---

## 8. Higiene y Boundedness

### 8.1 Higiene (Hygiene)

El sistema de macros es higienico por construccion:

- **Scope aislado:** los parametros de un macro solo existen dentro de su template.
- **Sin fugas de nombres:** un parametro `n` en `OP_XSWAP` y otro `n` en `OP_XDROP` son completamente independientes.
- **Sin estado compartido:** no hay variables globales ni ambiente.
- **Sin recursion:** la tabla de macros es un DAG; ciclos se detectan estaticamente.
- **Evaluacion eager:** los argumentos se evaluan antes de pasarse al macro.

Esto garantiza **transparencia referencial:** la misma invocacion siempre expande al mismo opcode stream, independientemente del contexto circundante.

### 8.2 Boundedness (acotacion)

Toda expansion debe ser finita y acotada:

| Restriccion | Descripcion |
|---|---|
| **Sin recursion** | Macros no pueden invocarse a si mismos ni formar ciclos. |
| **Loops finitos** | `LOOP[n]` expande exactamente n copias; n debe ser literal entero. |
| **Script size** | Max 10,000 bytes (consenso BTC); 1GB (consenso BSV). |
| **Opcode count** | Max 201 (standard relay); ilimitado (consenso BSV). |
| **Stack height** | Max 1,000 elementos. |
| **Push size** | Max 520 bytes (policy); 32MB (Chronicle BSV). |

El compilador mantiene un **ledger de expansion** y aborta si cualquier limite se excede.

### 8.3 Terminacion garantizada

La expansion es un computo aciclico:
- Cada token se visita una sola vez.
- Cada sustitucion de macro es una funcion finita.
- No hay computo en runtime.
- El script de salida es finito, bien formado, y valido bajo opcodes legacy.

Por induccion estructural, el expander siempre termina para cualquier input valido.

---

## 9. Manejo de Errores

### 9.1 Filosofia: fail-fast, no undefined behavior

El compilador es una **funcion parcial que es total sobre el dominio valido**. Para todo input invalido, retorna ⊥ (rechazo) en lugar de emitir bytecode parcial o incorrecto.

> *"Es mejor no emitir nada que emitir un script que los mineros puedan rechazar."*

### 9.2 Categorias de error

| Error | Causa | Respuesta del compilador |
|---|---|---|
| **UnboundMacro** | Token no existe en 𝓜 | Abortar; sugerir macros similares (fuzzy match). |
| **ArityMismatch** | Numero incorrecto de argumentos | Abortar; diagnosticar esperado vs recibido. |
| **TypeError** | Argumento no entero, negativo donde no se permite, etc. | Abortar; especificar tipo esperado. |
| **TemplateError** | La plantilla evalua a opcodes invalidos o pushes malformados | Abortar; reportar macro y argumentos. |
| **OverflowError** | Script expandido excede 10KB (o policy limit) | Abortar; reportar tamano actual vs limite. |
| **StackError** | Stack excederia 1,000 elementos durante simulacion | Abortar; reportar opcode y profundidad. |

### 9.3 Modos de compilacion

- **Fail-fast (default):** se detiene en el primer error. Requerido para wallets en produccion.
- **Debug mode:** acumula todos los errores encontrados para ayudar al desarrollador.

### 9.4 Diagnosticos estructurados

```
{
    "error": "TemplateError",
    "message": "Invalid opcode OP_PUSH17 in expansion of macro XDROP(17)",
    "location": 48,
    "context": "XDROP(17)"
}
```

Esto permite integracion con CI/CD, testing automatizado, y auditoria independiente.

---

## 10. Implicaciones para BSV

### 10.1 Alineacion natural

El articulo esta escrito desde una perspectiva general de Bitcoin Script, pero es **maximamente compatible** con BSV:

| Caracteristica del articulo | Como BSV la potencia |
|---|---|
| Emision de opcodes legacy | BSV tiene todos los opcodes habilitados (incluyendo CAT, SPLIT, MUL, DIV). |
| Scripts de tamano arbitrario | BSV consenso permite hasta 1GB; policy tipicamente 10MB. |
| OP_CAT habilitado | BSV lo tiene nativo; no se necesita fallback de precalculo. |
| Numeros grandes | Chronicle (2026) eleva el limite a 32MB, permitiendo aritmetica masiva on-chain. |
| OTDA (0x20) | Mejora la robustez de preimages para PUSHTX, que es el siguiente paso despues de macros. |

### 10.2 Ventaja competitiva de BSV

En BTC, el macro system esta severamente limitado:
- OP_CAT deshabilitado -> OP_HASHCAT requiere precalculo off-chain.
- Script size 10KB -> loops desenrollados muy pequenos.
- Opcodes aritmeticos limitados -> no se pueden hacer calculos complejos.

En BSV, el mismo source macro puede expandir a scripts **ordenes de magnitud mas grandes y expresivos**, manteniendo la misma compatibilidad de validacion (el nodo sigue viendo solo opcodes legacy).

### 10.3 Casos de uso en BSV

- **Tokens PELS:** El script se replica a si mismo en cada gasto; macros generan la logica de replicacion.
- **Covenants:** Verificacion de outputs usando PUSHTX; macros construyen el preimage byte a byte.
- **Verificacion STARK:** Numeros de 32MB permiten verificar pruebas de conocimiento cero directamente en Script.
- **DRM on-chain:** Content Covenant + License Covenant con reglas de transferencia perpetuas.

---

## 11. Critica y Limitaciones

### 11.1 Limitaciones inherentes al modelo

1. **Input debe ser conocido en compile-time:** Si un parametro depende de datos solo disponibles en runtime (ej. altura de bloque actual), no puede ser argumento de un macro. Debe manejarse via `nLockTime` o logica condicional en Script (IF/ELSE), no en macros.

2. **Explosion de tamano:** Un loop con bound grande genera un script masivo. En BTC esto es impracticable; en BSV es viable pero costoso en fees.

3. **No reemplaza PUSHTX:** Los macros abstracen la manipulacion del stack, pero PUSHTX (firma in-script que ve la transaccion) requiere construccion byte-a-byte del preimage. Los macros pueden *ayudar* a generar ese bytecode, pero no eliminan la complejidad.

4. **Curva de aprendizaje:** Escribir macros correctos requiere entender el algebra de stack. No es "Solidity facil"; es un modelo de computacion diferente.

### 11.2 Limitaciones del articulo

- **Sin implementacion concreta:** El articulo es teorico. No hay codigo fuente, repositorio, ni benchmarks.
- **Sin tratamiento de OP_IF/ELSE:** El articulo menciona que el flujo condicional de Script (IF/ELSE) es estatico, pero no explica como los macros interactuan con ramas condicionales.
- **Sin analisis de costo:** No discute cuanto mas caro (en satoshis/byte) es un script desenrollado vs uno dinamico.
- **Sin referencia a sCrypt:** sCrypt ya hace algo muy similar (transpilacion de TypeScript a Script). El articulo no contrasta su approach con sCrypt.

### 11.3 Comparacion con sCrypt

| Aspecto | Macro Expansion (articulo) | sCrypt |
|---|---|---|
| **Lenguaje fuente** | DSL macro minimalista | TypeScript con decoradores |
| **Compilador** | Wallet-side, single-pass | scrypt-ts (transpilador) |
| **Output** | Opcode stream plano | Opcode stream plano |
| **Verificacion** | Stack algebra simbolica | Type checking de TS + simulacion |
| **Loops** | Unrolling estatico | Unrolling estatico |
| **Estado** | Embebido en script (code+data) | Embebido en script (code+data) |
| **Madurez** | Teorico / blueprint | Produccion (usado activamente) |

El articulo es valioso como **fundamentacion teorica** y como **especificacion de un compilador minimalista**, pero sCrypt ya cubre la necesidad practica en el ecosistema BSV.

---

## 12. Conclusiones

### 12.1 Lo que el articulo logra

1. **Formaliza Bitcoin Script como 2PDA:** Demuestra rigurosamente que Script no es "subpotenciado", sino intencionalmente total sobre un espacio finito.

2. **Define un modelo de compilacion wallet-side:** Muestra que toda la complejidad puede trasladarse al wallet sin tocar el protocolo.

3. **Propone una familia canonica de macros:** XSWAP, XDROP, XROT, HASHCAT, LOOP son suficientes para expresar la mayoria de las manipulaciones de stack requeridas en contratos.

4. **Establece invariantes de seguridad:** Higiene, boundedness, determinismo, y fail-fast son no negociables.

5. **Conecta con teoria de compiladores:** Stack algebra, precondiciones/postcondiciones, y pruebas de composicion son herramientas estandar de compiladores formales aplicadas a Bitcoin.

### 12.2 Lo que significa para desarrolladores BSV

- **No necesitas esperar forks:** Puedes escribir contratos complejos hoy, usando solo opcodes de 2009.
- **El wallet es tu compilador:** Invierte en tooling wallet-side, no en lobbying por nuevos opcodes.
- **Los macros son bloques de construccion:** La familia canonica del articulo + los bloques de tu guia anterior = un toolkit completo.
- **Chronicle amplifica el modelo:** Con 32MB de script numbers y opcodes restaurados, los scripts desenrollados pueden ser mucho mas expresivos.

### 12.3 Citas clave

> *"Bitcoin Script, when viewed as a two-stack push-down automaton, is computationally equivalent to a universal Turing machine — provided all control flow is statically bounded and unrolled."*

> *"You write the loop once, but emit it many times — fully expanded, and verifiable by the node interpreter as a static script."*

> *"The wallet becomes the domain for symbolic computation. The node remains a deterministic verifier of finite acyclic state transitions."*

> *"By relocating complexity to the wallet compiler and leaving miners to validate only austere, legacy opcodes, the scheme reconciles expressive contract engineering with the immutability of the original protocol."*

---

*Documento de analisis generado a partir del articulo "Macro Expansion in Bitcoin Script" publicado en Substack.*
*Este resumen busca hacer accesible un texto denso y formal, manteniendo la rigurosidad tecnica del original.*
