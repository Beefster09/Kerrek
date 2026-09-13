package exact

import "base:intrinsics"
import "core:math"
import "core:math/big"
import "core:slice"

add :: proc {
	int_add,
	rat_add,
}

sub :: proc {
	int_sub,
	rat_sub,
}

mul :: proc {
	int_mul,
	rat_mul,
}

div :: proc {
	int_div,
	rat_div,
}

rem :: proc {
	int_rem,
	rat_rem,
}

cmp :: proc {
	int_cmp,
	rat_cmp,
}

eq :: proc {
	int_eq,
	rat_eq,
}

ne :: proc {
	int_ne,
	rat_ne,
}

lt :: proc {
	int_lt,
	rat_lt,
}

le :: proc {
	int_le,
	rat_le,
}

gt :: proc {
	int_gt,
	rat_gt,
}

ge :: proc {
	int_ge,
	rat_ge,
}

is_one :: proc {
	int_is_one,
	rat_is_one,
}

is_zero :: proc {
	int_is_zero,
	rat_is_zero,
}

gcd :: int_gcd
reduce :: rat_reduce

_Int_Op :: enum {
	Add,
	Sub,
	Mul,
	Div,
	Rem,
	Gcd,
}

_int_big_op :: proc(a, b: Int, op: _Int_Op, allocator := bigint_allocator) -> Int {
	a_big: ^big.Int
	switch aa in a {
	case i128:
		a_big = _promote(aa, allocator)
	case ^big.Int:
		a_big = aa
	}

	b_big: ^big.Int
	switch bb in b {
	case i128:
		b_big = _promote(bb, allocator)
	case ^big.Int:
		b_big = bb
	}

	result := new(big.Int, allocator)
	err: big.Error
	switch op {
	case .Add:
		err = big.add(result, a_big, b_big, allocator)
	case .Sub:
		err = big.sub(result, a_big, b_big, allocator)
	case .Mul:
		err = big.mul(result, a_big, b_big, allocator)
	case .Div:
		err = big.div(result, a_big, b_big, allocator)
	case .Rem:
		err = big.divmod(nil, result, a_big, b_big, allocator)
	case .Gcd:
		err = big.gcd(result, a_big, b_big, allocator)
	}
	assert(err == nil)

	if inline, ok := _demote(result); ok {
		return inline
	}
	return result
}

int_add :: proc(a, b: Int, allocator := bigint_allocator) -> Int {
	aa, a_inline := a.(i128)
	bb, b_inline := b.(i128)
	if intrinsics.likely(a_inline && b_inline) {
		result, overflow := intrinsics.overflow_add(aa, bb)
		if !overflow {
			return result
		}
	}
	return _int_big_op(a, b, .Add, allocator)
}

int_sub :: proc(a, b: Int, allocator := bigint_allocator) -> Int {
	aa, a_inline := a.(i128)
	bb, b_inline := b.(i128)
	if intrinsics.likely(a_inline && b_inline) {
		result, overflow := intrinsics.overflow_sub(aa, bb)
		if !overflow {
			return result
		}
	}
	return _int_big_op(a, b, .Sub, allocator)
}

int_mul :: proc(a, b: Int, allocator := bigint_allocator) -> Int {
	aa, a_inline := a.(i128)
	bb, b_inline := b.(i128)
	if intrinsics.likely(a_inline && b_inline) {
		result, overflow := intrinsics.overflow_mul(aa, bb)
		if !overflow {
			return result
		}
	}
	return _int_big_op(a, b, .Mul, allocator)
}

int_div :: proc(a, b: Int, allocator := bigint_allocator) -> Int {
	assert(!int_is_zero(b), "division by zero")
	aa, a_inline := a.(i128)
	bb, b_inline := b.(i128)
	if intrinsics.likely(a_inline && b_inline) {
		if aa != I128_MIN || bb != -1 {
			return aa / bb
		}
	}
	return _int_big_op(a, b, .Div, allocator)
}

