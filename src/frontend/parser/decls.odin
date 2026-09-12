package parser


import "../../common"
import "../../common/exact"
import "../ast"
import "../diagnostics"
import "../lexer"

_const_or_var :: proc(
	ps: ^Parser_State,
	$T: typeid,
) -> ^T where T == ast.Constant_Def ||
	T == ast.Local_Variable ||
	T == ast.Global_Variable {
	CONST :: T == ast.Constant_Def

	keyword, has_keyword := _match(ps, Keyword.Const when CONST else Keyword.Let)
	if !has_keyword {
		return nil
	}

	name_tok, ok := _match1(ps, Identifier)
	if !ok {
		_error_here(ps, "expected variable name here")
		_attempt_recovery(ps)
		return nil
	}

	type_expr: ast.Type_Expression
	if _just_match(ps, Punctuation.Colon) {
		type_expr = _type_expr(ps)
	}

	unit: ast.Declared_Unit = ast.Indeterminate_Unit.Inferred
	if _just_match(ps, Punctuation.Bar) {
		if _just_match(ps, Keyword.Nil) {
			unit = ast.Indeterminate_Unit.No_Unit
		} else if _just_match(ps, Keyword.Placeholder) {
			unit = ast.Indeterminate_Unit.Flexible
		} else {
			parsed_unit := _compound_unit(ps)
			if parsed_unit == nil {
				_error_here(ps, "expected a unit here")
				_attempt_recovery(ps)
				return nil
			}
			unit = parsed_unit
		}
	}

	value: union {
		ast.Expression,
		ast.Unbound_Var,
	}
	if _just_match(ps, Punctuation.Assign) {
		if ellipsis, matched := _match(ps, Punctuation.Ellipsis); matched {
			value = ast.Unbound_Var {
				span = ellipsis[0].span,
			}
		} else {
			value = _expr(ps)
			if value == nil {
				_error_here(ps, "expected an expression here")
				_attempt_recovery(ps)
				return nil
			}
		}
	}

	end_span := name_tok.span
	switch v in value {
	case ast.Expression:
		if v != nil {
			end_span = _expression_span(v)
		}
	case ast.Unbound_Var:
		end_span = v.span
	case nil:
		if type_expr != nil {
			end_span = _type_span(type_expr)
		}
	}
	span := common.merge_spans(keyword[0].span, end_span)

	when CONST {
		expr, has_expr := value.(ast.Expression)
		if !has_expr || expr == nil {
			diagnostics.emit(.Syntax_Error, name_tok.span, "constants must be given a value")
			return nil
		}
		decl := new(ast.Constant_Def)
		decl^ = {
			span = span,
			name = _name(name_tok),
			type = type_expr,
			unit = unit,
			expr = expr,
		}
		return decl
	} else {
		when T == ast.Local_Variable {
			decl := new(ast.Local_Variable)
			decl^ = {
				span = span,
				name = _name(name_tok),
				type = type_expr,
				unit = unit,
				expr = value,
			}
			return decl
		} else {
			if _, unbound := value.(ast.Unbound_Var); unbound {
				diagnostics.emit(.Syntax_Error, end_span, "global variables cannot be unbound")
				return nil
			}
			expr, _ := value.(ast.Expression)
			decl := new(ast.Global_Variable)
			decl^ = {
				span = span,
				name = _name(name_tok),
				type = type_expr,
				unit = unit,
				expr = expr,
			}
			return decl
		}
	}
}

