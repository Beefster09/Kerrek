package analysis

import "core:fmt"

import "../../common"
import "../ast"
import "../diagnostics"
import "../hir"
import "../resolver"

resolve :: proc {
	resolve_name,
	resolve_qualname,
}

resolve_name :: proc(
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

resolve_qualname :: proc(
	ts: ^Translation_State,
	scope: resolver.Scope,
	name: ast.Qualified_Name,
) -> resolver.Symbol {
	resolved := resolver.resolve(scope, name)
	if resolved != nil {
		ensure_toplevel_symbol_processed(ts, resolved)
	} else {
		diagnostics.emit(.Unresolved_Name, name.span, "'%s' could not be resolved", name)
	}
	return resolved
}

poison :: proc(ts: ^Translation_State, span: common.Span) -> ^hir.Poison {
	p := new(hir.Poison, ts.output.allocator)
	p.span = span
	return p
}

init_formatters :: proc() {
	fmt.register_user_formatter(ast.Qualified_Name, ast.fmt_qualname)
	fmt.register_user_formatter(Comptime_Type, fmt_comptime_type)
}
