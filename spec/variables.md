# Variables

`let` declares a runtime variable

Variable declarations may omit their type if they have been assigned an initial value

Variable declarations may omit their initial value if they are given a type with a well-defined zero value

You may also defer variable initialization using the ellipsis `...` as long as you have declared a type, which may be necessary if its type doesn't have a well-defined zero value. It is an error to access the variable if it might possibly be unbound.

```kerrek
let inferred = 123;
let zeroable: Integer;
let uninitialized: SomeEnum = ...;
```

## Type inference with flexibly typed values

- A plain numeric literal in hex, octal, or binary is inferred as `UInt64`
- An expression made of integer literals and no fractional division (floor division is ok) is inferred as `Integer`
- Hexfloats and numbers with an `f` suffix are inferred as `Float64`
	- Using these literals without first importing `intrinsics:float` should emit a warning
- Any other numeric value is inferred as `Decimal` (the floating point decimal version, not some arbitrary fixed point decimal type)
- String literals are inferred as `String`
- Rune literals are inferred as `Rune`
- `true` and `false` are inferred as `Boolean`
- `nil` cannot possibly imply a singular type and therefore must trigger a compiler error

# Constants

`const` declares a compile-time known constant

Constants *may* be omit their type, meaning their value will implicitly flex into whatever type is needed as long as it is compatible with the destination unless the value expression evaluates to a singular well-defined type. If the constant value needs to be used to infer a type, then the inferred type should be the same as if the constant were replaced with the expression that defines its value

```kerrek
const PI = 3.141592653589793238;
const FLASK = "You can't get ye flask";
```
