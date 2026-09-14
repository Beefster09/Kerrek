package resolver

import "../../common"
import "../diagnostics"


Scope :: struct {
	locals: map[common.Identifier]Partial_Symbol,
	parent: Scope_Parent,
}

Scope_Parent :: union {
	^Scope,
	^File,
}

@(deferred_out_by_ptr = _destroy_local_scope)
push_scope :: proc(parent: Scope_Parent) -> Scope {
	return {parent = parent, locals = make(map[common.Identifier]Partial_Symbol)}
}

_destroy_local_scope :: proc(scope: ^Scope) {
	delete(scope.locals)
}


Define_Local_Error :: enum {
	OK,
	Conflict,
}


define_local :: proc(
	scope: ^Scope,
	name: common.Name,
	symbol: Partial_Symbol,
) -> Define_Local_Error {
	if existing, exists := scope.locals[name.id]; exists {
		diag := diagnostics.emit(.Duplicate_Local, name.span, "name '%s' is already defined")
		if name_span, ok := span_of_name(existing); ok {
			diagnostics.reference(diag, name_span, "'%s' was previously defined here", name.id)
		}
		return .Conflict
	}

	scope.locals[name.id] = symbol

	return .OK
}
