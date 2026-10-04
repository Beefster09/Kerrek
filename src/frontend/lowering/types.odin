package lowering

import "../hir"
import "../mir"

lower_type_def :: proc(ctx: ^Translation_Context, type: hir.Type_Definition) -> mir.Type {
	return nil
}

lower_type :: proc(ctx: ^Translation_Context, type: hir.Type) -> mir.Type {
	return nil
}
