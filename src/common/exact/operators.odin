package exact

import "base:intrinsics"
import "core:math"
import "core:math/big"
import "core:slice"

add :: proc {
	int_add,
	rat_add,
	decimal_add,
}

sub :: proc {
	int_sub,
	rat_sub,
	decimal_sub,
}

mul :: proc {
	int_mul,
	rat_mul,
	decimal_mul,
}

pow :: proc {
	int_pow_int,
	rat_pow_int,
}

div :: proc {
	int_div,
	rat_div,
}

divrem :: proc {
	int_divrem,
}

floordiv :: proc {
	int_div,
	rat_floordiv,
	decimal_floordiv,
}

floor_div :: floordiv

rem :: proc {
	int_rem,
	rat_rem,
	decimal_rem,
}

mod :: proc {
	int_mod,
	rat_mod,
}

cmp :: proc {
	int_cmp,
	rat_cmp,
	decimal_cmp,
}

eq :: proc {
	int_eq,
	rat_eq,
	decimal_eq,
}

ne :: proc {
	int_ne,
	rat_ne,
	decimal_ne,
}

lt :: proc {
	int_lt,
	rat_lt,
	decimal_lt,
}

le :: proc {
	int_le,
	rat_le,
	decimal_le,
}

gt :: proc {
	int_gt,
	rat_gt,
	decimal_gt,
}

ge :: proc {
	int_ge,
	rat_ge,
	decimal_ge,
}

negate :: proc {
	int_negate,
	rat_negate,
}

reciprocal :: proc {
	int_reciprocal,
	rat_reciprocal,
}

decimal_digit_count :: proc {
	int_decimal_digit_count,
	decimal_decimal_digit_count,
}

is_negative :: proc {
	int_is_negative,
	rat_is_negative,
	decimal_is_negative,
}

is_one :: proc {
	int_is_one,
	rat_is_one,
	decimal_is_one,
}

is_zero :: proc {
	int_is_zero,
	rat_is_zero,
	decimal_is_zero,
}

is_even :: proc {
	int_is_even,
	rat_is_even,
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
		a_big = _promote(aa, context.temp_allocator)
	case ^big.Int:
		a_big = aa
	}

	b_big: ^big.Int
	switch bb in b {
	case i128:
		b_big = _promote(bb, context.temp_allocator)
	case ^big.Int:
		b_big = bb
	}

	result := new(big.Int, context.temp_allocator)
	err: big.Error
	switch op {
	case .Add:
		err = big.add(result, a_big, b_big, context.temp_allocator)
	case .Sub:
		err = big.sub(result, a_big, b_big, context.temp_allocator)
	case .Mul:
		err = big.mul(result, a_big, b_big, context.temp_allocator)
	case .Div:
		err = big.div(result, a_big, b_big, context.temp_allocator)
	case .Rem:
		err = big.divmod(nil, result, a_big, b_big, context.temp_allocator)
	case .Gcd:
		err = big.gcd(result, a_big, b_big, context.temp_allocator)
	}
	assert(err == nil)

	if inline, ok := _demote(result); ok {
		return inline
	}
	return clone(result, allocator)
}

