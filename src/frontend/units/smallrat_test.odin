#+test
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

_rat :: proc(n: i16, d: u8) -> Small_Rat {
	assert(MIN_DEN <= d && d <= MAX_DEN)
	return {n = n, d = d - 1}
}

@(test)
test_cmp_rat :: proc(t: ^testing.T) {
	cases := [?]Rat_Comparison_Case {
		{_rat(1, 3), _rat(1, 2), .Less},
		{_rat(1, 2), _rat(1, 3), .Greater},
		{_rat(1, 2), _rat(1, 2), .Equal},
		{_rat(2, 4), _rat(1, 2), .Equal}, // unreduced values
		{_rat(0, 32), _rat(0, 1), .Equal},
		{_rat(-1, 2), _rat(-1, 3), .Less},
		{_rat(-1, 3), _rat(-1, 2), .Greater},
		{_rat(-1, 32), _rat(0, 1), .Less},
		{_rat(1, 32), _rat(0, 1), .Greater},
		{_rat(-1024, 1), _rat(1023, 1), .Less}, // numerator boundaries
		{_rat(1023, 31), _rat(33, 1), .Equal},
		{_rat(1023, 31), _rat(1022, 31), .Greater},
		{_rat(-1024, 31), _rat(-1023, 31), .Less},
		{_rat(1, 32), _rat(1, 31), .Less}, // denominator boundary
		{_rat(31, 32), _rat(30, 31), .Greater}, // adjacent cross-products
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
		{_rat(1, 2), _rat(1, 3), _rat(5, 6), true},
		{_rat(-1, 2), _rat(1, 2), _rat(0, 1), true},
		{_rat(0, 1), _rat(7, 9), _rat(7, 9), true},
		{_rat(7, 9), _rat(0, 1), _rat(7, 9), true},
		{_rat(5, 6), _rat(-1, 2), _rat(1, 3), true},
		{_rat(-5, 6), _rat(1, 2), _rat(-1, 3), true},
		{_rat(1022, 1), _rat(1, 1), _rat(1023, 1), true}, // maximum numerator
		{_rat(1023, 1), _rat(1, 1), {}, false},
		{_rat(-1023, 1), _rat(-1, 1), _rat(-1024, 1), true}, // minimum numerator
		{_rat(-1024, 1), _rat(-1, 1), {}, false},
		{_rat(1, 32), _rat(0, 1), _rat(1, 32), true}, // maximum denominator
		{_rat(-1, 32), _rat(0, 1), _rat(-1, 32), true},
		{_rat(1, 32), _rat(1, 32), _rat(1, 16), true}, // oversized intermediate reduces
		{_rat(1, 32), _rat(1, 31), {}, false}, // irreducible denominator overflow
		{_rat(511, 31), _rat(512, 31), _rat(33, 1), true},
		{_rat(1000, 31), _rat(23, 31), _rat(33, 1), true},
		{_rat(-1000, 31), _rat(-23, 31), _rat(-33, 1), true},
		{_rat(17, 29), _rat(-13, 23), {}, false},
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
		{_rat(1, 2), _rat(1, 3), _rat(1, 6), true},
		{_rat(1, 2), _rat(1, 2), _rat(0, 1), true},
		{_rat(0, 1), _rat(7, 9), _rat(-7, 9), true},
		{_rat(7, 9), _rat(0, 1), _rat(7, 9), true},
		{_rat(5, 6), _rat(-1, 2), _rat(4, 3), true},
		{_rat(-5, 6), _rat(1, 2), _rat(-4, 3), true},
		{_rat(1023, 1), _rat(0, 1), _rat(1023, 1), true}, // maximum numerator
		{_rat(1023, 1), _rat(-1, 1), {}, false},
		{_rat(-1024, 1), _rat(0, 1), _rat(-1024, 1), true}, // minimum numerator
		{_rat(-1024, 1), _rat(1, 1), {}, false},
		{_rat(1, 32), _rat(0, 1), _rat(1, 32), true}, // maximum denominator
		{_rat(1, 32), _rat(-1, 32), _rat(1, 16), true}, // oversized intermediate reduces
		{_rat(1, 32), _rat(-1, 31), {}, false}, // irreducible denominator overflow
		{_rat(512, 31), _rat(-511, 31), _rat(33, 1), true},
		{_rat(-512, 31), _rat(511, 31), _rat(-33, 1), true},
		{_rat(17, 29), _rat(13, 23), {}, false},
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
		{_rat(1, 2), _rat(1, 3), _rat(1, 6), true},
		{_rat(-1, 2), _rat(1, 3), _rat(-1, 6), true},
		{_rat(-1, 2), _rat(-1, 3), _rat(1, 6), true},
		{_rat(0, 1), _rat(1023, 1), _rat(0, 1), true},
		{_rat(1023, 1), _rat(1, 1), _rat(1023, 1), true}, // maximum numerator
		{_rat(-1024, 1), _rat(1, 1), _rat(-1024, 1), true}, // minimum numerator
		{_rat(512, 1), _rat(2, 1), {}, false},
		{_rat(-1024, 1), _rat(-1, 1), {}, false},
		{_rat(1, 32), _rat(1, 1), _rat(1, 32), true}, // maximum denominator
		{_rat(1, 32), _rat(1, 2), {}, false}, // irreducible denominator overflow
		{_rat(2, 32), _rat(1, 2), _rat(1, 32), true}, // oversized denominator reduces
		{_rat(1023, 31), _rat(31, 3), _rat(341, 1), true}, // cross-cancellation
		{_rat(1000, 31), _rat(31, 25), _rat(40, 1), true},
		{_rat(33, 29), _rat(31, 3), _rat(341, 29), true},
		{_rat(-33, 29), _rat(31, 3), _rat(-341, 29), true},
		{_rat(100, 29), _rat(31, 3), {}, false}, // numerator overflow after reduction
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
		{_rat(1, 2), _rat(1, 3), _rat(3, 2), true},
		{_rat(-1, 2), _rat(1, 3), _rat(-3, 2), true},
		{_rat(-1, 2), _rat(-1, 3), _rat(3, 2), true},
		{_rat(0, 1), _rat(7, 9), _rat(0, 1), true},
		{_rat(1, 2), _rat(0, 1), {}, false}, // division by zero
		{_rat(0, 1), _rat(0, 1), {}, false},
		{_rat(1023, 1), _rat(1, 1), _rat(1023, 1), true}, // maximum numerator
		{_rat(-1024, 1), _rat(1, 1), _rat(-1024, 1), true}, // minimum numerator
		{_rat(1023, 1), _rat(1, 2), {}, false},
		{_rat(-1024, 1), _rat(-1, 1), {}, false},
		{_rat(1, 32), _rat(1, 1), _rat(1, 32), true}, // maximum denominator
		{_rat(1, 32), _rat(2, 1), {}, false}, // irreducible denominator overflow
		{_rat(2, 32), _rat(2, 1), _rat(1, 32), true}, // oversized denominator reduces
		{_rat(1023, 31), _rat(33, 1), _rat(1, 1), true}, // cross-cancellation
		{_rat(1000, 31), _rat(25, 31), _rat(40, 1), true},
		{_rat(31, 29), _rat(-3, 1), {}, false},
		{_rat(-1024, 31), _rat(-32, 1), _rat(32, 31), true},
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
