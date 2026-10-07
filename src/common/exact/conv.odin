package exact

import "base:intrinsics"
import "core:math"
import "core:math/big"


clone :: proc {
	clone_int,
	clone_rat,
	clone_decimal,
}

int_to_rat :: proc(i: Int) -> Rat {
	return {i, 1}
}

decimal_to_rat :: proc(value: Decimal, allocator := bigint_allocator) -> Rat {
	if value.scale == 0 {
		return {clone(value.significand, allocator), 1}
	}
	scale_magnitude := uint(value.scale) if value.scale > 0 else uint(-(value.scale + 1)) + 1
	factor := int_pow_int(Int(i128(10)), scale_magnitude, context.temp_allocator)
	if value.scale < 0 {
		return {int_mul(value.significand, factor, allocator), 1}
	}
	return rat_reduce({clone(value.significand, context.temp_allocator), factor}, allocator)
}

rat_to_decimal_rounded :: proc(value: Rat, scale: int, allocator := bigint_allocator) -> Decimal {
	scale_magnitude := uint(scale) if scale >= 0 else uint(-(scale + 1)) + 1
	factor := int_pow_int(Int(i128(10)), scale_magnitude, context.temp_allocator)
	result: Int
	if scale >= 0 {
		result = int_div_half_even(
			mul(value.numerator, factor, context.temp_allocator),
			value.denominator,
			allocator,
		)
	} else {
		result = int_div_half_even(
			value.numerator,
			mul(value.denominator, factor, context.temp_allocator),
			allocator,
		)
	}
	return {result, scale}
}

rat_to_decimal_exact :: proc(value: Rat, allocator := bigint_allocator) -> (Decimal, bool) {
	reduced := rat_reduce(value, context.temp_allocator)
	denominator := reduced.denominator
	twos, fives := 0, 0
	for int_is_zero(int_rem(denominator, Int(i128(2)), context.temp_allocator)) {
		denominator = int_div(denominator, Int(i128(2)), context.temp_allocator)
		twos += 1
	}
	for int_is_zero(int_rem(denominator, Int(i128(5)), context.temp_allocator)) {
		denominator = int_div(denominator, Int(i128(5)), context.temp_allocator)
		fives += 1
	}
	if !int_is_one(denominator) {
		return {}, false
	}

	scale := max(twos, fives)
	significand := clone(reduced.numerator, context.temp_allocator)
	if twos < scale {
		significand = int_mul(
			significand,
			int_pow_int(Int(i128(2)), uint(scale - twos), context.temp_allocator),
			context.temp_allocator,
		)
	}
	if fives < scale {
		significand = int_mul(
			significand,
			int_pow_int(Int(i128(5)), uint(scale - fives), context.temp_allocator),
			context.temp_allocator,
		)
	}
	return {clone(significand, allocator), scale}, true
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

clone_decimal :: proc(value: Decimal, allocator := bigint_allocator) -> Decimal {
	return {clone_int(value.significand, allocator), value.scale}
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
	assert(!is_zero(r.denominator), "rational denominator is zero")
	if is_zero(r) {
		return 0.0
	}

	sign := -1 if rat_is_negative(r) else 1
	numerator := int_abs(r.numerator, context.temp_allocator)
	denominator := int_abs(r.denominator, context.temp_allocator)

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
	fraction_mask :: (1 << (precision - 1)) - 1

	e := int_floor_log2_ratio(numerator, denominator)

	if intrinsics.unlikely(e < emin) {
		// subnormal
		m := int_div_pow2_half_even(
			numerator,
			denominator,
			precision - 1 - emin,
			context.temp_allocator,
		)

		if is_zero(m) {
			return math.copy_sign(F(0.0), F(sign))
		}

		if eq(m, 1 << (precision - 1), context.temp_allocator) {
			return math.copy_sign(transmute(F)(I(1) << (precision - 1)), F(sign))
		}

		return math.copy_sign(transmute(F)(I(m.(i128)) & fraction_mask), F(sign))
	}

	m := int_div_pow2_half_even(numerator, denominator, precision - 1 - e, context.temp_allocator)

	if eq(m, i128(1 << precision)) {
		e += 1
		m = div(m, 2, context.temp_allocator)
	}

	if e > emax {
		when F == f16 {
			return math.copy_sign(math.INF_F16, F(sign))
		} else when F == f32 {
			return math.copy_sign(math.INF_F32, F(sign))
		} else when F == f64 {
			return math.copy_sign(math.INF_F64, F(sign))
		}
	}

	return math.copy_sign(
		transmute(F)(I(m.(i128)) & fraction_mask | I(e + emax) << (precision - 1)),
		F(sign),
	)
}
