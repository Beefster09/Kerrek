#+test
package exact

import "core:math/big"
import "core:mem"
import "core:slice"
import "core:strings"
import "core:testing"

_ints_equal :: proc(a, b: Int) -> bool {
	switch aa in a {
	case i128:
		switch bb in b {
		case i128:
			return aa == bb
		case ^big.Int:
			inline, err := big.get(bb, i128)
			return err == nil && aa == inline
		}
	case ^big.Int:
		switch bb in b {
		case i128:
			inline, err := big.get(aa, i128)
			return err == nil && inline == bb
		case ^big.Int:
			equal, err := big.eq(aa, bb)
			return err == nil && equal
		}
	}
	return false
}

_expect_int :: proc(t: ^testing.T, actual: Int, expected: string) {
	expected_int, ok := parse_int(expected)
	testing.expectf(t, ok, "could not parse expected integer %q", expected)
	if ok {
		testing.expectf(
			t,
			_ints_equal(actual, expected_int),
			"expected %s (%v), got %v",
			expected,
			expected_int,
			actual,
		)
	}
}

_expect_rat :: proc(t: ^testing.T, actual: Rat, numerator, denominator: string) {
	expected_num, num_ok := parse_int(numerator)
	expected_den, den_ok := parse_int(denominator)
	testing.expectf(
		t,
		num_ok && den_ok,
		"could not parse expected rational %s/%s",
		numerator,
		denominator,
	)
	if !num_ok || !den_ok {
		return
	}

	testing.expectf(
		t,
		_ints_equal(actual.numerator, expected_num) &&
		_ints_equal(actual.denominator, expected_den),
		"expected %s/%s, got %r",
		numerator,
		denominator,
		actual,
	)
}

_decimal :: proc(t: ^testing.T, significand: string, scale: int) -> Decimal {
	value, ok := parse_int(significand)
	testing.expectf(t, ok, "could not parse decimal significand %q", significand)
	return {value, scale}
}

_expect_decimal :: proc(t: ^testing.T, actual: Decimal, significand: string, scale: int) {
	expected := _decimal(t, significand, scale)
	testing.expectf(
		t,
		_ints_equal(actual.significand, expected.significand) && actual.scale == scale,
		"expected decimal %s at scale %d, got %v at scale %d",
		significand,
		scale,
		actual.significand,
		actual.scale,
	)
}

Decimal_Rounded_Conversion_Case :: struct {
	value:       Rat,
	scale:       int,
	significand: string,
}

DECIMAL_ROUNDED_CONVERSION_CASES := [?]Decimal_Rounded_Conversion_Case {
	{Rat{1, 3}, 2, "33"},
	{Rat{2, 3}, 2, "67"},
	{Rat{-2, 3}, 2, "-67"},
	{Rat{5, 2}, 0, "2"},
	{Rat{7, 2}, 0, "4"},
	{Rat{-5, 2}, 0, "-2"},
	{Rat{-7, 2}, 0, "-4"},
	{Rat{7, -2}, 0, "-4"},
	{Rat{15, 100}, 1, "2"},
	{Rat{25, 100}, 1, "2"},
	{Rat{-15, 100}, 1, "-2"},
	{Rat{145, 1}, -1, "14"},
	{Rat{155, 1}, -1, "16"},
}

Decimal_Division_Case :: struct {
	left_significand:  string,
	left_scale:        int,
	right_significand: string,
	right_scale:       int,
	precision:         int,
	significand:       string,
	scale:             int,
}

@(rodata)
DECIMAL_DIVISION_CASES := [?]Decimal_Division_Case {
	{"1", 0, "3", 0, 2, "33", 2},
	{"100", 2, "300", 2, 2, "3333", 4},
	{"-1", 0, "8", 0, 2, "-12", 2},
	{"-3", 0, "8", 0, 2, "-38", 2},
	{"1", -1, "4", -1, 3, "25", 2},
	{"1234", 2, "2", 0, 0, "617", 2},
}

