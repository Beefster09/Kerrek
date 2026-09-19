package analysis

import "../../common"
import "../ast"
import "../hir"
import "../resolver"


build_type :: proc(
	ts: ^Translation_State,
	type_ast: ast.Type_Expression,
	scope: resolver.Scope,
) -> (
	hir.Type,
	bool,
) {
	return nil, false
}
