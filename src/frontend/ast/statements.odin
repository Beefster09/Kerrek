package ast

import "../../common"

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
	span:  Span,
	label: Maybe(Name),
	index: Maybe(Name),
	value: Name,
	over:  union {
		Expression,
		^Range_Expr,
	},
	body:  ^Block,
}

Range_Expr :: struct {
	span:      Span,
	start:     Expression,
	end:       Expression,
	inclusive: bool,
}

Step_Loop :: struct {
	span:      Span,
	label:     Maybe(Name),
	init:      []Local_Variable,
	steps:     []Assign_Statement,
	condition: Expression,
	body:      ^Block,
	order:     Step_Loop_Order,
}

Step_Loop_Order :: common.Step_Loop_Order
