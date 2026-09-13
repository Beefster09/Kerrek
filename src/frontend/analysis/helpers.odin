package analysis

import "../../common"
import "../resolver"

@(deferred_out_by_ptr = _destroy_local_scope)
_local_scope :: proc(parent: resolver.Scope_Parent) -> resolver.Scope {
	return {parent = parent, locals = make(map[common.Identifier]resolver.Partial_Symbol)}
}

_destroy_local_scope :: proc(scope: ^resolver.Scope) {
	delete(scope.locals)
}
