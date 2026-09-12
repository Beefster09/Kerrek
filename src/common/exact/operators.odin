package exact

import "base:intrinsics"
import "core:math/big"

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

_Int_Op :: enum {
	Add,
	Sub,
	Mul,
	Div,
	Rem,
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

rat_add :: proc(a, b: Rat, allocator := bigint_allocator) -> Rat {
	left := int_mul(a.numerator, b.denominator, allocator)
	right := int_mul(b.numerator, a.denominator, allocator)
	return {int_add(left, right, allocator), int_mul(a.denominator, b.denominator, allocator)}
}

rat_sub :: proc(a, b: Rat, allocator := bigint_allocator) -> Rat {
	left := int_mul(a.numerator, b.denominator, allocator)
	right := int_mul(b.numerator, a.denominator, allocator)
	return {int_sub(left, right, allocator), int_mul(a.denominator, b.denominator, allocator)}
}

rat_mul :: proc(a, b: Rat, allocator := bigint_allocator) -> Rat {
	return {
		int_mul(a.numerator, b.numerator, allocator),
		int_mul(a.denominator, b.denominator, allocator),
	}
}

rat_div :: proc(a, b: Rat, allocator := bigint_allocator) -> Rat {
	assert(!int_is_zero(b.numerator), "division by zero")
	return {
		int_mul(a.numerator, b.denominator, allocator),
		int_mul(a.denominator, b.numerator, allocator),
	}
}

rat_rem :: proc(a, b: Rat, allocator := bigint_allocator) -> Rat {
	assert(!int_is_zero(b.numerator), "division by zero")
	left := int_mul(a.numerator, b.denominator, allocator)
	right := int_mul(a.denominator, b.numerator, allocator)
	return {int_rem(left, right, allocator), int_mul(a.denominator, b.denominator, allocator)}
}

is_one :: proc {
	int_is_one,
	rat_is_one,
}

is_zero :: proc {
	int_is_zero,
	rat_is_zero,
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
