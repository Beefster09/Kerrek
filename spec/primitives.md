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

- `Integer(digits)`: An signed integer able to hold exactly `digits` decimal digits
	- stored in the smallest power-of-two sized machine integer that will fit that many digits
		- if no standard machine integer will fit it, it overflows into a multi-word integer (e.g. Int128) with the smallest number of 64-bit legs that will hold the desired range
		- requesting more digits than can fit in an Int128 (i.e. 34 digits) will emit a diagnostic warning to alert the user that operations on it may be slower than expected
	- exceeding the defined decimal range will emit an `OverflowError` that must be handled
- Sized integers (`Int64`, `UInt32`, etc...) behave as expected for machine integers
	- overflow and underflow wrap by default for machine integers, as that is the behavior most commonly expected for machine integers
	- you can set the overflow behavior to saturating arithmetic or to emit `OverflowError`

### Operator Semantics

All mathematical operators except for `/` are defined for integers. The operator you are looking for is `//`, the floor-division operator. Requiring you to opt into floor division instead of silently truncating helps to prevent subtle logic bugs and surprises.

Division by zero emits a `ZeroDivisionError` which panics by default

## Decimals

The Decimal types are:
- `Decimal(digits, scale)`: Signed fixed point decimal with enough storage for at least `digits` significant  digits and exactly `scale` of those digits after the decimal point
	- Follows the same size and storage rules of `Integer(digits)`, including diagnostic warning conditions.
	- `digits` must be a compile-time known positive integer
	- `scale` must be a compile-time known integer
		- negative `scale` and `scale > digits` are both well-formed and allowed, but both cases will trigger diagnostic warnings unless silenced, as it may be surprising and unintended
	- `Integer(d)` and `Decimal(d, 0)` are the same type, including the removal of the `/` operator

Floating point decimal and arbitrary precision decimal are not primitive types, as they do not have widespread support on consumer hardware.

## Binary Floats

Floats are inaccessible in the prelude namespace and exposed via `intrinsics:float`. As useful as they are, they have some non-obvious subtleties to them which trip up many programmers and silently make programs incorrect. By placing them out of reach of the prelude namespace, it helps to add some friction so that programmers are more inclined to reach for the tools that are more likely to be correct. Use floats only when you know for sure you need them.

The `intrinsics:float` backage exposes three types:

- `Binary64`
- `Binary32`
- `Binary16`

Their unusual naming is intentional to highlight their somewhat surprising behavior and steer users toward using `Decimal(digits, scale)` types when that will suffice.

### Operator Semantics

All mathematical binary operators are supported for binary floats except for `==` and `!=`. These have been known to surprise programmers for a variety of reasons: `0.1 + 0.2 != 0.3` is one of those classic examples but there's also `NaN != NaN` and some other nuances.

This additionally means that floats are not allowed to be the keys of a map.

if you would like to opt into the conventional equality operator, with all of its sharp edges, it is available as the `ieee_equal` function in `intrinsics:float`. Otherwise, you may prefer one of the approximate equality functions:

```kerrek
float.approx_equal(0.1f + 0.2f, 0.3f, 0.000001f);  \\ values are within 0.000001f of each other
float.approx_equal_ulp(0.1f + 0.2f, 0.3f, 3);  \\ values are within 3 ulps
float.round_equal(0.1f + 0.2f, 0.3f, 3);  \\ would round to the same decimal value with 3 digits after the decimal point
float.trunc_equal(0.1f + 0.2f, 0.3f, 3);  \\ would truncate to the same decimal value with 3 digits after the decimal point
```

Or possibly you may even want:

```kerrek
float.bits_equal(0.1f + 0.2f, 0.3f);  \\ the bit pattern is exactly the same; 0 != -0 in this case
float.ieee_equal(0.1f + 0.2f, 0.3f);  \\ equality as defined by IEEE 754, including NaN != NaN
```

# Non-Numeric Types

These types do not support any form of implicit conversion between each other

## Boolean

Has two values, `true` and `false`, following all standard expectations of boolean logic

The zero value is `false`

Booleans within structs may be no larger than 8 bits

### Operator Semantics

Booleans support the logic operators `and`, `or`, and `not`

Booleans support equality operators `==` and `!=`, but not the other four comparison operators

They also support multiplication with any other type that has a well-defined and valid zero value:

- true \* x -> x
- x \* true -> x
- false \* x -> (the zero value of the same type as x)
- x \* false -> (the zero value of the same type as x)

## String

Strings have value semantics and behave like values under all conditions which do not sidestep normal safety guarantees. Whether that is managed via small string optimization, immutability, or aggressive copying is considered an implementation detail, however implementations *should* aim to optimize Strings as much as possible. The exact tradeoffs made over minimizing copying vs avoiding keeping large string buffers alive is left to the implementation.

- The zero value is the empty string, and a fully zeroed struct representing a string value must be an empty string.
	- fully-zero does not need to be the only possible representation of the empty string
- Strings are assumed to be UTF-8 encoded.
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

Runes are stored in 32 bits i.e. 4 bytes

### Operator Semantics

Runes are fully comparable, supporting all six comparison operators.

All other operations are not allowed


## Byte

A byte is a single 8-bit value without numeric semantics. It can be converted to and from numeric types and accepts both integer and rune literals (and folded constants) within range, but does not support any operators besides `==` and `!=`.

The zero value is 0x00


## Opaque

The Opaque types are sized types (in 8, 16, 32, 64 bits as well as the pointer-sized bare `Opaque`) that support only equality testing. They can be converted to and from sized integers of the same size. Opaques must be explicitly converted and will never implicitly convert from integer literals, constants, or runtime values.

These are mainly intended to be the underlying type for distinct types for use with foreign functions (as many C APIs operate on an opaque pointer) and certain system calls (e.g. opaque file handles from fopen, pipes, sockets, etc...)

The zero value is valid, but likely not meaningful.


# Truthiness

Of the primitive types, only booleans are allowed in contexts that require booleans.

All values with a zero value of `nil` additionally implicitly convert to boolean.
