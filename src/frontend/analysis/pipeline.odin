package analysis

import "../hir"
import "../resolver"


// build_hir runs the semantic-analysis passes and freezes their accumulated
// declarations into output. The caller owns output and its arena.
build_hir :: proc(
	res: ^resolver.Resolver,
	entry_package: ^resolver.Package,
	output: ^hir.Translation_Unit,
) -> bool {
	assert(res != nil)
	assert(entry_package != nil)
	assert(output != nil)

	state: Translation_State
	init_state(&state, res, entry_package, output)
	defer destroy_state(&state)

	ok := analyze_declaration_signatures(&state)
	commit_hir_items(&state)
	return ok
}
