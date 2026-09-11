package parser

import "../../common"
import "../ast"
import "../diagnostics"


_block :: proc(ps: ^Parser_State) -> ^ast.Block {
	begin, ok := _match(ps, Punctuation.LCurly)
	if !ok {
		return nil
	}

	body := make([dynamic]ast.Statement)
	for {
		tok, has_token := _peek(ps)
		if !has_token {
			_error_before_here(ps, "block not closed")
			return nil
		}
		if tok.what == Punctuation.RCurly {
			ps.cur_token += 1
			block := new(ast.Block)
			block^ = {
				span = common.merge_spans(begin[0].span, tok.span),
				body = body[:],
			}
			return block
		}

		stmt := _statement(ps)
		if stmt != nil {
			append(&body, stmt)
		}
	}
}


_statement :: proc(ps: ^Parser_State) -> ast.Statement {
	tok, ok := _peek(ps)
	if !ok {
		return nil
	}

	stmt: ast.Statement
	switch tok.what {
	case Punctuation.Semicolon:
		ps.cur_token += 1
		diagnostics.emit(.Empty_Statement, common.collapse_span(tok.span), "empty statement")
		return nil

	case Keyword.Return:
		ps.cur_token += 1
		values := make([dynamic]ast.Expression)
		if first := _expr(ps); first != nil {
			append(&values, first)
			for _just_match(ps, Punctuation.Comma) {
				value := _expr(ps)
				if value == nil {
					break
				}
				append(&values, value)
			}
		}
		end_span := tok.span
		if len(values) > 0 {
			end_span = _expression_span(values[len(values) - 1])
		}
		ret := new(ast.Return_Statement)
		ret^ = {
			span   = common.merge_spans(tok.span, end_span),
			values = values[:],
		}
		stmt = ret

	case Keyword.Let:
		stmt = _const_or_var(ps, ast.Local_Variable)
	case Keyword.Const:
		stmt = _const_or_var(ps, ast.Local_Constant)

	case:
		expr := _expr(ps)
		if expr == nil {
			_error_here(ps, "invalid start of statement")
			_attempt_recovery(ps)
			return nil
		}

		lvalues := make([dynamic]ast.Expression)
		append(&lvalues, expr)
		for _just_match(ps, Punctuation.Comma) {
			lvalue := _expr(ps)
			if lvalue == nil {
				_error_here(ps, "expected an expression after the comma")
				_attempt_recovery(ps)
				return nil
			}
			append(&lvalues, lvalue)
		}

		if _just_match(ps, Punctuation.Assign) {
			rvalues := make([dynamic]ast.Expression)
			for {
				rvalue := _expr(ps)
				if rvalue == nil {
					_error_here(ps, "expected an expression here")
					_attempt_recovery(ps)
					return nil
				}
				append(&rvalues, rvalue)
				if !_just_match(ps, Punctuation.Comma) {
					break
				}
			}
			assignment := new(ast.Assign_Statement)
			assignment^ = {
				span  = common.merge_spans(
					_expression_span(expr),
					_expression_span(rvalues[len(rvalues) - 1]),
				),
				dests = lvalues[:],
				exprs = rvalues[:],
			}
			stmt = assignment
		} else if len(lvalues) != 1 {
			_error_here(ps, "expected an assignment here")
			return nil
		} else {
			expr_stmt := new(ast.Expr_Statement)
			expr_stmt^ = {
				span = _expression_span(expr),
				expr = expr,
			}
			stmt = expr_stmt
		}
	}

	if stmt == nil {
		return nil
	}
	if _end_of_statement(ps, required = false) {
		return stmt
	}
	_error_here(ps, "expected end of statement here")
	_attempt_recovery(ps)
	return nil
}
