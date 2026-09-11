package units

import "base:intrinsics"
import "base:runtime"
import "core:fmt"
import "core:io"
import "core:math"
import "core:slice"

import "../../common/exact"

Small_Rat :: struct {
	// CONSIDER: bit field (which will break some tests)
	numerator:   i8,
	denominator: u8,
}

RAT_ONE :: Small_Rat{1, 1}

MIN_NUM :: -1 << 7
MAX_NUM :: 1 << 7 - 1
MIN_DEN :: 0
MAX_DEN :: 1 << 8 - 1

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

cmp_rat :: proc "contextless" (a, b: Small_Rat) -> slice.Ordering {
	// NOTE: undefined behavior if either denominator == 0
	// the observed behavior should be infinity-ish, but we don't check
	l := i32(a.numerator) * i32(b.denominator)
	r := i32(b.numerator) * i32(a.denominator)
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
	if MIN_NUM <= n && n <= MAX_NUM && MIN_DEN < d && d <= MAX_DEN {
		return {i8(n), u8(d)}, true
	}
	return {}, false
}

fmt_rat :: proc(fi: ^fmt.Info, arg: any, verb: rune) -> bool {
	assert(arg.id == Small_Rat)
	switch verb {
	case 'v':
		fmt.fmt_struct(
			fi,
			arg,
			verb,
			// insane incantation to get the type info of the struct itself
			type_info_of(Small_Rat).variant.(runtime.Type_Info_Named).base.variant.(runtime.Type_Info_Struct),
			type_info_of(Small_Rat).variant.(runtime.Type_Info_Named).name,
		)
		return true
	case 's', 'r', 'd':
		r := (cast(^Small_Rat)arg.data)^
		io.write_int(fi.writer, int(r.numerator))
		if r.denominator != 0 {
			io.write_rune(fi.writer, '/')
			io.write_int(fi.writer, int(r.denominator))
		}
	case:
		return false
	}
	return true
}
