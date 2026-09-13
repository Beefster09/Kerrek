package analysis

import "../ast"
import "../diagnostics"
import "../resolver"
import "../units"


_Seen_Unit_Alias :: struct {
	alias: ^resolver.Unit_Alias,
	ref:   ast.Qualified_Name,
	prev:  ^_Seen_Unit_Alias,
}

get_canonical_unit :: proc(
	unit: ^ast.Compound_Unit,
	scope: ^resolver.Scope,
	_orig_definition: ^ast.Compound_Unit = nil,
	_seen_aliases: ^_Seen_Unit_Alias = nil,
) -> units.Compound_Unit {
	_has_seen_alias :: proc(seen: ^_Seen_Unit_Alias, alias: ^resolver.Unit_Alias) -> bool {
		for node := seen; node != nil; node = node.prev {
			if node.alias == alias {
				return true
			}
		}
		return false
	}

	if unit == nil {
		return nil
	}

	components := make([dynamic]units.Unit_Component, 0, len(unit.components))
	components_owned := true
	defer if components_owned {
		delete(components)
	}

	for component in unit.components {
		resolved := resolver.resolve_qualname(scope, component.base)
		#partial switch symbol in resolved {
		case ^resolver.Base_Unit:
			exponent, ok := _canonical_exponent(component.exponent)
			if !ok ||
			   !_add_canonical_component(&components, units.Unit_Component{symbol.id, exponent}) {
				diagnostics.emit(
					.Incomplete_Resolution,
					component.span,
					"this unit exponent is outside representable range",
				)
				return nil
			}

		case ^resolver.Unit_Alias:
			if _has_seen_alias(_seen_aliases, symbol) {
				assert(_orig_definition != nil)
				diag := diagnostics.emit(
					.Incomplete_Resolution,
					_orig_definition.span,
					"circular definition of unit aliases detected ...",
				)
				_reference_seen_aliases :: proc(
					diag: ^diagnostics.Diagnostic,
					seen: ^_Seen_Unit_Alias,
				) {
					if seen == nil {
						return
					}
					_reference_seen_aliases(diag, seen.prev)

					name := seen.alias.name
					if len(seen.ref.path) > 0 {
						name = seen.ref.path[len(seen.ref.path) - 1].id
					}
					diagnostics.reference(
						diag,
						seen.ref.span,
						"... '%s' references an alias ...",
						name,
					)
				}
				_reference_seen_aliases(diag, _seen_aliases)
				diagnostics.reference(
					diag,
					_seen_aliases.alias.ast.span,
					"... and ultimately loops back to this definition",
				)
				return nil
			}

			if symbol.canonical == nil {
				seen := _Seen_Unit_Alias {
					alias = symbol,
					ref   = component.base,
					prev  = _seen_aliases,
				}
				symbol.canonical = get_canonical_unit(
					symbol.ast.orig,
					scope,
					_orig_definition = _orig_definition if _orig_definition != nil else unit,
					_seen_aliases = &seen,
				)
				if symbol.canonical == nil {
					return nil
				}
			}

			exponent, ok := _canonical_exponent(component.exponent)
			if !ok {
				diagnostics.emit(
					.Incomplete_Resolution,
					component.span,
					"this unit exponent is outside representable range",
				)
				return nil
			}

			for i in 0 ..< units.num_components(symbol.canonical) {
				alias_component := units.get_component(symbol.canonical, i)
				alias_component.exp, ok = units.rat_mul(alias_component.exp, exponent)
				if !ok || !_add_canonical_component(&components, alias_component) {
					diagnostics.emit(
						.Incomplete_Resolution,
						component.span,
						"this unit exponent is outside representable range",
					)
					return nil
				}
			}

		case:
			diagnostics.emit(
				.Incomplete_Resolution,
				component.span,
				"this component does not resolve to a unit",
			)
			return nil
		}
	}

	shrink(&components)
	canonical := units.build_compound_unit(components[:], unit.is_absolute)
	if _, is_heap := canonical.(units.Heap_Compound_Unit); is_heap {
		components_owned = false
	}
	return canonical
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
