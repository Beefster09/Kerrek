package parser

import "../../common"
import "../ast"
import "../diagnostics"


_func_def :: proc(ps: ^Parser_State) -> ^ast.Func_Definition {
	func_keyword, has_keyword := _match(ps, Keyword.Func)
	assert(has_keyword)

	func_name, ok := _match1(ps, Identifier)
	if !ok {
		_error_here(ps, "expected function name")
		return nil
	}

	params, has_param_list := _param_list(ps)
	if !has_param_list {
		_error_here(ps, "expected a parameter list")
		return nil
	}

	returns := make([dynamic]^ast.Func_Return)
	error_type: ast.Type_Expression
	fallible := false
	if _just_match(ps, Punctuation.Arrow) {
		for {
			name: Maybe(ast.Name)
			start_span: ast.Span
			if named, ok := _match(ps, M.Identifier, Punctuation.Colon); ok {
				name = _name(named[0])
				start_span = named[0].span
			} else if next, ok := _peek(ps); ok {
				start_span = common.collapse_span(next.span)
			} else {
				_error_here(ps, "expected a return type here")
				return nil
			}

			return_type := _type_expr(ps)
			if return_type == nil {
				_error_here(ps, "expected a return type here")
				return nil
			}

			unit: ast.Declared_Unit = ast.Indeterminate_Unit.Inferred
			end_span := _type_span(return_type)
			if _just_match(ps, Punctuation.Bar) {
				parsed_unit := _compound_unit(ps)
				if parsed_unit == nil {
					_error_here(ps, "expected a unit here")
					return nil
				}
				unit = parsed_unit
				end_span = parsed_unit.span
			}

			result := new(ast.Func_Return)
			result^ = {
				span = common.merge_spans(start_span, end_span),
				name = name,
				type = return_type,
				unit = unit,
			}
			append(&returns, result)

			if !_just_match(ps, Punctuation.Comma) {
				break
			}
		}

		if _just_match(ps, Punctuation.Bang) {
			error_type = _type_expr(ps)
			fallible = true
		}
	}

	// Capability requirements are a TODO in pykerrek as well.
	body := _block(ps)
	_end_of_statement(ps, required = false)
	if body == nil {
		_error_here(ps, "function body required")
		return nil
	}

	function := new(ast.Func_Definition)
	function^ = {
		span = common.merge_spans(func_keyword[0].span, body.span),
		name = _name(func_name),
		params = params,
		returns = returns[:],
		error_type = error_type,
		fallible = fallible,
		body = body,
	}
	return function
}


_param_list :: proc(ps: ^Parser_State) -> ([]^ast.Formal_Parameter, bool) {
	if !_just_match(ps, Punctuation.LParen) {
		return nil, false
	}

	params := make([dynamic]^ast.Formal_Parameter)
	for {
		match, ok := _match(ps, M.Identifier, Punctuation.Colon)
		if !ok {
			break
		}

		param_type := _type_expr(ps, allow_generics = true)
		if param_type == nil {
			return nil, false
		}

		unit: ast.Declared_Unit = ast.Indeterminate_Unit.Inferred
		if _just_match(ps, Punctuation.Bar) {
			unit = _compound_unit(ps)
		}

		default: ast.Expression
		if _just_match(ps, Punctuation.Assign) {
			default = _expr(ps)
		}

		param := new(ast.Formal_Parameter)
		param^ = {
			span = common.merge_spans(match[0].span, _type_span(param_type)),
			name = _name(match[0]),
			type = param_type,
			unit = unit,
			default = default,
		}
		append(&params, param)

		if !_just_match(ps, Punctuation.Comma) {
			break
		}
	}

	if !_just_match(ps, Punctuation.RParen) {
		_error_here(ps, "expected end of parameter list")
		return nil, false
	}
	return params[:], true
}
