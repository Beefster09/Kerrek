package exact

import "base:intrinsics"
import "core:math/big"
import "core:mem"
import "core:strconv"
import "core:unicode"


parse_int :: proc(s: string, radix: int = 10, allocator := bigint_allocator) -> (Int, bool) {
	reg, ok := strconv.parse_i128(s, radix)
	if ok {
		return reg, true
	}
	large: big.Int
	err := big.atoi(&large, s, i8(radix), allocator)
	if err == nil {
		return large, true
	}

	return 0, false
}

I128_DEC_DIGITS :: 38
DIGIT_INITIAL_CAP :: 64

parse_decimal :: proc(s: string) -> (Rat, bool) {
	return #force_inline _parse_fractional(s, 10)
}

parse_hexfloat :: proc(s: string) -> (Rat, bool) {
	return #force_inline _parse_fractional(s, 16)
}

_parse_fractional :: proc(s: string, $RADIX: int) -> (Rat, bool) where RADIX == 10 || RADIX == 16 {
	EXP_CHAR :: 'e' when RADIX == 10 else 'p'
	I128_MAX_SCALE :: I128_DEC_DIGITS when RADIX == 10 else 128 / 16

	scratch: mem.Scratch
	{
		err := mem.scratch_init(&scratch, 4 * mem.Kilobyte)
		if err != nil {
			return {}, false
		}
	}
	defer mem.scratch_destroy(&scratch)
	scratch_alloc := mem.scratch_allocator(&scratch)

	digits := make([dynamic]u8, 0, DIGIT_INITIAL_CAP, scratch_alloc)
	point_found := false
	point_at: int
	exp: int
	sign := 1

	loop: for c, i in s {
		switch unicode.to_lower(c) {
		case '+':
			if i != 0 {
				return {}, false
			}
		case '-':
			if i == 0 {
				sign = -1
			} else {
				return {}, false
			}
		case '.':
			if point_found {break loop}
			point_at = i
			point_found = true
		case EXP_CHAR:
			exp2, ok := strconv.parse_i64(s[i + 1:], RADIX)
			if ok {
				exp = int(exp2)
			} else {
				return {}, false
			}
			break loop
		case '0' ..= '9':
			append(&digits, u8(c))
		case 'a' ..= 'f':
			when RADIX == 16 {
				append(&digits, u8(c))
			} else {
				break loop
			}
		case:
			break loop
		}
	}

	prec := len(digits) - point_at if point_found else 0

	base, ok := parse_int(transmute(string)digits[:], RADIX, scratch_alloc)
	if !ok {
		return {}, false
	}

	if prec >= exp {
		denominator_scale := prec - exp
		if denominator_scale <= I128_MAX_SCALE {
			den: i128 = 1
			for i in 0 ..< denominator_scale {
				den *= i128(RADIX)
			}
			num := clone(base)
			if sign < 0 {
				inplace_negate_int(&num)
			}
			return {num, den}, true
		} else {
			den: big.Int
			err := big.exp(&den, RADIX, denominator_scale, bigint_allocator)
			if err == nil {
				num := clone(base)
				if sign < 0 {
					inplace_negate_int(&num)
				}
				return {num, den}, true
			}
		}
	} else {
		scale := exp - prec
		if base_as_i128, base_is_i128 := base.(i128); scale <= I128_MAX_SCALE && base_is_i128 {
			mul: i128 = 1
			for i in 0 ..< scale {
				mul *= i128(RADIX)
			}
			result, overflow := intrinsics.overflow_mul(base_as_i128, mul)
			if !overflow {
				return {result, 1}, true
			}
		}

		base_big, mul, result: big.Int
		switch b in base {
		case i128:
			err := big.set(&base_big, b)
			if err != nil {
				return {}, false
			}
		case big.Int:
			base_big = b // intentional dumb copy since this is already a temp
		}

		{
			err := big.exp(&mul, RADIX, scale, scratch_alloc)
			if err != nil {
				return {}, false
			}
		}

		{
			err := big.mul(&result, &base_big, &mul, bigint_allocator)
			if err != nil {
				return {}, false
			}
		}

		if sign < 0 {
			result.sign = .Negative
		}
		return {result, 1}, true
	}

	return {}, false
}
