package exact

import "base:intrinsics"
import "core:math/big"
import "core:mem"
import "core:unicode"


_digit_value :: proc(c: rune) -> (int, bool) {
	switch c {
	case '0' ..= '9':
		return int(c - '0'), true
	case 'a' ..= 'f':
		return int(c - 'a') + 10, true
	case 'A' ..= 'F':
		return int(c - 'A') + 10, true
	}
	return 0, false
}

_is_digit_for_radix :: proc(c: rune, radix: int) -> bool {
	digit, ok := _digit_value(c)
	return ok && digit < radix
}

_underscore_between_digits :: proc(s: string, i, radix: int) -> bool {
	return i > 0 &&
	       i + 1 < len(s) &&
	       _is_digit_for_radix(rune(s[i - 1]), radix) &&
	       _is_digit_for_radix(rune(s[i + 1]), radix)
}

_valid_integer_syntax :: proc(s: string, radix: int) -> bool {
	if len(s) == 0 || radix < 2 || radix > 16 {
		return false
	}

	start := 1 if s[0] == '+' || s[0] == '-' else 0
	if start == len(s) {
		return false
	}

	body := s[start:]
	digits := 0
	for c, i in body {
		if c == '_' {
			if !_underscore_between_digits(body, i, radix) {
				return false
			}
			continue
		}
		if !_is_digit_for_radix(c, radix) {
			return false
		}
		digits += 1
	}
	return digits > 0
}


_parse_i128_checked :: proc(s: string, radix: int) -> (i128, bool) {
	if !_valid_integer_syntax(s, radix) {
		return 0, false
	}

	negative := false
	start := 0
	switch s[0] {
	case '-':
		negative = true
		start = 1
	case '+':
		start = 1
	}
	if start == len(s) {
		return 0, false
	}

	I128_ABS_MIN :: u128(1) << 127
	limit := I128_ABS_MIN if negative else I128_ABS_MIN - 1
	magnitude: u128
	for c in s[start:] {
		if c == '_' {
			continue
		}

		digit, ok := _digit_value(c)
		assert(ok)
		if digit >= radix || magnitude > (limit - u128(digit)) / u128(radix) {
			return 0, false
		}
		magnitude = magnitude * u128(radix) + u128(digit)
	}

	if negative {
		if magnitude == I128_ABS_MIN {
			return I128_MIN, true
		}
		return -i128(magnitude), true
	}
	return i128(magnitude), true
}


parse_int :: proc(s: string, radix: int = 10, allocator := bigint_allocator) -> (Int, bool) {
	if !_valid_integer_syntax(s, radix) {
		return 0, false
	}

	reg, ok := _parse_i128_checked(s, radix)
	if ok {
		return reg, true
	}
	large := new(big.Int, allocator)
	big_source := s[1:] if len(s) > 0 && s[0] == '+' else s
	normalized := make([dynamic]u8, 0, len(big_source), context.temp_allocator)
	defer delete(normalized)
	for c in big_source {
		if c != '_' {
			append(&normalized, u8(c))
		}
	}
	err := big.atoi(large, transmute(string)normalized[:], i8(radix), allocator)
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
	EXP_RADIX :: 10 when RADIX == 10 else 2
	BITS_PER_DIGIT :: 1 when RADIX == 10 else 4
	I128_MAX_SCALE :: I128_DEC_DIGITS when RADIX == 10 else 126

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
		if c == '_' {
			if !_underscore_between_digits(s, i, RADIX) {
				return {}, false
			}
			continue
		}

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
			if point_found {
				return {}, false
			}
			point_at = len(digits)
			point_found = true
		case EXP_CHAR:
			exp2, ok := _parse_i128_checked(s[i + 1:], 10)
			if ok && i128(min(int)) <= exp2 && exp2 <= i128(max(int)) {
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
				return {}, false
			}
		case:
			return {}, false
		}
	}

	prec := (len(digits) - point_at) * BITS_PER_DIGIT if point_found else 0

	base, ok := parse_int(transmute(string)digits[:], RADIX, scratch_alloc)
	if !ok {
		return {}, false
	}

	if prec >= exp {
		denominator_scale := prec - exp
		if denominator_scale <= I128_MAX_SCALE {
			den: i128 = 1
			for _ in 0 ..< denominator_scale {
				den *= i128(EXP_RADIX)
			}
			num := clone(base)
			if sign < 0 {
				inplace_negate_int(&num)
			}
			return rat_reduce({num, den}), true
		} else {
			den := new(big.Int, bigint_allocator)
			err := big.exp(den, EXP_RADIX, denominator_scale, bigint_allocator)
			if err == nil {
				num := clone(base)
				if sign < 0 {
					inplace_negate_int(&num)
				}
				return rat_reduce({num, den}), true
			}
		}
	} else {
		scale := exp - prec
		if base_as_i128, base_is_i128 := base.(i128); scale <= I128_MAX_SCALE && base_is_i128 {
			mul: i128 = 1
			for _ in 0 ..< scale {
				mul *= i128(EXP_RADIX)
			}
			result, overflow := intrinsics.overflow_mul(base_as_i128, mul)
			if !overflow {
				return rat_reduce({result, 1}), true
			}
		}

		base_big, mul: big.Int
		switch b in base {
		case i128:
			err := big.set(&base_big, b)
			if err != nil {
				return {}, false
			}
		case ^big.Int:
			base_big = b^ // intentional dumb copy since this is already a temp
		}

		{
			err := big.exp(&mul, EXP_RADIX, scale, scratch_alloc)
			if err != nil {
				return {}, false
			}
		}

		result := new(big.Int, bigint_allocator)
		{
			err := big.mul(result, &base_big, &mul, bigint_allocator)
			if err != nil {
				return {}, false
			}
		}

		if sign < 0 {
			result.sign = .Negative
		}
		return rat_reduce({result, 1}), true
	}

	return {}, false
}
