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
	- Its inline size must not be larger than 40 bytes even if the value itself is stored in heap memory
	- A fully zeroed inline value must be semantically zero
	- overflow/underflow may allocate an arbitrary-sized integer to hold the value
	- if it does not, an `OverflowError` should be omitted, which will panic if not handled
	- for all practical intents and purposes, an `Integer` has the semantics of an unbounded mathematical integer, but it is *not guaranteed* to be an arbitrary precision integer that never overflows (and technically BigInteger implementations have a limit too, it's just that you'll practically never reach it)
		- If you need a type that is guaranteed to be arbitrary precision, for instance in cryptographic code, use `core:math/bigint`
	- The compiler may use a smaller machine integer if it can prove that would never overflow
- Sized integers (`Int64`, `UInt32`, etc...) behave as expected for machine integers
	- overflow and underflow wrap by default for sized integers, as that is the behavior most commonly expected for machine integers

### Operator Semantics

All mathematical operators except for `/` are defined for integers. The operator you are looking for is `//`, the floor-division operator. Requiring you to opt into floor division instead of silently truncating helps to prevent subtle logic bugs and surprises.

Division by zero emits a `ZeroDivisionError` which panics by default

## Decimals

The Decimal types are:
- `Decimal(d, p)`: Signed fixed point decimal with enough storage for at least `d` significant  digits and exactly `p` of those digits after the decimal point
	- Overflow and underflow outside the predetermined range must trigger an `OverflowError` even if the underlying storage could hold the new value.
	- `d` must be a compile-time known positive integer
	- `p` must be a compile-time known integer < `d` (negative is well-defined albeit not useful)
	- The compiler must support up to 30 significant digits at minimum
	- The overall size of the value may be no larger than the smallest multiple of whatever the pointer size is on the target hardware that can hold the number of requested digits
	- The storage must be inline when applicable (e.g. structs, enums, stack if possible)
	- When `p == 0`, the value may implicitly convert to `Integer`
- `Decimal`: High-precision floating point decimal able to hold at least 30 significant decimal digits with an exponent able to represent at least +-100 orders of magnitude; plus NaN and +-Infinity
	- Its inline size must not exceed 40 bytes even if the value itself is stored in heap memory or similar.
	- A fully zeroed inline value must be semantically zero
	- an IEEE decimal128 conforms to these requirements
- `Dec64`: IEEE decimal64 or semantic equivalent that fits in 64 bits
- `Dec32`: IEEE decimal32 or semantic equivalent that fits in 32 bits

## Binary Floats

Floats are inaccessible in the default namespace and exposed via `intrinsics:floats`. As useful as they are, they have some non-obvious subtleties to them which trip up many programmers and silently make programs incorrect. By placing them out of reach of the default namespace, it helps to add some friction so that programmers are more inclined to reach for the tools that are more likely to be correct. Use floats only when you know for sure you need them.

This exposes two types:

- `Float64`
- `Float32`

these may be renamed to `BinFloat64` and `BinFloat32` before version 1.0 to further reinforce the fact that they have some surprising semantics and point out that the floating point is, in fact, a binary point between binary digits rather than a decimal point as many might expect.

### Operator Semantics

All mathematical binary operators are supported for floats except for `==` and `!=`. These have been known to surprise programmers for a variety of reasons: `0.1 + 0.2 != 0.3` is one of those classic examples but there's also `NaN != NaN` and some other nuances.

This additionally means that floats are not allowed to be the keys of a map.

if you would like to opt into the conventional equality operator, with all of its sharp edges, it is available as the `ieee_equal` function in `intrinsics:floats`. Otherwise, you may prefer one of the approximate equality functions:

```kerrek
floats.approx_equal(0.1f + 0.2f, 0.3f, 0.000001f);  \\ values are within 0.000001f of each other
floats.approx_equal_ulp(0.1f + 0.2f, 0.3f, 3);  \\ values are within 3 ulps
floats.round_equal(0.1f + 0.2f, 0.3f, 3);  \\ would round to the same decimal value with 3 digits after the decimal point
floats.trunc_equal(0.1f + 0.2f, 0.3f, 3);  \\ would truncate to the same decimal value with 3 digits after the decimal point
```

# Non-Numeric Types

These types do not support any form of implicit conversion between each other

## Boolean

Has two values, `true` and `false`, following all standard expectations of boolean logic

The zero value is `false`

Booleans within structs may be no larger than 8 bits

### Operator Semantics

Booleans support the logic operators `and`, `or`, and `not`

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

All other operations are not allowed


## Byte

A byte is a single 8-bit value without numeric semantics. It can be converted to and from numeric types and accepts both integer and rune literals (and folded constants) within range, but does not support any operators besides `==` and `!=`.

The zero value is 0x00

# Truthiness

Of the primitive types, only booleans are allowed in contexts that require booleans.

All values with a zero value of `nil` additionally implicitly convert to boolean.
