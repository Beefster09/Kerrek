package parser

import "core:fmt"

import "../../common"
import "../ast"
import "../diagnostics"
import "../lexer"


_expr :: proc(ps: ^Parser_State) -> ast.Expression {
	expr := _expr_atom(ps)
	if expr == nil {
		return nil
	}

	expr = _binop_expr(ps, expr)
	if expr == nil {
		return nil
	}

	if _just_match(ps, Keyword.Reinterpret, Keyword.Unit, Keyword.As) {
		to_unit := _compound_unit(ps)
		if to_unit == nil {
			_error_here(ps, "expected a target unit for unit reinterpretation")
			return expr
		}
		reinterpret := new(ast.Unit_Reinterpret_Expr)
		reinterpret^ = {
			span     = common.merge_spans(_expression_span(expr), to_unit.span),
			expr     = expr,
			new_unit = to_unit,
		}
		return reinterpret
	}

	if _just_match(ps, Keyword.As) {
		to_type := _type_expr(ps)
		if to_type == nil {
			_error_here(ps, "expected a target type for cast expression")
			return expr
		}
		cast_expr := new(ast.Cast_Expr)
		cast_expr^ = {
			span = common.merge_spans(_expression_span(expr), _type_span(to_type)),
			expr = expr,
			to   = to_type,
		}
		return cast_expr
	}

	return expr
}


_expr_atom :: proc(ps: ^Parser_State) -> ast.Expression {
	atom: ast.Expression

	if lparen, ok := _match(ps, Punctuation.LParen); ok {
		inner := _expr(ps)
		if inner == nil {
			_error_here(ps, "expected an expression inside the parentheses")
			return nil
		}
		if rparen, ok := _match(ps, Punctuation.RParen); ok {
			_set_expression_span(inner, common.merge_spans(lparen[0].span, rparen[0].span))
			atom = inner
		} else {
			diagnostics.emit(
				.Syntax_Error,
				lparen[0].span,
				"parenthesized expression was not closed",
			)
			return nil
		}
	} else if ident, ok := _match1(ps, Identifier); ok {
		name_expr := new(ast.Name_Expr)
		name_expr^ = {
			span = ident.span,
			name = _name(ident),
		}
		atom = name_expr
	} else {
		atom = _literal_expr(ps)
	}

	// Field access, dereference, calls, and indexing are still unimplemented in
	// pykerrek and intentionally remain outside this compatibility port.
	return atom
}


_literal_expr :: proc(ps: ^Parser_State) -> ast.Expression {
	tok, ok := _peek(ps)
	if !ok {
		return nil
	}

	#partial switch value in tok.what {
	case Numeric:
		ps.cur_token += 1
		unit := _compound_unit(ps)
		literal := new(ast.Scalar_Literal_Expr)
		literal^ = {
			span  = common.merge_spans(tok.span, unit.span) if unit != nil else tok.span,
			value = value.value,
			unit  = unit,
		}
		return literal

	case String:
		ps.cur_token += 1
		literal := new(ast.Simple_Literal_Expr)
		literal^ = {
			span  = tok.span,
			value = value.value,
		}
		return literal

	case Rune:
		ps.cur_token += 1
		literal := new(ast.Simple_Literal_Expr)
		literal^ = {
			span  = tok.span,
			value = value.codepoint,
		}
		return literal

	case Keyword:
		#partial switch value {
		case .True:
			literal := new(ast.Simple_Literal_Expr)
			literal^ = {
				span  = tok.span,
				value = true,
			}
			ps.cur_token += 1
			return literal
		case .False:
			literal := new(ast.Simple_Literal_Expr)
			literal^ = {
				span  = tok.span,
				value = false,
			}
			ps.cur_token += 1
			return literal
		case .Nil:
			literal := new(ast.Simple_Literal_Expr)
			literal^ = {
				span  = tok.span,
				value = common.Flex_Value.Nil,
			}
			ps.cur_token += 1
			return literal
		case .Placeholder:
			placeholder := new(ast.Placeholder_Expr)
			placeholder.span = tok.span
			ps.cur_token += 1
			return placeholder
		case:
			return nil
		}
	}

	return nil
}


