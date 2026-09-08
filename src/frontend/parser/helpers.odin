package parser

import "base:intrinsics"
import "core:slice"

import "../ast"
import "../lexer"

Punctuation :: lexer.Punctuation
Keyword :: lexer.Keyword
Identifier :: lexer.Identifier
Directive :: lexer.Directive
String :: lexer.String
Rune :: lexer.Rune
Numeric :: lexer.Numeric

Parsing_State :: struct {
	tokens:      []lexer.Token,
	cur_token:   int,
	error_count: int,
}

peek :: proc "contextless" (ps: ^Parsing_State) -> (lexer.Token, bool) {
	if 0 <= ps.cur_token && ps.cur_token < len(ps.tokens) {
		return ps.tokens[ps.cur_token], true
	}
	return {}, false
}

pop :: proc "contextless" (ps: ^Parsing_State) -> (lexer.Token, bool) {
	if 0 <= ps.cur_token && ps.cur_token < len(ps.tokens) {
		result := ps.tokens[ps.cur_token]
		ps.cur_token += 1
		return result, true
	}
	return {}, false
}

_end_of_statement :: proc(ps: ^Parsing_State) -> bool {
	if ps.tokens[ps.cur_token].what == Punctuation.Semicolon {
		ps.cur_token += 1
		return true
	}

	return false
}

_attempt_recovery :: proc "contextless" (ps: ^Parsing_State) {
	for ps.cur_token < len(ps.tokens) {
		tok := ps.tokens[ps.cur_token]
		ps.cur_token += 1
		if tok.what == Punctuation.Semicolon || tok.what == Punctuation.RCurly {
			return
		}
	}
	ps.cur_token = len(ps.tokens)
}

_attach_annotations :: proc(
	to: ^$T,
	annotations: []^ast.Annotation,
) where intrinsics.type_has_field(T, "annotations") {
	to.annotations = slice.clone(annotations)
}
