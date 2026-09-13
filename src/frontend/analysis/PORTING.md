# Semantic analysis porting plan

The Python implementation in `pykerrek/frontend/analysis.py`, `exprs.py`, and
`types.py` is a behavioral reference, not an architecture that must be copied.
The Odin implementation should preserve its useful diagnostics and language
rules while taking advantage of explicit arenas, tagged unions, and the
resolver's linked scope chain.

## Boundary between resolution and analysis

The resolver owns partial symbols and lexical scopes. The HIR owns fully
analyzed declarations, types, expressions, and statements. Resolver symbols
hold typed links to their completed HIR nodes so references can be joined
without a second symbol table or `rawptr` casts.

`resolver.Scope` is a linked chain:

```text
body/block scope -> function scope -> file
```

Analysis routines should receive one `^resolver.Scope`. Entering a function or
block allocates a child scope whose `parent` points at the current scope (or at
the defining file for a function's root scope). This replaces the Python
`*scopes` convention. It makes lookup cost proportional to lexical depth, keeps
call frames small, and makes the ownership/lifetime of each lexical environment
explicit.

Points to settle while implementing scopes:

- ~~Decide whether parameters and named returns share the function scope. Sharing
  catches collisions directly; separate chained scopes can encode intentional
  shadowing if the language permits it.~~
    - named returns are only visible to `with defer` expressions (not yet defined in the function HIR or AST)
    - parameters are in a separate scope from the main function body. Each enclosed block (except those within `\if`) produces a new scope. This is the same semantics as Odin itself, and I think is the overall correct design.
    - shadowing symbols from outer scopes is always allowed and produces a warning diagnostic if it's not simply aliasing a symbol of the same name from an outer scope
    - shadowing is allowed; duplicate symbols in the same scope are not
- Define whether a local is visible in its own initializer and whether block
  declarations become visible sequentially or for the whole block.
    - `let` and `const` declarations: the name is not visible until after the value evaluates. This allows them to shadow and copy values from outer scopes by the same name
    - `func` declarations: the name is visible immediately so that recursion is possible
- Allocate scope maps and scope nodes from the resolver/analysis arena. Never
  retain a pointer to a stack-created scope.
- Add `push_scope(parent)` and `define_local(scope, symbol)` helpers so map
  initialization, shadowing diagnostics, and parent wiring have one policy.
- Keep package/file lookup as the terminal parent operation. Builtin fallback
  should have one well-defined place rather than being repeated by analysis.

## Open representation choices

- Named returns currently resolve to `resolver.Named_Return`, but the ported
  `hir.Func_Return` is only signature metadata, not a variable-like HIR symbol.
  Before exposing named returns in bodies, either give return slots symbol
  identity or lower them to ordinary implicit locals with a return-slot marker.
- Capability expressions remain opaque in HIR, matching the Python prototype.
  When capability analysis starts, replace that placeholder with resolved
  named/all/any nodes rather than retaining AST qualified names.
- `Type_With_Args` has syntax but no direct HIR node. Decide whether it denotes
  generic instantiation, type construction, or both, then represent its
  canonical type separately from any runtime constructor expression.
- Several aggregate/interface nodes are ahead of parser support. Keep them in
  the HIR vocabulary, but add semantic construction only when their AST forms
  and rules are stable enough to test.
- Decide whether invalid-but-recovered constructs get explicit poison HIR nodes
  or are omitted. Explicit poison generally improves diagnostic recovery but
  must be rejected by validation before lowering.

## Suggested passes

### 1. Declaration graph and state

Keep the resolver's eager top-level symbol collection. Replace the current
`processed: bool` with a state such as `Unseen`, `Processing`, `Done`, and
`Failed` before recursive semantic processing is ported. Encountering
`Processing` is a dependency cycle; `Failed` prevents duplicate diagnostics and
partially initialized HIR from being reused.

Create and cache stable HIR declaration nodes before descending when recursive
references are legal. Fill their bodies/signatures afterward. Store all HIR
nodes and their backing slices in a translation-unit arena.

### 2. Declaration signatures

Port unit types, base units, aliases, capabilities, annotations, type
definitions, global signatures, and function signatures before function bodies.
This pass should:

- resolve every named type and tag;
- canonicalize aliases while retaining source-facing names where reflection or
  diagnostics need them;
- create parameter and named-return symbols in the function scope;
- validate defaults and annotation arguments as compile-time expressions;
- record, but not yet enforce, capability requirements; and
- choose the entry point and validate its signature.

Doing signatures as a distinct step avoids making source order determine which
function calls can be typed.

### 3. Compile-time values and units

Port the flexible literal/value model from `exprs.py` as its own small module.
Keep "not materialized yet" values separate from HIR constants: flexible
integer/decimal/nil/zero values need an expected type and unit before they can
become a `hir.Const_Expr`.

Use `units.Compound_Unit` as the canonical realized representation. Important
cases to cover explicitly are flexible units, explicit no-unit, absolute versus
relative units, conversion factors that cannot be represented exactly, and
aliases whose expansion is cyclic.

### 4. Expression analysis

Use a context record rather than a long parameter list. Likely fields are the
current scope, expected type(s), expected unit(s), value category (read/place),
and whether compile-time evaluation is required.

Return a result that can distinguish one value, multiple values, flexible
compile-time values, and an error/poison result. Avoid using `nil` for every
failure mode: it loses whether a diagnostic was already emitted and tends to
produce cascades.

Port expression families in this order:

1. literals, names, moves, and parentheses;
2. unary/binary operators and contextual literal materialization;
3. casts, unit conversions, and reinterpretation;
4. calls, overload selection, named/default arguments, and multi-return values;
5. field access, indexing, enum construction, and aggregate construction.

Overload selection should rank candidates without mutating the final HIR. Once
a unique candidate wins, materialize conversions and commit its HIR nodes.

### 5. Statements and bodies

Create the function scope once, then push a child scope for every lexical block.
Build statements in source order and append successfully recovered poison nodes
or skip invalid nodes according to one documented recovery policy. Check return
arity/types/units against the current function signature, and make implicit
default initialization explicit as `Zero_Of` in HIR.

Track control-flow facts needed during analysis (for example, whether a block
definitely returns) separately from the HIR node layout. Ownership, move, and
borrow validation may eventually want a CFG; do not force those checks into the
recursive AST walk if the MIR is the more natural representation.

### 6. Validation and lowering handoff

Run a cheap HIR validator even after analysis succeeds. It should assert that:

- every reachable symbol reference points to a completed HIR declaration;
- single-value nodes have one type/unit and call result arrays have matching
  lengths;
- no unresolved/flexible type or inferred unit reaches lowering;
- assignment destinations are writable;
- fallibility/error types and returns agree with function signatures; and
- all slices and pointers belong to storage that outlives lowering.

Only validated HIR should be accepted by MIR lowering.

## Initial implementation milestones

1. Add analysis context/arena initialization and translation-unit map setup.
2. Port unit type, base unit, alias, and primitive/simple type analysis.
3. Port function signatures and linked function/body scope construction.
4. Port literal/name expression analysis and local/global variables.
5. Port operators, conversions, calls, and return checking.
6. Add annotations/capabilities and the remaining aggregate type nodes.
7. Add HIR validation, then begin MIR lowering against the Odin HIR.

Each milestone should have parser-to-HIR tests that inspect symbol identity,
resolved types, realized units, and diagnostics. Add focused tests for nested
scope shadowing, same-name siblings, parameter/local collisions, forward
references, and dependency cycles before broad end-to-end fixtures.