_binop_expr :: proc(
	ps: ^Parser_State,
	lhs: ast.Expression,
	min_precedence := 0,
) -> ast.Expression {
	result := lhs
	for {
		op_tok1, has_op1 := _peek(ps)
		if !has_op1 {
			return result
		}
		op, has_binary_op := _binary_op(op_tok1)
		if !has_binary_op {
			return result
		}
		prec1 := BINOPS_PRECEDENCE[op].prec
		if prec1 < min_precedence {
			return result
		}

		ps.cur_token += 1
		rhs := _expr_atom(ps)
		if rhs == nil {
			_error_here(ps, "expected a sub-expression here")
			return nil
		}

		for {
			op_tok2, has_op2 := _peek(ps)
			if !has_op2 {
				break
			}
			op2, has_binary_op2 := _binary_op(op_tok2)
			if !has_binary_op2 {
				break
			}
			info2 := BINOPS_PRECEDENCE[op2]
			if info2.associativity == .None && info2.prec == prec1 {
				diagnostics.emit(
					.Syntax_Error,
					op_tok2.span,
					"operators %s and %s are not associative",
					_operator_string(op_tok1),
					_operator_string(op_tok2),
				)
				return nil
			}
			if !(info2.prec > prec1 || info2.associativity == .Right && info2.prec == prec1) {
				break
			}
			rhs = _binop_expr(ps, rhs, prec1 + (1 if info2.prec > prec1 else 0))
			if rhs == nil {
				return nil
			}
		}

		binop := new(ast.Binop_Expr)
		binop^ = {
			span = common.merge_spans(_expression_span(result), _expression_span(rhs)),
			op   = op,
			lhs  = result,
			rhs  = rhs,
		}
		result = binop
	}
}


_binary_op :: proc "contextless" (tok: lexer.Token) -> (common.Binary_Op, bool) {
	#partial switch what in tok.what {
	case Punctuation:
		op := PUNCT_BINOP[what]
		return op, op != common.Binary_Op(0)
	case Keyword:
		op := KW_BINOP[what]
		return op, op != common.Binary_Op(0)
	case:
		return common.Binary_Op(0), false
	}
}


_operator_string :: proc(tok: lexer.Token) -> string {
	#partial switch what in tok.what {
	case Punctuation:
		return lexer.PUNCTUATION_STRINGS[what]
	case Keyword:
		return lexer.KEYWORD_STRINGS[what]
	case:
		return fmt.tprintf("%v", what)
	}
}


_expression_span :: proc "contextless" (expr: ast.Expression) -> ast.Span {
	switch node in expr {
	case ^ast.Name_Expr:
		return node.span
	case ^ast.Placeholder_Expr:
		return node.span
	case ^ast.FieldAccess_Expr:
		return node.span
	case ^ast.Scalar_Literal_Expr:
		return node.span
	case ^ast.Simple_Literal_Expr:
		return node.span
	case ^ast.Implicit_Enum_Expr:
		return node.span
	case ^ast.Move_Expr:
		return node.span
	case ^ast.Binop_Expr:
		return node.span
	case ^ast.Unary_Expr:
		return node.span
	case ^ast.Address_Of_Expr:
		return node.span
	case ^ast.Dereference_Expr:
		return node.span
	case ^ast.Cast_Expr:
		return node.span
	case ^ast.Unit_Conversion_Expr:
		return node.span
	case ^ast.Unit_Reinterpret_Expr:
		return node.span
	case ^ast.Index_Expr:
		return node.span
	case ^ast.Callish_Expr:
		return node.span
	case ^ast.Type_Expr_Expr:
		return node.span
	case ^ast.Unit_Expr:
		return node.span
	case nil:
		return {}
	}
	return {}
}


_set_expression_span :: proc "contextless" (expr: ast.Expression, span: ast.Span) {
	switch node in expr {
	case ^ast.Name_Expr:
		node.span = span
	case ^ast.Placeholder_Expr:
		node.span = span
	case ^ast.FieldAccess_Expr:
		node.span = span
	case ^ast.Scalar_Literal_Expr:
		node.span = span
	case ^ast.Simple_Literal_Expr:
		node.span = span
	case ^ast.Implicit_Enum_Expr:
		node.span = span
	case ^ast.Move_Expr:
		node.span = span
	case ^ast.Binop_Expr:
		node.span = span
	case ^ast.Unary_Expr:
		node.span = span
	case ^ast.Address_Of_Expr:
		node.span = span
	case ^ast.Dereference_Expr:
		node.span = span
	case ^ast.Cast_Expr:
		node.span = span
	case ^ast.Unit_Conversion_Expr:
		node.span = span
	case ^ast.Unit_Reinterpret_Expr:
		node.span = span
	case ^ast.Index_Expr:
		node.span = span
	case ^ast.Callish_Expr:
		node.span = span
	case ^ast.Type_Expr_Expr:
		node.span = span
	case ^ast.Unit_Expr:
		node.span = span
	case nil:
	}
}
