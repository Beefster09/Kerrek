#+test
package analysis

import "core:testing"

import "../../common"
import "../ast"
import "../diagnostics"
import "../hir"
import "../resolver"


_test_name :: proc(id: string, offset: u32) -> common.Name {
	return {
		id = common.Identifier(id),
		span = {
			file = 1,
			start = {offset = offset, line = 1, col = offset + 1},
			end = {offset = offset + u32(len(id)), line = 1, col = offset + u32(len(id)) + 1},
		},
	}
}

@(test)
test_declarations_have_stable_hir_identity :: proc(t: ^testing.T) {
	output: hir.Translation_Unit
	hir.init(&output)
	defer hir.destroy(&output)

	res: resolver.Resolver
	resolver.init(&res)
	defer resolver.destroy(&res)

	pkg: resolver.Package
	state: Translation_State
	init_state(&state, &res, &pkg, &output)

	name := _test_name("work", 0)
	func_ast := ast.Func_Definition{span = name.span, name = name}
	function := resolver.Function {
		header = {id = 10_000, name = name.id},
		ast = &func_ast,
	}
	file := resolver.File {
		defined_symbols = make([dynamic]resolver.Partial_Symbol, res.allocator),
		own_package = &pkg,
	}
	append(&file.defined_symbols, &function)
	pkg.files = make([]^resolver.File, 1, res.allocator)
	pkg.files[0] = &file
	res.packages["test"] = &pkg
	append(&res.loaded_packages, &pkg)

	testing.expect(t, prepare_declaration_graph(&state))
	first := function.hir
	testing.expect(t, first != nil)
	testing.expect(t, len(state.hir_items.funcs) == 1)
	testing.expect(t, state.symbols_by_id[function.id] != nil)

	testing.expect(t, prepare_declaration(&state, &function))
	testing.expect(t, function.hir == first)
	testing.expect(t, len(state.hir_items.funcs) == 1)

	commit_hir_items(&state)
	testing.expect(t, len(output.funcs) == 1)
	testing.expect(t, output.funcs[0] == first)
	destroy_state(&state)

	// Scratch teardown must not invalidate HIR declarations.
	testing.expect(t, first.id == function.id)
	testing.expect(t, first.name.id == name.id)
}

@(test)
test_declaration_state_detects_cycles_and_suppresses_retries :: proc(t: ^testing.T) {
	diagnostics.initialize()
	defer diagnostics.destroy()

	output: hir.Translation_Unit
	hir.init(&output)
	defer hir.destroy(&output)

	res: resolver.Resolver
	resolver.init(&res)
	defer resolver.destroy(&res)

	pkg: resolver.Package
	state: Translation_State
	init_state(&state, &res, &pkg, &output)
	defer destroy_state(&state)

	a_name := _test_name("a", 0)
	b_name := _test_name("b", 2)
	a_ast := ast.Type_Alias{span = a_name.span, name = a_name}
	b_ast := ast.Type_Alias{span = b_name.span, name = b_name}
	a := resolver.Type_Alias{header = {id = 10_000, name = a_name.id}, ast = &a_ast}
	b := resolver.Type_Alias{header = {id = 10_001, name = b_name.id}, ast = &b_ast}
	ctx := Declaration_Context{translation = &state}

	testing.expect(t, begin_declaration(ctx, &a) == .Ready)
	testing.expect(t, begin_declaration(ctx, &b) == .Ready)
	testing.expect(t, begin_declaration(ctx, &a, b_name.span) == .Cycle)
	testing.expect(t, a.state == .Failed)
	testing.expect(t, b.state == .Failed)

	testing.expect(t, !finish_declaration(&state, &b, false))
	testing.expect(t, b.state == .Failed)
	testing.expect(t, !finish_declaration(&state, &a, true))
	testing.expect(t, a.state == .Failed)
	testing.expect(t, begin_declaration(ctx, &a) == .Failed)
	testing.expect(t, len(state.processing_stack) == 0)
}

@(test)
test_completed_declaration_is_not_processed_twice :: proc(t: ^testing.T) {
	output: hir.Translation_Unit
	hir.init(&output)
	defer hir.destroy(&output)

	res: resolver.Resolver
	resolver.init(&res)
	defer resolver.destroy(&res)

	pkg: resolver.Package
	state: Translation_State
	init_state(&state, &res, &pkg, &output)
	defer destroy_state(&state)

	name := _test_name("ready", 0)
	unit_ast := ast.Unit_Type_Decl{span = name.span, name = name}
	unit := resolver.Unit_Type{header = {id = 10_000, name = name.id}, ast = &unit_ast}
	ctx := Declaration_Context{translation = &state}

	testing.expect(t, begin_declaration(ctx, &unit) == .Ready)
	testing.expect(t, finish_declaration(&state, &unit, true))
	testing.expect(t, unit.state == .Done)
	testing.expect(t, begin_declaration(ctx, &unit) == .Already_Done)
	testing.expect(t, len(state.processing_stack) == 0)
}
