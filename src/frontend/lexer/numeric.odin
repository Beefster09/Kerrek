package lexer

import "core:unicode"
import "core:unicode/utf8"

import "../../common"
import "../../common/exact"
import "../diagnostics"


// Scan every numeric form with one explicit state machine.

_digit_in_radix :: proc(c: rune, radix: int) -> bool {
	switch {
	case '0' <= c && c <= '9':
		return int(c - '0') < radix
	case 'a' <= c && c <= 'f':
		return int(c - 'a') + 10 < radix
	case 'A' <= c && c <= 'F':
		return int(c - 'A') + 10 < radix
	}
	return false
}

_underscore_between_digits :: proc(s: string, i, radix: int) -> bool {
	return(
		i > 0 &&
		i + 1 < len(s) &&
		_digit_in_radix(rune(s[i - 1]), radix) &&
		_digit_in_radix(rune(s[i + 1]), radix) \
	)
}

_exponent_marker_starts_identifier :: proc(s: string, i: int) -> bool {
	if i + 1 >= len(s) {
		return false
	}
	next, _ := utf8.decode_rune(s[i + 1:])
	return unicode.is_alpha(next)
}

_scan_numeric_dfa :: proc(src: string) -> (length: int, format: Number_Format, ok: bool) {
	state: enum {
		Start,
		Leading_Zero,
		Decimal_Whole,
		Decimal_Fraction,
		Decimal_Exponent,
		Decimal_Exponent_Digits,
		Hex_First_Digit,
		Hex_Whole,
		Hex_Fraction,
		Hex_Exponent,
		Hex_Exponent_Digits,
		Octal_First_Digit,
		Octal_Whole,
		Binary_First_Digit,
		Binary_Whole,
	}
	exponent_digits := 0
	format = .DecimalInteger

	for c, i in src {
		switch state {
		case .Start:
			if '0' <= c && c <= '9' {
				state = .Leading_Zero if c == '0' else .Decimal_Whole
			} else {
				return
			}

		case .Leading_Zero:
			switch c {
			case 'x':
				format = .HexInteger
				state = .Hex_First_Digit
			case 'o':
				format = .OctalInteger
				state = .Octal_First_Digit
			case 'b':
				format = .BinaryInteger
				state = .Binary_First_Digit
			case '.':
				format = .Decimal
				state = .Decimal_Fraction
			case 'e', 'E':
				if _exponent_marker_starts_identifier(src, i) {
					length = i
					ok = true
					return
				}
				format = .Decimal
				state = .Decimal_Exponent
			case '_':
				if _underscore_between_digits(src, i, 10) {
					state = .Decimal_Whole
				} else {
					length = i
					ok = true
					return
				}
			case '0' ..= '9':
				state = .Decimal_Whole
			case:
				length = i
				ok = true
				return
			}

		case .Decimal_Whole:
			switch c {
			case '0' ..= '9':
			case '_':
				if !_underscore_between_digits(src, i, 10) {
					length = i
					ok = true
					return
				}
			case '.':
				format = .Decimal
				state = .Decimal_Fraction
			case 'e', 'E':
				if _exponent_marker_starts_identifier(src, i) {
					length = i
					ok = true
					return
				}
				format = .Decimal
				state = .Decimal_Exponent
			case:
				length = i
				ok = true
				return
			}

		case .Decimal_Fraction:
			switch c {
			case '0' ..= '9':
			case '_':
				if !_underscore_between_digits(src, i, 10) {
					length = i
					ok = true
					return
				}
			case 'e', 'E':
				if _exponent_marker_starts_identifier(src, i) {
					length = i
					ok = true
					return
				}
				state = .Decimal_Exponent
			case:
				length = i
				ok = true
				return
			}

		case .Decimal_Exponent:
			switch c {
			case '0' ..= '9':
				exponent_digits = 1
				state = .Decimal_Exponent_Digits
			case '+', '-':
				state = .Decimal_Exponent_Digits
			case:
				return
			}

		case .Decimal_Exponent_Digits:
			switch c {
			case '0' ..= '9':
				exponent_digits += 1
			case '_':
				if !_underscore_between_digits(src, i, 10) {
					if exponent_digits == 0 {
						return
					}
					length = i
					ok = true
					return
				}
			case:
				if exponent_digits == 0 {
					return
				}
				length = i
				ok = true
				return
			}

		case .Hex_First_Digit:
			if _digit_in_radix(c, 16) {
				state = .Hex_Whole
			} else {
				return
			}

		case .Hex_Whole:
			switch c {
			case '0' ..= '9', 'a' ..= 'f', 'A' ..= 'F':
			case '_':
				if !_underscore_between_digits(src, i, 16) {
					length = i
					ok = true
					return
				}
			case '.':
				format = .HexFloat
				state = .Hex_Fraction
			case 'p', 'P':
				if _exponent_marker_starts_identifier(src, i) {
					length = i
					ok = true
					return
				}
				format = .HexFloat
				state = .Hex_Exponent
			case:
				length = i
				ok = true
				return
			}

		case .Hex_Fraction:
			switch c {
			case '0' ..= '9', 'a' ..= 'f', 'A' ..= 'F':
			case '_':
				if !_underscore_between_digits(src, i, 16) {
					length = i
					ok = true
					return
				}
			case 'p', 'P':
				if _exponent_marker_starts_identifier(src, i) {
					length = i
					ok = true
					return
				}
				state = .Hex_Exponent
			case:
				length = i
				ok = true
				return
			}

		case .Hex_Exponent:
			switch c {
			case '0' ..= '9':
				exponent_digits = 1
				state = .Hex_Exponent_Digits
			case '+', '-':
				state = .Hex_Exponent_Digits
			case:
				return
			}

		case .Hex_Exponent_Digits:
			switch c {
			case '0' ..= '9':
				exponent_digits += 1
			case '_':
				if !_underscore_between_digits(src, i, 10) {
					if exponent_digits == 0 {
						return
					}
					length = i
					ok = true
					return
				}
			case:
				if exponent_digits == 0 {
					return
				}
				length = i
				ok = true
				return
			}

		case .Octal_First_Digit:
			if _digit_in_radix(c, 8) {
				state = .Octal_Whole
			} else {
				return
			}

		case .Octal_Whole:
			if _digit_in_radix(c, 8) {
			} else if c == '_' && _underscore_between_digits(src, i, 8) {
				// The separator is valid; remain in this state.
			} else {
				length = i
				ok = true
				return
			}

		case .Binary_First_Digit:
			if _digit_in_radix(c, 2) {
				state = .Binary_Whole
			} else {
				return
			}

		case .Binary_Whole:
			if _digit_in_radix(c, 2) {
			} else if c == '_' && _underscore_between_digits(src, i, 2) {
				// The separator is valid; remain in this state.
			} else {
				length = i
				ok = true
				return
			}
		}
	}

	length = len(src)
	#partial switch state {
	case .Leading_Zero,
	     .Decimal_Whole,
	     .Decimal_Fraction,
	     .Hex_Whole,
	     .Hex_Fraction,
	     .Octal_Whole,
	     .Binary_Whole:
		ok = true
	case .Decimal_Exponent_Digits, .Hex_Exponent_Digits:
		ok = exponent_digits > 0
	case:
		ok = false
	}
	return
}

