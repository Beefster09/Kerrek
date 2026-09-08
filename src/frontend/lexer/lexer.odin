package lexer

import "base:runtime"
import "core:fmt"
import "core:strings"

import "../../common"

@(private = "file")
_PREALLOC_CAP_FACTOR_MUL :: #config(TOKEN_PREALLOC_FACTOR_MUL, 1)
@(private = "file")
_PREALLOC_CAP_FACTOR_DIV :: #config(TOKEN_PREALLOC_FACTOR_DIV, 4)

tokenize :: proc(sf: ^common.Source_File) -> []Token {
	assert(sf.contents != nil)

	tokens := make(
		[dynamic]Token,
		0,
		len(sf.contents) * _PREALLOC_CAP_FACTOR_MUL / _PREALLOC_CAP_FACTOR_DIV,
	)

	last_thing_was_garbage := false
	advance_by := 1
	cursor := common.Cursor {
		file = sf.id,
		line = 1,
		col  = 1,
	}
	src := transmute(string)sf.contents
	for offset := 0; offset < len(src); {
		advance_by = 1
		defer { 	// col advance and line offsets; run after each loop
			fmt.assertf(advance_by >= 1, "advance_by = %d", advance_by)
			common.cursor_advance(&cursor, src[cursor.offset:], advance_by)
			offset = int(cursor.offset)
		}

		switch c := src[offset]; c {
		case ' ', '\t', '\n', '\r':
			// control code or space; no token to produce
			last_thing_was_garbage = false // but spaces DO break up garbage
		case '\'':
			// rune
			if rune_literal, n := _match_rune_literal(cursor, src[offset:]); n > 0 {
				append(
					&tokens,
					Token {
						span = common.cursor_to_span(cursor, len(rune_literal.raw), n),
						what = rune_literal,
					},
				)
				advance_by = len(rune_literal.raw)
				last_thing_was_garbage = false
			} else {
				append(
					&tokens,
					Token {
						span = common.cursor_to_span(cursor, 1),
						what = Garbage(src[offset:offset + 1]),
					},
				)
				last_thing_was_garbage = true
			}

		case '"':
			if str, end, matched := _match_string_literal(cursor, src[offset:]); matched {
				append(&tokens, Token{span = common.cursor_to_span(cursor, end), what = str})
				advance_by = len(str.raw)
				last_thing_was_garbage = false
			} else {
				append(
					&tokens,
					Token {
						span = common.cursor_to_span(cursor, 1),
						what = Garbage(src[offset:offset + 1]),
					},
				)
				last_thing_was_garbage = true
			}
		case '\\':
			// comment?
			if strings.starts_with(src[offset:], "\\\\") {
				newline_at := strings.index(src[offset:], "\n")
				if newline_at != -1 {
					advance_by = newline_at
				} else {
					advance_by = len(src) - offset
				}

				// raw string?
			} else if str, end, matched := _match_string_literal(cursor, src[offset:]); matched {
				append(&tokens, Token{span = common.cursor_to_span(cursor, end), what = str})
				advance_by = len(str.raw)
				last_thing_was_garbage = false

				// directive?
			} else if directive, width := _match_ident_like(src[offset:]); directive != "" {
				append(
					&tokens,
					Token {
						span = common.cursor_to_span(cursor, len(directive), width),
						// ASSUMPTION: the underlying strings of the directive are never
						// going to outlive the loaded source.
						// There should be specific AST nodes dedicated to each use case
						// and in the rare case that a particular directive's textual value
						// must be preserved, you can intern it on the spot
						what = Directive(directive),
					},
				)
				last_thing_was_garbage = false
				advance_by = len(directive)

				// welp, I guess it's garbage
			} else {
				append(
					&tokens,
					Token {
						span = common.cursor_to_span(cursor, 1),
						what = Garbage(src[offset:offset + 1]),
					},
				)
				last_thing_was_garbage = true
			}

		case:
			// punctuation, identifier, keyword, or garbage
			if numeric, n := _match_numeric(cursor, src[offset:]); n > 0 {
				append(
					&tokens,
					Token {
						span = common.cursor_to_span(cursor, len(numeric.raw), n),
						what = numeric,
					},
				)
				advance_by = len(numeric.raw)
				last_thing_was_garbage = false

			} else if punct, n := _match_punctuation(cursor, src[offset:]); n > 0 {
				append(&tokens, Token{span = common.cursor_to_span(cursor, n), what = punct})
				last_thing_was_garbage = false
				advance_by = n

			} else if ident, width := _match_ident_like(src[offset:]); ident != "" {
				what: Token_Data

				for kw_str, keyword in KEYWORD_STRINGS {
					if ident == kw_str {
						what = keyword
						break
					}
				}

				if what == nil {
					interned_ident, err := strings.intern_get(&common.ident_intern, ident)
					assert(err == nil, "identifier intern failed")
					what = Identifier(interned_ident)
				}

				append(
					&tokens,
					Token{span = common.cursor_to_span(cursor, len(ident), width), what = what},
				)
				last_thing_was_garbage = false
				advance_by = len(ident)

			} else if last_thing_was_garbage {
				last_tok := &tokens[len(tokens) - 1]
				last_tok.span.end.offset += 1
				last_tok.span.end.col += 1 // FIXME: does not respect utf8 or wide characters
				last_tok.what = Garbage(src[last_tok.span.start.offset:offset + 1])

			} else {
				append(
					&tokens,
					Token {
						span = common.cursor_to_span(cursor, 1),
						what = Garbage(src[offset:offset + 1]),
					},
				)
				last_thing_was_garbage = true
			}
		}
	}

	shrink(&tokens)
	return tokens[:]
}
