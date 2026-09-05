package lexer

import "core:strings"


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
	return "", 0
}