@(rodata)
DECIMAL_DIGIT_COUNT_CASES := [?]struct {
	value:  string,
	digits: int,
} {
	{"0", 1},
	{"9", 1},
	{"-9", 1},
	{"10", 2},
	{"-10", 2},
	{"170141183460469231731687303715884105727", 39},
	{"-170141183460469231731687303715884105728", 39},
	{"9999999999999999999999999999999999999999999999999999999999999999999999999999", 76},
	{"-10000000000000000000000000000000000000000000000000000000000000000000000000000", 77},
}

_expect_int_ordering :: proc(t: ^testing.T, a, b: Int, expected: slice.Ordering) {
	actual := cmp(a, b)
	testing.expectf(
		t,
		actual == expected,
		"expected integer ordering %v, got %v",
		expected,
		actual,
	)
	testing.expect(t, eq(a, b) == (expected == .Equal))
	testing.expect(t, ne(a, b) == (expected != .Equal))
	testing.expect(t, lt(a, b) == (expected == .Less))
	testing.expect(t, le(a, b) == (expected != .Greater))
	testing.expect(t, gt(a, b) == (expected == .Greater))
	testing.expect(t, ge(a, b) == (expected != .Less))
}

_expect_rat_ordering :: proc(t: ^testing.T, a, b: Rat, expected: slice.Ordering) {
	actual := cmp(a, b)
	testing.expectf(
		t,
		actual == expected,
		"expected rational ordering %v, got %v",
		expected,
		actual,
	)
	testing.expect(t, eq(a, b) == (expected == .Equal))
	testing.expect(t, ne(a, b) == (expected != .Equal))
	testing.expect(t, lt(a, b) == (expected == .Less))
	testing.expect(t, le(a, b) == (expected != .Greater))
	testing.expect(t, gt(a, b) == (expected == .Greater))
	testing.expect(t, ge(a, b) == (expected != .Less))
}

_expect_decimal_ordering :: proc(t: ^testing.T, a, b: Decimal, expected: slice.Ordering) {
	actual := cmp(a, b)
	testing.expectf(
		t,
		actual == expected,
		"expected decimal ordering %v, got %v",
		expected,
		actual,
	)
	testing.expect(t, eq(a, b) == (expected == .Equal))
	testing.expect(t, ne(a, b) == (expected != .Equal))
	testing.expect(t, lt(a, b) == (expected == .Less))
	testing.expect(t, le(a, b) == (expected != .Greater))
	testing.expect(t, gt(a, b) == (expected == .Greater))
	testing.expect(t, ge(a, b) == (expected != .Less))
}

_test_comparisons :: proc(t: ^testing.T) {
	_expect_int_ordering(t, Int(-3), Int(-2), .Less)
	_expect_int_ordering(t, Int(5), Int(5), .Equal)
	_expect_int_ordering(t, Int(8), Int(5), .Greater)

	large, large_ok := parse_int("170141183460469231731687303715884105728")
	large_copy, large_copy_ok := parse_int("170141183460469231731687303715884105728")
	negative_large, negative_large_ok := parse_int("-170141183460469231731687303715884105729")
	testing.expect(t, large_ok && large_copy_ok && negative_large_ok)
	if large_ok && large_copy_ok && negative_large_ok {
		I128_MAX :: (1 << 127) - 1
		_expect_int_ordering(t, Int(I128_MAX), large, .Less)
		_expect_int_ordering(t, large, Int(I128_MAX), .Greater)
		_expect_int_ordering(t, large, large_copy, .Equal)
		_expect_int_ordering(t, negative_large, Int(I128_MIN), .Less)

		_expect_rat_ordering(t, Rat{large, 2}, Rat{Int(I128_MAX), 1}, .Less)
	}

	_expect_rat_ordering(t, Rat{1, 3}, Rat{1, 2}, .Less)
	_expect_rat_ordering(t, Rat{2, 4}, Rat{1, 2}, .Equal)
	_expect_rat_ordering(t, Rat{-1, 2}, Rat{-1, 3}, .Less)
	_expect_rat_ordering(t, Rat{1, -2}, Rat{-1, 3}, .Less)
	_expect_rat_ordering(t, Rat{-1, -2}, Rat{1, 2}, .Equal)
	_expect_rat_ordering(t, Rat{0, -7}, Rat{0, 1}, .Equal)
}

