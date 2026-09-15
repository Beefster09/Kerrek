#+test
package analysis

import "core:testing"

import "../../common"
import "../ast"
import "../diagnostics"
import "../hir"
import "../resolver"
import "../units"


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

	// Unit aliases use the same declaration graph rather than maintaining a
	// second, subtly different cycle detector.
	file := resolver.File {
		defined_symbols = make([dynamic]resolver.Partial_Symbol, res.allocator),
		own_package = &pkg,
	}
	pkg.defined_symbols = make(map[common.Identifier]resolver.Partial_Symbol, res.allocator)
	file_scope := resolver.Scope {
		locals = make(map[common.Identifier]resolver.Partial_Symbol, res.allocator),
		parent = &file,
	}

	woman_name := _test_name("woman", 10)
	woman_ref := _test_name("woman", 20)
	woman_path := [?]ast.Name{woman_ref}
	woman_components := [?]ast.Unit_Component {{
		span = woman_ref.span,
		base = {span = woman_ref.span, path = woman_path[:]},
	}}
	woman_unit := ast.Compound_Unit {
		span = woman_ref.span,
		components = woman_components[:],
	}
	woman_ast := ast.Unit_Alias_Decl {
		span = common.merge_spans(woman_name.span, woman_ref.span),
		name = woman_name,
		orig = &woman_unit,
	}
	woman := resolver.Unit_Alias {
		header = {id = 10_010, name = woman_name.id, defined_in = &file},
		ast = &woman_ast,
	}
	pkg.defined_symbols[woman.name] = &woman

	unit_ctx := Declaration_Context {
		translation = &state,
		file = &file,
		scope = &file_scope,
	}
	testing.expect(t, !process_declaration_signature(unit_ctx, &woman))
	testing.expect(t, woman.state == .Failed)
	testing.expect(t, len(state.processing_stack) == 0)

	dog_name := _test_name("dog", 30)
	canine_name := _test_name("canine", 40)
	dog_ref_path := [?]ast.Name{_test_name("canine", 50)}
	canine_ref_path := [?]ast.Name{_test_name("dog", 60)}
	dog_components := [?]ast.Unit_Component {{
		span = dog_ref_path[0].span,
		base = {span = dog_ref_path[0].span, path = dog_ref_path[:]},
	}}
	canine_components := [?]ast.Unit_Component {{
		span = canine_ref_path[0].span,
		base = {span = canine_ref_path[0].span, path = canine_ref_path[:]},
	}}
	dog_unit := ast.Compound_Unit{span = dog_ref_path[0].span, components = dog_components[:]}
	canine_unit := ast.Compound_Unit {
		span = canine_ref_path[0].span,
		components = canine_components[:],
	}
	dog_ast := ast.Unit_Alias_Decl{name = dog_name, orig = &dog_unit}
	canine_ast := ast.Unit_Alias_Decl{name = canine_name, orig = &canine_unit}
	dog := resolver.Unit_Alias {
		header = {id = 10_011, name = dog_name.id, defined_in = &file},
		ast = &dog_ast,
	}
	canine := resolver.Unit_Alias {
		header = {id = 10_012, name = canine_name.id, defined_in = &file},
		ast = &canine_ast,
	}
	pkg.defined_symbols[dog.name] = &dog
	pkg.defined_symbols[canine.name] = &canine

	testing.expect(t, !process_declaration_signature(unit_ctx, &dog))
	testing.expect(t, dog.state == .Failed)
	testing.expect(t, canine.state == .Failed)
	testing.expect(t, len(state.processing_stack) == 0)

	delete(file_scope.locals)
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