int_negate :: proc(i: Int, allocator := bigint_allocator) -> Int {
	i := clone(i, allocator)
	inplace_negate_int(&i, allocator)
	return i
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

int_divrem :: proc(a, b: Int, allocator := bigint_allocator) -> (Int, Int) {
	assert(!int_is_zero(b), "division by zero")
	aa, a_inline := a.(i128)
	bb, b_inline := b.(i128)
	if intrinsics.likely(a_inline && b_inline) {
		if aa != I128_MIN || bb != -1 {
			return math.divmod(aa, bb)
		}
	}

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

	quotient := new(big.Int, allocator)
	remainder := new(big.Int, allocator)
	err := big.divmod(quotient, remainder, a_big, b_big, allocator)
	assert(err == nil)

	q_res: Int = quotient
	if d, ok := _demote(quotient); ok {
		q_res = d
	}
	r_res: Int = remainder
	if r, ok := _demote(remainder); ok {
		r_res = r
	}
	return q_res, r_res
}

int_div_half_even :: proc(a, b: Int, allocator := bigint_allocator) -> Int {
	q, r := divrem(a, b, context.temp_allocator)
	twice_remainder := mul(int_abs(r, context.temp_allocator), 2, context.temp_allocator)
	abs_denominator := int_abs(b, context.temp_allocator)
	switch cmp(twice_remainder, abs_denominator, context.temp_allocator) {
	case .Less:
		return clone(q, allocator)
	case .Greater:
		step := -1 if is_negative(a) != is_negative(b) else 1
		return add(q, Int(i128(step)), allocator)
	case .Equal:
		if int_is_even(q) {
			return clone(q, allocator)
		}
		step := -1 if is_negative(a) != is_negative(b) else 1
		return add(q, Int(i128(step)), allocator)
	}
	unreachable()
}

int_div_pow2_half_even :: proc(a, b: Int, shift: int, allocator := bigint_allocator) -> Int {
	if shift >= 0 {
		scale := int_shl(1, uint(shift), context.temp_allocator)
		return int_div_half_even(mul(a, scale, context.temp_allocator), b, allocator)
	}

	scale := int_shl(1, uint(-shift), context.temp_allocator)
	return int_div_half_even(a, mul(b, scale, context.temp_allocator), allocator)
}

int_bit_length :: proc(i: Int) -> int {
	ii, i_inline := i.(i128)
	if intrinsics.likely(i_inline) {
		return 128 - int(intrinsics.count_leading_zeros(_i128_abs_u128(ii)))
	}

	result, err := big.count_bits(i.(^big.Int), context.temp_allocator)
	assert(err == nil)
	return result
}

decimal_decimal_digit_count :: proc(d: Decimal) -> int {
	return #force_inline int_decimal_digit_count(d.significand)
}

int_decimal_digit_count :: proc(i: Int) -> int {
	switch ii in i {
	case i128:
		magnitude := _i128_abs_u128(ii)
		digits := 1
		for magnitude >= 10 {
			magnitude /= 10
			digits += 1
		}
		return digits
	case ^big.Int:
		if int_is_zero(i) {
			return 1
		}
		magnitude := ii^
		magnitude.sign = .Zero_or_Positive
		log, err := big.log(&magnitude, 10, context.temp_allocator)
		assert(err == nil)
		return log + 1
	}
	unreachable()
}

int_shl :: proc(i: Int, shift: uint, allocator := bigint_allocator) -> Int {
	if inline, ok := i.(i128); ok && int_bit_length(inline) + int(shift) < 127 {
		return inline << shift
	}

	base: ^big.Int
	switch ii in i {
	case i128:
		base = _promote(ii, context.temp_allocator)
	case ^big.Int:
		base = ii
	}

	result := new(big.Int, allocator)
	err := big.shl(result, base, int(shift), allocator)
	assert(err == nil)
	return result
}

int_floor_log2_ratio :: proc(a, b: Int) -> int {
	e0 := int_bit_length(a) - int_bit_length(b)

	if e0 >= 0 {
		if lt(a, int_shl(b, uint(e0), context.temp_allocator), context.temp_allocator) {
			return e0 - 1
		} else {
			return e0
		}
	} else {
		if lt(int_shl(a, uint(-e0), context.temp_allocator), b, context.temp_allocator) {
			return e0 - 1
		} else {
			return e0
		}
	}
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

rat_reduce :: proc(r: Rat, allocator := bigint_allocator) -> Rat {
	assert(!int_is_zero(r.denominator), "rational denominator is zero")
	if int_is_zero(r.numerator) {
		return {0, 1}
	}

	factor := int_gcd(r.numerator, r.denominator, context.temp_allocator)
	result := Rat {
		int_div(r.numerator, factor, allocator),
		int_div(r.denominator, factor, allocator),
	}
	if int_is_negative(result.denominator) {
		inplace_negate_int(&result.numerator, allocator)
		inplace_negate_int(&result.denominator, allocator)
	}
	return result
}

rat_negate :: proc(r: Rat, allocator := bigint_allocator) -> Rat {
	return {int_negate(r.numerator, allocator), clone(r.denominator, allocator)}
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

int_pow_int :: proc(base: Int, pow: uint, allocator := bigint_allocator) -> Int {
	result := Int(i128(1))
	cur_sq := base
	for i in 0 ..< (size_of(type_of(pow)) * 8) - intrinsics.count_leading_zeros(pow) {
		bit := (pow >> u8(i)) & 0b1
		if bit != 0 {
			result = mul(result, cur_sq, context.temp_allocator)
		}
		cur_sq = mul(cur_sq, cur_sq, context.temp_allocator)
	}
	return clone(result, allocator)
}

rat_pow_int :: proc(base: Rat, pow: int, allocator := bigint_allocator) -> Rat {
	result := RAT_ONE
	cur_sq := base
	unsigned_pow := uint(abs(pow))
	for i in 0 ..< (size_of(type_of(unsigned_pow)) * 8) - intrinsics.count_leading_zeros(unsigned_pow) {
		bit := (unsigned_pow >> u8(i)) & 0b1
		if bit != 0 {
			result = mul(result, cur_sq, context.temp_allocator)
		}
		cur_sq = mul(cur_sq, cur_sq, context.temp_allocator)
	}
	if pow < 0 {
		result = reciprocal(result)
	}
	return clone(result, allocator)
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

int_reciprocal :: proc "contextless" (i: Int) -> Rat {
	return {i128(1), i}
}

rat_reciprocal :: proc "contextless" (r: Rat) -> Rat {
	return {r.denominator, r.numerator}
}

_mod :: proc(lhs, rhs: $T, allocator := bigint_allocator) -> T {
	rem := rem(lhs, rhs, allocator)
	if !is_negative(rem) {
		return rem
	}
	return add(rhs, rem, allocator)
}
rat_mod :: proc(lhs, rhs: Rat, allocator := bigint_allocator) -> Rat {
	return #force_inline _mod(lhs, rhs, allocator)
}
int_mod :: proc(lhs, rhs: Int, allocator := bigint_allocator) -> Int {
	return #force_inline _mod(lhs, rhs, allocator)
}

rat_floordiv :: proc(lhs, rhs: Rat, allocator := bigint_allocator) -> Rat {
	quotient := div(lhs, rhs, allocator)
	whole := int_div(quotient.numerator, quotient.denominator, allocator)
	rem := int_rem(quotient.numerator, quotient.denominator, allocator)
	if rat_is_negative(quotient) && !int_is_zero(rem) {
		whole = int_sub(whole, Int(i128(1)), allocator)
	}
	return Rat{numerator = whole, denominator = i128(1)}
}

_decimal_rescale :: proc(value: Decimal, scale: int, allocator := bigint_allocator) -> Int {
	assert(scale >= value.scale, "decimal scale cannot decrease")
	if scale == value.scale {
		return clone(value.significand, allocator)
	}
	factor := int_pow_int(Int(i128(10)), uint(scale - value.scale), context.temp_allocator)
	return int_mul(value.significand, factor, allocator)
}

_decimal_aligned :: proc(a, b: Decimal) -> (Int, Int, int) {
	scale := max(a.scale, b.scale)
	return _decimal_rescale(a, scale, context.temp_allocator),
		_decimal_rescale(b, scale, context.temp_allocator),
		scale
}

decimal_add :: proc(a, b: Decimal, allocator := bigint_allocator) -> Decimal {
	aa, bb, scale := _decimal_aligned(a, b)
	return {int_add(aa, bb, allocator), scale}
}

decimal_sub :: proc(a, b: Decimal, allocator := bigint_allocator) -> Decimal {
	aa, bb, scale := _decimal_aligned(a, b)
	return {int_sub(aa, bb, allocator), scale}
}

decimal_mul :: proc(a, b: Decimal, allocator := bigint_allocator) -> Decimal {
	natural_scale := a.scale + b.scale
	scale := max(max(a.scale, b.scale), natural_scale)
	significand := int_mul(a.significand, b.significand, context.temp_allocator)
	return {_decimal_rescale({significand, natural_scale}, scale, allocator), scale}
}

decimal_div_with_precision :: proc(
	a, b: Decimal,
	precision: int,
	allocator := bigint_allocator,
) -> Decimal {
	assert(precision >= 0, "decimal division precision cannot be negative")
	base_scale := max(a.scale, b.scale)
	assert(base_scale <= max(int) - precision, "decimal division scale overflow")
	aa := _decimal_rescale(a, base_scale, context.temp_allocator)
	bb := _decimal_rescale(b, base_scale, context.temp_allocator)
	return rat_to_decimal_rounded({aa, bb}, base_scale + precision, allocator)
}

decimal_rem :: proc(a, b: Decimal, allocator := bigint_allocator) -> Decimal {
	aa, bb, scale := _decimal_aligned(a, b)
	return {int_rem(aa, bb, allocator), scale}
}

decimal_floordiv :: proc(a, b: Decimal, allocator := bigint_allocator) -> Decimal {
	aa, bb, _ := _decimal_aligned(a, b)
	quotient, remainder := int_divrem(aa, bb, context.temp_allocator)
	if int_is_negative(aa) != int_is_negative(bb) && !int_is_zero(remainder) {
		quotient = int_sub(quotient, Int(i128(1)), context.temp_allocator)
	}
	return {clone(quotient, allocator), 0}
}

decimal_cmp :: proc(a, b: Decimal, allocator := bigint_allocator) -> slice.Ordering {
	aa, bb, _ := _decimal_aligned(a, b)
	return int_cmp(aa, bb, allocator)
}

decimal_eq :: proc(a, b: Decimal, allocator := bigint_allocator) -> bool {
	return #force_inline decimal_cmp(a, b, allocator) == .Equal
}

decimal_ne :: proc(a, b: Decimal, allocator := bigint_allocator) -> bool {
	return #force_inline decimal_cmp(a, b, allocator) != .Equal
}

decimal_lt :: proc(a, b: Decimal, allocator := bigint_allocator) -> bool {
	return #force_inline decimal_cmp(a, b, allocator) == .Less
}

decimal_le :: proc(a, b: Decimal, allocator := bigint_allocator) -> bool {
	return #force_inline decimal_cmp(a, b, allocator) != .Greater
}

decimal_gt :: proc(a, b: Decimal, allocator := bigint_allocator) -> bool {
	return #force_inline decimal_cmp(a, b, allocator) == .Greater
}

decimal_ge :: proc(a, b: Decimal, allocator := bigint_allocator) -> bool {
	return #force_inline decimal_cmp(a, b, allocator) != .Less
}

decimal_is_negative :: proc(value: Decimal) -> bool {
	return int_is_negative(value.significand)
}

decimal_is_one :: proc(value: Decimal) -> bool {
	return decimal_eq(value, DECIMAL_ONE, context.temp_allocator)
}

decimal_is_zero :: proc(value: Decimal) -> bool {
	return int_is_zero(value.significand)
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

int_abs :: proc(i: Int, allocator := bigint_allocator) -> Int {
	if is_negative(i) {
		return negate(i, allocator)
	} else {
		return i
	}
}

rat_is_negative :: proc(i: Rat) -> bool {
	return int_is_negative(i.numerator) != int_is_negative(i.denominator)
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

int_is_even :: proc(i: Int) -> bool {
	switch ii in i {
	case i128:
		return ii & 1 == 0
	case ^big.Int:
		return ii.digit == nil || ii.digit[0] & 1 == 0
	}
	return false
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

rat_is_even :: proc(r: Rat) -> bool {
	return int_is_even(r.numerator) && int_is_one(r.denominator)
}

I128_MIN :: -1 << 127

inplace_negate_int :: proc(i: ^Int, allocator := bigint_allocator) {
	switch &ii in i^ {
	case i128:
		if intrinsics.unlikely(ii == I128_MIN) {
			result := _promote(ii, allocator)
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
