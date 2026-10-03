#+test
package analysis

import "core:mem"
import "core:sync"
import "core:testing"

import "../../common"
import "../ast"
import "../diagnostics"
import "../hir"
import "../resolver"


@(test)
test_invalid_compound_units_fail :: proc(t: ^testing.T) {
	sync.lock(&common.Test_Global_State_Lock)
	defer sync.unlock(&common.Test_Global_State_Lock)
	diagnostics.initialize()
	defer diagnostics.destroy()

	arena: mem.Dynamic_Arena
	mem.dynamic_arena_init(&arena)
	defer mem.dynamic_arena_destroy(&arena)
	context.allocator = mem.dynamic_arena_allocator(&arena)
	context.temp_allocator = context.allocator

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

	scope := resolver.temp_scope(nil)
	base_unit := resolver.new_symbol(&res, resolver.Base_Unit, "meter")
	base_unit.state = .Done
	scope.locals[base_unit.name] = base_unit

	cases := []struct {
		name: string,
		unit: ast.Compound_Unit,
	} {
		{
			name = "unresolved component",
			unit = {components = []ast.Unit_Component {
				{base = {path = []common.Name{{id = "not_a_unit"}}}},
			}},
		},
		{
			name = "combined exponent overflow",
			unit = {components = []ast.Unit_Component {
				{
					base = {path = []common.Name{{id = "meter"}}},
					exponent = ast.Integer_Unit_Exponent{exp = 1023},
				},
				{
					base = {path = []common.Name{{id = "meter"}}},
					exponent = ast.Integer_Unit_Exponent{exp = 1023},
				},
			}},
		},
	}

	for tc, i in cases {
		_, ok := get_canonical_unit(&ts, &cases[i].unit, &scope, ts.allocator)
		testing.expectf(t, !ok, "%s: expected invalid unit to fail", tc.name)
	}
}
