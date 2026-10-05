#+test
package analysis

import "base:runtime"
import "core:mem"
import "core:strings"
import "core:testing"

import "../hir"
import "../resolver"
import "../units"


@(test)
test_translation_state_allocator_ownership :: proc(t: ^testing.T) {
	res: resolver.Resolver
	resolver.init(&res)
	defer resolver.destroy(&res)
	pkg: resolver.Package
	tu: hir.Module
	hir.init(&tu)
	defer hir.destroy(&tu)
	ts: Translation_State
	init_state(&ts, &res, &pkg, &tu)
	defer destroy_state(&ts)

	scope := resolver.new_scope(nil, ts.allocator)
	cases := []struct {
		name:     string,
		actual:   runtime.Allocator,
		expected: runtime.Allocator,
	} {
		{"HIR types", ts.hir_items.types.allocator, tu.allocator},
		{"HIR funcs", ts.hir_items.funcs.allocator, tu.allocator},
		{"HIR variables", ts.hir_items.variables.allocator, tu.allocator},
		{"HIR units", ts.hir_items.units.allocator, tu.allocator},
		{"HIR capabilities", ts.hir_items.capabilities.allocator, tu.allocator},
		{"HIR annotations", ts.hir_items.annotations.allocator, tu.allocator},
		{"pending bodies", ts.pending_bodies.allocator, ts.allocator},
		{"unit conversion edges", ts.unit_conversions.edges.allocator, ts.allocator},
		{"persistent scope", scope.locals.allocator, ts.allocator},
	}
	for tc in cases {
		testing.expectf(t, tc.actual == tc.expected, "%s has the wrong allocator", tc.name)
	}
}


@(test)
test_output_values_copy_owned_data :: proc(t: ^testing.T) {
	source_arena: mem.Dynamic_Arena
	mem.dynamic_arena_init(&source_arena)
	defer mem.dynamic_arena_destroy(&source_arena)
	source_allocator := mem.dynamic_arena_allocator(&source_arena)

	tu: hir.Module
	hir.init(&tu)
	defer hir.destroy(&tu)
	ts := Translation_State {
		output = &tu,
	}

	source_string := strings.clone("temporary string", source_allocator)
	value := Comptime_Value {
		value = source_string,
		type  = Comptime_Type(hir.Type(hir.Primitive_Type.String)),
		unit  = hir.Indeterminate_Unit.No_Unit,
	}
	built, ok := materialize_value(&ts, value, {}, hir.Type(hir.Primitive_Type.String))
	testing.expect(t, ok)
	if !ok {
		return
	}
	constant := built.(^hir.Const_Expr)
	output_string := constant.value.(string)
	testing.expect(t, output_string == source_string)
	testing.expect(t, raw_data(output_string) != raw_data(source_string))

	components := make([]units.Component, units.MAX_INLINE_UNITS + 1, source_allocator)
	for &component, i in components {
		component = {
			unit = hir.Symbol_ID(i + 1),
			exp  = units.RAT_ONE,
		}
	}
	source_unit := hir.Realized_Unit(
		units.Compound_Unit(units.Heap_Compound_Unit{components = components}),
	)
	output_unit := source_unit
	output_compound := output_unit.(units.Compound_Unit)
	output_heap := output_compound.(units.Heap_Compound_Unit)
	testing.expect(t, len(output_heap.components) == len(components))
	testing.expect(t, raw_data(output_heap.components) != raw_data(components))
	for component, i in output_heap.components {
		testing.expect(t, component == components[i])
	}
}
