package exact

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
