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
	i := i
	switch &ii in i {
	case i128:
		return ii
	case big.Int:
		result: big.Int
		big.set(&result, &ii, allocator = allocator)
		return result
	}
	panic("unreachable")
}

clone_rat :: proc(r: Rat, allocator := bigint_allocator) -> Rat {
	return {clone_int(r.numerator, allocator), clone_int(r.denominator, allocator)}
}
