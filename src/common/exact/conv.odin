package exact

import "base:intrinsics"
import "core:fmt"
import "core:math"
import "core:math/big"


clone :: proc {
	clone_int,
	clone_rat,
}

int_to_rat :: proc(i: Int) -> Rat {
	return {i, 1}
}

clone_int :: proc(i: Int, allocator := bigint_allocator) -> Int {
	switch ii in i {
	case i128:
		return ii
	case ^big.Int:
		result := new(big.Int, allocator)
		big.set(result, ii, allocator = allocator)
		return result
	}
	panic("unreachable")
}

clone_rat :: proc(r: Rat, allocator := bigint_allocator) -> Rat {
	return {clone_int(r.numerator, allocator), clone_int(r.denominator, allocator)}
}

_promote :: proc(inline: i128, allocator := bigint_allocator) -> ^big.Int {
	result := new(big.Int, allocator)
	err := big.set(result, inline, allocator = allocator)
	assert(err == nil)
	return result
}

_demote :: proc(bigint: ^big.Int) -> (i128, bool) {
	magnitude_value := bigint^
	magnitude_value.sign = .Zero_or_Positive
	magnitude, err := big.get(&magnitude_value, u128)
	if err != nil {
		return 0, false
	}

	I128_ABS_MIN :: u128(1) << 127
	if bigint.sign == .Negative {
		if magnitude > I128_ABS_MIN {
			return 0, false
		}
		if magnitude == I128_ABS_MIN {
			return I128_MIN, true
		}
		return -i128(magnitude), true
	}
	if magnitude >= I128_ABS_MIN {
		return 0, false
	}
	return i128(magnitude), true
}

to_float :: proc(r: Rat, $F: typeid) -> F where intrinsics.type_is_float(F) {
	if is_zero(r) {
		return 0.0
	}

	sign := int_sign(r.numerator)
	numerator := int_abs(r.numerator, context.temp_allocator)

	when F == f16 {
		precision :: 11
		emin :: -14
		emax :: 15
		I :: u16
	} else when F == f32 {
		precision :: 24
		emin :: -126
		emax :: 127
		I :: u32
	} else when F == f64 {
		precision :: 53
		emin :: -1022
		emax :: 1023
		I :: u64
	} else {
		#panic("type not supported")
	}
	mask :: 1 << precision - 1

	e := int_floor_log2_ratio(r.numerator, r.denominator)

	if intrinsics.unlikely(e < emin) {
		// subnormal
		scale := int_shl(1, uint(precision - 1 - emin), context.temp_allocator)
		m := int_div_half_even(
			mul(r.numerator, scale, context.temp_allocator),
			r.denominator,
			context.temp_allocator,
		)

		if is_zero(m) {
			return math.copy_sign(F(0.0), F(sign))
		}

		if eq(m, 1 << (precision - 1), context.temp_allocator) {
			return math.copy_sign(transmute(F)I(1), F(sign))
		}

		return math.copy_sign(transmute(F)(I(m.(i128)) & mask), F(sign))
	}

	// normal
	scale := int_shl(1, uint(precision - 1 - e), context.temp_allocator)
	m := int_div_half_even(
		mul(r.numerator, scale, context.temp_allocator),
		r.denominator,
		context.temp_allocator,
	)

	if eq(m, i128(1 << precision)) {
		e += 1
		m = div(m, 2, context.temp_allocator)
	}

	if e > emax {
		when F == f16 {
			return math.INF_F16
		} else when F == f32 {
			return math.INF_F32
		} else when F == f64 {
			return math.INF_F64
		}
	}

	fmt.printfln(
		"%016x %016x %g",
		m,
		mask,
		transmute(F)(I(m.(i128)) & mask | I(e + emax) << (precision - 1)),
	)
	return math.copy_sign(
		transmute(F)(I(m.(i128)) & mask | I(e + emax) << (precision - 1)),
		F(sign),
	)
}
