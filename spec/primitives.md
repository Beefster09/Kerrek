# Primitive Types

This document outlines the expected observable semantics of each primitive type.

# Numeric Types

Numeric types support all standard mathematical operators

The zero value is as you would expect, which must be represented as all bits set to zero

All numeric types may be explicitly converted between one another via casts

Numeric types additionally support all implicit conversions which can losslessly represent all possible values of the original type

## Compile-time numerics

Numbers at compile time should be stored as losslessly as possible (e.g. rationals/BigRat/Fraction) and only truncated when the destination demands a concrete type.

## Integers

- `Integer`: High-range integer able to hold at least 35 decimal digits, positive or negative
	- Its inline size must not be larger than 256 bits (32 bytes) even if the value itself is stored in heap memory
	- A fully zeroed inline value must be semantically zero
	- overflow may, in order of preference: allocate an arbitrary-sized integer to hold the value, saturate, or panic; it *must not* wrap
	- for all practical intents and purposes, an `Integer` has the semantics of an unbounded mathematical integer.
- Sized integers behave as expected for machine integers
	- overflow and underflow *must* wrap for sized integers, as that is the behavior most commonly expected for machine integers

### Operator Semantics

All mathematical operators except for `/` are defined for integers.

The operator you are looking for is `//`, the floor-division operator. Requiring you to opt into floor division instead of silently truncating helps to prevent subtle logic bugs and surprises.

Division by zero emits a ZeroDivisionError which must be handled unless the divisor is known not to be zero.

## Decimals

The Decimal types are:
- `Decimal`: High-precision decimal able to hold at least 30 significant decimal digits with an exponent able to represent at least +-100 orders of magnitude; plus NaN and +-Infinity
	- Its inline size must not exceed 256 bits (32 bytes) even if the value itself is stored in heap memory or similar.
	- A fully zeroed inline value must be semantically zero
- `Dec64`: exactly 64 bits, representing at least all possible values represented by IEEE decimal64
- `Dec32`: exactly 32 bits, representing at least all possible values represented by IEEE decimal32

## Floats

Floats are inaccessible in the default namespace and exposed via `intrinsics:float`

# Non-Numeric Types

These types do not support any form of implicit conversion between each other

## Boolean

Has two values, `true` and `false`, following all standard expectations of boolean logic

The zero value is `false`

Booleans within structs may be no larger than 8 bits

### Operator Semantics

Booleans support equality operators, but not the other four comparison operators

They also support multiplication with any other type with a well-defined and valid zero value:

- true + X -> X
- X + true -> X
- false + X -> (the zero value of the same type as X)
- X + false -> (the zero value of the same type as X)

## String

Strings have value semantics and behave like values under all conditions which do not sidestep normal safety guarantees. Whether that is managed via small string optimization, immutability, or aggressive copying is considered an implementation detail, however implementations *should* aim to optimize Strings as much as possible. The exact tradeoffs made over minimizing copying vs avoiding keeping large string buffers alive is left to the implementation.

- The zero value is the empty string, and a fully zeroed struct representing a string value must be an empty string.
	- fully-zero does not need to be the only possible representation of the empty string
- Strings are UTF-8 encoded.
- Strings may contain null bytes.
- Strings may contain invalid UTF-8 sequences.
- Two Strings are considered equal if they are the same length and contain the same sequence of bytes
- Iterating over a string *must* yield runes at each step, and must return each rune in the string.
	- If any invalid UTF-8 sequences are encountered during iteration, the Unicode replacement character (U+FFFD) should be yielded
- An index n into a string corresponds to the nth UTF-8 byte, and the return value of said indexing operation is of type Byte
- The result of `len` corresponds to the size of the buffer, not the number of codepoints in a string.
- String slicing *may* create a copy of part of the string buffer
- String slicing which does not copy *must* ensure the source buffer outlives the slice
- String concatenation via the `+` operator is only allowed at compile-time for string values known at compile time.

## Rune

A rune represents a single unicode codepoint and must be able to represent, at minimum, values from U+0000 to U+10FFFF, inclusive

The zero value is U+0000

Runes must not be larger than 32 bits

### Operator Semantics

Runes are fully comparable, supporting all six comparison operators.

Additionally, the following mathematical operators are defined:
- Rune - Rune -> Integer
- Rune + Integer -> Rune
- Integer + Rune -> Rune

All other operations are not allowed


## Byte

A byte is a single 8-bit value without numeric semantics. It can be converted to and from numeric types and accepts both integer and rune literals (and folded constants) within range, but does not support any operators besides `==` and `!=`.

The zero value is 0x00

# Truthiness

Of the primitive types, only booleans are allowed in contexts that require booleans.

Pointers and optionals additionally implicitly convert to boolean based on whether the pointer/optional is nil.