_unit_conversion :: proc(ps: ^Parser_State) -> ^ast.Unit_Conversion_Def {
	direction: ast.Conversion_Direction
	direction_tok: lexer.Token
	if m, ok := _match(ps, Keyword.To); ok {
		direction_tok = m[0]
		direction = .To
	} else if m, ok := _match(ps, Keyword.From); ok {
		direction_tok = m[0]
		direction = .From
	} else {
		_error_here(ps, "expected a unit conversion here")
		return nil
	}

	other, ok := _qualname(ps, required = true)
	if !ok {
		return nil
	}
	end_span := other.span

	if !_just_match(ps, Punctuation.Colon) {
		_error_here(ps, "expected a colon here")
		return nil
	}

	multiplier: ast.Unit_Conversion_Operand = exact.Rat{1, 1}
	divisor: ast.Unit_Conversion_Operand = exact.Rat{1, 1}
	has_multiplier := false
	has_divisor := false

	if _just_match(ps, Punctuation.Star) {
		has_multiplier = true
		if num, ok := _match1(ps, Numeric); ok {
			multiplier = num.what.value
			end_span = num.span
		} else if qualname, ok := _qualname(ps); ok {
			multiplier = qualname
			end_span = qualname.span
		} else {
			_error_here(ps, "expected a number or named constant as the multiplier")
			return nil
		}
	}

	if _just_match(ps, Punctuation.Slash) {
		has_divisor = true
		if num, ok := _match1(ps, Numeric); ok {
			divisor = num.what.value
			end_span = num.span
		} else if qualname, ok := _qualname(ps); ok {
			divisor = qualname
			end_span = qualname.span
		} else {
			_error_here(ps, "expected a number or named constant as the divisor")
			return nil
		}
	}

	if !has_multiplier && !has_divisor {
		_error_here(ps, "a multiplier and/or divisor is required for unit conversions")
	}
	if !_end_of_statement(ps) {
		return nil
	}

	conversion := new(ast.Unit_Conversion_Def)
	conversion^ = {
		span       = common.merge_spans(direction_tok.span, end_span),
		direction  = direction,
		other      = other,
		multiplier = multiplier,
		divisor    = divisor,
	}
	return conversion
}

_unit_decl :: proc(ps: ^Parser_State) -> ast.Top_Level_Declaration {
	// unit type alias
	if m, matched := _match(ps, Keyword.Unit, Keyword.Type, M.Identifier, Punctuation.Assign);
	   matched {
		base := _compound_unit(ps, required = true)
		if base == nil {
			return nil
		}

		if _end_of_statement(ps) {
			decl := new(ast.Unit_Type_Alias_Decl)
			decl^ = {
				span = common.merge_spans(m[0].span, base.span),
				name = _name(m[2]),
				orig = base,
			}
			return decl
		}

		// unit type declaration
	} else if m, matched := _match(ps, Keyword.Unit, Keyword.Type, M.Identifier); matched {
		if _end_of_statement(ps) {
			decl := new(ast.Unit_Type_Decl)
			decl^ = {
				span = common.merge_spans(m[0].span, m[2].span),
				name = _name(m[2]),
			}
			return decl
		}

		// unit alias
	} else if m, matched := _match(ps, Keyword.Unit, M.Identifier, Punctuation.Assign); matched {
		base := _compound_unit(ps, required = true)
		if base != nil && _end_of_statement(ps) {
			decl := new(ast.Unit_Alias_Decl)
			decl^ = {
				span = common.merge_spans(m[0].span, base.span),
				name = _name(m[1]),
				orig = base,
			}
			return decl
		}

		// unit declaration
	} else if m, matched := _match(ps, Keyword.Unit, M.Identifier); matched {
		unit_type: ast.Qualified_Name
		if _just_match(ps, Punctuation.Colon) {
			unit_type, _ = _qualname(ps, required = true) // plain unit
		}

		if _just_match(ps, Punctuation.LCurly) {
			conversions := make([dynamic]^ast.Unit_Conversion_Def)

			rcurly: lexer.Token
			closed := false
			for tok in _peek(ps) {
				if tok.what == Punctuation.RCurly {
					rcurly = tok
					closed = true
					break
				}

				conversion := _unit_conversion(ps)
				if conversion == nil {
					_attempt_recovery(ps)
					return nil
				}

				append(&conversions, conversion)
			}
			if !closed {
				_error_before_here(ps, "unit declaration was not closed")
				return nil
			}
			ps.cur_token += 1

			decl := new(ast.Unit_Decl)
			decl^ = {
				span        = common.merge_spans(m[0].span, rcurly.span),
				name        = _name(m[1]),
				unit_type   = unit_type,
				conversions = conversions[:],
			}
			return decl

		} else if _end_of_statement(ps, required = false) { 	// required = false is a bit weird here; prevents redundant diagnostic
			end_span := m[1].span
			if len(unit_type.path) > 0 {
				end_span = unit_type.span
			}
			decl := new(ast.Unit_Decl)
			decl^ = {
				span      = common.merge_spans(m[0].span, end_span),
				name      = _name(m[1]),
				unit_type = unit_type,
			}
			return decl
		} else {
			_error_before_here(ps, "expected '{{' or ';' here")
			_attempt_recovery(ps)
			return nil
		}
	}

	_error_here(ps, "invalid form of unit declaration")
	_attempt_recovery(ps)

	return nil
}
