package lexer

import "core:fmt"
import "core:strconv"
import "core:strings"
import "core:unicode"
import "core:unicode/utf8"

import "../../common"
import "../../common/exact"
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


_match_string_literal :: proc(
	start: common.Cursor,
	s: string,
) -> (
	str_lit: String,
	end: common.Cursor,
	matched: bool,
) {
	mode: String_Mode
	start_offset := 0
	switch s[0] {
	case '"':
		mode = .Normal
	case '\\':
		if s[1] != '"' {
			return {}, start, false
		}
		mode = .Raw
		start_offset = 1
	case:
		return {}, start, false
	}

	multiline := strings.starts_with(s[start_offset:], `"""`)
	quote_count := 3 if multiline else 1
	start_offset += quote_count
	end_offset: int
	closed := false

	assert(start_offset >= 1)
	loop: for i in start_offset ..< len(s) {
		switch c := s[i]; c {
		case '"':
			if mode != .Raw && s[i - 1] == '\\' { 	// i - 1 is safe because start_offset >= 1
				continue loop
			}
			if !multiline {
				end_offset = i + 1
				closed = true
				break loop
			}
			if strings.starts_with(s[i:], `"""`) {
				end_offset = i + 3
				closed = true
				break loop
			}
		case '\n':
			if !multiline {
				end_offset = i
				closed = false
				break loop
			}
		}
	}

	if !closed {
		diagnostics.emit(
			.Unclosed_String,
			common.cursor_to_span(start, 1),
			"string literal was not closed",
		)
		return {}, start, false
	}

	end = start

	switch mode {
	case .Raw:
		common.cursor_advance(&end, s, end_offset)
		return {
				raw = s[:end_offset],
				value = strings.clone(s[start_offset:end_offset - quote_count]),
				mode = mode,
				is_multiline = multiline,
			},
			end,
			true
	case .Normal:
		common.cursor_advance(&end, s, start_offset)

		trim_leading_whitespace := 0

		// trim common leading whitespace for multiline strings that start with a line break
		if multiline && s[start_offset] == '\n' {
			line_iter := s[start_offset + 1:end_offset]
			max_leading_space := end_offset

			for line in strings.split_lines_iterator(&line_iter) {
				trimmed_line := strings.trim_left_space(line)
				if trimmed_line == "" || trimmed_line == `"""` {
					continue // ignore empty lines or the last line if it has no text on it besides the triple-quotes
				}
				leading_space := len(line) - len(trimmed_line)
				if leading_space < max_leading_space {
					max_leading_space = leading_space
				}
			}

			// Possibly surprising behavior: if there were no significant lines in the string literal
			// then the resulting string will only contain newlines (except for the first one)
			trim_leading_whitespace = max_leading_space
		}

		sb: strings.Builder
		strings.builder_init(&sb, 0, end_offset - quote_count)
		advance_by: int
		ignore_space := trim_leading_whitespace
		for i := start_offset; i < end_offset - quote_count; i += advance_by {
			advance_by = 1
			defer {
				assert(advance_by >= 1)
				common.cursor_advance(&end, s[i:], advance_by)
			}

			switch c := s[i]; c {
			case '\\':
				r, n := _interpret_escape(end, s[i:])
				if n > 0 {
					strings.write_rune(&sb, r)
					advance_by = n
				} else {
					advance_by = 2
				}
			case '\n':
				if !(multiline && i == start_offset) {
					strings.write_byte(&sb, c)
				}
				ignore_space = trim_leading_whitespace
			case:
				if ignore_space > 0 {
					ignore_space -= 1
					continue
				}
				strings.write_byte(&sb, c)
			}
		}

		common.cursor_advance(&end, s[end_offset - quote_count:], quote_count)
		return {
				raw = s[:end_offset],
				value = strings.to_string(sb),
				mode = mode,
				is_multiline = multiline,
			},
			end,
			true
	}

	return {}, start, false
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
			panic("TODO")
		} else {
			if sign != 0 {
				diagnostics.emit(
					.Signed_Unsigned_Literal,
					common.cursor_to_span(cursor, 1),
					"hex integer literal is signed",
				)
			}
			value, ok := exact.parse_int(unsigned[2:2 + match_len], 16)
			assert(ok)
			length := 2 + match_len + sign_skip
			return {raw = full[:length], value = exact.int_to_rat(value), format = .HexInteger},
				length
		}

	} else if strings.starts_with(unsigned, "0o") {

		if sign != 0 {
			diagnostics.emit(
				.Signed_Unsigned_Literal,
				common.cursor_to_span(cursor, 1),
				"found signed octal integer literal",
			)
		}
		panic("TODO")

	} else if strings.starts_with(unsigned, "0b") {
		if sign != 0 {
			diagnostics.emit(
				.Signed_Unsigned_Literal,
				common.cursor_to_span(cursor, 1),
				"found signed binary integer literal",
			)
		}
		panic("TODO")
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
		value, ok := exact.parse_int(full[:match_len], 10)
		assert(ok)
		return {raw = full[:match_len], value = exact.int_to_rat(value), format = .DecimalInteger},
			match_len
	case .Decimal:
		value, ok := exact.parse_decimal(full[:match_len], 10)
		assert(ok)
		return {raw = full[:match_len], value = value, format = .Decimal}, match_len
	case .Float:
		panic("float literals not yet implemented")
	}

	return {}, 0
}
