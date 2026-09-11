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

@(test)
test_cmp_rat :: proc(t: ^testing.T) {
	cases := [?]Rat_Comparison_Case {
		{{n = 1, d = 3}, {n = 1, d = 2}, .Less},
		{{n = 1, d = 2}, {n = 1, d = 3}, .Greater},
		{{n = 1, d = 2}, {n = 1, d = 2}, .Equal},
		{{n = 2, d = 4}, {n = 1, d = 2}, .Equal}, // unreduced values
		{{n = 0, d = 31}, {n = 0, d = 1}, .Equal},
		{{n = -1, d = 2}, {n = -1, d = 3}, .Less},
		{{n = -1, d = 3}, {n = -1, d = 2}, .Greater},
		{{n = -1, d = 31}, {n = 0, d = 1}, .Less},
		{{n = 1, d = 31}, {n = 0, d = 1}, .Greater},
		{{n = -1024, d = 1}, {n = 1023, d = 1}, .Less}, // numerator boundaries
		{{n = 1023, d = 31}, {n = 33, d = 1}, .Equal},
		{{n = 1023, d = 31}, {n = 1022, d = 31}, .Greater},
		{{n = -1024, d = 31}, {n = -1023, d = 31}, .Less},
		{{n = 1, d = 31}, {n = 1, d = 30}, .Less}, // denominator boundary
		{{n = 30, d = 31}, {n = 29, d = 30}, .Greater}, // adjacent cross-products
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
		{{n = 1, d = 2}, {n = 1, d = 3}, {n = 5, d = 6}, true},
		{{n = -1, d = 2}, {n = 1, d = 2}, {n = 0, d = 1}, true},
		{{n = 0, d = 1}, {n = 7, d = 9}, {n = 7, d = 9}, true},
		{{n = 7, d = 9}, {n = 0, d = 1}, {n = 7, d = 9}, true},
		{{n = 5, d = 6}, {n = -1, d = 2}, {n = 1, d = 3}, true},
		{{n = -5, d = 6}, {n = 1, d = 2}, {n = -1, d = 3}, true},
		{{n = 1022, d = 1}, {n = 1, d = 1}, {n = 1023, d = 1}, true}, // maximum numerator
		{{n = 1023, d = 1}, {n = 1, d = 1}, {}, false},
		{{n = -1023, d = 1}, {n = -1, d = 1}, {n = -1024, d = 1}, true}, // minimum numerator
		{{n = -1024, d = 1}, {n = -1, d = 1}, {}, false},
		{{n = 1, d = 31}, {n = 0, d = 1}, {n = 1, d = 31}, true}, // maximum denominator
		{{n = -1, d = 31}, {n = 0, d = 1}, {n = -1, d = 31}, true},
		{{n = 1, d = 30}, {n = 1, d = 30}, {n = 1, d = 15}, true}, // oversized intermediate reduces
		{{n = 1, d = 31}, {n = 1, d = 30}, {}, false}, // irreducible denominator overflow
		{{n = 511, d = 31}, {n = 512, d = 31}, {n = 33, d = 1}, true},
		{{n = 1000, d = 31}, {n = 23, d = 31}, {n = 33, d = 1}, true},
		{{n = -1000, d = 31}, {n = -23, d = 31}, {n = -33, d = 1}, true},
		{{n = 17, d = 29}, {n = -13, d = 23}, {}, false},
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
		{{n = 1, d = 2}, {n = 1, d = 3}, {n = 1, d = 6}, true},
		{{n = 1, d = 2}, {n = 1, d = 2}, {n = 0, d = 1}, true},
		{{n = 0, d = 1}, {n = 7, d = 9}, {n = -7, d = 9}, true},
		{{n = 7, d = 9}, {n = 0, d = 1}, {n = 7, d = 9}, true},
		{{n = 5, d = 6}, {n = -1, d = 2}, {n = 4, d = 3}, true},
		{{n = -5, d = 6}, {n = 1, d = 2}, {n = -4, d = 3}, true},
		{{n = 1023, d = 1}, {n = 0, d = 1}, {n = 1023, d = 1}, true}, // maximum numerator
		{{n = 1023, d = 1}, {n = -1, d = 1}, {}, false},
		{{n = -1024, d = 1}, {n = 0, d = 1}, {n = -1024, d = 1}, true}, // minimum numerator
		{{n = -1024, d = 1}, {n = 1, d = 1}, {}, false},
		{{n = 1, d = 31}, {n = 0, d = 1}, {n = 1, d = 31}, true}, // maximum denominator
		{{n = 1, d = 30}, {n = -1, d = 30}, {n = 1, d = 15}, true}, // oversized intermediate reduces
		{{n = 1, d = 31}, {n = -1, d = 30}, {}, false}, // irreducible denominator overflow
		{{n = 512, d = 31}, {n = -511, d = 31}, {n = 33, d = 1}, true},
		{{n = -512, d = 31}, {n = 511, d = 31}, {n = -33, d = 1}, true},
		{{n = 17, d = 29}, {n = 13, d = 23}, {}, false},
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
		{{n = 1, d = 2}, {n = 1, d = 3}, {n = 1, d = 6}, true},
		{{n = -1, d = 2}, {n = 1, d = 3}, {n = -1, d = 6}, true},
		{{n = -1, d = 2}, {n = -1, d = 3}, {n = 1, d = 6}, true},
		{{n = 0, d = 1}, {n = 1023, d = 1}, {n = 0, d = 1}, true},
		{{n = 1023, d = 1}, {n = 1, d = 1}, {n = 1023, d = 1}, true}, // maximum numerator
		{{n = -1024, d = 1}, {n = 1, d = 1}, {n = -1024, d = 1}, true}, // minimum numerator
		{{n = 512, d = 1}, {n = 2, d = 1}, {}, false},
		{{n = -1024, d = 1}, {n = -1, d = 1}, {}, false},
		{{n = 1, d = 31}, {n = 1, d = 1}, {n = 1, d = 31}, true}, // maximum denominator
		{{n = 1, d = 31}, {n = 1, d = 2}, {}, false}, // irreducible denominator overflow
		{{n = 2, d = 31}, {n = 1, d = 2}, {n = 1, d = 31}, true}, // oversized denominator reduces
		{{n = 1023, d = 31}, {n = 31, d = 3}, {n = 341, d = 1}, true}, // cross-cancellation
		{{n = 1000, d = 31}, {n = 31, d = 25}, {n = 40, d = 1}, true},
		{{n = 33, d = 29}, {n = 31, d = 3}, {n = 341, d = 29}, true},
		{{n = -33, d = 29}, {n = 31, d = 3}, {n = -341, d = 29}, true},
		{{n = 100, d = 29}, {n = 31, d = 3}, {}, false}, // numerator overflow after reduction
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
		{{n = 1, d = 2}, {n = 1, d = 3}, {n = 3, d = 2}, true},
		{{n = -1, d = 2}, {n = 1, d = 3}, {n = -3, d = 2}, true},
		{{n = -1, d = 2}, {n = -1, d = 3}, {n = 3, d = 2}, true},
		{{n = 0, d = 1}, {n = 7, d = 9}, {n = 0, d = 1}, true},
		{{n = 1, d = 2}, {n = 0, d = 1}, {}, false}, // division by zero
		{{n = 0, d = 1}, {n = 0, d = 1}, {}, false},
		{{n = 1023, d = 1}, {n = 1, d = 1}, {n = 1023, d = 1}, true}, // maximum numerator
		{{n = -1024, d = 1}, {n = 1, d = 1}, {n = -1024, d = 1}, true}, // minimum numerator
		{{n = 1023, d = 1}, {n = 1, d = 2}, {}, false},
		{{n = -1024, d = 1}, {n = -1, d = 1}, {}, false},
		{{n = 1, d = 31}, {n = 1, d = 1}, {n = 1, d = 31}, true}, // maximum denominator
		{{n = 1, d = 31}, {n = 2, d = 1}, {}, false}, // irreducible denominator overflow
		{{n = 2, d = 31}, {n = 2, d = 1}, {n = 1, d = 31}, true}, // oversized denominator reduces
		{{n = 1023, d = 31}, {n = 33, d = 1}, {n = 1, d = 1}, true}, // cross-cancellation
		{{n = 1000, d = 31}, {n = 25, d = 31}, {n = 40, d = 1}, true},
		{{n = 31, d = 29}, {n = -3, d = 1}, {}, false},
		{{n = -1024, d = 31}, {n = -32, d = 1}, {n = 32, d = 31}, true},
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
