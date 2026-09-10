package parser

import "core:slice"

import "../../common"
import "../ast"
import "../lexer"

_name :: proc {
	_name_from_typed_token,
	_name_from_untyped_token,
}

_name_from_typed_token :: proc(from: _Typed_Token(Identifier)) -> ast.Name {
	return {from.span, from.what}
}

_name_from_untyped_token :: proc(from: lexer.Token) -> ast.Name {
	return {from.span, from.what.(Identifier)}
}

_qualname :: proc(ps: ^Parser_State, required := false) -> (ast.Qualified_Name, bool) {
	path := make([dynamic]ast.Name)

	if q, ok := _match1(ps, Identifier); ok {
		append(&path, _name(q))

		for m in _match(ps, Punctuation.Dot, M.Identifier) {
			append(&path, _name(m[1]))
		}

		return {common.merge_spans(path[0].span, path[len(path) - 1].span), path[:]}, true
	} else {
		if required {
			_error_here(ps, "expected a qualified name here")
		}
		return {}, false
	}

}
