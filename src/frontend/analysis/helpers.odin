package analysis

import "../../common"
import "../hir"
import "../resolver"

resolve :: proc(
	ts: ^Translation_State,
	scope: resolver.Scope,
	name: common.Identifier,
) -> resolver.Symbol {
	resolved := resolver.lookup(scope, name)
	if resolved != nil {
		ensure_toplevel_symbol_processed(ts, resolved)
	}
	return resolved
}

poison :: proc(ts: ^Translation_State, span: common.Span) -> ^hir.Poison {
	p := new(hir.Poison, ts.output.allocator)
	p.span = span
	return p
}
