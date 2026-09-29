---
title: DSL grammar
section: 12
version: 0.189
status: draft
normative: true
depends_on: [16-static-semantics.md]
---

# 12. Grammar

This section defines which texts parse. [§16](16-static-semantics.md) defines which parsed scenarios are valid.
```ebnf
ScenarioFile     ::= ImportDecl* VehicleSpecDecl* (ComponentDecl | FnDecl)* ScenarioDecl
ImportDecl       ::= "use" Ident ("::" Ident)* "::" "{" IdentList "}" ";"
VehicleSpecDecl  ::= "vehicle_spec" Ident "{" (Ident "=" Expr ";")* "}"

ComponentDecl    ::= "component" Ident FmuClause? RateClause? TierClause? ":" "(" PortList? ")" "->" TypeSpec (Block | ";")
FmuClause        ::= "from_fmu" "(" StringLit ")"
RateClause       ::= "(" "rate" ":" FreqLit ")"
TierClause       ::= "(" "required_tier" ":" IntLit ")"
PortList         ::= PortDecl ("," PortDecl)*
PortDecl         ::= Ident ":" TypeSpec
TypeSpec         ::= Ident ("<" TypeArg ("," TypeArg)* ">")?
TypeArg          ::= TypeSpec | IntLit | "(" ")"

FnDecl           ::= "fn" Ident "(" PortList? ")" "->" TypeSpec "{" "return" PipeExpr ";" "}"
Block            ::= "{" (ParamDecl | BindInputsBlock | BindOutputsBlock | StepBlock)* "}"
ParamDecl        ::= "param" Ident ":" TypeSpec "=" Expr ";"
BindInputsBlock  ::= "bind_inputs" "{" (StringLit "=" Expr ";")* "}"
BindOutputsBlock ::= "bind_outputs" "->" TypeSpec "{" (Ident "=" Expr ";")* "}"
StepBlock        ::= "step" "(" PortList ")" "->" TypeSpec "{" Stmt* "}"

ScenarioDecl     ::= "scenario" Ident "{" WorldStmt* ActorDecl* BindStmt* EventStmt* TerminateStmt "}"
WorldStmt        ::= ("map" "=" Expr ";") | ("timestep" "=" TimeLit ";") | ("seed" "=" IntLit ";") | EnvBlock
EnvBlock         ::= "environment" "{" (Ident "=" Expr ";" | CallExpr ";")* "}"

ActorDecl        ::= "actor" Ident "=" CallExpr ("with" ActorBody)? ";"
ActorBody        ::= "{" PriorsBlock? SensorsBlock? ChainDecl* PhysicsDecl? "}"
PriorsBlock      ::= "priors" "{" (Ident "=" Expr ";")* "}"
SensorsBlock     ::= "sensors" "{" (Ident "=" CallExpr ";")* "}"
ChainDecl        ::= "chain" Ident "=" PipeExpr ";"
PhysicsDecl      ::= "physics" "=" PipeExpr ";"

BindStmt         ::= "bind" ("[" IdentList "]" | Ident) "->" PipeExpr ";"
PipeExpr         ::= PrimaryPipe (">>" PrimaryPipe)*
PrimaryPipe      ::= CallExpr | "(" PipeExpr ("+" PipeExpr)* ")" | ArbitrateExpr | Ident
ArbitrateExpr    ::= "Arbitrate" "(" PipeExpr "," PipeExpr "," "via" ":" CallExpr ")"
EventStmt        ::= "on" "(" Expr ")" "{" SpliceStmt+ "}"
SpliceStmt       ::= "splice" Ident "." Ident "=" PipeExpr ";"
TerminateStmt    ::= "terminate" "when" "(" Expr ")" ";"

Stmt             ::= LetStmt | IfStmt | ReturnStmt
LetStmt          ::= "let" Ident "=" Expr ";"
IfStmt           ::= "if" Expr "{" Stmt* "}" ("else" "{" Stmt* "}")?
ReturnStmt       ::= "return" Expr ";"

Expr             ::= AndExpr ("or" AndExpr)*
AndExpr          ::= NotExpr ("and" NotExpr)*
NotExpr          ::= "not" NotExpr | CmpExpr
CmpExpr          ::= AddExpr (("<" | "<=" | ">" | ">=" | "==" | "!=") AddExpr)?
AddExpr          ::= MulExpr (("+" | "-") MulExpr)*
MulExpr          ::= UnaryExpr (("*" | "/") UnaryExpr)*
UnaryExpr        ::= "-" UnaryExpr | PostfixExpr
PostfixExpr      ::= PrimaryExpr ("." Ident | "(" ArgList? ")" | "[" Expr "]")*
PrimaryExpr      ::= Literal | ScopedIdent | "(" Expr ")" | ArrayLit | RecordLit | "any"
ArrayLit         ::= "[" (Expr ("," Expr)*)? "]"
RecordLit        ::= "{" (Ident ":" Expr ("," Ident ":" Expr)*)? "}"
CallExpr         ::= ScopedIdent "(" ArgList? ")"
ArgList          ::= Arg ("," Arg)*
Arg              ::= (Ident ":")? Expr
ScopedIdent      ::= Ident ("::" Ident)*
IdentList        ::= Ident ("," Ident)*
Literal          ::= QuantityLit | FloatLit | HexLit | IntLit | StringLit | BoolLit
BoolLit          ::= "true" | "false"
```

**Lexical Rules:**
* `Ident` is `[A-Za-z_][A-Za-z0-9_]*` and is not a reserved word. The reserved words are `use`, `fn`, `component`, `scenario`, `actor`, `let`, `if`, `else`, `return`, `or`, `and`, `not`, `true`, `false`, `any`, and `Arbitrate`. Every other quoted word in the grammar is a contextual keyword. It is a keyword only where the grammar expects it and is an `Ident` elsewhere, so `rate: 20Hz` in a sensor call and `std::physics` in an import are valid.
* `IntLit` is `[0-9]+`. `HexLit` is `0x[0-9A-Fa-f]+`. `FloatLit` is `[0-9]+ "." [0-9]+`. `StringLit` is a double-quoted string with `\"` and `\\` escapes.
* `QuantityLit ::= (FloatLit | IntLit) UnitExpr`, with no whitespace anywhere inside it. `UnitExpr ::= UnitAtom (("*" | "/") UnitAtom)*` and `UnitAtom ::= UnitName ("^" [0-9]+)?`. A `UnitExpr` applies `*` and `/` left to right, so `N*s/m` is N·s/m and `N/m*s` is also N·s/m. `UnitName` is one of `m`, `s`, `ms`, `us`, `ns`, `kg`, `N`, `Pa`, `rad`, `deg`, `Hz`. The lexer takes the longest match for every token, so `0x03` is one `HexLit`, and a `QuantityLit` must not be followed directly by a letter, digit, or `_`. The lexer does not backtrack, so `3.0m/speed` is a lexical error. So `0.45rad/s` and `2850.0kg*m^2` are single tokens. To divide a quantity by a variable named `s`, write spaces: `2.0m / s`.
* `FreqLit` is a `QuantityLit` whose `UnitExpr` is exactly the atom `Hz`. `TimeLit` is a `QuantityLit` whose `UnitExpr` is exactly one of the atoms `s`, `ms`, `us`, or `ns`, with no exponent or operator.
* `//` starts a comment that runs to the end of the line. Whitespace separates tokens and is otherwise ignored.