_test_gcd_and_reduction :: proc(t: ^testing.T) {
	_expect_int(t, gcd(Int(54), Int(24)), "6")
	_expect_int(t, gcd(Int(-54), Int(24)), "6")
	_expect_int(t, gcd(Int(0), Int(24)), "24")
	_expect_int(t, gcd(Int(I128_MIN), Int(0)), "170141183460469231731687303715884105728")

	large, large_ok := parse_int("170141183460469231731687303715884105728")
	half, half_ok := parse_int("85070591730234615865843651857942052864")
	testing.expect(t, large_ok && half_ok)
	if large_ok && half_ok {
		_expect_int(t, gcd(large, half), "85070591730234615865843651857942052864")
	}

	_expect_rat(t, reduce(Rat{6, 8}), "3", "4")
	_expect_rat(t, reduce(Rat{-6, -8}), "3", "4")
	_expect_rat(t, reduce(Rat{6, -8}), "-3", "4")
	_expect_rat(t, reduce(Rat{0, -8}), "0", "1")
}

_test_int_arithmetic :: proc(t: ^testing.T) {
	I128_MAX :: (1 << 127) - 1

	_expect_int(t, add(Int(2), Int(3)), "5")
	_expect_int(t, add(Int(I128_MAX), Int(1)), "170141183460469231731687303715884105728")
	_expect_int(t, sub(Int(I128_MIN), Int(1)), "-170141183460469231731687303715884105729")
	_expect_int(t, mul(Int(I128_MAX), Int(2)), "340282366920938463463374607431768211454")

	large, ok := parse_int("170141183460469231731687303715884105728")
	testing.expect(t, ok)
	if ok {
		_expect_int(t, sub(large, Int(1)), "170141183460469231731687303715884105727")
		_expect_int(t, div(large, Int(2)), "85070591730234615865843651857942052864")
		_expect_int(t, rem(large, Int(3)), "2")
	}
	negative_large, negative_ok := parse_int("-170141183460469231731687303715884105728")
	testing.expect(t, negative_ok)
	if negative_ok {
		demoted := add(negative_large, Int(1))
		_, inline := demoted.(i128)
		testing.expect(t, inline)
		_expect_int(t, demoted, "-170141183460469231731687303715884105727")
		_expect_int(t, rem(negative_large, Int(3)), "-2")
	}

	_expect_int(t, div(Int(-7), Int(3)), "-2")
	_expect_int(t, div(Int(I128_MIN), Int(-1)), "170141183460469231731687303715884105728")
	_expect_int(t, rem(Int(-7), Int(3)), "-1")
	_expect_int(t, rem(Int(I128_MIN), Int(-1)), "0")
}

_test_rat_arithmetic :: proc(t: ^testing.T) {
	_expect_rat(t, add(Rat{1, 2}, Rat{1, 3}), "5", "6")
	_expect_rat(t, sub(Rat{1, 2}, Rat{5, 6}), "-1", "3")
	_expect_rat(t, mul(Rat{-2, 3}, Rat{9, 10}), "-3", "5")
	_expect_rat(t, div(Rat{2, 3}, Rat{-4, 5}), "-5", "6")
	_expect_rat(t, rem(Rat{7, 3}, Rat{2, 3}), "1", "3")
	_expect_rat(t, rem(Rat{-7, 3}, Rat{2, 3}), "-1", "3")

	large, ok := parse_int("170141183460469231731687303715884105728")
	testing.expect(t, ok)
	if ok {
		_expect_rat(
			t,
			add(Rat{large, 1}, Rat{1, 2}),
			"340282366920938463463374607431768211457",
			"2",
		)
	}
}