int_rem :: proc(a, b: Int, allocator := bigint_allocator) -> Int {
	assert(!int_is_zero(b), "division by zero")
	aa, a_inline := a.(i128)
	bb, b_inline := b.(i128)
	if intrinsics.likely(a_inline && b_inline) {
		if aa == I128_MIN && bb == -1 {
			return 0
		}
		return aa % bb
	}
	return _int_big_op(a, b, .Rem, allocator)
}

_i128_abs_u128 :: proc(value: i128) -> u128 {
	if value >= 0 {
		return u128(value)
	}
	return u128(-(value + 1)) + 1
}

int_gcd :: proc(a, b: Int, allocator := bigint_allocator) -> Int {
	aa, a_inline := a.(i128)
	bb, b_inline := b.(i128)
	if intrinsics.likely(a_inline && b_inline) {
		x := math.gcd(_i128_abs_u128(aa), _i128_abs_u128(bb))

		I128_ABS_MIN :: u128(1) << 127
		if x < I128_ABS_MIN {
			return i128(x)
		}
		result := _promote(I128_MIN, allocator)
		result.sign = .Zero_or_Positive
		return result
	}
	return _int_big_op(a, b, .Gcd, allocator)
}

int_cmp :: proc(a, b: Int, allocator := bigint_allocator) -> slice.Ordering {
	aa, a_inline := a.(i128)
	bb, b_inline := b.(i128)
	if intrinsics.likely(a_inline && b_inline) {
		switch {
		case aa < bb:
			return .Less
		case aa > bb:
			return .Greater
		case:
			return .Equal
		}
	}

	a_big := _promote(aa, allocator) if a_inline else a.(^big.Int)
	b_big := _promote(bb, allocator) if b_inline else b.(^big.Int)
	comparison, err := big.cmp(a_big, b_big, allocator)
	assert(err == nil)
	switch {
	case comparison < 0:
		return .Less
	case comparison > 0:
		return .Greater
	case:
		return .Equal
	}
}

int_eq :: proc(a, b: Int, allocator := bigint_allocator) -> bool {
	return #force_inline int_cmp(a, b, allocator) == .Equal
}

int_ne :: proc(a, b: Int, allocator := bigint_allocator) -> bool {
	return #force_inline int_cmp(a, b, allocator) != .Equal
}

int_lt :: proc(a, b: Int, allocator := bigint_allocator) -> bool {
	return #force_inline int_cmp(a, b, allocator) == .Less
}

int_le :: proc(a, b: Int, allocator := bigint_allocator) -> bool {
	return #force_inline int_cmp(a, b, allocator) != .Greater
}

int_gt :: proc(a, b: Int, allocator := bigint_allocator) -> bool {
	return #force_inline int_cmp(a, b, allocator) == .Greater
}

int_ge :: proc(a, b: Int, allocator := bigint_allocator) -> bool {
	return #force_inline int_cmp(a, b, allocator) != .Less
}

int_is_negative :: proc(i: Int) -> bool {
	switch ii in i {
	case i128:
		return ii < 0
	case ^big.Int:
		return ii.sign == .Negative
	}
	return false
}

rat_reduce :: proc(r: Rat, allocator := bigint_allocator) -> Rat {
	assert(!int_is_zero(r.denominator), "rational denominator is zero")
	if int_is_zero(r.numerator) {
		return {0, 1}
	}

	factor := int_gcd(r.numerator, r.denominator, allocator)
	result := Rat {
		int_div(r.numerator, factor, allocator),
		int_div(r.denominator, factor, allocator),
	}
	if int_is_negative(result.denominator) {
		inplace_negate_int(&result.numerator)
		inplace_negate_int(&result.denominator)
	}
	return result
}

rat_add :: proc(a, b: Rat, allocator := bigint_allocator) -> Rat {
	left := int_mul(a.numerator, b.denominator, allocator)
	right := int_mul(b.numerator, a.denominator, allocator)
	return rat_reduce(
		{int_add(left, right, allocator), int_mul(a.denominator, b.denominator, allocator)},
		allocator,
	)
}

rat_sub :: proc(a, b: Rat, allocator := bigint_allocator) -> Rat {
	left := int_mul(a.numerator, b.denominator, allocator)
	right := int_mul(b.numerator, a.denominator, allocator)
	return rat_reduce(
		{int_sub(left, right, allocator), int_mul(a.denominator, b.denominator, allocator)},
		allocator,
	)
}

