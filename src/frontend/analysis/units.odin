package analysis

import "base:runtime"
import "core:slice"

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
		return get_canonical_unit(ts, unit, scope, ts.output.allocator)
	}

	return nil, false
}

get_canonical_unit :: proc(
	ts: ^Translation_State,
	unit: ^ast.Compound_Unit,
	scope: resolver.Scope,
	allocator: runtime.Allocator,
) -> (
	result: units.Compound_Unit,
	all_ok: bool,
) {
	if unit == nil {
		return nil, false
	}

	b: units.Builder
	units.builder_init(&b, context.temp_allocator)
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
				if units.builder_add(&b, unit.canonical, exp) != .OK {
					all_ok = false
					diagnostics.emit(
						.Unit_Exponent_Not_Representable,
						exp_span,
						"this exponent is not representable",
					)
				}
			} else {
				all_ok = false
				diagnostics.emit(
					.Unit_Exponent_Not_Representable,
					exp_span,
					"this exponent is not representable",
				)
			}
		case ^resolver.Base_Unit:
			if exp_span, exp, ok := _canonical_exponent(component.exponent); ok {
				if units.builder_add(&b, unit.id, exp) != .OK {
					all_ok = false
					diagnostics.emit(
						.Unit_Exponent_Not_Representable,
						exp_span,
						"this exponent is not representable",
					)
				}
			} else {
				all_ok = false
				diagnostics.emit(
					.Unit_Exponent_Not_Representable,
					exp_span,
					"this exponent is not representable",
				)
			}
		case:
			all_ok = false
			diagnostics.emit(
				.Invalid_Unit_Name,
				component.base.span,
				"'%s' does not name a unit",
				component.base,
			)
		}
	}

	return units.to_compound_unit(&b, allocator), all_ok
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
				.Invalid_Unit_Conversion_Factor,
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

