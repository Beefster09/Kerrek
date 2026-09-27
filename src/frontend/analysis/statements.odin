package analysis

import "../ast"
import "../hir"
import "../resolver"

build_block :: proc(
	ts: ^Translation_State,
	src: ^ast.Block,
	outer_scope: resolver.Scope,
) -> ^hir.Block {
	locals := resolver.temp_scope(outer_scope)
	body := make([dynamic]hir.Statement, ts.allocator)

	for stmt in src.body {
		switch stmt in stmt {
		case ^ast.Block:
			inner := build_block(ts, stmt, &locals)
			if inner != nil {
				append(&body, inner)
			}
		case ^ast.Expr_Statement:
		case ^ast.Assign_Statement:
		case ^ast.Local_Variable:
		case ^ast.Constant_Def:
		case ^ast.Return_Statement:
		}
	}

	return nil
}
