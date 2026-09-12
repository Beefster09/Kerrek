#+test
package lexer

import "core:testing"

Numeric_Case :: struct {
	source:      string,
	raw:         string,
	format:      Number_Format,
	numerator:   i128,
	denominator: i128,
}

_expect_numeric :: proc(t: ^testing.T, tc: Numeric_Case) {
	actual, length := _match_numeric({}, tc.source)
	testing.expectf(
		t,
		length == len(tc.raw),
		"expected %q to consume %d bytes, got %d",
		tc.source,
		len(tc.raw),
		length,
	)
	testing.expectf(t, actual.raw == tc.raw, "expected raw literal %q, got %q", tc.raw, actual.raw)
	testing.expectf(
		t,
		actual.format == tc.format,
		"expected %q to have format %v, got %v",
		tc.raw,
		tc.format,
		actual.format,
	)

	numerator, numerator_inline := actual.value.numerator.(i128)
	denominator, denominator_inline := actual.value.denominator.(i128)
	testing.expectf(t, numerator_inline, "expected %q numerator to remain inline", tc.raw)
	testing.expectf(t, denominator_inline, "expected %q denominator to remain inline", tc.raw)
	if numerator_inline && denominator_inline {
		testing.expectf(
			t,
			numerator == tc.numerator,
			"expected %q numerator %d, got %d",
			tc.raw,
			tc.numerator,
			numerator,
		)
		testing.expectf(
			t,
			denominator == tc.denominator,
			"expected %q denominator %d, got %d",
			tc.raw,
			tc.denominator,
			denominator,
		)
	}
}

@(test)
test_match_numeric :: proc(t: ^testing.T) {
	cases := [?]Numeric_Case {
		{"123tail", "123", .DecimalInteger, 123, 1},
		{"12.50e-1tail", "12.50e-1", .Decimal, 1250, 1000},
		{"0xdeadBEEF!", "0xdeadBEEF", .HexInteger, 3735928559, 1},
		{"0x1.8p1tail", "0x1.8p1", .HexFloat, 24, 8},
		{"0x1p10tail", "0x1p10", .HexFloat, 1024, 1},
	}
	for tc in cases {
		_expect_numeric(t, tc)
	}
}

// These cases specify the intended result while their lexer branches remain TODO.
RUN_PENDING_RADIX_LITERAL_TESTS :: #config(RUN_PENDING_RADIX_LITERAL_TESTS, false)

@(test)
test_match_octal_numeric :: proc(t: ^testing.T) {
	when RUN_PENDING_RADIX_LITERAL_TESTS {
		_expect_numeric(t, {"0o755tail", "0o755", .OctalInteger, 493, 1})
	}
}

@(test)
test_match_binary_numeric :: proc(t: ^testing.T) {
	when RUN_PENDING_RADIX_LITERAL_TESTS {
		_expect_numeric(t, {"0b101101tail", "0b101101", .BinaryInteger, 45, 1})
	}
}
