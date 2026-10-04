package hir


Statement :: union {
	^Local_Variable,
	^Return_Statement,
	^Expr_Statement,
	^Assign_Statement,
	^Block,
	^Poison,
}

Local_Variable :: struct {
	using _:     _Symbol_Header,
	type:        Type,
	unit:        Realized_Unit,
	// A nil expression represents an explicitly unbound variable. Semantic
	// analysis materializes an implicit default as a typed Zero_Of constant.
	expr:        Expression,
	annotations: []^Annotation,
}

Return_Statement :: struct {
	span:  Span,
	value: Expression,
}

Expr_Statement :: struct {
	span: Span,
	expr: Expression,
}

Assign_Statement :: struct {
	span:  Span,
	dests: []Expression,
	exprs: []Expression,
}

Block :: struct {
	span: Span,
	body: []Statement,
}

statement_span :: proc "contextless" (stmt: Statement) -> Span {
	switch stmt in stmt {
	case ^Local_Variable:
		return stmt.span
	case ^Return_Statement:
		return stmt.span
	case ^Expr_Statement:
		return stmt.span
	case ^Assign_Statement:
		return stmt.span
	case ^Block:
		return stmt.span
	case ^Poison:
		return stmt.span
	}
	return {}
}
