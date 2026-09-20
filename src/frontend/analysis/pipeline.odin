package analysis

import "../hir"
import "../resolver"
import "../units"


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
	output: ^hir.Translation_Unit,
	ret_err: Translation_Error,
) {
	assert(res != nil)
	assert(entry_package != nil)

	tu := new(hir.Translation_Unit)
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
		bodies_ok &&= err != .OK
	}
	if !(top_ok && bodies_ok) {
		return nil, .Semantic_Analysis_Failed
	}
	commit_hir_items(&ts)

	return tu, .OK
}