_test_decimal_arithmetic :: proc(t: ^testing.T) {
	a := _decimal(t, "1234", 2)
	b := _decimal(t, "6", 1)
	_expect_decimal(t, add(a, b), "1294", 2)
	_expect_decimal(t, sub(a, b), "1174", 2)
	_expect_decimal(t, mul(_decimal(t, "123", 2), _decimal(t, "20", 1)), "2460", 3)
	_expect_decimal(t, rem(a, b), "34", 2)
	_expect_decimal(t, rem(_decimal(t, "-1234", 2), b), "-34", 2)
	_expect_decimal(t, floor_div(a, b), "20", 0)
	_expect_decimal(t, floor_div(_decimal(t, "-1234", 2), b), "-21", 0)
	_expect_decimal(t, floor_div(a, _decimal(t, "-6", 1)), "-21", 0)

	_expect_decimal(t, add(_decimal(t, "12", -1), _decimal(t, "3", 1)), "1203", 1)
	_expect_decimal(t, mul(_decimal(t, "2", -1), _decimal(t, "3", -1)), "60", -1)

	large_addend := _decimal(
		t,
		"9999999999999999999999999999999999999999999999999999999999999999999999999999",
		0,
	)
	_expect_decimal(
		t,
		add(large_addend, DECIMAL_ONE),
		"10000000000000000000000000000000000000000000000000000000000000000000000000000",
		0,
	)
	_expect_decimal(
		t,
		mul(
			_decimal(t, "99999999999999999999999999999999999999", 0),
			_decimal(t, "1000000000000000000000000000000000000000", 0),
		),
		"99999999999999999999999999999999999999000000000000000000000000000000000000000",
		0,
	)
}

_test_decimal_comparisons :: proc(t: ^testing.T) {
	_expect_decimal_ordering(t, _decimal(t, "123", 2), _decimal(t, "1230", 3), .Equal)
	_expect_decimal_ordering(t, _decimal(t, "-1", -2), _decimal(t, "-999", 1), .Less)
	_expect_decimal_ordering(t, _decimal(t, "1", -2), _decimal(t, "999", 1), .Greater)

	testing.expect(t, is_one(DECIMAL_ONE))
	testing.expect(t, is_one(_decimal(t, "100", 2)))
	testing.expect(t, !is_one(_decimal(t, "10", 2)))
	testing.expect(t, is_zero(_decimal(t, "0", 77)))
	testing.expect(t, is_negative(_decimal(t, "-1", -77)))
	testing.expect(t, !is_negative(_decimal(t, "0", 0)))
}

_test_decimal_conversions :: proc(t: ^testing.T) {
	_expect_rat(t, decimal_to_rat(_decimal(t, "1234", 2)), "617", "50")
	_expect_rat(t, decimal_to_rat(_decimal(t, "123", -2)), "12300", "1")

	cases := [?]struct {
		value:       Rat,
		significand: string,
		scale:       int,
	} {
		{Rat{617, 50}, "1234", 2},
		{Rat{1, 8}, "125", 3},
		{Rat{-1, -40}, "25", 3},
		{Rat{0, -7}, "0", 0},
	}
	for tc in cases {
		actual, ok := rat_to_decimal_exact(tc.value)
		testing.expect(t, ok)
		if ok {
			_expect_decimal(t, actual, tc.significand, tc.scale)
			converted_back := decimal_to_rat(actual)
			testing.expect(t, eq(converted_back, tc.value))
		}
	}

	_, ok := rat_to_decimal_exact(Rat{1, 3})
	testing.expect(t, !ok)
	large := _decimal(
		t,
		"10000000000000000000000000000000000000000000000000000000000000000000000000000",
		77,
	)
	rational := decimal_to_rat(large)
	round_trip, converted := rat_to_decimal_exact(rational)
	testing.expect(t, converted)
	if converted {
		testing.expect(t, eq(round_trip, large))
	}
}

_test_decimal_rounded_conversion :: proc(t: ^testing.T) {
	for tc in DECIMAL_ROUNDED_CONVERSION_CASES {
		actual := rat_to_decimal_rounded(tc.value, tc.scale)
		_expect_decimal(t, actual, tc.significand, tc.scale)
	}

	_expect_decimal(
		t,
		rat_to_decimal_rounded(Rat{1, 3}, 77),
		"33333333333333333333333333333333333333333333333333333333333333333333333333333",
		77,
	)
}

