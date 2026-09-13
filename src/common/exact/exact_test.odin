#+test
package exact

import "core:math/big"
import "core:mem"
import "core:slice"
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
	}{{"101101", 2, "45"}, {"755", 8, "493"}, {"deadBEEF", 16, "3735928559"}}
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

	decimal_cases := [?]struct {
		source:      string,
		numerator:   string,
		denominator: string,
	} {
		{"12.34", "617", "50"},
		{"-1.25", "-5", "4"},
		{"1e3", "1000", "1"},
		{"1.5e-2", "3", "200"},
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
	_, ok = parse_hexfloat("1p-")
	testing.expect(t, !ok)
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
	_test_comparisons(t)
	_test_parsing(t)
}
