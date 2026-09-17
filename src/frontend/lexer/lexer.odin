package lexer

import "base:runtime"
import "core:fmt"
import "core:strings"
import "core:unicode"
import "core:unicode/utf8"

import "../../common"
import "../diagnostics"

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

	_append_garbage :: proc(tokens: ^[dynamic]Token, src: string, cursor: common.Cursor) -> int {
		r, n := utf8.decode_rune(src[cursor.offset:])
		if n <= 0 {
			n = 1
		}
		width := unicode.normalized_east_asian_width(r)
		span := common.cursor_to_span(cursor, n, width)

		if len(tokens) > 0 {
			last := &tokens[len(tokens) - 1]

			if _, is_garbage := last.what.(Garbage);
			   is_garbage &&
			   last.span.file == span.file &&
			   last.span.end.offset == span.start.offset {

				last.span.end = span.end
				last.what = Garbage(src[last.span.start.offset:span.end.offset])
				return n
			}
		}

		append(tokens, Token{span = span, what = Garbage(src[span.start.offset:span.end.offset])})
		return n
	}

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
			} else {
				advance_by = _append_garbage(&tokens, src, cursor)
			}

		case '"':
			if str, end, matched := _match_string_literal(cursor, src[offset:]); matched {
				append(&tokens, Token{span = common.cursor_to_span(cursor, end), what = str})
				advance_by = len(str.raw)
			} else {
				advance_by = _append_garbage(&tokens, src, cursor)
			}
		case '`':
			// escaped identifier: allows keywords, emoji, numbers
			if ident, n, w := _match_weird_ident(cursor, src[offset:]); ident != "" {
				interned_ident, err := strings.intern_get(&common.ident_intern, ident)
				assert(err == nil, "identifier intern failed")
				append(
					&tokens,
					Token {
						span = common.cursor_to_span(cursor, n, w),
						what = Identifier(interned_ident),
					},
				)
				advance_by = n
				// not a valid escaped identifier, so it's garbage
			} else {
				advance_by = _append_garbage(&tokens, src, cursor)
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
				advance_by = len(directive)

				// welp, I guess it's garbage
			} else {
				advance_by = _append_garbage(&tokens, src, cursor)
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

			} else if punct, n := _match_punctuation(cursor, src[offset:]); n > 0 {
				append(&tokens, Token{span = common.cursor_to_span(cursor, n), what = punct})
				advance_by = n

			} else if ident, width := _match_ident_like(src[offset:]); ident != "" {
				span := common.cursor_to_span(cursor, len(ident), width)

				what: Token_Data
				is_keyword := false

				for kw_str, keyword in KEYWORD_STRINGS {
					if ident == kw_str {
						what = keyword
						is_keyword = true
						break
					}
				}

				if what == nil {
					interned_ident, err := strings.intern_get(&common.ident_intern, ident)
					assert(err == nil, "identifier intern failed")
					what = Identifier(interned_ident)
				}

				if len(tokens) > 0 {
					prev_token := tokens[len(tokens) - 1]
					if num, is_num := prev_token.what.(Numeric);
					   is_num && prev_token.span.end.offset == cursor.offset {
						diag := diagnostics.emit(
							.Number_Followed_By_Identifier,
							common.merge_spans(prev_token.span, span),
							"number followed by %s without whitespace",
							"keyword" if is_keyword else "identifier",
						)
						diagnostics.suggest(
							diag,
							"put a space between %s and %s to make your intent clear",
							num.raw,
							ident,
						)
					}
				}

				append(&tokens, Token{span = span, what = what})
				advance_by = len(ident)

			} else {
				advance_by = _append_garbage(&tokens, src, cursor)
			}
		}
	}

	shrink(&tokens)
	return tokens[:]
}