_test_decimal_division :: proc(t: ^testing.T) {
	for tc in DECIMAL_DIVISION_CASES {
		left := _decimal(t, tc.left_significand, tc.left_scale)
		right := _decimal(t, tc.right_significand, tc.right_scale)
		actual := decimal_div_with_precision(left, right, tc.precision)
		_expect_decimal(t, actual, tc.significand, tc.scale)
	}

	_expect_decimal(
		t,
		decimal_div_with_precision(DECIMAL_ONE, _decimal(t, "3", 0), 77),
		"33333333333333333333333333333333333333333333333333333333333333333333333333333",
		77,
	)
}

_test_decimal_digit_count :: proc(t: ^testing.T) {
	for tc in DECIMAL_DIGIT_COUNT_CASES {
		value, ok := parse_int(tc.value)
		testing.expectf(t, ok, "could not parse digit-count case %q", tc.value)
		if ok {
			testing.expect_value(t, decimal_digit_count(value), tc.digits)
		}
	}
}

_test_decimal_formatting :: proc(t: ^testing.T) {
	cases := [?]struct {
		value:    Decimal,
		expected: string,
	} {
		{_decimal(t, "1234", 0), "1234"},
		{_decimal(t, "1234", 2), "12.34"},
		{_decimal(t, "1234", 6), "0.001234"},
		{_decimal(t, "1200", 3), "1.200"},
		{_decimal(t, "-12", 4), "-0.0012"},
		{_decimal(t, "12", -3), "12000"},
		{_decimal(t, "0", 3), "0.000"},
	}
	for tc in cases {
		builder: strings.Builder
		strings.builder_init(&builder)
		write_decimal(strings.to_writer(&builder), tc.value)
		testing.expect_value(t, strings.to_string(builder), tc.expected)
		strings.builder_destroy(&builder)
	}
}

_test_rat_allocator_ownership :: proc(t: ^testing.T) {
	denominator, ok := parse_int("170141183460469231731687303715884105729")
	testing.expect(t, ok)
	if !ok {
		return
	}

	arena: mem.Dynamic_Arena
	mem.dynamic_arena_init(&arena)
	defer mem.dynamic_arena_destroy(&arena)
	allocations: mem.Tracking_Allocator
	mem.tracking_allocator_init(&allocations, mem.dynamic_arena_allocator(&arena))
	defer mem.tracking_allocator_destroy(&allocations)
	allocator := mem.tracking_allocator(&allocations)

	result := negate(Rat{I128_MIN, denominator}, allocator)
	numerator := result.numerator.(^big.Int)
	result_denominator := result.denominator.(^big.Int)
	testing.expect(t, rawptr(numerator) in allocations.allocation_map)
	testing.expect(t, rawptr(result_denominator) in allocations.allocation_map)
	testing.expect(t, result_denominator != denominator.(^big.Int))
}

_test_bigint_formatting :: proc(t: ^testing.T) {
	heap_source := strings.repeat("9", STACK_DIGITS + 1)
	defer delete(heap_source)
	cases := []string {
		"170141183460469231731687303715884105729",
		"-170141183460469231731687303715884105729",
		heap_source,
	}
	for source in cases {
		value, ok := parse_int(source)
		testing.expect(t, ok)
		if !ok {
			continue
		}

		builder: strings.Builder
		strings.builder_init(&builder)
		write_int(strings.to_writer(&builder), value)
		testing.expect_value(t, strings.to_string(builder), source)
		strings.builder_destroy(&builder)
	}
}