@(test)
test_unit_alias_signature_is_canonicalized :: proc(t: ^testing.T) {
	output: hir.Translation_Unit
	hir.init(&output)
	defer hir.destroy(&output)

	res: resolver.Resolver
	resolver.init(&res)
	defer resolver.destroy(&res)

	pkg := resolver.Package {
		defined_symbols = make(map[common.Identifier]resolver.Partial_Symbol, res.allocator),
	}
	file := resolver.File {
		defined_symbols = make([dynamic]resolver.Partial_Symbol, res.allocator),
		own_package = &pkg,
	}

	state: Translation_State
	init_state(&state, &res, &pkg, &output)
	defer destroy_state(&state)

	meter_name := _test_name("meter", 0)
	meter_ast := ast.Unit_Decl{name = meter_name}
	meter := resolver.Base_Unit {
		header = {id = 10_000, name = meter_name.id, defined_in = &file},
		ast = &meter_ast,
	}
	pkg.defined_symbols[meter.name] = &meter

	m_name := _test_name("m", 10)
	meter_ref := _test_name("meter", 14)
	meter_path := [?]ast.Name{meter_ref}
	components := [?]ast.Unit_Component {{
		span = meter_ref.span,
		base = {span = meter_ref.span, path = meter_path[:]},
	}}
	alias_unit := ast.Compound_Unit{span = meter_ref.span, components = components[:]}
	alias_ast := ast.Unit_Alias_Decl{name = m_name, orig = &alias_unit}
	alias := resolver.Unit_Alias {
		header = {id = 10_001, name = m_name.id, defined_in = &file},
		ast = &alias_ast,
	}
	pkg.defined_symbols[alias.name] = &alias

	ctx := Declaration_Context{translation = &state, file = &file}
	testing.expect(t, process_declaration_signature(ctx, &alias))
	testing.expect(t, alias.state == .Done)
	testing.expect(t, meter.state == .Done)
	testing.expect(t, units.num_components(alias.canonical) == 1)
	component := units.get_component(alias.canonical, 0)
	testing.expect(t, component.unit == meter.id)
	testing.expect(t, units.rat_eq(component.exp, units.RAT_ONE))
}


@(test)
test_function_signature_builds_parameters_without_body_scopes :: proc(t: ^testing.T) {
	output: hir.Translation_Unit
	hir.init(&output)
	defer hir.destroy(&output)

	res: resolver.Resolver
	resolver.init(&res)
	defer resolver.destroy(&res)
	res.next_symbol_id = 10_002

	pkg := resolver.Package {
		defined_symbols = make(map[common.Identifier]resolver.Partial_Symbol, res.allocator),
	}
	file := resolver.File {
		defined_symbols = make([dynamic]resolver.Partial_Symbol, res.allocator),
		own_package = &pkg,
	}
	scope := resolver.Scope {
		locals = make(map[common.Identifier]resolver.Partial_Symbol, res.allocator),
		parent = &file,
	}
	defer delete(scope.locals)

	state: Translation_State
	init_state(&state, &res, &pkg, &output)
	defer destroy_state(&state)

	type_name := _test_name("Number", 0)
	type_ast := ast.Type_Alias{name = type_name}
	type_symbol := resolver.Type_Alias {
		header = {
			id = 10_000,
			name = type_name.id,
			state = .Done,
			defined_in = &file,
		},
		ast = &type_ast,
		hir = hir.Primitive_Type.Int64,
	}
	pkg.defined_symbols[type_symbol.name] = &type_symbol

	type_ref_name := _test_name("Number", 20)
	type_path := [?]ast.Name{type_ref_name}
	type_ref := ast.Simple_Type {
		span = type_ref_name.span,
		type = {span = type_ref_name.span, path = type_path[:]},
	}
	param_name := _test_name("value", 30)
	param_ast := ast.Formal_Parameter {
		span = common.merge_spans(param_name.span, type_ref.span),
		name = param_name,
		type = &type_ref,
		unit = ast.Indeterminate_Unit.No_Unit,
	}
	return_name := _test_name("result", 40)
	return_ast := ast.Func_Return {
		span = type_ref.span,
		name = return_name,
		type = &type_ref,
		unit = ast.Indeterminate_Unit.No_Unit,
	}
	params := [?]^ast.Formal_Parameter{&param_ast}
	returns := [?]^ast.Func_Return{&return_ast}
	function_name := _test_name("work", 50)
	function_ast := ast.Func_Definition {
		span = function_name.span,
		name = function_name,
		params = params[:],
		returns = returns[:],
	}
	function := resolver.Function {
		header = {id = 10_001, name = function_name.id, defined_in = &file},
		ast = &function_ast,
	}
	pkg.defined_symbols[function.name] = &function

	ctx := Declaration_Context{translation = &state, file = &file, scope = &scope}
	testing.expect(t, process_declaration_signature(ctx, &function))
	testing.expect(t, function.state == .Done)
	testing.expect(t, len(function.hir.params) == 1)
	testing.expect(t, function.hir.params[0].type == hir.Primitive_Type.Int64)
	testing.expect(t, function.hir.params[0].name.id == param_name.id)
	testing.expect(t, len(function.hir.returns) == 1)
	testing.expect(t, function.hir.returns[0].type == hir.Primitive_Type.Int64)
	testing.expect(t, len(state.pending_bodies) == 1)
	testing.expect(t, state.pending_bodies[0].symbol == &function)
}
