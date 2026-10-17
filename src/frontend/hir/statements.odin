package hir

import "../../common"

Statement :: union {
	^If_Statement,
	^Each_Loop,
	^Step_Loop,
	^Local_Variable,
	^Return_Statement,
	^Expr_Statement,
	^Assign_Statement,
	^Block,
	^Poison,
}

statement_span :: proc "contextless" (stmt: Statement) -> Span {
	switch stmt in stmt {
	case ^If_Statement:
		return stmt.span
	case ^Each_Loop:
		return stmt.span
	case ^Step_Loop:
		return stmt.span
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
	index: ^Local_Variable,
	value: ^Local_Variable,
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
	init:      []Local_Variable,
	steps:     []Assign_Statement,
	condition: Expression,
	body:      ^Block,
	order:     Step_Loop_Order,
}

Step_Loop_Order :: common.Step_Loop_Order
