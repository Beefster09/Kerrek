package units

import "core:slice"
import "core:testing"

Rat_Binary_Case :: struct {
	a:        Small_Rat,
	b:        Small_Rat,
	expected: Small_Rat,
	ok:       bool,
}

Rat_Comparison_Case :: struct {
	a:        Small_Rat,
	b:        Small_Rat,
	expected: slice.Ordering,
}

rat :: proc(n: i16, d: u8) -> Small_Rat {
	assert(MIN_DEN <= d && d <= MAX_DEN)
	return {n = n, d = d - 1}
}

@(test)
test_cmp_rat :: proc(t: ^testing.T) {
	cases := [?]Rat_Comparison_Case {
		{rat(1, 3), rat(1, 2), .Less},
		{rat(1, 2), rat(1, 3), .Greater},
		{rat(1, 2), rat(1, 2), .Equal},
		{rat(2, 4), rat(1, 2), .Equal}, // unreduced values
		{rat(0, 32), rat(0, 1), .Equal},
		{rat(-1, 2), rat(-1, 3), .Less},
		{rat(-1, 3), rat(-1, 2), .Greater},
		{rat(-1, 32), rat(0, 1), .Less},
		{rat(1, 32), rat(0, 1), .Greater},
		{rat(-1024, 1), rat(1023, 1), .Less}, // numerator boundaries
		{rat(1023, 31), rat(33, 1), .Equal},
		{rat(1023, 31), rat(1022, 31), .Greater},
		{rat(-1024, 31), rat(-1023, 31), .Less},
		{rat(1, 32), rat(1, 31), .Less}, // denominator boundary
		{rat(31, 32), rat(30, 31), .Greater}, // adjacent cross-products
	}

	for tc, i in cases {
		actual := cmp_rat(tc.a, tc.b)
		testing.expectf(
			t,
			actual == tc.expected,
			"cmp_rat case %d: ordering mismatch for %v and %v: expected %v, got %v",
			i,
			tc.a,
			tc.b,
			tc.expected,
			actual,
		)
	}
}

@(test)
test_add_rat :: proc(t: ^testing.T) {
	cases := [?]Rat_Binary_Case {
		{rat(1, 2), rat(1, 3), rat(5, 6), true},
		{rat(-1, 2), rat(1, 2), rat(0, 1), true},
		{rat(0, 1), rat(7, 9), rat(7, 9), true},
		{rat(7, 9), rat(0, 1), rat(7, 9), true},
		{rat(5, 6), rat(-1, 2), rat(1, 3), true},
		{rat(-5, 6), rat(1, 2), rat(-1, 3), true},
		{rat(1022, 1), rat(1, 1), rat(1023, 1), true}, // maximum numerator
		{rat(1023, 1), rat(1, 1), {}, false},
		{rat(-1023, 1), rat(-1, 1), rat(-1024, 1), true}, // minimum numerator
		{rat(-1024, 1), rat(-1, 1), {}, false},
		{rat(1, 32), rat(0, 1), rat(1, 32), true}, // maximum denominator
		{rat(-1, 32), rat(0, 1), rat(-1, 32), true},
		{rat(1, 32), rat(1, 32), rat(1, 16), true}, // oversized intermediate reduces
		{rat(1, 32), rat(1, 31), {}, false}, // irreducible denominator overflow
		{rat(511, 31), rat(512, 31), rat(33, 1), true},
		{rat(1000, 31), rat(23, 31), rat(33, 1), true},
		{rat(-1000, 31), rat(-23, 31), rat(-33, 1), true},
		{rat(17, 29), rat(-13, 23), {}, false},
	}

	for tc, i in cases {
		actual, ok := add_rat(tc.a, tc.b)
		testing.expectf(
			t,
			ok == tc.ok,
			"add_rat case %d: success mismatch for %v and %v: expected %v, got %v",
			i,
			tc.a,
			tc.b,
			tc.ok,
			ok,
		)
		if tc.ok && ok {
			testing.expectf(
				t,
				actual == tc.expected,
				"add_rat case %d: result mismatch for %v and %v: expected %v, got %v",
				i,
				tc.a,
				tc.b,
				tc.expected,
				actual,
			)
		}
	}
}

