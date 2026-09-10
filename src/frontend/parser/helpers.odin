package parser

import "base:intrinsics"
import "core:slice"

import "../../common"
import "../ast"
import "../diagnostics"
import "../lexer"

Punctuation :: lexer.Punctuation
Keyword :: lexer.Keyword
Identifier :: lexer.Identifier
Directive :: lexer.Directive
String :: lexer.String
Rune :: lexer.Rune
Numeric :: lexer.Numeric

Parser_State :: struct {
	tokens:      []lexer.Token,
	cur_token:   int,
	error_count: int,
}

_peek :: proc "contextless" (ps: ^Parser_State, offset := 0) -> (lexer.Token, bool) {
	index := ps.cur_token + offset
	if 0 <= index && index < len(ps.tokens) {
		return ps.tokens[index], true
	}
	return {}, false
}

_pop :: proc "contextless" (ps: ^Parser_State) -> (lexer.Token, bool) {
	if 0 <= ps.cur_token && ps.cur_token < len(ps.tokens) {
		result := ps.tokens[ps.cur_token]
		ps.cur_token += 1
		return result, true
	}
	return {}, false
}

_Typed_Token :: struct(T: typeid) where intrinsics.type_is_variant_of(lexer.Token_Data, T) {
	span: common.Span,
	what: T,
}

_Match_Item :: union {
	Punctuation,
	Keyword,
	Directive,
	M,
}

@(private)
M :: enum {
	Identifier,
	String,
	Rune,
	Numeric,
}

_match :: proc(ps: ^Parser_State, expected: ..union {
		Punctuation,
		Keyword,
		Directive,
		M,
	}) -> ([]lexer.Token, bool) {

	for exp_union, i in expected {
		if tok, exists := _peek(ps, i); exists {
			switch exp in exp_union {
			case M:
				switch exp {
				case .Identifier:
					if _, ok := tok.what.(Identifier); !ok {
						return nil, false
					}
				case .String:
					if _, ok := tok.what.(String); !ok {
						return nil, false
					}
				case .Rune:
					if _, ok := tok.what.(Rune); !ok {
						return nil, false
					}
				case .Numeric:
					if _, ok := tok.what.(Numeric); !ok {
						return nil, false
					}
				}
			case Punctuation:
				if tok.what != exp {
					return nil, false
				}
			case Keyword:
				if tok.what != exp {
					return nil, false
				}
			case Directive:
				if tok.what != exp {
					return nil, false
				}
			}
		}
	}

	advance_by := len(expected)
	results := ps.tokens[ps.cur_token:ps.cur_token + advance_by]
	ps.cur_token += advance_by
	return results, true
}

_just_match :: proc(ps: ^Parser_State, expected: ..union {
		Punctuation,
		Keyword,
		Directive,
	}) -> bool {

	for exp_union, i in expected {
		if tok, exists := _peek(ps, i); exists {
			switch exp in exp_union {
			case Punctuation:
				if tok.what != exp {
					return false
				}
			case Keyword:
				if tok.what != exp {
					return false
				}
			case Directive:
				if tok.what != exp {
					return false
				}
			}
		}
	}

	ps.cur_token += len(expected)
	return true
}

_match1 :: proc(
	ps: ^Parser_State,
	$T: typeid,
) -> (
	_Typed_Token(T),
	bool,
) where intrinsics.type_is_variant_of(lexer.Token_Data, T) {
	if tok, exists := _peek(ps); exists {
		if what, is_type := tok.what.(T); is_type {
			ps.cur_token += 1
			return {tok.span, what}, true
		}
	}
	return {}, false
}

_end_of_statement :: proc(ps: ^Parser_State, _: ..struct{}, required := true) -> bool {
	if ps.tokens[ps.cur_token].what == Punctuation.Semicolon {
		ps.cur_token += 1
		return true
	}

	if required {
		prev := ps.tokens[max(ps.cur_token - 1, 0)]
		diagnostics.emit(
			.Syntax_Error,
			{file = prev.span.file, start = prev.span.end, end = prev.span.end},
			"expected ';' here",
		)
	}

	return false
}

_attempt_recovery :: proc "contextless" (ps: ^Parser_State) {
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
	annotations: ^[dynamic]^ast.Annotation,
) where intrinsics.type_has_field(T, "annotations") {
	to.annotations = slice.clone(annotations^[:])
	clear(annotations)
}


_error_here :: proc(ps: ^Parser_State, format: string, args: ..any) -> ^diagnostics.Diagnostic {
	return diagnostics.emit_with_default_level(
		.Syntax_Error,
		ps.tokens[ps.cur_token].span,
		format,
		..args,
	)
}

_error_before_here :: proc(
	ps: ^Parser_State,
	format: string,
	args: ..any,
) -> ^diagnostics.Diagnostic {
	return diagnostics.emit_with_default_level(
		.Syntax_Error,
		common.collapse_span_to_end(ps.tokens[max(ps.cur_token - 1, 0)].span),
		format,
		..args,
	)
}
