# Overview

Kerrek comes with all of the trappings of a many other procedural language: structs, functions, enums, distinct types, compile-time constants, etc... Programmers from C, Zig, Odin, and Go should all feel at home.

Additionally, there are some other notable features that may feel novel or unusual:
- Decimal as the default real type
- Floats do not support == and !=
- Numeric types can have units, which the type checker verifies are correct
- Capabilities: constrained mutation and function calls
- Value labels: tools for things like taint analysis
- Explicit interface vtables and interface objects
- Builtin smart pointers; no GC
- `async` anything as long as you don't leak it
- Errors are values, with Result-like semantics
- Constrained long-range control flow with `abort`
- Backtick-escaped identifiers for avoiding conflicts with keywords
- Double backslash for comments
- Modulo operator (`mod`) with looser binding than addition


# Putting the safety on binary floating point foot guns

Floats trip up beginners with subtle bugs and surprising behavior. 0.1 + 0.2 != 0.3 in floating point land, and decimal values in general cannot be exactly represented. Equality can behave subtly wrong due to rounding differences.

Floats aren't bad, and they're the numeric type that hardware optimized for, but they're inappropriate for a lot of real world business use cases due to the aforementioned issues. If you know you need them, you should have them and if you know the exact float behavior you want, you should be able to do it.

Float types are not available in the builtin namespace in Kerrek. Rather, you must import them from the intrinsics package:

```kerrek
import intrinsics:floats using Float64

func burninate_cottage(fieriness: Float64) -> Float64 {
	return fieriness * 10
}
```

Equality operators are not permitted for floating point types, however `<` and its friends are still supported, and a handful of useful equality and approx equality tests are provided in the intrinsics:float package:

```kerrek
import intrinsics:floats using Float64
import core:units/si

func throw_baby(initial_velocity: Float64<si.Meter per si.Second>) -> Float64<si.Meter> {
	if floats.approx_equal(initial_velocity, 0, 0.001) {
		return 0
	}

	\\ etc...
}
```

Floats otherwise behave like builtin types because they are builtin; they're just hidden from the default namespace.
