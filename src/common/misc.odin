package common

import "base:intrinsics"
import "base:runtime"
import "core:io"
import "core:math/big"
import "core:strings"

import "exact"

Primitive_Value :: union #no_nil {
	Untyped_Nil,
	Untyped_Zero,
	exact.Rat,
	string,
	rune,
	byte,
	bool,
}

Untyped_Nil :: struct {}
Untyped_Zero :: struct {}

i256 :: distinct [4]u64

INT64_DECIMAL_MAX_MAGNITUDE :: 18.964889726830815
INT128_DECIMAL_MAX_MAGNITUDE :: 38.23080944932561
INT256_DECIMAL_MAX_MAGNITUDE :: 76.7626488943152

write_i256 :: proc(w: io.Writer, value: i256) {
	SIGN_BIT :: 1 << 63
	value := cast([4]u64)value
	is_negative := value[3] & SIGN_BIT != 0
	size := 1
	for d, j in value {
		if (d != ~u64(0) if is_negative else d != 0) {
			size = j + 1
		}
	}

	if size <= 2 {
		// fast-path / workaround because big.int_itoa_raw is broken for small values
		io.write_i128(w, (transmute([2]i128)value)[0])
		return
	}

	i := big.Int {
		used = size,
	}
	if is_negative {
		// negate via two's complement
		overflow_one := true
		#unroll for j in 0 ..< 4 {
			value[j] = ~value[j]
			if overflow_one {
				value[j], overflow_one = intrinsics.overflow_add(value[j], 1)
			}
		}

	}
	i.digit = transmute([dynamic]big.DIGIT)runtime.Raw_Dynamic_Array {
		data = &value[0],
		len = 4,
		cap = 4,
		allocator = runtime.nil_allocator(),
	}
	digits_str, err := big.int_itoa_string(&i, 10, allocator = context.temp_allocator)
	if err == nil {
		// workaround for int_itoa_string sometimes putting too many 0s at the beginning
		if is_negative {
			io.write_rune(w, '-')
		}
		io.write_string(w, strings.trim_left(digits_str, "0"))
	} else {
		io.write_string(w, "##ERROR##")
	}
}

exact_int_to_i256 :: proc(exact_integer: exact.Int) -> (i256, bool) {
	switch integer in exact_integer {
	case i128:
		chunks := transmute([2]u64)integer
		filler := ~u64(0) if integer < 0 else 0
		return {expand_values(chunks), filler, filler}, true

	case ^big.Int:
		bits, err := big.count_bits(integer, context.temp_allocator)
		if err != nil || bits > 255 {
			return {}, false
		}
		result: [4]big.DIGIT
		copy(result[:], integer.digit[:])
		if integer.sign == .Negative {
			overflow_one := true
			#unroll for i in 0 ..< 4 {
				result[i] = ~result[i]
				if overflow_one {
					result[i], overflow_one = intrinsics.overflow_add(result[i], 1)
				}
			}
		}
		return transmute(i256)result, true
	}

	unreachable()
}

Pointer_Ownership :: enum {
	Borrow,
	Owned,
	Shared,
	Weak,
	Unsafe,
}

Unary_Op :: enum {
	Positive = 1,
	Negate,
	Not,
}

Binary_Op :: enum {
	Add = 1,
	Subtract,
	Multiply,
	True_Divide,
	Floor_Divide,
	Remainder,
	Modulo,
	Power,
	Equal,
	Not_Equal,
	Less,
	Less_Equal,
	Greater,
	Greater_Equal,
	Is,
	Is_Not,
	And,
	Or,
}

ARITHMETIC_UNOPS :: bit_set[Unary_Op]{.Positive, .Negate}
ARITHMETIC_BINOPS :: bit_set[Binary_Op] {
	.Add,
	.Subtract,
	.Multiply,
	.True_Divide,
	.Floor_Divide,
	.Power,
	.Modulo,
	.Remainder,
}

COMPARISON_BINOPS :: bit_set[Binary_Op] {
	.Equal,
	.Not_Equal,
	.Less,
	.Less_Equal,
	.Greater,
	.Greater_Equal,
	.Is,
	.Is_Not,
}

BOOLEAN_UNOPS :: bit_set[Unary_Op]{.Not}
BOOLEAN_BINOPS :: bit_set[Binary_Op]{.And, .Or}

@(rodata)
UNARY_OP_STRINGS := [Unary_Op]string {
	.Positive = "+",
	.Negate   = "-",
	.Not      = "not",
}

@(rodata)
BINARY_OP_STRINGS := [Binary_Op]string {
	.Add           = "+",
	.Subtract      = "-",
	.Multiply      = "*",
	.True_Divide   = "/",
	.Floor_Divide  = "//",
	.Remainder     = "%",
	.Modulo        = "mod",
	.Power         = "**",
	.Equal         = "==",
	.Not_Equal     = "!=",
	.Less          = "<",
	.Less_Equal    = "<=",
	.Greater       = ">",
	.Greater_Equal = ">=",
	.Is            = "is",
	.Is_Not        = "is_not",
	.And           = "and",
	.Or            = "or",
}
