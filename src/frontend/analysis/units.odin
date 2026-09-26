package analysis

import "../../common"
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
	infer_as: hir.Realized_Unit = hir.Indeterminate_Unit.Flexible,
) -> (
	hir.Realized_Unit,
	bool,
) {
	switch unit in unit {
	case ^ast.No_Unit:
		return hir.Indeterminate_Unit.No_Unit, true
	case ^ast.Flexible_Unit:
		return hir.Indeterminate_Unit.Flexible, true
	case ^ast.Inferred_Unit:
		return infer_as, true
	case ^ast.Compound_Unit:
		return get_canonical_unit(ts, unit, scope)
	}

	return nil, false
}

get_canonical_unit :: proc(
	ts: ^Translation_State,
	unit: ^ast.Compound_Unit,
	scope: resolver.Scope,
) -> (
	result: units.Compound_Unit,
	all_ok: bool,
) {
	if unit == nil {
		return nil, false
	}

	b: units.Builder
	units.builder_init(&b, ts.allocator)
	defer units.builder_destroy(&b)

	all_ok = true

	process_component: for component in unit.components {
		unit := resolve(ts, scope, component.base)
		#partial switch unit in unit {
		case ^resolver.Unit_Alias:
			if unit.state != .Done {
				// cyclical dependency; should have already emitted an error
				all_ok = false
				continue process_component
			}

			if exp_span, exp, ok := _canonical_exponent(component.exponent); ok {
				units.builder_add(&b, unit.canonical, exp)
			} else {
				all_ok = false
				diagnostics.emit(.TBD, exp_span, "this exponent is not representable")
			}
		case ^resolver.Base_Unit:
			if exp_span, exp, ok := _canonical_exponent(component.exponent); ok {
				units.builder_add(&b, unit.id, exp)
			} else {
				all_ok = false
				diagnostics.emit(.TBD, exp_span, "this exponent is not representable")
			}
		case:
			all_ok = false
			diagnostics.emit(
				.TBD,
				component.base.span,
				"'%s' does not name a unit",
				component.base,
			)
		}
	}

	return units.to_compound_unit(&b, ts.output.allocator), true
}

_canonical_exponent :: proc(exponent: ast.Unit_Exponent) -> (common.Span, units.Small_Rat, bool) {
	switch exp in exponent {
	case ast.Integer_Unit_Exponent:
		return exp.span, units.rat(exp.exp, 1)
	case ast.Rational_Unit_Exponent:
		return exp.span, units.rat(exp.num, exp.den)
	case nil:
		return {}, units.RAT_ONE, true
	}
	return {}, {}, false
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

_units_equal :: proc(a, b: hir.Realized_Unit) -> bool {
	if a_iu, a_ok := a.(hir.Indeterminate_Unit); a_ok {
		if b_iu, b_ok := b.(hir.Indeterminate_Unit); b_ok {
			return a_iu == b_iu
		}
	}

	if lunit, a_ok := a.(units.Compound_Unit); a_ok {
		if runit, b_ok := b.(units.Compound_Unit);
		   b_ok && units.compound_units_equal(lunit, runit) {
			return true
		}
	}

	return false
}

_unit_is_flexible :: proc(u: hir.Realized_Unit) -> bool {
	if iu, ok := u.(hir.Indeterminate_Unit); ok {
		return iu == .Flexible
	}
	return false
}

_is_no_unit :: proc(u: hir.Realized_Unit) -> bool {
	if iu, ok := u.(hir.Indeterminate_Unit); ok {
		return iu == .No_Unit
	}
	return false
}
