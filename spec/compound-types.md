
# Static Arrays

Static arrays have a compile-time known length. This allows them to be value types.

```kerrek
[3]Integer(12)
[SOME_CONSTANT]String
[TWO + CONSTANTS]Decimal(12,3)
[1 + TWO]Boolean
```

# Views

A view is a 1- to 16- dimensional view into somewhere else in memory

```
[]Int64           \\ 1-dimensional borrowed view
[shared]Int64     \\ 1-dimensional shared view
[#1; weak]Int64   \\ 1-dimensional weak view; alternate spelling
[#2]Pixel         \\ 2-dimensional borrowed view
[#3; owned]Block  \\ 3-dimensional owned view
```

You may create owned and shared views into heap memory under one of the following two conditions:
- The element type has a well-defined zero value
- All element values are specified

Slicing can only produce a weak or borrowed view

# Dynamic Arrays

Dynamic arrays are one-dimensional dynamically resizable arrays

```
[dynamic]Decimal(15, 5)
[dynamic]String
```

Dynamic arrays cannot change size while a borrow pointer alias of any of its elements exists, as the resize may invalidate the pointer.

# Maps

Maps represent key-value mappings between any two values.

- The zero value is the empty map (not `nil`)
- Keys must be value types supporting the `==` operator; pointers are not allowed as keys
- Maps are considered uniquely owned.
	- If you want to pass maps around, you need to pass them by pointer or by move
- Get operations must be O(1) in all cases
- Put and Delete operations must be O(1) assuming storage does not need to be reallocated
- Maps may reallocate their backing storage any time an element is added
- The implementation may choose either a hash table or an enumerated array depending on the key and value types

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
	Paper(Integer(3)),
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

All other variants are assigned arbitrary unique positive slots. Users should not depend on variants having specific slot numbers unless they are explicitly assigned.

Enums support equality if and only if all of its variants with payloads are types supporting equality

You can test which variant an enum value is via `switch` statements and the `is` operator

Enums do not support ordering comparison operators.
