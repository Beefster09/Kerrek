package analysis

import "../ast"
import "../diagnostics"
import "../resolver"
import "../units"


Unit_Domain :: enum {
	Value,
	Type,
}


// Canonical unit expansion participates in the declaration graph. Alias
// recursion therefore uses the same Processing/Failed states as type aliases
// and produces one stable dependency-cycle diagnostic per cycle.
get_canonical_unit :: proc(
	ctx: Declaration_Context,
	unit: ^ast.Compound_Unit,
	domain := Unit_Domain.Value,
) -> (
	units.Compound_Unit,
	bool,
) {
	if unit == nil {
		return nil, false
	}

	context.allocator = ctx.translation.output.allocator
	components := make([dynamic]units.Unit_Component, 0, len(unit.components))

	for component in unit.components {
		exponent, exponent_ok := _canonical_exponent(component.exponent)
		if !exponent_ok {
			_emit_unit_exponent_error(component.span)
			return nil, false
		}

		resolved := resolver.resolve_qualname(_resolution_parent(ctx), component.base)
		if resolved == nil {
			return nil, false
		}

		switch domain {
		case .Value:
			#partial switch symbol in resolved {
			case ^resolver.Base_Unit:
				if !process_declaration_signature(ctx, symbol, component.base.span) {
					return nil, false
				}
				if !_add_canonical_component(
					&components,
					units.Unit_Component{symbol.id, exponent},
				) {
					_emit_unit_exponent_error(component.span)
					return nil, false
				}

			case ^resolver.Unit_Alias:
				if !process_declaration_signature(ctx, symbol, component.base.span) {
					return nil, false
				}
				if !_append_alias_components(&components, symbol.canonical, exponent) {
					_emit_unit_exponent_error(component.span)
					return nil, false
				}

			case:
				diagnostics.emit(
					.Invalid_Unit,
					component.span,
					"'%s' does not name a value unit",
					_component_name(component).id,
				)
				return nil, false
			}

		case .Type:
			#partial switch symbol in resolved {
			case ^resolver.Unit_Type:
				if !process_declaration_signature(ctx, symbol, component.base.span) {
					return nil, false
				}
				if !_add_canonical_component(
					&components,
					units.Unit_Component{symbol.id, exponent},
				) {
					_emit_unit_exponent_error(component.span)
					return nil, false
				}

			case ^resolver.Unit_Type_Alias:
				if !process_declaration_signature(ctx, symbol, component.base.span) {
					return nil, false
				}
				if !_append_alias_components(&components, symbol.canonical, exponent) {
					_emit_unit_exponent_error(component.span)
					return nil, false
				}

			case:
				diagnostics.emit(
					.Invalid_Unit,
					component.span,
					"'%s' does not name a unit type",
					_component_name(component).id,
				)
				return nil, false
			}
		}
	}

	shrink(&components)
	return units.build_compound_unit(components[:], unit.is_absolute), true
}


_component_name :: proc(component: ast.Unit_Component) -> ast.Name {
	if len(component.base.path) > 0 {
		return component.base.path[len(component.base.path) - 1]
	}
	return {}
}


_emit_unit_exponent_error :: proc(span: ast.Span) {
	diagnostics.emit(.Invalid_Unit, span, "this unit exponent is outside representable range")
}


_append_alias_components :: proc(
	components: ^[dynamic]units.Unit_Component,
	alias: units.Compound_Unit,
	exponent: units.Small_Rat,
) -> bool {
	if alias == nil {
		return false
	}
	for i in 0 ..< units.num_components(alias) {
		alias_component := units.get_component(alias, i)
		multiplied, ok := units.rat_mul(alias_component.exp, exponent)
		if !ok {
			return false
		}
		alias_component.exp = multiplied
		if !_add_canonical_component(components, alias_component) {
			return false
		}
	}
	return true
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


_add_canonical_component :: proc(
	components: ^[dynamic]units.Unit_Component,
	component: units.Unit_Component,
) -> bool {
	for &existing, i in components^ {
		if existing.unit != component.unit {
			continue
		}

		new_exp, ok := units.rat_add(existing.exp, component.exp)
		if !ok {
			return false
		}
		if units.is_zero(new_exp) {
			unordered_remove(components, i)
		} else {
			existing.exp = new_exp
		}
		return true
	}

	if !units.is_zero(component.exp) {
		append(components, component)
	}
	return true
}
