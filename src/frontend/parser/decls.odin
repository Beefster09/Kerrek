package parser


import "../../common"
import "../ast"
import "../lexer"

_const_or_var :: proc(ps: ^Parser_State, $MODE: enum {
		Local,
		Global,
	}) -> union {
		^ast.Global_Variable,
		^ast.Global_Constant,
		^ast.Local_Variable,
		^ast.Local_Constant,
	} {
	return nil
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
			for tok in _peek(ps) {
				if tok.what == Punctuation.RCurly {
					rcurly = tok
					break
				}

				// conversion := _unit_conversion(ps)
				conversion: ^ast.Unit_Conversion_Def = nil
				if conversion == nil {
					_attempt_recovery(ps)
					return nil
				}

				append(&conversions, conversion)
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

		} else if _end_of_statement(ps) {
			decl := new(ast.Unit_Decl)
			decl^ = {
				span      = common.merge_spans(m[0].span, unit_type.span),
				name      = _name(m[1]),
				unit_type = unit_type,
			}
			return decl
		} else {
			_error_before_here(ps, "expected '{' or ';' here")
			_attempt_recovery(ps)
			return nil
		}
	}

	_error_here(ps, "invalid form of unit declaration")
	_attempt_recovery(ps)

	return nil
}
