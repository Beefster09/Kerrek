package analysis

import "../../common"
import "../diagnostics"
import "../hir"
import "../resolver"

resolve :: proc(
	ts: ^Translation_State,
	scope: resolver.Scope,
	name: common.Name,
) -> resolver.Symbol {
	resolved := resolver.lookup(scope, name.id)
	if resolved != nil {
		ensure_toplevel_symbol_processed(ts, resolved)
	} else {
		diagnostics.emit(.Unresolved_Name, name.span, "'%s' could not be resolved", name.id)
	}
	return resolved
}

poison :: proc(ts: ^Translation_State, span: common.Span) -> ^hir.Poison {
	p := new(hir.Poison, ts.output.allocator)
	p.span = span
	return p
}
