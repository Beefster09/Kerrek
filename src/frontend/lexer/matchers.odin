package lexer

import "core:strings"
import "core:unicode"
import "core:unicode/utf8"


_match_punctuation :: proc(s: string) -> (Punctuation, int) {
	longest_match := Punctuation(0)
	longest_match_len := 0
	for ps, punct in PUNCTUATION_STRINGS {
		if strings.starts_with(s, ps) && len(ps) > longest_match_len {
			longest_match_len = len(ps)
			longest_match = punct
		}
	}

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
