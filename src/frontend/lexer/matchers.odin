package lexer

import "core:math/big"
import "core:strconv"
import "core:strings"
import "core:unicode"
import "core:unicode/utf8"

import "../../common"
import "../diagnostics"


_match_punctuation :: proc(cursor: common.Cursor, s: string) -> (punct: Punctuation, width: int) {
	longest_match := Punctuation(0)
	longest_match_len := 0
	for ps, punct in PUNCTUATION_STRINGS {
		if strings.starts_with(s, ps) && len(ps) > longest_match_len {
			longest_match_len = len(ps)
			longest_match = punct
		}
	}

	// TODO: check if followed by punctuation that could be interpreted another way and emit a diagnostic if so

	return longest_match, longest_match_len
}


_match_ident_like :: proc(s: string) -> (idlike: string, width: int) {
	for i := 0; i < len(s); {
		r, n := utf8.decode_rune(s[i:])
		if r == '_' || unicode.is_alpha(r) || i > 0 && unicode.is_number(r) {
			width += unicode.normalized_east_asian_width(r)
			i += n
		} else {
			return s[:i], width
		}
	}

	return "", 0
}


_match_rune_literal :: proc(cursor: common.Cursor, s: string) -> (rune_lit: Rune, width: int) {
	if s[0] != '\'' {
		return {}, 0
	}

	codepoint: rune
	length: int
	switch c := s[1]; c {
	case '\\':
		codepoint, length = _interpret_escape(common.cursor_add(cursor, 1), s[1:])
		if length == 0 {
			return {}, 0
		}
		width = length

	case ' ', '\'':
		codepoint = rune(c)
		length = 1
		width = length

	case:
		codepoint, length = utf8.decode_rune(s[1:])
		width = unicode.normalized_east_asian_width(codepoint)
	}

	if s[length + 1] == '\'' {
		length += 2
		width += 2
	} else {
		diagnostics.emit(
			.Unclosed_Rune,
			common.cursor_to_span(cursor, length + 1, width + 1),
			"unclosed rune: %s",
			strings.trim_space(s[:length + 1]),
		)
		return {}, 0
	}

	return {s[:length], codepoint}, width
}


_interpret_escape :: proc(cursor: common.Cursor, s: string) -> (rune, int) {
	if s[0] != '\\' {
		return 0, 0
	}

	_hex_escape :: proc(cursor: common.Cursor, s: string, n: int) -> (rune, bool) {
		if _is_hex(s[2:n]) {
			v, ok := strconv.parse_u64(s[2:n], 16)
			if ok {
				return rune(v), true
			}
		}
		diagnostics.emit(
			.Invalid_Escape,
			common.cursor_to_span(cursor, n),
			"invalid escape: '%s'",
			s[:n],
		)
		return 0, false
	}

	switch c := s[1]; c {
	case '0':
		return 0, 2
	case 'n':
		return '\n', 2
	case 't':
		return '\t', 2
	case 'r':
		return '\r', 2
	case 'e':
		return '\e', 2
	case 'a':
		return '\a', 2
	case 'b':
		return '\b', 2
	case 'x':
		if r, ok := _hex_escape(cursor, s, 4); ok {
			return r, 4
		}
	case 'u':
		if r, ok := _hex_escape(cursor, s, 6); ok {
			return r, 6
		}
	case 'U':
		if r, ok := _hex_escape(cursor, s, 8); ok {
			return r, 8
		}

	case '"' | '\'' | '\\':
		return rune(c), 2

	case:
		diagnostics.emit(
			.Invalid_Escape,
			common.cursor_to_span(cursor, 2),
			"invalid escape: '%s'",
			s[:2],
		)
	}
	return 0, 0
}

_is_hex :: proc(s: string) -> bool {
	for c in s {
		switch c {
		case '0' ..= '9', 'a' ..= 'f', 'A' ..= 'F':
		// intentionally blank
		case:
			return false
		}
	}
	return true
}

