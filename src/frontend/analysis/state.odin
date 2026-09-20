package analysis

import "base:runtime"
import "core:mem"

import "../../common"
import "../ast"
import "../hir"
import "../resolver"


Translation_State :: struct {
	symbol_resolver:  ^resolver.Resolver,
	entry_package:    ^resolver.Package,
	output:           ^hir.Translation_Unit,
	hir_items:        HIR_Accumulator,
	symbols_by_id:    map[common.Symbol_ID]resolver.Symbol,
	pending_bodies:   [dynamic]Pending_Function_Body,
	processing_stack: [dynamic]resolver.Symbol, // used to detect and emit diagnostics for dependency cycles
	scratch_arena:    mem.Dynamic_Arena,
	allocator:        runtime.Allocator,
}

HIR_Accumulator :: struct {
	types:        [dynamic]hir.Type_Definition,
	funcs:        [dynamic]^hir.Func_Definition,
	variables:    [dynamic]^hir.Global_Variable,
	units:        [dynamic]^hir.Base_Unit,
	capabilities: [dynamic]^hir.Capability,
	annotations:  [dynamic]^hir.Annotation_Def,
}

Pending_Function_Body :: struct {
	symbol: ^resolver.Function,
	params: []^resolver.Formal_Parameter,
}

init_state :: proc(
	state: ^Translation_State,
	res: ^resolver.Resolver,
	entry_package: ^resolver.Package,
	output: ^hir.Translation_Unit,
) {
	assert(state != nil)
	assert(res != nil)
	assert(entry_package != nil)
	assert(output != nil)

	state.symbol_resolver = res
	state.entry_package = entry_package
	state.output = output
	{
		context.allocator = output.allocator
		state.hir_items.types = make([dynamic]hir.Type_Definition)
		state.hir_items.funcs = make([dynamic]^hir.Func_Definition)
		state.hir_items.variables = make([dynamic]^hir.Global_Variable)
		state.hir_items.units = make([dynamic]^hir.Base_Unit)
		state.hir_items.capabilities = make([dynamic]^hir.Capability)
		state.hir_items.annotations = make([dynamic]^hir.Annotation_Def)
	}

	mem.dynamic_arena_init(&state.scratch_arena)
	state.allocator = mem.dynamic_arena_allocator(&state.scratch_arena)
	{
		context.allocator = state.allocator
		state.symbols_by_id = make(map[common.Symbol_ID]resolver.Symbol)
		state.pending_bodies = make([dynamic]Pending_Function_Body)
		state.processing_stack = make([dynamic]resolver.Symbol)
	}
}

// commit_hir_items freezes the declaration collections for validation. No
// declarations may be appended after this point because a later reallocation
// would leave Translation_Unit holding stale slices.
commit_hir_items :: proc(state: ^Translation_State) {
	assert(state != nil)
	assert(state.output != nil)

	state.output.types = state.hir_items.types[:]
	state.output.funcs = state.hir_items.funcs[:]
	state.output.variables = state.hir_items.variables[:]
	state.output.units = state.hir_items.units[:]
	state.output.capabilities = state.hir_items.capabilities[:]
	state.output.annotations = state.hir_items.annotations[:]

	state.hir_items = {}
}

destroy_state :: proc(state: ^Translation_State) {
	if state == nil {
		return
	}
	mem.dynamic_arena_destroy(&state.scratch_arena)
	state^ = {}
}
