package parser

import "../../common"
import "../ast"
import "../diagnostics"


_type_expr :: proc(ps: ^Parser_State, allow_generics := false) -> ast.Type_Expression {
	typ: ast.Type_Expression
	tok, has_tok := _peek(ps)
	if !has_tok {
		_error_here(ps, "expected a type here")
		return nil
	}

	switch tok.what {
	case Punctuation.Dollar:
		if template, ok := _match(ps, Punctuation.Dollar, M.Identifier); ok {
			generic := new(ast.Generic_Type)
			generic^ = {
				span = common.merge_spans(template[0].span, template[1].span),
				name = _name(template[1]),
			}
			typ = generic
		}
		if !allow_generics {
			diagnostics.emit(.Syntax_Error, tok.span, "generic types are not allowed here")
		}

	case Punctuation.Caret, Keyword.Owned, Keyword.Shared, Keyword.Weak:
		typ = _pointer_type(ps)

	case Punctuation.LSquare:
		// Arrays are not implemented in the Python parser yet.

	case Keyword.Map:
		// Maps are not implemented in the Python parser yet.

	case Punctuation.Question:
		question, _ := _pop(ps)
		inner := _type_expr(ps, allow_generics)
		if inner != nil {
			optional := new(ast.Optional_Type)
			optional^ = {
				span = common.merge_spans(question.span, _type_span(inner)),
				base = inner,
			}
			typ = optional
		} else {
			_error_here(ps, "expected a type expression after the optional specifier")
		}

	case Punctuation.LParen:
		lparen, _ := _pop(ps)
		typ = _type_expr(ps, allow_generics)
		if typ != nil {
			if rparen, ok := _match(ps, Punctuation.RParen); ok {
				_set_type_span(typ, common.merge_spans(lparen.span, rparen[0].span))
			} else {
				_error_here(ps, "parenthesized type expression was not closed")
			}
		} else {
			_error_here(ps, "expected a type expression inside the parentheses")
		}

	case:
		typ = _simple_type(ps)
	}

	if typ == nil {
		_error_here(ps, "expected a type here")
		return nil
	}

	tags := make([dynamic]ast.Qualified_Name)
	for _just_match(ps, Punctuation.Tilde) {
		tag, ok := _qualname(ps)
		if !ok {
			_error_here(ps, "expected a tag name here")
			return nil
		}
		append(&tags, tag)
	}

	if len(tags) > 0 {
		tagged := new(ast.Type_With_Tags)
		tagged^ = {
			span = common.merge_spans(_type_span(typ), tags[len(tags) - 1].span),
			base = typ,
			tags = tags[:],
		}
		typ = tagged
	}

	return typ
}


_simple_type :: proc(ps: ^Parser_State) -> ast.Type_Expression {
	qualname, ok := _qualname(ps)
	if !ok {
		return nil
	}
	simple := new(ast.Simple_Type)
	simple^ = {span = qualname.span, type = qualname}
	return simple
}


_pointer_type :: proc(ps: ^Parser_State) -> ast.Type_Expression {
	prefix, ok := _pop(ps)
	if !ok {
		return nil
	}

	ownership: common.Pointer_Ownership
	switch prefix.what {
	case Punctuation.Caret:
		ownership = .Borrow
	case Keyword.Owned:
		ownership = .Owned
	case Keyword.Shared:
		ownership = .Shared
	case Keyword.Weak:
		ownership = .Weak
	case:
		diagnostics.emit(.Syntax_Error, prefix.span, "invalid prefix of pointer type")
		return nil
	}

	to := _type_expr(ps)
	if to == nil {
		_error_here(ps, "pointer type must point to something")
		return nil
	}

	pointer := new(ast.Pointer_Type)
	pointer^ = {
		span = common.merge_spans(prefix.span, _type_span(to)),
		to = to,
		ownership = ownership,
	}
	return pointer
}


_type_span :: proc "contextless" (typ: ast.Type_Expression) -> ast.Span {
	switch node in typ {
	case ^ast.Simple_Type:
		return node.span
	case ^ast.Type_With_Args:
		return node.span
	case ^ast.Generic_Type:
		return node.span
	case ^ast.Optional_Type:
		return node.span
	case ^ast.Pointer_Type:
		return node.span
	case ^ast.Type_With_Tags:
		return node.span
	case nil:
		return {}
	}
	return {}
}


_set_type_span :: proc "contextless" (typ: ast.Type_Expression, span: ast.Span) {
	switch node in typ {
	case ^ast.Simple_Type:
		node.span = span
	case ^ast.Type_With_Args:
		node.span = span
	case ^ast.Generic_Type:
		node.span = span
	case ^ast.Optional_Type:
		node.span = span
	case ^ast.Pointer_Type:
		node.span = span
	case ^ast.Type_With_Tags:
		node.span = span
	case nil:
	}
}
