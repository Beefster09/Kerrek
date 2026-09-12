package units

import "base:intrinsics"
import "base:runtime"
import "core:fmt"
import "core:io"
import "core:math"
import "core:slice"

import "../../common/exact"

NUMERATOR_BITS :: 11
DENOMINATOR_BITS :: 5

Small_Rat :: bit_field i16 {
	// CONSIDER: bit field (which will break some tests)
	n: i16 | NUMERATOR_BITS,
	d: u8  | DENOMINATOR_BITS,
}

RAT_ONE :: Small_Rat {
	n = 1,
	d = 0,
}

RAT_ZERO :: Small_Rat {
	n = 0,
	d = 0,
}

MIN_NUM :: -1 << (NUMERATOR_BITS - 1)
MAX_NUM :: 1 << (NUMERATOR_BITS - 1) - 1
MIN_DEN :: 1
MAX_DEN :: 1 << DENOMINATOR_BITS

rat :: proc {
	rat_from_exact,
	rat_from_ints,
}

rat_from_exact :: proc(value: exact.Rat) -> (Small_Rat, bool) {
	n, nsmall := value.numerator.(i128)
	d, dsmall := value.denominator.(i128)
	if nsmall && dsmall {
		return #force_inline rat_from_ints(n, d)
	}
	return {}, false
}

add_rat :: proc "contextless" (a, b: Small_Rat) -> (Small_Rat, bool) {
	l := i32(a.n) * i32(b.d + 1)
	r := i32(b.n) * i32(a.d + 1)
	n := l + r
	d := i32(a.d + 1) * i32(b.d + 1)
	return #force_inline rat_from_ints(n, d)
}

sub_rat :: proc "contextless" (a, b: Small_Rat) -> (Small_Rat, bool) {
	l := i32(a.n) * i32(b.d + 1)
	r := i32(b.n) * i32(a.d + 1)
	n := l - r
	d := i32(a.d + 1) * i32(b.d + 1)
	return #force_inline rat_from_ints(n, d)
}

mul_rat :: proc "contextless" (a, b: Small_Rat) -> (Small_Rat, bool) {
	n := i32(a.n) * i32(b.n)
	d := i32(a.d + 1) * i32(b.d + 1)
	return #force_inline rat_from_ints(n, d)
}

div_rat :: proc "contextless" (a, b: Small_Rat) -> (Small_Rat, bool) {
	n := i32(a.n) * i32(b.d + 1)
	d := i32(a.d + 1) * i32(b.n)
	return #force_inline rat_from_ints(n, d)
}

cmp_rat :: proc "contextless" (a, b: Small_Rat) -> slice.Ordering {
	l := i32(a.n) * i32(b.d + 1)
	r := i32(b.n) * i32(a.d + 1)
	if l < r {
		return .Less
	}
	if l > r {
		return .Greater
	}
	return .Equal
}

lt_rat :: proc "contextless" (a, b: Small_Rat) -> bool {
	return #force_inline cmp_rat(a, b) == .Less
}

eq_rat :: proc "contextless" (a, b: Small_Rat) -> bool {
	return #force_inline cmp_rat(a, b) == .Equal
}

gt_rat :: proc "contextless" (a, b: Small_Rat) -> bool {
	return #force_inline cmp_rat(a, b) == .Greater
}

rat_from_ints :: proc "contextless" (
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
		return {n = 0, d = 0}, true
	}
	gcd := math.gcd(n, d)
	n /= gcd
	d /= gcd
	if d < 0 {
		n = -n
		d = -d
	}
	if MIN_NUM <= n && n <= MAX_NUM && MIN_DEN <= d && d <= MAX_DEN {
		return {n = i16(n), d = u8(d - 1)}, true
	}
	return {}, false
}

fmt_rat :: proc(fi: ^fmt.Info, arg: any, verb: rune) -> bool {
	assert(arg.id == Small_Rat)
	r := (cast(^Small_Rat)arg.data)^
	switch verb {
	case 'v':
		io.write_string(fi.writer, "Small_Rat(")
		io.write_int(fi.writer, int(r.n))
		io.write_rune(fi.writer, '/')
		io.write_int(fi.writer, int(r.d + 1))
		io.write_rune(fi.writer, ')')
		return true
	case 's', 'r', 'd':
		io.write_int(fi.writer, int(r.n))
		io.write_rune(fi.writer, '/')
		io.write_int(fi.writer, int(r.d + 1))
	case:
		return false
	}
	return true
}
