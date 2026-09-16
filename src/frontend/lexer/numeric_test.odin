#+test
package lexer

import "core:strings"
import "core:testing"

import "../../common"
import "../../common/exact"
import "../diagnostics"

Numeric_Case :: struct {
	source:      string,
	raw:         string,
	format:      Number_Format,
	numerator:   i128,
	denominator: i128,
	digits:      u32,
	precision:   u32,
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
	if length != len(tc.raw) {
		return
	}

	testing.expectf(t, actual.raw == tc.raw, "expected raw literal %q, got %q", tc.raw, actual.raw)
	testing.expectf(
		t,
		actual.format == tc.format,
		"expected %q to have format %v, got %v",
		tc.raw,
		tc.format,
		actual.format,
	)
	testing.expectf(
		t,
		actual.digits == tc.digits,
		"expected %q to have %d significant digits, got %d",
		tc.raw,
		tc.digits,
		actual.digits,
	)
	testing.expectf(
		t,
		actual.precision == tc.precision,
		"expected %q to have precision %d, got %d",
		tc.raw,
		tc.precision,
		actual.precision,
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

_expect_tokenized_numeric :: proc(t: ^testing.T, tc: Numeric_Case, index: int) {
	contents := strings.clone(tc.source)
	sf := common.inject_source_file(tc.raw, transmute([]u8)contents)
	tokens := tokenize(sf)
	defer delete(tokens)

	testing.expectf(t, len(tokens) > 0, "expected %q to produce at least one token", tc.source)
	if len(tokens) == 0 {
		return
	}

	numeric, ok := tokens[0].what.(Numeric)
	testing.expectf(t, ok, "expected first token in %q to be numeric", tc.source)
	if !ok {
		return
	}
	testing.expectf(
		t,
		numeric.raw == tc.raw,
		"expected first token in %q to be %q, got %q",
		tc.source,
		tc.raw,
		numeric.raw,
	)
	testing.expectf(
		t,
		tokens[0].span.file == sf.id,
		"expected token %d to retain injected source id",
		index,
	)
	testing.expectf(
		t,
		tokens[0].span.end.offset == u32(len(tc.raw)),
		"expected %q token span to end at %d, got %d",
		tc.raw,
		len(tc.raw),
		tokens[0].span.end.offset,
	)
}

_expect_dfa_equivalent :: proc(t: ^testing.T, source: string) {
	expected, expected_length := _match_numeric({}, source)
	actual, actual_length := _match_numeric_dfa({}, source)
	testing.expectf(
		t,
		actual_length == expected_length,
		"DFA consumed %d bytes of %q; production matcher consumed %d",
		actual_length,
		source,
		expected_length,
	)
	if actual_length == 0 || expected_length == 0 {
		return
	}

	testing.expectf(
		t,
		actual.raw == expected.raw,
		"DFA matched %q; expected %q",
		actual.raw,
		expected.raw,
	)
	testing.expectf(
		t,
		actual.format == expected.format,
		"DFA format for %q was %v; expected %v",
		source,
		actual.format,
		expected.format,
	)
	testing.expectf(
		t,
		actual.digits == expected.digits,
		"DFA digit count for %q was %d; expected %d",
		source,
		actual.digits,
		expected.digits,
	)
	testing.expectf(
		t,
		actual.precision == expected.precision,
		"DFA precision for %q was %d; expected %d",
		source,
		actual.precision,
		expected.precision,
	)
	testing.expectf(
		t,
		exact.eq(actual.value, expected.value),
		"DFA value for %q differs from production matcher",
		source,
	)
}

_expect_adjacent_identifier_warning :: proc(
	t: ^testing.T,
	source, numeric_raw, identifier_raw: string,
) {
	clear(&diagnostics._current_diagnostics)
	contents := strings.clone(source)
	sf := common.inject_source_file(source, transmute([]u8)contents)
	tokens := tokenize(sf)
	defer delete(tokens)

	testing.expectf(
		t,
		len(tokens) >= 2,
		"expected %q to produce at least two tokens, got %d",
		source,
		len(tokens),
	)
	if len(tokens) < 2 {
		return
	}
	numeric, numeric_ok := tokens[0].what.(Numeric)
	_, identifier_ok := tokens[1].what.(Identifier)
	_, keyword_ok := tokens[1].what.(Keyword)
	testing.expectf(
		t,
		numeric_ok && numeric.raw == numeric_raw,
		"expected %q to begin with numeric %q",
		source,
		numeric_raw,
	)
	testing.expectf(
		t,
		identifier_ok || keyword_ok,
		"expected %q to have an identifier-like second token",
		source,
	)
	identifier_start := len(numeric_raw)
	identifier_end := identifier_start + len(identifier_raw)
	testing.expectf(
		t,
		tokens[1].span.start.offset == u32(identifier_start) &&
		tokens[1].span.end.offset == u32(identifier_end),
		"expected %q to contain identifier-like token %q immediately after the number",
		source,
		identifier_raw,
	)

	testing.expectf(
		t,
		len(diagnostics._current_diagnostics) == 1,
		"expected one diagnostic for %q, got %d",
		source,
		len(diagnostics._current_diagnostics),
	)
	if len(diagnostics._current_diagnostics) != 1 {
		return
	}
	diagnostic := diagnostics._current_diagnostics[0]
	testing.expectf(
		t,
		diagnostic.code == .Number_Followed_By_Identifier,
		"expected adjacency warning for %q, got %v",
		source,
		diagnostic.code,
	)
	testing.expectf(
		t,
		diagnostic.level == .Warning,
		"expected warning level for %q, got %v",
		source,
		diagnostic.level,
	)
	testing.expectf(
		t,
		diagnostic.span.file == sf.id,
		"expected warning for %q to retain injected source id",
		source,
	)
	testing.expectf(
		t,
		diagnostic.span.start.offset == 0,
		"expected warning for %q to start at byte zero",
		source,
	)
	testing.expectf(
		t,
		diagnostic.span.end.offset == u32(identifier_end),
		"expected warning for %q to end at byte %d, got %d",
		source,
		identifier_end,
		diagnostic.span.end.offset,
	)
}

_expect_no_adjacent_identifier_warning :: proc(t: ^testing.T, source: string) {
	clear(&diagnostics._current_diagnostics)
	contents := strings.clone(source)
	sf := common.inject_source_file(source, transmute([]u8)contents)
	tokens := tokenize(sf)
	defer delete(tokens)

	for diagnostic in diagnostics._current_diagnostics {
		testing.expectf(
			t,
			diagnostic.code != .Number_Followed_By_Identifier,
			"did not expect an adjacency warning for %q",
			source,
		)
	}
}

@(test)
test_numeric_literals :: proc(t: ^testing.T) {
	diagnostics.initialize()
	defer diagnostics.destroy()
	defer common.destroy_source_storage_for_testing()
	defer strings.intern_destroy(&common.ident_intern)

	cases := [?]Numeric_Case {
		// Decimal integers: separators do not contribute to digit counts.
		{"0", "0", .DecimalInteger, 0, 1, 1, 0},
		{"000_001 ", "000_001", .DecimalInteger, 1, 1, 1, 0},
		{"1_000_000\t", "1_000_000", .DecimalInteger, 1000000, 1, 7, 0},
		{"123456789\n", "123456789", .DecimalInteger, 123456789, 1, 9, 0},

		// Non-decimal integers exercise mixed case and every supported radix.
		{"0xdead_BEEF;", "0xdead_BEEF", .HexInteger, 3735928559, 1, 8, 0},
		{"0x0_0_1)", "0x0_0_1", .HexInteger, 1, 1, 1, 0},
		{"0o7_5_5,", "0o7_5_5", .OctalInteger, 493, 1, 3, 0},
		{"0b101_101🙂", "0b101_101", .BinaryInteger, 45, 1, 6, 0},

		// Decimal fractions and exponents permit separators only between digits.
		{"12.50e-1?", "12.50e-1", .Decimal, 5, 4, 4, 2},
		{"1_2.5_0e-1_0}", "1_2.5_0e-1_0", .Decimal, 1, 800000000, 4, 2},
		{"0.001_20/", "0.001_20", .Decimal, 3, 2500, 3, 5},
		{"0.000]", "0.000", .Decimal, 0, 1, 1, 3},
		{"1e1_0+", "1e1_0", .Decimal, 10000000000, 1, 1, 0},
		{"12.5E-1:", "12.5E-1", .Decimal, 5, 4, 3, 1},

		// Hex-float precision is counted in hexadecimal fractional digits.
		{"0x1.8p1%", "0x1.8p1", .HexFloat, 3, 1, 2, 1},
		{"0x1.a_bp+1_0&", "0x1.a_bp+1_0", .HexFloat, 1708, 1, 3, 2},
		{"0x0.08p0|", "0x0.08p0", .HexFloat, 1, 32, 1, 2},
		{"0x1p10~", "0x1p10", .HexFloat, 1024, 1, 1, 0},
		{"0x1P10", "0x1P10", .HexFloat, 1024, 1, 1, 0},
		// The binary exponent is optional when the literal contains a point.
		{"0x1.8", "0x1.8", .HexFloat, 3, 2, 2, 1},
		{"0x1.;", "0x1.", .HexFloat, 1, 1, 1, 0},
		{"0x0.08 ", "0x0.08", .HexFloat, 1, 32, 1, 2},
		{"0xa.b_c)", "0xa.b_c", .HexFloat, 687, 64, 3, 2},
	}

	for tc, i in cases {
		_expect_numeric(t, tc)
		_expect_tokenized_numeric(t, tc, i)
		_expect_dfa_equivalent(t, tc.source)
	}

	// Exercise termination independently from numeric form. These suffixes are
	// deliberately safe delimiters for every radix in the table above.
	suffixes := [?]string {
		"", // end of file
		" ",
		"\t",
		"\n",
		"\r\n",
		"\"",
		"'",
		";",
		",",
		")",
		"]",
		"}",
		"+",
		"-",
		"*",
		"/",
		"// comment",
		"%",
		"&",
		"|",
		"^",
		"?",
		"~",
		":",
		"::",
		"@",
		"#",
		"$",
		"=",
		"==",
		"<",
		"<=",
		">",
		">=",
		"->",
		"\\comment",
		"tail",
		"meters123",
		"Zebra",
		"_name",
		"éclair",
		"变量",
		"🙂",
		"🔥tail",
		"🧪_42",
	}

	for tc, case_index in cases {
		for suffix, suffix_index in suffixes {
			parts := [?]string{tc.raw, suffix}
			source, err := strings.concatenate(parts[:])
			testing.expectf(t, err == nil, "could not build suffix case %q + %q", tc.raw, suffix)
			if err != nil {
				continue
			}

			suffix_case := tc
			suffix_case.source = source
			_expect_numeric(t, suffix_case)
			_expect_tokenized_numeric(t, suffix_case, case_index * len(suffixes) + suffix_index)
			_expect_dfa_equivalent(t, suffix_case.source)
			delete(source)
		}
	}

	// Dot and exponent-marker suffixes are context-sensitive rather than plain
	// delimiters, so keep their expected maximal matches explicit.
	contextual_suffix_cases := [?]Numeric_Case {
		{"1.", "1.", .Decimal, 1, 1, 1, 0},
		{"1..", "1.", .Decimal, 1, 1, 1, 0},
		{"1...tail", "1.", .Decimal, 1, 1, 1, 0},
		{"1.e2tail", "1.e2", .Decimal, 100, 1, 1, 0},
		{"0x1.p2tail", "0x1.p2", .HexFloat, 4, 1, 1, 0},
		{"0x1face!", "0x1face", .HexInteger, 129742, 1, 5, 0},
		{"123abc", "123", .DecimalInteger, 123, 1, 3, 0},
		{"0o7octal", "0o7", .OctalInteger, 7, 1, 1, 0},
		{"0b10binary", "0b10", .BinaryInteger, 2, 1, 2, 0},
		{"0xfff.3a5dftail", "0xfff.3a5df", .HexFloat, 0xfff3a5df, 0x100000, 8, 5},
	}
	for tc, i in contextual_suffix_cases {
		_expect_numeric(t, tc)
		_expect_tokenized_numeric(t, tc, i)
		_expect_dfa_equivalent(t, tc.source)
	}

	adjacent_identifier_cases := [?]struct {
		source:         string,
		numeric_raw:    string,
		identifier_raw: string,
	} {
		{"123abc", "123", "abc"},
		{"1example", "1", "example"},
		{"1eels", "1", "eels"},
		{"0x1panda", "0x1", "panda"},
		{"0o7octal", "0o7", "octal"},
		{"0b10binary", "0b10", "binary"},
		{"42_name", "42", "_name"},
		{"7éclair", "7", "éclair"},
		{"9变量", "9", "变量"},
		{"1if", "1", "if"},
		{"1.5meters ", "1.5", "meters"},
		{"1e2units;", "1e2", "units"},
		{"0x1p2turns🔥", "0x1p2", "turns"},
	}
	for tc in adjacent_identifier_cases {
		_expect_adjacent_identifier_warning(t, tc.source, tc.numeric_raw, tc.identifier_raw)
	}

	non_adjacent_identifier_cases := [?]string {
		"123 abc",
		"123+abc",
		"123🙂",
		"0x1face",
		"1e2",
		"123;abc",
	}
	for source in non_adjacent_identifier_cases {
		_expect_no_adjacent_identifier_warning(t, source)
	}

	boundary_cases := [?]struct {
		source: string,
		raw:    string,
	} {


		// An underscore may never begin or end any run of digits.
		{"_1", ""},
		{"1_", "1"},
		{"1__2", "1"},
		{"0x_1", ""},
		{"0x1_", "0x1"},
		{"0o_7", ""},
		{"0o7_", "0o7"},
		{"0b_1", ""},
		{"0b1_", "0b1"},

		// Separators adjacent to a decimal point or exponent are not consumed.
		{"1_.0", "1"},
		{"1._0", "1."},
		{"1.0_", "1.0"},
		{"1_e2", "1"},
		{"1e_2", ""},
		{"1e2_", "1e2"},
		{"1e+_2", ""},
		{"1e+2_", "1e+2"},
		{"0x1_p2", "0x1"},
		{"0x1p_2", ""},
		{"0x1p2_", "0x1p2"},
		{"0x1p+_2", ""},
		{"0x1p+2_", "0x1p+2"},
		{"0x1._8", "0x1."},
		{"0x1.8_", "0x1.8"},
		{"0x1.8p", ""},
		{"0x1.8p_2", ""},
		{"0x1.8p+", ""},
		// A leading exponent marker should be treated as an identifier.
		{"1example", "1"},
		{"1eels", "1"},
		{"0x1panda", "0x1"},
		{"0x1.panda", "0x1."},
		{"0x1.8panda", "0x1.8"},
	}

	for tc in boundary_cases {
		actual, length := _match_numeric({}, tc.source)
		testing.expectf(
			t,
			length == len(tc.raw),
			"expected boundary case %q to consume %q (%d bytes), got %q (%d bytes)",
			tc.source,
			tc.raw,
			len(tc.raw),
			actual.raw,
			length,
		)
		if length > 0 {
			testing.expectf(
				t,
				actual.raw == tc.raw,
				"expected boundary case %q to match %q, got %q",
				tc.source,
				tc.raw,
				actual.raw,
			)
		}
		_expect_dfa_equivalent(t, tc.source)
	}
}
