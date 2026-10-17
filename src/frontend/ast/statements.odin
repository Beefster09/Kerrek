package ast

Statement :: union {
	^Return_Statement,
	^Expr_Statement,
	^Assign_Statement,
	^Local_Variable,
	^Constant_Def,
	^If_Statement,
	^Each_Loop,
	^Step_Loop,
	^Block,
}

Block :: struct {
	span: Span,
	body: []Statement,
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

If_Statement :: struct {
	span:      Span,
	condition: Expression,
	body:      ^Block,
	alt:       union {
		^Block,
		^If_Statement,
	},
}

Each_Loop :: struct {
	span:      Span,
	index_var: Maybe(Name),
	value_var: Name,
	body:      ^Block,
}

Step_Loop :: struct {
	span:         Span,
	initializers: []Local_Variable,
	steps:        []Assign_Statement,
	condition:    Expression,
	body:         ^Block,
	order:        enum {
		Cond_Body_Step, // traditional 3-clause for
		Step_Cond_Body, // while (x = next())
		Body_Cond_Step, // do ... while
	},
}
