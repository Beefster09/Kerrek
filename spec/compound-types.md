
# Maps

Maps represent key-value mappings between any two values.

- The zero value is the empty map (not `nil`)
- Keys must be value types supporting the `==` operator; pointers are not allowed as keys
- Maps are reference types supporting `owned`, `shared`, `weak`, and borrow ownership classes
- Get operations must be O(1) in all cases
- Put and Delete operations must be O(1) assuming storage does not need to be reallocated
- Maps may reallocate their backing storage any time an element is added
- The implementation may choose either a hash table or an enumerated array depending on the key and value types

# Static Arrays

Static arrays have a compile-time known length. This allows them to be value types.

```kerrek
[3]Integer
[SOME_CONSTANT]String
[TWO + CONSTANTS]Decimal(12,3)
[1 + TWO]Boolean
```

# Dimensioned Arrays (Slices)
# Dynamic Arrays

# Struct Types

`struct` defines a record type, a.k.a. a product type

The zero value of a struct is defined if and only if all of its fields have a type with a defined zero value

Structs support equality if and only if all of its fields are of types supporting equality

The compiler is free to reorder struct fields unless you annotate the struct definition with a `@layout` annotation

```
@layout("C")
struct SomethingINeedForACLibrary {
	\\ ...
}

@layout("COBOL")
struct VeryImportantFinancialData {
	\\ ...
}
```

If the compiler doesn't understand the specific layout requested, it *must* emit an error.

# Enum Types

`enum` defines a list of values or a tagged union a.k.a. sum type

Each item in the list of variants may carry *one* type as its payload. You may also define a variant without a name as long as it has a typed payload. Specifying multiple unnamed variants of the same type is invalid.

```kerrek
enum Game {
	Rock,
	Paper(Integer),
	(Scissors),
}
```

By default, an enum does not have a zero value. If you would like it to have a zero value, you must explicitly assign a variant to slot 0.

```kerrek
enum Bar {
	Nothing = 0,
	Something,
	WhoCares,
	Potato,
}
```

Each variant with an assigned slot must be assigned a different integer slot. Numeric slots may be negative. The tag stored to identify which variant the value is *must* be large enough to hold the largest explicit slot number

All other variants are assigned arbitrary unique positive slots. Programmers should not depend on variants having specific slot numbers unless they are explicitly assigned.

Enums support equality if and only if all of its variants with payloads are types supporting equality

You can test which variant an enum value is via `switch` statements and the `is` operator

Enums do not support ordering comparison operators.
