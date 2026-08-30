# DSL Grammar (EBNF)

```ebnf
script          = statement_list, EOF;
statement_list  = statement, { ";", statement }, [ ";" ];
statement       = opcode_literal
                | macro_invocation
                | loop_block
                | conditional
                | compile_error
                | block;

opcode_literal  = "OP_", identifier;
macro_invocation= identifier, [ "[", arg_list, "]" ], [ "{", body, "}" ];
loop_block      = "LOOP", "[", integer, "]", "{", body, "}";
conditional     = "@", flag, "{", body, "}", [ "else", "{", body, "}" ];
compile_error   = "@compileError", "(", string, ")";

flag            = "era", "(", era, ")"
                | "has", "(", feature, ")"
                | "limit", "(", limit_kind, ",", magnitude, ")"
                | "network", "(", network, ")"
                | "standardness", "(", std_flag, ")"
                | "version", "[", integer, "]"
                | "bsv" | "chronicle" | "btc_strict";

arg_list        = arg, { ",", arg };
arg             = integer | string | opcode_literal | iterator_var;
body            = statement_list;

magnitude       = integer, [ ("K"|"M"|"G"|"KB"|"MB"|"GB") ];
integer         = [ "-" ], digit, { digit };
string          = hex_string | quoted_string;
hex_string      = "0x", hex_digit, { hex_digit };
quoted_string   = '"', { character - '"' }, '"';
identifier      = letter, { letter | digit | "_" };
iterator_var    = "<", identifier, ">";

era             = "satoshi" | "bip" | "bch" | "bsv_pre_genesis" | "genesis" | "chronicle";
feature         = identifier;
limit_kind      = "push" | "script" | "opcodes" | "stack";
network         = "btc_mainnet" | "btc_testnet" | "bch_mainnet" | "bch_testnet"
                | "bsv_mainnet" | "bsv_testnet" | "bsv_regtest";
std_flag        = "dersig" | "low_s" | "forkid" | "cleanstack" | "nulldummy"
                | "sigpushonly" | "minimaldata" | "minimalif";
```

## Flag semantics

Flags are pure predicates evaluated against `CompileOptions`. The chosen
branch is expanded; the other is discarded entirely (a `@compileError` in a
dead branch never fires).

| Directive | Evaluates true when |
|---|---|
| `@era(e)` | the effective era equals `e` (exact match). Effective era = `options.era` ?? `eraFromBlockHeightForNetwork(block_height, network ?? target)` ?? `defaultEraForNetwork(network ?? target)`. Height→era is network-aware: BTC never leaves `bip`, BCH caps at `bch`, only BSV reaches `bsv_pre_genesis`/`genesis`/`chronicle` |
| `@has(f)` | the effective feature set contains `f`. The feature set is `options.features` OR-ed with `featuresForEra(effective_era)`, plus `bsv`/`btc_strict` derived from the network. Unknown names emit a warning and evaluate to false |
| `@limit(kind, n)` | the effective limit of `kind` is `>= n`. Legacy `max_script_size`/`max_stack_elements`/`max_push_size` override `limits.script`/`limits.stack`/`limits.push` when non-default |
| `@network(net)` | the effective network equals `net` (`options.network` wins over legacy `target`) |
| `@standardness(f)` | `options.standardness.f` is set (predicate only; no structural validation) |
| `@version[N]` | `options.protocol_version >= N` |
| `@bsv` | legacy: the effective network is any BSV network |
| `@chronicle` | legacy: the effective era is `chronicle` (no longer an alias of `@bsv`) |
| `@btc_strict` | legacy: the effective network is a BTC network |
| `@compileError("msg")` | statement, not a conditional: always fails expansion with `ExpandError.CompileError` when reached |

Era boundaries (mainnet heights): satoshi 0–173,804 · bip 173,805–478,557 ·
bch 478,558–556,766 · bsv_pre_genesis 556,767–620,537 · genesis
620,538–943,815 · chronicle 943,816+.
