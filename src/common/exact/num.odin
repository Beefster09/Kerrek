package common

import "base:runtime"
import "core:math/big"
import "core:mem/virtual"

bigint_allocator: runtime.Allocator
_bigint_arena: virtual.Arena


// an exact value represented as a rational
Rat :: struct {
	numerator:   ExactInt,
	denominator: ExactInt,
}

// An integer that is an i128 in the general case but promotes to bigint for very large values
Int :: union {
	i128,
	big.Int,
}


fmt_int :: proc()