_match_numeric :: proc(cursor: common.Cursor, full: string) -> (Numeric, int) {
	sign := 0 // also encodes if sign is given

	switch full[0] {
	case '+':
		sign = 1
	case '-':
		sign = -1
	}

	sign_skip := 0 if sign == 0 else 1
	unsigned := full[sign_skip:]

	if strings.starts_with(unsigned, "0x") {
		_check_hexfloat :: proc(s: string) -> (length: int, is_float: bool, ok: bool) {
			state: enum {
				Whole,
				Fractional,
				Exponent,
				Exponent_Digits,
			}
			whole_digits := 0
			frac_digits := 0
			exp_digits := 0
			for c, i in s {
				switch state {
				case .Whole:
					switch c {
					case '0' ..= '9', 'a' ..= 'f', 'A' ..= 'F':
						whole_digits += 1
					case '.':
						is_float = true
						state = .Fractional
					case 'p':
						is_float = true
						state = .Exponent
					case:
						return i, false, whole_digits > 0
					}
				case .Fractional:
					switch c {
					case '0' ..= '9', 'a' ..= 'f', 'A' ..= 'F':
						frac_digits += 1
					case 'p':
						state = .Exponent
					case:
						return i, true, whole_digits > 0
					}
				case .Exponent:
					switch c {
					case '0' ..= '9', 'a' ..= 'f', 'A' ..= 'F':
						exp_digits += 1
						state = .Exponent_Digits
					case '+', '-':
						state = .Exponent_Digits
					case:
						return 0, true, false
					}
				case .Exponent_Digits:
					switch c {
					case '0' ..= '9', 'a' ..= 'f', 'A' ..= 'F':
						exp_digits += 1
					case:
						return i, true, whole_digits > 0 && exp_digits > 0
					}
				}
			}

			return len(s), is_float, whole_digits > 0 && (!is_float || exp_digits > 0)
		}
		match_len, is_float, ok := _check_hexfloat(unsigned[2:])

		if !ok {
			diagnostics.emit(
				.Invalid_Number_Literal,
				common.cursor_to_span(cursor, match_len + 2 + sign_skip),
				"invalid hex literal",
			)
			return {}, 0
		} else if is_float {
			floatval, nr, ok := strconv.parse_f64_prefix(full)
			if !ok {
				diagnostics.emit(
					.Invalid_Number_Literal,
					common.cursor_to_span(cursor, nr),
					"invalid hex float literal",
				)
				return {}, 0
			}
		} else {
			if sign != 0 {
				diagnostics.emit(
					.Signed_Unsigned_Literal,
					common.cursor_to_span(cursor, 1),
					"hex integer literal is signed",
				)
			}
			value: big.Rat
			err := big.atoi(&value.a, unsigned[2:2 + match_len], 16, common.bigint_allocator)
			assert(err == nil)
			big.one(&value.b)
			length := 2 + match_len + sign_skip
			return {raw = full[:length], value = value, format = .HexInteger}, length
		}
	} else if strings.starts_with(unsigned, "0o") {

		if sign != 0 {
			diagnostics.emit(
				.Signed_Unsigned_Literal,
				common.cursor_to_span(cursor, 1),
				"found signed octal integer literal",
			)
		}
	} else if strings.starts_with(unsigned, "0b") {

		if sign != 0 {
			diagnostics.emit(
				.Signed_Unsigned_Literal,
				common.cursor_to_span(cursor, 1),
				"found signed binary integer literal",
			)
		}
	}

	_check_decimal :: proc(s: string) -> (length: int, form: Number_Format, ok: bool) {
		state: enum {
			Whole,
			Fractional,
			Exponent,
			Exponent_Digits,
			Float_Terminator,
			Float_Terminator_After_Exponent,
		}
		form = .DecimalInteger
		whole_digits := 0
		frac_digits := 0
		exp_digits := 0
		for c, i in s {
			switch state {
			case .Whole:
				switch c {
				case '0' ..= '9':
					whole_digits += 1
				case '.':
					form = .Decimal
					state = .Fractional
				case 'e':
					form = .Decimal
					state = .Exponent
				case 'f':
					form = .Float
					state = .Float_Terminator
				case:
					return i, .DecimalInteger, whole_digits > 0
				}
			case .Fractional:
				switch c {
				case '0' ..= '9':
					frac_digits += 1
				case 'e':
					form = .Decimal
					state = .Exponent
				case 'f':
					form = .Float
					state = .Float_Terminator
				case:
					return i, .Decimal, whole_digits > 0
				}
			case .Exponent:
				switch c {
				case '0' ..= '9':
					exp_digits += 1
					state = .Exponent_Digits
				case '+', '-':
					state = .Exponent_Digits
				case:
					return 0, .Decimal, false
				}
			case .Exponent_Digits:
				switch c {
				case '0' ..= '9':
					exp_digits += 1
				case 'f':
					form = .Float
					state = .Float_Terminator_After_Exponent
				case:
					return i, .Decimal, whole_digits > 0 && exp_digits > 0
				}
			case .Float_Terminator:
				return i, .Float, whole_digits > 0
			case .Float_Terminator_After_Exponent:
				return i, .Float, whole_digits > 0 && exp_digits > 0
			}
		}

		#partial switch state {
		case .Float_Terminator_After_Exponent:
			return len(s), .Float, whole_digits > 0 && exp_digits > 0
		case:
			return len(s), form, whole_digits > 0
		}

	}
	match_len, form, ok := _check_decimal(unsigned)
	if !ok {
		return {}, 0
	}

	match_len += sign_skip

	#partial switch form {
	case .DecimalInteger:
		value: big.Rat
		err := big.atoi(&value.a, full[:match_len], 10, common.bigint_allocator)
		assert(err == nil)
		big.one(&value.b)
		return {raw = full[:match_len], value = value, format = .DecimalInteger}, match_len
	case .Decimal:
	case .Float:
	}

	return {}, 0
}
