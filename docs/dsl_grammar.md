# DSL Grammar (EBNF)

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
arg             = integer | string | opcode_literal;
body            = statement_list;

integer         = [ "-" ], digit, { digit };
string          = hex_string | quoted_string;
hex_string      = "0x", hex_digit, { hex_digit };
quoted_string   = '"', { character - '"' }, '"';
identifier      = letter, { letter | digit | "_" };
```