_test_parsing :: proc(t: ^testing.T) {
	value, ok := parse_int("170141183460469231731687303715884105728")
	testing.expect(t, ok)
	if ok {
		_expect_int(t, value, "170141183460469231731687303715884105728")
	}

	int_cases := [?]struct {
		source: string,
		radix:  int,
		value:  string,
	} {
		{"101_101", 2, "45"},
		{"7_5_5", 8, "493"},
		{"dead_BEEF", 16, "3735928559"},
		// Exercise the big.Int fallback with separators as well as the i128 path.
		{"170_141_183_460_469_231_731_687_303_715_884_105_728", 10, "170141183460469231731687303715884105728"},
	}
	for tc in int_cases {
		actual, parsed := parse_int(tc.source, tc.radix)
		testing.expectf(t, parsed, "expected %q (base %d) to parse", tc.source, tc.radix)
		if parsed {
			_expect_int(t, actual, tc.value)
		}
	}

	_, ok = parse_int("12z", 10)
	testing.expect(t, !ok)
	_, ok = parse_int("2", 2)
	testing.expect(t, !ok)
	_, ok = parse_int("")
	testing.expect(t, !ok)
	_, ok = parse_int("+")
	testing.expect(t, !ok)
	invalid_integer_separators := [?]string{"_1", "1_", "1__2", "+_1", "-_1"}
	for source in invalid_integer_separators {
		_, parsed := parse_int(source)
		testing.expectf(t, !parsed, "expected integer %q to reject misplaced separators", source)
	}

	decimal_cases := [?]struct {
		source:      string,
		numerator:   string,
		denominator: string,
	} {
		{"12.34", "617", "50"},
		{"-1.25", "-5", "4"},
		{"1e3", "1000", "1"},
		{"1.5e-2", "3", "200"},
		{"1_2.5_0e-1_0", "1", "800000000"},
		{"0.00", "0", "1"},
	}
	for tc in decimal_cases {
		actual, parsed := parse_decimal(tc.source)
		testing.expectf(t, parsed, "expected decimal %q to parse", tc.source)
		if parsed {
			_expect_rat(t, actual, tc.numerator, tc.denominator)
		}
	}

	hexfloat_cases := [?]struct {
		source:      string,
		numerator:   string,
		denominator: string,
	} {
		{"1p2", "4", "1"},
		{"1.8p1", "3", "1"},
		{"1p-1", "1", "2"},
		{"-a.fp2", "-175", "4"},
		{"1p10", "1024", "1"},
	}
	for tc in hexfloat_cases {
		actual, parsed := parse_hexfloat(tc.source)
		testing.expectf(t, parsed, "expected hexadecimal float %q to parse", tc.source)
		if parsed {
			_expect_rat(t, actual, tc.numerator, tc.denominator)
		}
	}

	_, ok = parse_decimal("1e+")
	testing.expect(t, !ok)
	_, ok = parse_decimal("1.2.3")
	testing.expect(t, !ok)
	invalid_fractional_separators := [?]string {
		"_1.0",
		"1_.0",
		"1._0",
		"1.0_",
		"1__0.0",
		"1_e2",
		"1e_2",
		"1e2_",
		"1e+_2",
	}
	for source in invalid_fractional_separators {
		_, parsed := parse_decimal(source)
		testing.expectf(t, !parsed, "expected decimal %q to reject misplaced separators", source)
	}
	_, ok = parse_hexfloat("1p-")
	testing.expect(t, !ok)
	invalid_hexfloat_separators := [?]string {
		"_1p0",
		"1_.0p0",
		"1._0p0",
		"1.0_p0",
		"1.0p_1",
		"1.0p1_",
		"1.0p+_1",
	}
	for source in invalid_hexfloat_separators {
		_, parsed := parse_hexfloat(source)
		testing.expectf(t, !parsed, "expected hex float %q to reject misplaced separators", source)
	}
	_, ok = parse_hexfloat("1p999999999999999999999999999999999999999")
	testing.expect(t, !ok)
}

@(test)
test_exact :: proc(t: ^testing.T) {
	arena: mem.Dynamic_Arena
	mem.dynamic_arena_init(&arena, block_size = 8 * mem.Kilobyte)
	defer mem.dynamic_arena_destroy(&arena)

	previous_allocator := bigint_allocator
	bigint_allocator = mem.dynamic_arena_allocator(&arena)
	defer {bigint_allocator = previous_allocator}

	_test_int_arithmetic(t)
	_test_gcd_and_reduction(t)
	_test_rat_arithmetic(t)
	_test_decimal_arithmetic(t)
	_test_decimal_comparisons(t)
	_test_decimal_conversions(t)
	_test_decimal_rounded_conversion(t)
	_test_decimal_division(t)
	_test_decimal_digit_count(t)
	_test_decimal_formatting(t)
	_test_rat_allocator_ownership(t)
	_test_bigint_formatting(t)
	_test_comparisons(t)
	_test_parsing(t)
	_test_float_conversion(t)
}
