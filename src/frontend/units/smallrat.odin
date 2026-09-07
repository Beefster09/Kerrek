package units

import "base:intrinsics"
import "core:math"

import "../../common/exact"

Small_Rat :: struct {
	numerator:   i8,
	denominator: u8,
}

RAT_ONE :: Small_Rat{1, 1}

MIN_I8 :: -1 << 7
MAX_I8 :: 1 << 7 - 1
MIN_U8 :: 0
MAX_U8 :: 1 << 8 - 1

rat_from_exact :: proc(value: exact.Rat) -> (Small_Rat, bool) {
	n, nsmall := value.numerator.(i128)
	d, dsmall := value.denominator.(i128)
	if nsmall && dsmall {
		return _reduce_to_rat(n, d)
	}
	return {}, false
}

add_rat :: proc "contextless" (a, b: Small_Rat) -> (Small_Rat, bool) {
	l := i32(a.numerator) * i32(b.denominator)
	r := i32(b.numerator) * i32(a.denominator)
	n := l + r
	d := i32(a.denominator) * i32(b.denominator)
	return _reduce_to_rat(n, d)
}

sub_rat :: proc "contextless" (a, b: Small_Rat) -> (Small_Rat, bool) {
	l := i32(a.numerator) * i32(b.denominator)
	r := i32(b.numerator) * i32(a.denominator)
	n := l - r
	d := i32(a.denominator) * i32(b.denominator)
	return _reduce_to_rat(n, d)
}

mul_rat :: proc "contextless" (a, b: Small_Rat) -> (Small_Rat, bool) {
	n := i32(a.numerator) * i32(b.numerator)
	d := i32(a.denominator) * i32(b.denominator)
	return _reduce_to_rat(n, d)
}

div_rat :: proc "contextless" (a, b: Small_Rat) -> (Small_Rat, bool) {
	n := i32(a.numerator) * i32(b.denominator)
	d := i32(a.denominator) * i32(b.numerator)
	return _reduce_to_rat(n, d)
}

_reduce_to_rat :: proc "contextless" (
	n, d: $I,
) -> (
	Small_Rat,
	bool,
) where intrinsics.type_is_integer(I) {
	n := n
	d := d
	if d == 0 {
		return {}, false
	}
	if n == 0 {
		return {0, 1}, true
	}
	gcd := math.gcd(n, d)
	n /= gcd
	d /= gcd
	if d < 0 {
		n = -n
		d = -d
	}
	if MIN_I8 <= n && n <= MAX_I8 && MIN_U8 < d && d <= MAX_U8 {
		return {i8(n), u8(d)}, true
	}
	return {}, false
}
