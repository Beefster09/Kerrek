package parser

import "../../common"
import "../ast"
import "../diagnostics"

_compound_unit :: proc(ps: ^Parser_State, required := false) -> ^ast.Compound_Unit {
	leading_hash, is_absolute := _match(ps, Punctuation.Hash)

	if tok, ok := _peek(ps); ok {
		if tnum, ok := tok.what.(Numeric); ok && tnum.raw == "1" {
			ps.cur_token += 1
			unit := new(ast.Compound_Unit)
			unit^ = {
				span        = common.merge_spans(tok.span, leading_hash[0].span) if is_absolute else tok.span,
				components  = nil,
				is_absolute = is_absolute,
			}
			return unit
		}
	}

	components := make([dynamic]ast.Unit_Component)
	in_denominator := false
	for component in _qualname(ps) {
		exponent: ast.Unit_Exponent = nil
		comp_start := component.span.start
		comp_end := component.span.end

		if m, ok := _match(ps, Punctuation.Caret, M.Numeric); ok {
			exp := m[1].what.(Numeric)

			if exp.format == .DecimalInteger {
				if exp128, ok := exp.value.numerator.(i128);
				   ok && -128 <= exp128 && exp128 <= 127 {
					exponent = ast.Integer_Unit_Exponent{m[1].span, int(exp128)}
				} else {
					diagnostics.emit(
						.Syntax_Error,
						m[1].span,
						"exponent is outside supported range",
					)
				}
				comp_end = m[1].span.end
			} else {
				diagnostics.emit(
					.Syntax_Error,
					m[1].span,
					"a decimal integer literal is required here",
				)
			}
		} else if m, ok := _match(
			ps,
			Punctuation.Caret,
			Punctuation.LParen,
			M.Numeric,
			Punctuation.Slash,
			M.Numeric,
			Punctuation.RParen,
		); ok {
			num := m[2].what.(Numeric)
			den := m[4].what.(Numeric)

			if num.format == .DecimalInteger && den.format == .DecimalInteger {
				small_num: int
				small_den: int
				in_range := true

				if num128, ok := num.value.numerator.(i128);
				   ok && -1 << 63 <= num128 && num128 <= 1 << 63 - 1 {
					small_num = int(num128)
				} else {
					in_range = false
					diagnostics.emit(
						.Syntax_Error,
						m[2].span,
						"exponent numerator is outside supported range",
					)
				}

				if den128, ok := den.value.numerator.(i128);
				   ok && 1 < den128 && den128 <= 1 << 63 - 1 {
					small_den = int(den128)
				} else {
					in_range = false
					diagnostics.emit(
						.Syntax_Error,
						m[4].span,
						"exponent denominator is outside supported range",
					)
				}

				if in_range {
					exponent = ast.Rational_Unit_Exponent {
						common.merge_spans(m[2].span, m[4].span),
						small_num,
						small_den,
					}
				}

				comp_end = m[5].span.end
			} else {
				diagnostics.emit(
					.Syntax_Error,
					common.merge_spans(m[2].span, m[4].span),
					"both the numerator and denominator here must be decimal integers",
				)
			}
		}

		if in_denominator {
			switch &exp in exponent {
			case ast.Integer_Unit_Exponent:
				exp.exp = -exp.exp
			case ast.Rational_Unit_Exponent:
				exp.num = -exp.num
			case nil:
				exponent = ast.Integer_Unit_Exponent {
					common.collapse_span_to_end(component.span),
					-1,
				}
			}
		}

		append(
			&components,
			ast.Unit_Component {
				span = {file = component.span.file, start = comp_start, end = comp_end},
				base = component,
				exponent = exponent,
			},
		)

		if _just_match(ps, Keyword.Per) {
			in_denominator = true
		}
	}

	if len(components) == 0 {
		if required {
			d := _error_here(ps, "expected a unit here")
			diagnostics.suggest(d, "did you mean the dimensionless 'unit' spelled as: 1 ?")
		}
		return nil
	}

	unit := new(ast.Compound_Unit)
	unit^ = {
		span        = common.merge_spans(
			leading_hash[0].span if is_absolute else components[0].span,
			components[len(components) - 1].span,
		),
		components  = components[:],
		is_absolute = is_absolute,
	}
	return unit
}
