package units

import "core:testing"

Rat_Binary_Case :: struct {
	a:        Small_Rat,
	b:        Small_Rat,
	expected: Small_Rat,
	ok:       bool,
}

@(test)
test_add_rat :: proc(t: ^testing.T) {
	cases := [?]Rat_Binary_Case {
		{Small_Rat{1, 2}, Small_Rat{1, 3}, Small_Rat{5, 6}, true},
		{Small_Rat{-1, 2}, Small_Rat{1, 2}, Small_Rat{0, 1}, true},
		{Small_Rat{0, 1}, Small_Rat{7, 9}, Small_Rat{7, 9}, true},
		{Small_Rat{7, 9}, Small_Rat{0, 1}, Small_Rat{7, 9}, true},
		{Small_Rat{2, 3}, Small_Rat{1, 3}, Small_Rat{1, 1}, true},
		{Small_Rat{-2, 3}, Small_Rat{-1, 3}, Small_Rat{-1, 1}, true},
		{Small_Rat{5, 6}, Small_Rat{-1, 2}, Small_Rat{1, 3}, true},
		{Small_Rat{-5, 6}, Small_Rat{1, 2}, Small_Rat{-1, 3}, true},
		{Small_Rat{63, 1}, Small_Rat{64, 1}, Small_Rat{127, 1}, true}, // inclusive storage boundary
		{Small_Rat{-64, 1}, Small_Rat{-64, 1}, Small_Rat{-128, 1}, true}, // inclusive storage boundary
		{Small_Rat{127, 1}, Small_Rat{1, 1}, Small_Rat{}, false},
		{Small_Rat{-128, 1}, Small_Rat{-1, 1}, Small_Rat{}, false},
		{Small_Rat{1, 255}, Small_Rat{0, 1}, Small_Rat{1, 255}, true}, // inclusive storage boundary
		{Small_Rat{-1, 255}, Small_Rat{0, 1}, Small_Rat{-1, 255}, true}, // inclusive storage boundary
		{Small_Rat{1, 200}, Small_Rat{1, 200}, Small_Rat{1, 100}, true}, // stresses i16 intermediates
		{Small_Rat{1, 254}, Small_Rat{1, 254}, Small_Rat{1, 127}, true}, // stresses i16 intermediates
		{Small_Rat{100, 201}, Small_Rat{-100, 201}, Small_Rat{0, 1}, true}, // stresses i16 intermediates
		{Small_Rat{63, 127}, Small_Rat{64, 127}, Small_Rat{1, 1}, true},
		{Small_Rat{50, 251}, Small_Rat{50, 251}, Small_Rat{100, 251}, true}, // stresses i16 intermediates
		{Small_Rat{-50, 251}, Small_Rat{-50, 251}, Small_Rat{-100, 251}, true}, // stresses i16 intermediates
		{Small_Rat{-50, 251}, Small_Rat{1, 3}, Small_Rat{}, false},
		{Small_Rat{-1, 7}, Small_Rat{-50, 251}, Small_Rat{}, false},
		{Small_Rat{-63, 127}, Small_Rat{7, 10}, Small_Rat{}, false},
		{Small_Rat{-1, 251}, Small_Rat{5, 6}, Small_Rat{}, false},
		{Small_Rat{3, 1}, Small_Rat{-63, 127}, Small_Rat{}, false},
		{Small_Rat{3, 7}, Small_Rat{5, 9}, Small_Rat{62, 63}, true},
		{Small_Rat{127, 254}, Small_Rat{-17, 31}, Small_Rat{-3, 62}, true},
		{Small_Rat{-4, 5}, Small_Rat{7, 1}, Small_Rat{31, 5}, true},
		{Small_Rat{-2, 7}, Small_Rat{-2, 1}, Small_Rat{-16, 7}, true},
		{Small_Rat{-1, 127}, Small_Rat{-17, 31}, Small_Rat{}, false},
		{Small_Rat{-1, 251}, Small_Rat{1, 1}, Small_Rat{}, false},
		{Small_Rat{1, 2}, Small_Rat{1, 127}, Small_Rat{}, false},
		{Small_Rat{2, 7}, Small_Rat{-13, 17}, Small_Rat{-57, 119}, true},
		{Small_Rat{-100, 201}, Small_Rat{-1, 7}, Small_Rat{}, false},
		{Small_Rat{1, 251}, Small_Rat{-2, 5}, Small_Rat{}, false},
		{Small_Rat{3, 7}, Small_Rat{5, 6}, Small_Rat{53, 42}, true},
		{Small_Rat{-3, 7}, Small_Rat{50, 251}, Small_Rat{}, false},
		{Small_Rat{-17, 31}, Small_Rat{1, 1}, Small_Rat{14, 31}, true},
		{Small_Rat{-17, 31}, Small_Rat{-3, 4}, Small_Rat{}, false},
		{Small_Rat{-50, 251}, Small_Rat{-3, 7}, Small_Rat{}, false},
		{Small_Rat{63, 127}, Small_Rat{17, 31}, Small_Rat{}, false},
		{Small_Rat{1, 4}, Small_Rat{1, 127}, Small_Rat{}, false},
		{Small_Rat{-1, 3}, Small_Rat{0, 1}, Small_Rat{-1, 3}, true},
		{Small_Rat{1, 200}, Small_Rat{1, 127}, Small_Rat{}, false},
		{Small_Rat{-7, 8}, Small_Rat{1, 2}, Small_Rat{-3, 8}, true},
		{Small_Rat{3, 7}, Small_Rat{2, 3}, Small_Rat{23, 21}, true},
		{Small_Rat{5, 9}, Small_Rat{-4, 5}, Small_Rat{-11, 45}, true},
		{Small_Rat{-1, 1}, Small_Rat{5, 6}, Small_Rat{-1, 6}, true},
		{Small_Rat{2, 7}, Small_Rat{3, 4}, Small_Rat{29, 28}, true},
		{Small_Rat{11, 12}, Small_Rat{13, 17}, Small_Rat{}, false},
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
		{Small_Rat{1, 2}, Small_Rat{1, 3}, Small_Rat{1, 6}, true},
		{Small_Rat{1, 2}, Small_Rat{1, 2}, Small_Rat{0, 1}, true},
		{Small_Rat{0, 1}, Small_Rat{7, 9}, Small_Rat{-7, 9}, true},
		{Small_Rat{7, 9}, Small_Rat{0, 1}, Small_Rat{7, 9}, true},
		{Small_Rat{2, 3}, Small_Rat{1, 3}, Small_Rat{1, 3}, true},
		{Small_Rat{-2, 3}, Small_Rat{-1, 3}, Small_Rat{-1, 3}, true},
		{Small_Rat{5, 6}, Small_Rat{-1, 2}, Small_Rat{4, 3}, true},
		{Small_Rat{-5, 6}, Small_Rat{1, 2}, Small_Rat{-4, 3}, true},
		{Small_Rat{127, 1}, Small_Rat{0, 1}, Small_Rat{127, 1}, true}, // inclusive storage boundary
		{Small_Rat{-128, 1}, Small_Rat{0, 1}, Small_Rat{-128, 1}, true}, // inclusive storage boundary
		{Small_Rat{127, 1}, Small_Rat{-1, 1}, Small_Rat{}, false},
		{Small_Rat{-128, 1}, Small_Rat{1, 1}, Small_Rat{}, false},
		{Small_Rat{1, 255}, Small_Rat{0, 1}, Small_Rat{1, 255}, true}, // inclusive storage boundary
		{Small_Rat{-1, 255}, Small_Rat{0, 1}, Small_Rat{-1, 255}, true}, // inclusive storage boundary
		{Small_Rat{1, 200}, Small_Rat{-1, 200}, Small_Rat{1, 100}, true}, // stresses i16 intermediates
		{Small_Rat{1, 254}, Small_Rat{-1, 254}, Small_Rat{1, 127}, true}, // stresses i16 intermediates
		{Small_Rat{100, 201}, Small_Rat{100, 201}, Small_Rat{0, 1}, true}, // stresses i16 intermediates
		{Small_Rat{64, 127}, Small_Rat{-63, 127}, Small_Rat{1, 1}, true},
		{Small_Rat{50, 251}, Small_Rat{-50, 251}, Small_Rat{100, 251}, true}, // stresses i16 intermediates
		{Small_Rat{-50, 251}, Small_Rat{50, 251}, Small_Rat{-100, 251}, true}, // stresses i16 intermediates
		{Small_Rat{1, 4}, Small_Rat{100, 201}, Small_Rat{}, false},
		{Small_Rat{-1, 254}, Small_Rat{-50, 251}, Small_Rat{}, false},
		{Small_Rat{-3, 5}, Small_Rat{-50, 251}, Small_Rat{}, false},
		{Small_Rat{-3, 4}, Small_Rat{-2, 5}, Small_Rat{-7, 20}, true},
		{Small_Rat{-3, 7}, Small_Rat{0, 1}, Small_Rat{-3, 7}, true},
		{Small_Rat{-3, 4}, Small_Rat{-63, 127}, Small_Rat{}, false},
		{Small_Rat{7, 8}, Small_Rat{-2, 1}, Small_Rat{23, 8}, true},
		{Small_Rat{-5, 9}, Small_Rat{2, 3}, Small_Rat{-11, 9}, true},
		{Small_Rat{-2, 3}, Small_Rat{-1, 200}, Small_Rat{}, false},
		{Small_Rat{-100, 201}, Small_Rat{3, 4}, Small_Rat{}, false},
		{Small_Rat{2, 1}, Small_Rat{5, 9}, Small_Rat{13, 9}, true},
		{Small_Rat{-1, 254}, Small_Rat{0, 1}, Small_Rat{-1, 254}, true},
		{Small_Rat{1, 251}, Small_Rat{1, 251}, Small_Rat{0, 1}, true},
		{Small_Rat{-2, 7}, Small_Rat{100, 201}, Small_Rat{}, false},
		{Small_Rat{5, 9}, Small_Rat{7, 8}, Small_Rat{-23, 72}, true},
		{Small_Rat{-1, 3}, Small_Rat{50, 251}, Small_Rat{}, false},
		{Small_Rat{-1, 3}, Small_Rat{-1, 251}, Small_Rat{}, false},
		{Small_Rat{1, 127}, Small_Rat{3, 5}, Small_Rat{}, false},
		{Small_Rat{-3, 1}, Small_Rat{-4, 5}, Small_Rat{-11, 5}, true},
		{Small_Rat{-1, 3}, Small_Rat{-1, 3}, Small_Rat{0, 1}, true},
		{Small_Rat{-4, 5}, Small_Rat{1, 3}, Small_Rat{-17, 15}, true},
		{Small_Rat{-1, 127}, Small_Rat{-50, 251}, Small_Rat{}, false},
		{Small_Rat{1, 200}, Small_Rat{-50, 251}, Small_Rat{}, false},
		{Small_Rat{-13, 17}, Small_Rat{2, 3}, Small_Rat{-73, 51}, true},
		{Small_Rat{1, 200}, Small_Rat{-3, 7}, Small_Rat{}, false},
		{Small_Rat{100, 201}, Small_Rat{-1, 251}, Small_Rat{}, false},
		{Small_Rat{1, 1}, Small_Rat{-3, 5}, Small_Rat{8, 5}, true},
		{Small_Rat{-5, 9}, Small_Rat{-3, 5}, Small_Rat{2, 45}, true},
		{Small_Rat{-1, 251}, Small_Rat{17, 31}, Small_Rat{}, false},
		{Small_Rat{5, 9}, Small_Rat{1, 200}, Small_Rat{}, false},
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
		{Small_Rat{1, 2}, Small_Rat{1, 3}, Small_Rat{1, 6}, true},
		{Small_Rat{-1, 2}, Small_Rat{1, 3}, Small_Rat{-1, 6}, true},
		{Small_Rat{-1, 2}, Small_Rat{-1, 3}, Small_Rat{1, 6}, true},
		{Small_Rat{0, 1}, Small_Rat{127, 1}, Small_Rat{0, 1}, true},
		{Small_Rat{127, 1}, Small_Rat{1, 1}, Small_Rat{127, 1}, true}, // inclusive storage boundary
		{Small_Rat{-128, 1}, Small_Rat{1, 1}, Small_Rat{-128, 1}, true}, // inclusive storage boundary
		{Small_Rat{127, 1}, Small_Rat{2, 1}, Small_Rat{}, false},
		{Small_Rat{-128, 1}, Small_Rat{2, 1}, Small_Rat{}, false},
		{Small_Rat{2, 3}, Small_Rat{3, 4}, Small_Rat{1, 2}, true},
		{Small_Rat{5, 6}, Small_Rat{6, 5}, Small_Rat{1, 1}, true},
		{Small_Rat{7, 9}, Small_Rat{3, 14}, Small_Rat{1, 6}, true},
		{Small_Rat{-7, 9}, Small_Rat{3, 14}, Small_Rat{-1, 6}, true},
		{Small_Rat{1, 255}, Small_Rat{1, 1}, Small_Rat{1, 255}, true}, // inclusive storage boundary
		{Small_Rat{-1, 255}, Small_Rat{1, 1}, Small_Rat{-1, 255}, true}, // inclusive storage boundary
		{Small_Rat{100, 201}, Small_Rat{100, 200}, Small_Rat{50, 201}, true}, // reduced result fits; raw i16 denominator product does not
		{Small_Rat{-100, 201}, Small_Rat{100, 200}, Small_Rat{-50, 201}, true}, // reduced result fits; raw i16 denominator product does not
		{Small_Rat{100, 251}, Small_Rat{125, 100}, Small_Rat{125, 251}, true},
		{Small_Rat{63, 127}, Small_Rat{2, 63}, Small_Rat{2, 127}, true},
		{Small_Rat{127, 254}, Small_Rat{2, 1}, Small_Rat{1, 1}, true},
		{Small_Rat{-128, 255}, Small_Rat{1, 1}, Small_Rat{-128, 255}, true},
		{Small_Rat{7, 10}, Small_Rat{63, 127}, Small_Rat{}, false},
		{Small_Rat{17, 31}, Small_Rat{2, 3}, Small_Rat{34, 93}, true},
		{Small_Rat{-1, 2}, Small_Rat{1, 5}, Small_Rat{-1, 10}, true},
		{Small_Rat{-2, 3}, Small_Rat{-1, 127}, Small_Rat{}, false},
		{Small_Rat{17, 31}, Small_Rat{-1, 254}, Small_Rat{}, false},
		{Small_Rat{-1, 3}, Small_Rat{3, 4}, Small_Rat{-1, 4}, true},
		{Small_Rat{127, 254}, Small_Rat{1, 4}, Small_Rat{1, 8}, true},
		{Small_Rat{-7, 1}, Small_Rat{-7, 10}, Small_Rat{49, 10}, true},
		{Small_Rat{3, 4}, Small_Rat{-4, 5}, Small_Rat{-3, 5}, true},
		{Small_Rat{-7, 10}, Small_Rat{-2, 7}, Small_Rat{1, 5}, true},
		{Small_Rat{5, 6}, Small_Rat{0, 1}, Small_Rat{0, 1}, true},
		{Small_Rat{1, 200}, Small_Rat{1, 200}, Small_Rat{}, false},
		{Small_Rat{-1, 5}, Small_Rat{2, 5}, Small_Rat{-2, 25}, true},
		{Small_Rat{-4, 5}, Small_Rat{0, 1}, Small_Rat{0, 1}, true},
		{Small_Rat{-1, 4}, Small_Rat{-3, 4}, Small_Rat{3, 16}, true},
		{Small_Rat{3, 4}, Small_Rat{2, 3}, Small_Rat{1, 2}, true},
		{Small_Rat{-1, 5}, Small_Rat{7, 1}, Small_Rat{-7, 5}, true},
		{Small_Rat{-100, 201}, Small_Rat{-4, 5}, Small_Rat{80, 201}, true},
		{Small_Rat{3, 4}, Small_Rat{17, 31}, Small_Rat{51, 124}, true},
		{Small_Rat{-1, 5}, Small_Rat{1, 7}, Small_Rat{-1, 35}, true},
		{Small_Rat{-2, 3}, Small_Rat{1, 251}, Small_Rat{}, false},
		{Small_Rat{1, 2}, Small_Rat{50, 251}, Small_Rat{25, 251}, true},
		{Small_Rat{1, 127}, Small_Rat{1, 4}, Small_Rat{}, false},
		{Small_Rat{-4, 5}, Small_Rat{-3, 4}, Small_Rat{3, 5}, true},
		{Small_Rat{-11, 12}, Small_Rat{50, 251}, Small_Rat{}, false},
		{Small_Rat{17, 31}, Small_Rat{-50, 251}, Small_Rat{}, false},
		{Small_Rat{-1, 2}, Small_Rat{-2, 7}, Small_Rat{1, 7}, true},
		{Small_Rat{1, 200}, Small_Rat{-7, 10}, Small_Rat{}, false},
		{Small_Rat{-1, 200}, Small_Rat{-1, 2}, Small_Rat{}, false},
		{Small_Rat{5, 6}, Small_Rat{-7, 1}, Small_Rat{-35, 6}, true},
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
		{Small_Rat{1, 2}, Small_Rat{1, 3}, Small_Rat{3, 2}, true},
		{Small_Rat{-1, 2}, Small_Rat{1, 3}, Small_Rat{-3, 2}, true},
		{Small_Rat{-1, 2}, Small_Rat{-1, 3}, Small_Rat{3, 2}, true},
		{Small_Rat{0, 1}, Small_Rat{7, 9}, Small_Rat{0, 1}, true},
		{Small_Rat{1, 2}, Small_Rat{0, 1}, Small_Rat{}, false}, // division by zero
		{Small_Rat{-1, 2}, Small_Rat{0, 1}, Small_Rat{}, false}, // division by zero
		{Small_Rat{127, 1}, Small_Rat{1, 1}, Small_Rat{127, 1}, true}, // inclusive storage boundary
		{Small_Rat{-128, 1}, Small_Rat{1, 1}, Small_Rat{-128, 1}, true}, // inclusive storage boundary
		{Small_Rat{127, 1}, Small_Rat{1, 2}, Small_Rat{}, false},
		{Small_Rat{-128, 1}, Small_Rat{1, 2}, Small_Rat{}, false},
		{Small_Rat{2, 3}, Small_Rat{4, 5}, Small_Rat{5, 6}, true},
		{Small_Rat{5, 6}, Small_Rat{10, 9}, Small_Rat{3, 4}, true},
		{Small_Rat{7, 9}, Small_Rat{14, 3}, Small_Rat{1, 6}, true},
		{Small_Rat{-7, 9}, Small_Rat{14, 3}, Small_Rat{-1, 6}, true},
		{Small_Rat{1, 255}, Small_Rat{1, 1}, Small_Rat{1, 255}, true}, // inclusive storage boundary
		{Small_Rat{-1, 255}, Small_Rat{1, 1}, Small_Rat{-1, 255}, true}, // inclusive storage boundary
		{Small_Rat{100, 201}, Small_Rat{100, 201}, Small_Rat{1, 1}, true},
		{Small_Rat{63, 127}, Small_Rat{63, 127}, Small_Rat{1, 1}, true},
		{Small_Rat{127, 254}, Small_Rat{1, 2}, Small_Rat{1, 1}, true},
		{Small_Rat{-128, 255}, Small_Rat{1, 1}, Small_Rat{-128, 255}, true},
		{Small_Rat{-1, 1}, Small_Rat{-1, 2}, Small_Rat{2, 1}, true},
		{Small_Rat{-11, 12}, Small_Rat{1, 7}, Small_Rat{-77, 12}, true},
		{Small_Rat{3, 7}, Small_Rat{127, 254}, Small_Rat{6, 7}, true},
		{Small_Rat{-3, 1}, Small_Rat{3, 5}, Small_Rat{-5, 1}, true},
		{Small_Rat{1, 1}, Small_Rat{-2, 7}, Small_Rat{-7, 2}, true},
		{Small_Rat{13, 17}, Small_Rat{-7, 8}, Small_Rat{-104, 119}, true},
		{Small_Rat{-2, 7}, Small_Rat{5, 6}, Small_Rat{-12, 35}, true},
		{Small_Rat{-1, 7}, Small_Rat{-7, 1}, Small_Rat{1, 49}, true},
		{Small_Rat{7, 8}, Small_Rat{127, 254}, Small_Rat{7, 4}, true},
		{Small_Rat{1, 4}, Small_Rat{2, 1}, Small_Rat{1, 8}, true},
		{Small_Rat{-2, 3}, Small_Rat{63, 127}, Small_Rat{}, false},
		{Small_Rat{2, 5}, Small_Rat{1, 127}, Small_Rat{}, false},
		{Small_Rat{31, 63}, Small_Rat{-2, 3}, Small_Rat{-31, 42}, true},
		{Small_Rat{1, 251}, Small_Rat{-3, 4}, Small_Rat{}, false},
		{Small_Rat{-7, 1}, Small_Rat{-100, 201}, Small_Rat{}, false},
		{Small_Rat{-7, 10}, Small_Rat{-50, 251}, Small_Rat{}, false},
		{Small_Rat{1, 200}, Small_Rat{-1, 4}, Small_Rat{-1, 50}, true},
		{Small_Rat{1, 251}, Small_Rat{-3, 7}, Small_Rat{}, false},
		{Small_Rat{1, 127}, Small_Rat{-1, 1}, Small_Rat{-1, 127}, true},
		{Small_Rat{-11, 12}, Small_Rat{-1, 254}, Small_Rat{}, false},
		{Small_Rat{0, 1}, Small_Rat{-2, 7}, Small_Rat{0, 1}, true},
		{Small_Rat{7, 8}, Small_Rat{-2, 3}, Small_Rat{-21, 16}, true},
		{Small_Rat{63, 127}, Small_Rat{-13, 17}, Small_Rat{}, false},
		{Small_Rat{0, 1}, Small_Rat{0, 1}, Small_Rat{}, false},
		{Small_Rat{-100, 201}, Small_Rat{-2, 1}, Small_Rat{50, 201}, true},
		{Small_Rat{-63, 127}, Small_Rat{-7, 1}, Small_Rat{9, 127}, true},
		{Small_Rat{-3, 4}, Small_Rat{5, 6}, Small_Rat{-9, 10}, true},
		{Small_Rat{1, 4}, Small_Rat{11, 12}, Small_Rat{3, 11}, true},
		{Small_Rat{-2, 3}, Small_Rat{4, 5}, Small_Rat{-5, 6}, true},
		{Small_Rat{-31, 63}, Small_Rat{1, 200}, Small_Rat{}, false},
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
