package analysis

import "../../common/exact"
import "../ast"
import "../diagnostics"
import "../hir"
import "../resolver"
import "../units"


build_unit :: proc(
	ts: ^Translation_State,
	unit: ast.Declared_Unit,
	scope: resolver.Scope,
) -> (
	hir.Realized_Unit,
	bool,
) {
	return nil, false
}

get_canonical_unit :: proc(
	ts: ^Translation_State,
	unit: ^ast.Compound_Unit,
	scope: resolver.Scope,
) -> (
	units.Compound_Unit,
	bool,
) {
	if unit == nil {
		return nil, false
	}

	components := make([dynamic]units.Unit_Component, 0, len(unit.components))

	for component in unit.components {
		// TODO
	}

	shrink(&components)
	return units.build_compound_unit(components[:]), true
}


_emit_unit_exponent_error :: proc(span: ast.Span) {
	diagnostics.emit(.Invalid_Unit, span, "this unit exponent is outside representable range")
}


_canonical_exponent :: proc(exponent: ast.Unit_Exponent) -> (units.Small_Rat, bool) {
	switch exp in exponent {
	case ast.Integer_Unit_Exponent:
		return units.rat(exp.exp, 1)
	case ast.Rational_Unit_Exponent:
		return units.rat(exp.num, exp.den)
	case nil:
		return units.RAT_ONE, true
	}
	return {}, false
}

_get_conversion_operand :: proc(
	ts: ^Translation_State,
	scope: resolver.Scope,
	op: ast.Unit_Conversion_Operand,
) -> (
	exact.Rat,
	bool,
) {
	switch op in op {
	case ast.Qualified_Name:
		if resolved, ok := resolve(ts, scope, op).(^resolver.Constant); ok {
			if resolved.state == .Failed {
				return {}, false
			}
			// TODO: check that the value is an untyped and unitless constant
			return resolved.value.value.(exact.Rat)
		} else {
			diagnostics.emit(
				.Invalid_Type,
				op.span,
				"this needs to be a number or untyped numeric constant",
			)
		}
	case exact.Rat:
		return op, true
	}

	return {}, false
}
