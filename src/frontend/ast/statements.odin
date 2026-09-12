package ast

Statement :: union {
	^Return_Statement,
	^Expr_Statement,
	^Assign_Statement,
	^Local_Variable,
	^Constant_Def,
	^Block,
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

Local_Variable :: struct {
	span: Span,
	name: Name,
	type: Type_Expression,
	unit: Declared_Unit,
	expr: union {
		Expression,
		Unbound_Var,
	},
}

Unbound_Var :: struct {
	span: Span,
}

Block :: struct {
	span: Span,
	body: []Statement,
}
