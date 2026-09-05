package lexer

import "base:runtime"
import "core:strings"
import "core:unicode"
import "core:unicode/utf8"

import "../../common"

PREALLOC_CAP_FACTOR_MUL :: #config(TOKEN_PREALLOC_FACTOR_MUL, 1)
PREALLOC_CAP_FACTOR_DIV :: #config(TOKEN_PREALLOC_FACTOR_DIV, 4)

tokenize :: proc(src_path: string) -> ([]Token, common.Load_Source_Error) {
	sf, ldsrc_err := common.load_source(src_path)
	if ldsrc_err != .OK {
		return nil, ldsrc_err
	}

	tokens := make(
		[dynamic]Token,
		0,
		len(sf.contents) * PREALLOC_CAP_FACTOR_MUL / PREALLOC_CAP_FACTOR_DIV,
	)

	last_thing_was_garbage := false
	advance_by := 1
	line: u16 = 1
	col: u16 = 1
	src := transmute(string)sf.contents
	for offset := 0; offset < len(src); offset += advance_by {
		advance_by = 1
		defer { 	// col advance and line offsets
			assert(advance_by >= 1)
			for i in offset ..< offset + advance_by {
				switch c := src[i]; c {
				case '\n':
					append(&sf.line_offsets, u32(i + 1))
					col = 1
					line += 1
				case '\t':
					col += common.tab_width - (col - 1) % common.tab_width
				case 0 ..< ' ':
				// other ASCII control; no need to increment col
				case ' ' ..< utf8.LOCB:
					col += 1
				case utf8.LOCB ..= utf8.HICB:
				// continuation byte; no need to increment col
				case utf8.T2 ..< utf8.T5:
					r, n := utf8.decode_rune(src[i:])
					if n > 1 {
						col += u16(unicode.normalized_east_asian_width(r))
					}
				}
			}
		}

		switch c := src[offset]; c {
		case 0 ..= ' ':
			// control code or space; no token to produce
			last_thing_was_garbage = false
		case '0' ..= '9': // numeric
		case '\'': // rune
		case '"': // string
		case '\\':
			// comment maybe
			if offset + 1 >= len(src) {
				append(
					&tokens,
					Token {
						span = {
							file = sf.id,
							start = {u32(offset), line, col},
							end = {u32(offset + 1), line, col + 1},
						},
						what = Punctuation.Backslash,
					},
				)
				last_thing_was_garbage = false
			} else if src[offset + 1] == '\\' {
				newline_at := strings.index(src[offset:], "\n")
				if newline_at != -1 {
					advance_by = newline_at
				} else {
					advance_by = len(src) - offset
				}
			}
		case:
			// punctuation, identifier, placeholder, or garbage
			if punct, n := _match_punctuation(src[offset:]); n > 0 {
				append(
					&tokens,
					Token {
						span = {
							file = sf.id,
							start = {u32(offset), line, col},
							end = {u32(offset + n), line, col + u16(n)},
						},
						what = punct,
					},
				)
				last_thing_was_garbage = false
				advance_by = n
			} else if ident, width := _match_ident_like(src[offset:]); ident != "" {
				// TODO
			} else if last_thing_was_garbage {
				last_tok := &tokens[len(tokens) - 1]
				last_tok.span.end.offset += 1
				last_tok.span.end.col += 1
				(cast(^runtime.Raw_String)(&last_tok.what.(Garbage))).len += 1
			} else {
				append(
					&tokens,
					Token {
						span = {
							file = sf.id,
							start = {u32(offset), line, col},
							end = {u32(offset + 1), line, col + 1},
						},
						what = Garbage(src[offset:offset + 1]),
					},
				)
				last_thing_was_garbage = true
			}
		}
	}

	shrink(&tokens)
	return tokens[:], .OK
}