@(test)
test_sub_rat :: proc(t: ^testing.T) {
	cases := [?]Rat_Binary_Case {
		{rat(1, 2), rat(1, 3), rat(1, 6), true},
		{rat(1, 2), rat(1, 2), rat(0, 1), true},
		{rat(0, 1), rat(7, 9), rat(-7, 9), true},
		{rat(7, 9), rat(0, 1), rat(7, 9), true},
		{rat(5, 6), rat(-1, 2), rat(4, 3), true},
		{rat(-5, 6), rat(1, 2), rat(-4, 3), true},
		{rat(1023, 1), rat(0, 1), rat(1023, 1), true}, // maximum numerator
		{rat(1023, 1), rat(-1, 1), {}, false},
		{rat(-1024, 1), rat(0, 1), rat(-1024, 1), true}, // minimum numerator
		{rat(-1024, 1), rat(1, 1), {}, false},
		{rat(1, 32), rat(0, 1), rat(1, 32), true}, // maximum denominator
		{rat(1, 32), rat(-1, 32), rat(1, 16), true}, // oversized intermediate reduces
		{rat(1, 32), rat(-1, 31), {}, false}, // irreducible denominator overflow
		{rat(512, 31), rat(-511, 31), rat(33, 1), true},
		{rat(-512, 31), rat(511, 31), rat(-33, 1), true},
		{rat(17, 29), rat(13, 23), {}, false},
	}

	for tc, i in cases {
		actual, ok := sub_rat(tc.a, tc.b)
		testing.expectf(
			t,
			ok == tc.ok,
			"sub_rat case %d: success mismatch for %v and %v: expected %v, got %v",
			i,
			tc.a,
			tc.b,
			tc.ok,
			ok,
		)
		if tc.ok && ok {
			testing.expectf(
				t,
				actual == tc.expected,
				"sub_rat case %d: result mismatch for %v and %v: expected %v, got %v",
				i,
				tc.a,
				tc.b,
				tc.expected,
				actual,
			)
		}
	}
}

@(test)
test_mul_rat :: proc(t: ^testing.T) {
	cases := [?]Rat_Binary_Case {
		{rat(1, 2), rat(1, 3), rat(1, 6), true},
		{rat(-1, 2), rat(1, 3), rat(-1, 6), true},
		{rat(-1, 2), rat(-1, 3), rat(1, 6), true},
		{rat(0, 1), rat(1023, 1), rat(0, 1), true},
		{rat(1023, 1), rat(1, 1), rat(1023, 1), true}, // maximum numerator
		{rat(-1024, 1), rat(1, 1), rat(-1024, 1), true}, // minimum numerator
		{rat(512, 1), rat(2, 1), {}, false},
		{rat(-1024, 1), rat(-1, 1), {}, false},
		{rat(1, 32), rat(1, 1), rat(1, 32), true}, // maximum denominator
		{rat(1, 32), rat(1, 2), {}, false}, // irreducible denominator overflow
		{rat(2, 32), rat(1, 2), rat(1, 32), true}, // oversized denominator reduces
		{rat(1023, 31), rat(31, 3), rat(341, 1), true}, // cross-cancellation
		{rat(1000, 31), rat(31, 25), rat(40, 1), true},
		{rat(33, 29), rat(31, 3), rat(341, 29), true},
		{rat(-33, 29), rat(31, 3), rat(-341, 29), true},
		{rat(100, 29), rat(31, 3), {}, false}, // numerator overflow after reduction
	}

	for tc, i in cases {
		actual, ok := mul_rat(tc.a, tc.b)
		testing.expectf(
			t,
			ok == tc.ok,
			"mul_rat case %d: success mismatch for %v and %v: expected %v, got %v",
			i,
			tc.a,
			tc.b,
			tc.ok,
			ok,
		)
		if tc.ok && ok {
			testing.expectf(
				t,
				actual == tc.expected,
				"mul_rat case %d: result mismatch for %v and %v: expected %v, got %v",
				i,
				tc.a,
				tc.b,
				tc.expected,
				actual,
			)
		}
	}
}

@(test)
test_div_rat :: proc(t: ^testing.T) {
	cases := [?]Rat_Binary_Case {
		{rat(1, 2), rat(1, 3), rat(3, 2), true},
		{rat(-1, 2), rat(1, 3), rat(-3, 2), true},
		{rat(-1, 2), rat(-1, 3), rat(3, 2), true},
		{rat(0, 1), rat(7, 9), rat(0, 1), true},
		{rat(1, 2), rat(0, 1), {}, false}, // division by zero
		{rat(0, 1), rat(0, 1), {}, false},
		{rat(1023, 1), rat(1, 1), rat(1023, 1), true}, // maximum numerator
		{rat(-1024, 1), rat(1, 1), rat(-1024, 1), true}, // minimum numerator
		{rat(1023, 1), rat(1, 2), {}, false},
		{rat(-1024, 1), rat(-1, 1), {}, false},
		{rat(1, 32), rat(1, 1), rat(1, 32), true}, // maximum denominator
		{rat(1, 32), rat(2, 1), {}, false}, // irreducible denominator overflow
		{rat(2, 32), rat(2, 1), rat(1, 32), true}, // oversized denominator reduces
		{rat(1023, 31), rat(33, 1), rat(1, 1), true}, // cross-cancellation
		{rat(1000, 31), rat(25, 31), rat(40, 1), true},
		{rat(31, 29), rat(-3, 1), {}, false},
		{rat(-1024, 31), rat(-32, 1), rat(32, 31), true},
	}

	for tc, i in cases {
		actual, ok := div_rat(tc.a, tc.b)
		testing.expectf(
			t,
			ok == tc.ok,
			"div_rat case %d: success mismatch for %v and %v: expected %v, got %v",
			i,
			tc.a,
			tc.b,
			tc.ok,
			ok,
		)
		if tc.ok && ok {
			testing.expectf(
				t,
				actual == tc.expected,
				"div_rat case %d: result mismatch for %v and %v: expected %v, got %v",
				i,
				tc.a,
				tc.b,
				tc.expected,
				actual,
			)
		}
	}
}
