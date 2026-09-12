package hir


Statement :: union {
	^Local_Variable,
	^Return_Statement,
	^Expr_Statement,
	^Assign_Statement,
	^Block,
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
	span:   Span,
	values: []Expression,
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