_match_numeric :: proc(cursor: common.Cursor, src: string) -> (Numeric, int) {
	length, format, ok := _scan_numeric_dfa(src)
	if !ok {
		#partial switch format {
		case .HexInteger, .HexFloat:
			diagnostics.emit(
				.Invalid_Number_Literal,
				common.cursor_to_span(cursor, max(length, 2)),
				"invalid hex literal",
			)
		case .OctalInteger:
			diagnostics.emit(
				.Invalid_Number_Literal,
				common.cursor_to_span(cursor, max(length, 2)),
				"found no digits in octal literal",
			)
		case .BinaryInteger:
			diagnostics.emit(
				.Invalid_Number_Literal,
				common.cursor_to_span(cursor, max(length, 2)),
				"found no digits in binary literal",
			)
		case:
		}
		return {}, 0
	}

	raw := src[:length]
	value: exact.Rat
	parsed := false

	#partial switch format {
	case .DecimalInteger:
		integer, ok := exact.parse_int(raw, 10)
		if ok {
			value = exact.int_to_rat(integer)
			parsed = true
		}
	case .HexInteger:
		integer, ok := exact.parse_int(raw[2:], 16)
		if ok {
			value = exact.int_to_rat(integer)
			parsed = true
		}
	case .OctalInteger:
		integer, ok := exact.parse_int(raw[2:], 8)
		if ok {
			value = exact.int_to_rat(integer)
			parsed = true
		}
	case .BinaryInteger:
		integer, ok := exact.parse_int(raw[2:], 2)
		if ok {
			value = exact.int_to_rat(integer)
			parsed = true
		}
	case .Decimal:
		value, parsed = exact.parse_decimal(raw)
	case .HexFloat:
		value, parsed = exact.parse_hexfloat(raw[2:])
	case:
		return {}, 0
	}

	if !parsed {
		return {}, 0
	}
	digits, precision := _count_numeric_digits(raw, format)
	return {raw = raw, value = value, digits = digits, precision = precision, format = format},
		length
}

_count_numeric_digits :: proc(
	raw: string,
	format: Number_Format,
) -> (
	digits: u32,
	precision: u32,
) {
	start := 0
	#partial switch format {
	case .HexInteger, .OctalInteger, .BinaryInteger, .HexFloat:
		start = 2
	case:
	}

	saw_digit := false
	saw_nonzero := false
	after_point := false
	for c in raw[start:] {
		if format == .Decimal && (c == 'e' || c == 'E') ||
		   format == .HexFloat && (c == 'p' || c == 'P') {
			break
		}
		switch c {
		case '.':
			after_point = true
		case '0':
			saw_digit = true
			if after_point {
				precision += 1
			}
			if saw_nonzero {
				digits += 1
			}
		case '1' ..= '9', 'a' ..= 'f', 'A' ..= 'F':
			saw_digit = true
			saw_nonzero = true
			digits += 1
			if after_point {
				precision += 1
			}
		case:
		}
	}
	digits = max(digits, 1) if saw_digit else 0
	return
}
