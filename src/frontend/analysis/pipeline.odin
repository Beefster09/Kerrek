package analysis

import "../hir"
import "../resolver"


Translation_Error :: enum {
	OK,
	Type_Check_Failed,
}


// build_hir runs the semantic-analysis passes and freezes their accumulated
// declarations into output. The caller owns output and its arena.
build_hir :: proc(
	res: ^resolver.Resolver,
	entry_package: ^resolver.Package,
) -> (
	output: ^hir.Translation_Unit,
	err: Translation_Error,
) {
	assert(res != nil)
	assert(entry_package != nil)

	output = new(hir.Translation_Unit)
	hir.init(output)

	state: Translation_State
	init_state(&state, res, entry_package, output)
	defer destroy_state(&state)

	ok := process_toplevel_items(&state)
	commit_hir_items(&state)

	return output, .OK
}