rat_mul :: proc(a, b: Rat, allocator := bigint_allocator) -> Rat {
	return rat_reduce(
		{
			int_mul(a.numerator, b.numerator, allocator),
			int_mul(a.denominator, b.denominator, allocator),
		},
		allocator,
	)
}

rat_div :: proc(a, b: Rat, allocator := bigint_allocator) -> Rat {
	assert(!int_is_zero(b.numerator), "division by zero")
	return rat_reduce(
		{
			int_mul(a.numerator, b.denominator, allocator),
			int_mul(a.denominator, b.numerator, allocator),
		},
		allocator,
	)
}

rat_rem :: proc(a, b: Rat, allocator := bigint_allocator) -> Rat {
	assert(!int_is_zero(b.numerator), "division by zero")
	left := int_mul(a.numerator, b.denominator, allocator)
	right := int_mul(a.denominator, b.numerator, allocator)
	return rat_reduce(
		{int_rem(left, right, allocator), int_mul(a.denominator, b.denominator, allocator)},
		allocator,
	)
}

rat_cmp :: proc(a, b: Rat, allocator := bigint_allocator) -> slice.Ordering {
	assert(!int_is_zero(a.denominator), "rational denominator is zero")
	assert(!int_is_zero(b.denominator), "rational denominator is zero")
	left := int_mul(a.numerator, b.denominator, allocator)
	right := int_mul(b.numerator, a.denominator, allocator)
	ordering := int_cmp(left, right, allocator)
	if int_is_negative(a.denominator) != int_is_negative(b.denominator) {
		switch ordering {
		case .Less:
			return .Greater
		case .Greater:
			return .Less
		case .Equal:
			return .Equal
		}
	}
	return ordering
}

rat_eq :: proc(a, b: Rat, allocator := bigint_allocator) -> bool {
	return #force_inline rat_cmp(a, b, allocator) == .Equal
}

rat_ne :: proc(a, b: Rat, allocator := bigint_allocator) -> bool {
	return #force_inline rat_cmp(a, b, allocator) != .Equal
}

rat_lt :: proc(a, b: Rat, allocator := bigint_allocator) -> bool {
	return #force_inline rat_cmp(a, b, allocator) == .Less
}

rat_le :: proc(a, b: Rat, allocator := bigint_allocator) -> bool {
	return #force_inline rat_cmp(a, b, allocator) != .Greater
}

rat_gt :: proc(a, b: Rat, allocator := bigint_allocator) -> bool {
	return #force_inline rat_cmp(a, b, allocator) == .Greater
}

rat_ge :: proc(a, b: Rat, allocator := bigint_allocator) -> bool {
	return #force_inline rat_cmp(a, b, allocator) != .Less
}

int_is_one :: proc(i: Int) -> bool {
	switch ii in i {
	case i128:
		return ii == 1
	case ^big.Int:
		is_one, err := big.eq(ii, big.INT_ONE)
		return err == nil && is_one
	}
	return false
}

rat_is_one :: proc(r: Rat) -> bool {
	return int_is_one(r.numerator) && int_is_one(r.denominator)
}

int_is_zero :: proc(i: Int) -> bool {
	switch ii in i {
	case i128:
		return ii == 0
	case ^big.Int:
		is_zero, err := big.eq(ii, big.INT_ZERO)
		return err == nil && is_zero
	}
	return false
}

rat_is_zero :: proc(r: Rat) -> bool {
	return int_is_zero(r.numerator) && !int_is_zero(r.denominator)
}

I128_MIN :: -1 << 127

inplace_negate_int :: proc(i: ^Int) {
	switch &ii in i^ {
	case i128:
		if intrinsics.unlikely(ii == I128_MIN) {
			result := _promote(ii)
			result.sign = .Zero_or_Positive
			i^ = result
		} else {
			i^ = -ii
		}
	case ^big.Int:
		if ii.sign == .Zero_or_Positive {
			ii.sign = .Negative
		} else {
			ii.sign = .Zero_or_Positive
		}
	}
}
