package exact

import "base:intrinsics"
import "core:math/big"

is_one :: proc {
	int_is_one,
	rat_is_one,
}

is_zero :: proc {
	int_is_zero,
	rat_is_zero,
}

int_is_one :: proc(i: Int) -> bool {
	i := i
	switch &ii in i {
	case i128:
		return ii == 1
	case big.Int:
		is_one, err := big.eq(&ii, big.INT_ONE)
		return err == nil && is_one
	}
	return false
}

rat_is_one :: proc(r: Rat) -> bool {
	return int_is_one(r.numerator) && int_is_one(r.denominator)
}

int_is_zero :: proc(i: Int) -> bool {
	i := i
	switch &ii in i {
	case i128:
		return ii == 0
	case big.Int:
		is_zero, err := big.eq(&ii, big.INT_ZERO)
		return err == nil && is_zero
	}
	return false
}

rat_is_zero :: proc(r: Rat) -> bool {
	return int_is_zero(r.numerator) && !int_is_zero(r.denominator)
}

I128_MIN :: -1 << 127

inline_negate :: proc(i: ^Int) {
	switch &ii in i^ {
	case i128:
		if intrinsics.expect(ii == I128_MIN, false) {
			result: big.Int
			err := big.set(&result, ii, allocator = bigint_allocator)
			assert(err == nil)
			result.sign = .Zero_or_Positive
		} else {
			i^ = -ii
		}
	case big.Int:
		if ii.sign == .Zero_or_Positive {
			ii.sign = .Negative
		} else {
			ii.sign = .Zero_or_Positive
		}
	}
}
