package analysis

import "../../util"
import "../hir"
import "../resolver"
import "../units"
import "core:fmt"
import "core:mem"


Translation_Error :: enum {
	OK,
	Semantic_Analysis_Failed,
}


// build_hir runs the semantic-analysis passes and freezes their accumulated
// declarations into output. The caller owns output and its arena.
build_hir :: proc(
	res: ^resolver.Resolver,
	entry_package: ^resolver.Package,
) -> (
	output: ^hir.Module,
	ret_err: Translation_Error,
) {
	assert(res != nil)
	assert(entry_package != nil)

	prev := units.push_name_getter(
		res,
		proc(res: ^resolver.Resolver, id: resolver.Symbol_ID) -> (string, bool) {
			if base_unit, ok := res.units_by_id[id]; ok {
				return string(base_unit.name), true
			}
			return "", false
		},
	)
	defer units.pop_name_getter(prev)

	arena: mem.Dynamic_Arena
	mem.dynamic_arena_init(&arena)
	defer mem.dynamic_arena_destroy(&arena)
	context.temp_allocator = mem.dynamic_arena_allocator(&arena)

	tu := new(hir.Module)
	hir.init(tu)
	defer if ret_err != .OK {
		hir.destroy(tu)
		free(tu)
	}

	ts: Translation_State
	init_state(&ts, res, entry_package, tu)
	defer destroy_state(&ts)

	top_ok := process_toplevel_items(&ts)

	units.freeze_conversion_graph(&ts.unit_conversions)

	bodies_ok := true
	for pending_func in ts.pending_bodies {
		err := build_function_body(&ts, pending_func.func, pending_func.root_scope)
		bodies_ok &&= err == .OK
		free_all(context.temp_allocator)
	}
	if !(top_ok && bodies_ok) {
		return nil, .Semantic_Analysis_Failed
	}
	commit_hir_items(&ts)

	return tu, .OK
}
