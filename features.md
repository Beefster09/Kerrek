# Overview

Kerrek comes with all of the trappings of a many other procedural language: structs, functions, enums, distinct types, compile-time constants, etc... Programmers from Odin, Go, and Swift should all feel at home.

Some feature highlights:
- Decimal as the default real type
- Built-in fixed-point decimal
- Floats do not support `==` and `!=`
- Integers do not support `/` for division.
	- Use `//` instead, to show you intended floor division.
- Double backslash for comments
- Numeric types can have units, which the type checker verifies are used coherently
- Facts: tools for things like taint analysis
- Capabilities: constrained mutation and function calls
- [Explicit interface vtables and interface objects](/spec/interfaces.md)
- [Builtin smart pointers; no GC](/spec/pointers.md)
- [Constrained `async`/`await` threaded concurrency](/spec/concurrency.md)
- [A fresh new take on error handling](/spec/errors.md)
- Constrained long-range control flow with `abort`
- Backtick-escaped identifiers for avoiding conflicts with keywords
- Modulo operator (`mod`) with looser binding than addition
- Function monkeypatching within tests (and *only* tests)


# Putting the safety on binary floating point foot guns

Floats trip up beginners with subtle bugs and surprising behavior. 0.1 + 0.2 != 0.3 in floating point land, and decimal values in general cannot be exactly represented. Equality can behave subtly wrong due to rounding differences.

Floats aren't bad, and they're the numeric type that hardware optimized for, but they're inappropriate for a lot of real world business use cases due to the aforementioned issues. If you know you need them, you should have them and if you know the exact float behavior you want, you should be able to do it.

You should prefer a fixed point Decimal type unless you know you need a binary floating point number.

Float types are not available in the builtin namespace in Kerrek. Rather, you must import them from the intrinsics:float package:

```kerrek
import intrinsics:float using Binary64

func burninate_cottage(fieriness: Binary64) -> Binary64 {
	return fieriness * 10
}
```

Equality operators are not permitted for floating point types, however `<` and its friends are still supported, and a handful of useful equality and approx equality tests are provided in the intrinsics:float package:

```kerrek
import intrinsics:float using Binary64
import core:units/si

func throw_baby(initial_velocity: Binary64 | si.Meter per si.Second) -> Binary64 | si.Meter {
	if floats.approx_equal(initial_velocity, 0, 0.001) {
		return 0
	}

	\\ etc...
}
```

Floats otherwise behave like builtin types because they are builtin; they're just hidden from the default namespace.