_eval_binop_unit :: proc(
	ts: ^Translation_State,
	binop: ^ast.Binop_Expr,
	lhs: Eval_Result,
	lunit: hir.Realized_Unit,
	rhs: Eval_Result,
	runit: hir.Realized_Unit,
) -> (
	result_unit: hir.Realized_Unit,
	result_lhs: Eval_Result,
	result_rhs: Eval_Result,
	all_ok: bool,
) {
	_maybe_convert_rhs :: proc(
		ts: ^Translation_State,
		binop: ^ast.Binop_Expr,
		rhs: Eval_Result,
		rmult: exact.Rat,
	) -> (
		Eval_Result,
		bool,
	) {
		// FIXME: this function tends to materialize too early,
		// and prefers coercing the right unit to match the left even when context would say otherwise
		if exact.is_one(rmult) || rhs == nil {
			return rhs, true
		}

		value := rhs
		if comptime, ok := value.(Comptime_Value); ok {
			materialized, mat_ok := materialize_value(ts, comptime, ast.expression_span(binop.rhs))
			if !mat_ok {
				return nil, false
			}
			value = materialized
		}

		type, unit, has_value := _type_and_unit(value)
		if !has_value {
			return nil, false
		}
		realized_type, rt_ok := type.(hir.Type)
		if !rt_ok {
			return nil, false
		}

		expr := new(hir.Unit_Conversion_Expr, ts.output.allocator)
		expr^ = {
			span   = ast.expression_span(binop.rhs),
			expr   = value.(hir.Expression),
			type   = realized_type,
			unit   = unit,
			factor = exact.clone(rmult, ts.output.allocator),
		}
		return hir.Expression(expr), true
	}

	if lhs == nil || rhs == nil {
		return
	}

	if _is_no_unit(lunit) && _is_no_unit(runit) {
		return hir.Indeterminate_Unit.No_Unit, lhs, rhs, true
	}

	switch binop.op {
	case .And, .Or:
		return hir.Indeterminate_Unit.No_Unit, lhs, rhs, true

	case .Equal, .Not_Equal, .Less, .Greater, .Less_Equal, .Greater_Equal, .Is, .Is_Not:
		_, rmult, coerced := _coerce_units(lunit, runit)
		if !coerced {
			diagnostics.emit(
				.Unit_Mismatch,
				binop.span,
				"units (%v) and (%v) do not match and do not have any known conversions",
				lunit,
				runit,
			)
		}
		converted_rhs, ok := _maybe_convert_rhs(ts, binop, rhs, rmult)
		return hir.Indeterminate_Unit.No_Unit, lhs, converted_rhs, ok

	case .Add, .Subtract, .Remainder, .Modulo:
		coerced_unit, rmult, coerced := _coerce_units(lunit, runit)
		if !coerced {
			diagnostics.emit(
				.Unit_Mismatch,
				binop.span,
				"units (%v) and (%v) do not match and do not have any known conversions",
				lunit,
				runit,
			)
			return
		}
		converted_rhs, ok := _maybe_convert_rhs(ts, binop, rhs, rmult)
		return coerced_unit, lhs, converted_rhs, ok

	case .Multiply:
		lcanonical, l_has_unit := lunit.(units.Compound_Unit)
		rcanonical, r_has_unit := runit.(units.Compound_Unit)
		if l_has_unit && r_has_unit {
			unit, err := units.combine_units(
				lcanonical,
				units.RAT_ONE,
				rcanonical,
				units.RAT_ONE,
				ts.allocator,
			)
			if err != .OK {
				return
			}
			return unit, lhs, rhs, true
		} else if l_has_unit && _unit_is_flexible(runit) {
			return lunit, lhs, rhs, true
		} else if r_has_unit && _unit_is_flexible(lunit) {
			return runit, lhs, rhs, true
		} else if _unit_is_flexible(lunit) && _unit_is_flexible(runit) {
			return hir.Indeterminate_Unit.Flexible, lhs, rhs, true
		} else if (_is_no_unit(lunit) || _unit_is_flexible(lunit)) &&
		   (_is_no_unit(runit) || _unit_is_flexible(runit)) {
			return hir.Indeterminate_Unit.No_Unit, lhs, rhs, true
		}
		diagnostics.emit(
			.Invalid_Unit_Operation,
			binop.span,
			"you cannot multiply a unitless value with a value with units (|%v| %s |%v|)",
			lunit,
			common.BINARY_OP_STRINGS[binop.op],
			runit,
		)
		return

	case .True_Divide, .Floor_Divide:
		lcanonical, l_has_unit := lunit.(units.Compound_Unit)
		rcanonical, r_has_unit := runit.(units.Compound_Unit)
		if l_has_unit && r_has_unit {
			unit, err := units.combine_units(
				lcanonical,
				units.RAT_ONE,
				rcanonical,
				units.Small_Rat{n = -1},
				ts.allocator,
			)
			if err != .OK {
				return
			}
			return unit, lhs, rhs, true
		} else if l_has_unit && _unit_is_flexible(runit) {
			return lunit, lhs, rhs, true
		} else if r_has_unit && _unit_is_flexible(lunit) {
			unit, err := units.combine_units(
				rcanonical,
				units.Small_Rat{n = -1},
				units.Inline_Compound_Unit{},
				units.RAT_ONE,
				ts.allocator,
			)
			if err != .OK {
				return
			}
			return unit, lhs, rhs, true
		} else if _unit_is_flexible(lunit) && _unit_is_flexible(runit) {
			return hir.Indeterminate_Unit.Flexible, lhs, rhs, true
		} else if (_is_no_unit(lunit) || _unit_is_flexible(lunit)) &&
		   (_is_no_unit(runit) || _unit_is_flexible(runit)) {
			return hir.Indeterminate_Unit.No_Unit, lhs, rhs, true
		}
		diagnostics.emit(
			.Invalid_Unit_Operation,
			binop.span,
			"you cannot divide a unitless value by a value with units or vice-versa (|%v| %s |%v|)",
			lunit,
			common.BINARY_OP_STRINGS[binop.op],
			runit,
		)
		return

	case .Power:
		if canonical, is_canonical := lunit.(units.Compound_Unit);
		   is_canonical && units.num_components(canonical) > 0 {
			if exponent, known := rhs.(Comptime_Value); known {
				if exponent_value, numeric := exponent.value.(exact.Rat); numeric {
					rhs_is_unitless := _is_no_unit(runit) || _unit_is_flexible(runit)
					if rhs_unit, rhs_canonical := runit.(units.Compound_Unit); rhs_canonical {
						rhs_is_unitless = units.num_components(rhs_unit) == 0
					}
					if rhs_is_unitless {
						if exponent_units, representable := units.rat_from_exact(exponent_value);
						   representable && exponent_units.d == 0 {
							unit, err := units.combine_units(
								canonical,
								exponent_units,
								units.Inline_Compound_Unit{},
								units.RAT_ONE,
								ts.allocator,
							)
							if err == .OK {
								return unit, lhs, rhs, true
							}
						} else {
							diagnostics.emit(
								.Invalid_Unit_Exponent,
								ast.expression_span(binop.rhs),
								"fractional exponents are not currently supported for values with units",
							)
							return
						}
					}
				}
			}
			diagnostics.emit(
				.Invalid_Unit_Exponent,
				ast.expression_span(binop.rhs),
				"exponents of unit expressions must be statically known unitless integers",
			)
			return
		}

		if rhs_unit, rhs_canonical := runit.(units.Compound_Unit);
		   rhs_canonical && units.num_components(rhs_unit) > 0 {
			diagnostics.emit(
				.Invalid_Unit_Exponent,
				ast.expression_span(binop.rhs),
				"exponents must be unitless or ratios",
			)
			return
		}
		return lunit, lhs, rhs, true
	}

	unreachable()
}

_coerce_units :: proc(
	lhs: hir.Realized_Unit,
	rhs: hir.Realized_Unit,
) -> (
	hir.Realized_Unit,
	exact.Rat,
	bool,
) {
	if _unit_is_flexible(lhs) {
		return rhs, exact.RAT_ONE, true
	} else if _unit_is_flexible(rhs) {
		return lhs, exact.RAT_ONE, true
	}

	if _units_equal(lhs, rhs) {
		return lhs, exact.RAT_ONE, true
	}

	// TODO: find conversion from one to the other

	return nil, {}, false
}
