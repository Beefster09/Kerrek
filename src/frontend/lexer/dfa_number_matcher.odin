package lexer

import "../../common"
import "../../common/exact"


// This is an alternate implementation of _match_numeric. Unlike the production
// matcher, which splits each numeric family into a small checker, this version
// puts every numeric form into one explicit state machine

Number_DFA_Result :: struct {
	length:    int,
	format:    Number_Format,
	precision: u32,
	ok:        bool,
}

_scan_numeric_dfa :: proc(src: string) -> (result: Number_DFA_Result) {
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
	result.format = .DecimalInteger

	scan: for c, i in src {
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
				result.format = .HexInteger
				state = .Hex_First_Digit
			case 'o':
				result.format = .OctalInteger
				state = .Octal_First_Digit
			case 'b':
				result.format = .BinaryInteger
				state = .Binary_First_Digit
			case '.':
				result.format = .Decimal
				state = .Decimal_Fraction
			case 'e', 'E':
				if _exponent_marker_starts_identifier(src, i) {
					result.length = i
					result.ok = true
					break scan
				}
				result.format = .Decimal
				state = .Decimal_Exponent
			case '_':
				if _underscore_between_digits(src, i, 10) {
					state = .Decimal_Whole
				} else {
					result.length = i
					result.ok = true
					break scan
				}
			case '0' ..= '9':
				state = .Decimal_Whole
			case:
				result.length = i
				result.ok = true
				break scan
			}

		case .Decimal_Whole:
			switch c {
			case '0' ..= '9':
			case '_':
				if !_underscore_between_digits(src, i, 10) {
					result.length = i
					result.ok = true
					break scan
				}
			case '.':
				result.format = .Decimal
				state = .Decimal_Fraction
			case 'e', 'E':
				if _exponent_marker_starts_identifier(src, i) {
					result.length = i
					result.ok = true
					break scan
				}
				result.format = .Decimal
				state = .Decimal_Exponent
			case:
				result.length = i
				result.ok = true
				break scan
			}

		case .Decimal_Fraction:
			switch c {
			case '0' ..= '9':
				result.precision += 1
			case '_':
				if !_underscore_between_digits(src, i, 10) {
					result.length = i
					result.ok = true
					break scan
				}
			case 'e', 'E':
				if _exponent_marker_starts_identifier(src, i) {
					result.length = i
					result.ok = true
					break scan
				}
				state = .Decimal_Exponent
			case:
				result.length = i
				result.ok = true
				break scan
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
					result.length = i
					result.ok = true
					break scan
				}
			case:
				if exponent_digits == 0 {
					return
				}
				result.length = i
				result.ok = true
				break scan
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
					result.length = i
					result.ok = true
					break scan
				}
			case '.':
				result.format = .HexFloat
				state = .Hex_Fraction
			case 'p', 'P':
				if _exponent_marker_starts_identifier(src, i) {
					result.length = i
					result.ok = true
					break scan
				}
				result.format = .HexFloat
				state = .Hex_Exponent
			case:
				result.length = i
				result.ok = true
				break scan
			}

		case .Hex_Fraction:
			switch c {
			case '0' ..= '9', 'a' ..= 'f', 'A' ..= 'F':
				result.precision += 1
			case '_':
				if !_underscore_between_digits(src, i, 16) {
					return
				}
			case 'p', 'P':
				if _exponent_marker_starts_identifier(src, i) {
					return
				}
				state = .Hex_Exponent
			case:
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
					result.length = i
					result.ok = true
					break scan
				}
			case:
				if exponent_digits == 0 {
					return
				}
				result.length = i
				result.ok = true
				break scan
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
				result.length = i
				result.ok = true
				break scan
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
				result.length = i
				result.ok = true
				break scan
			}
		}
	}

	if result.ok {
		return
	}

	result.length = len(src)
	#partial switch state {
	case .Leading_Zero, .Decimal_Whole, .Decimal_Fraction, .Hex_Whole, .Octal_Whole, .Binary_Whole:
		result.ok = true
	case .Decimal_Exponent_Digits, .Hex_Exponent_Digits:
		result.ok = exponent_digits > 0
	case:
		result.ok = false
	}
	return
}

_match_numeric_dfa :: proc(cursor: common.Cursor, src: string) -> (Numeric, int) {
	match := _scan_numeric_dfa(src)
	if !match.ok {
		return {}, 0
	}

	raw := src[:match.length]
	value: exact.Rat
	parsed := false

	#partial switch match.format {
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
	return {
			raw = raw,
			value = value,
			digits = _count_significant_digits(raw, match.format),
			precision = match.precision,
			format = match.format,
		},
		match.length
}
