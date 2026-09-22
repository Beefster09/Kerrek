package ast

import "../../common"
import "../../common/exact"
import "../lexer"

Expression :: union {
	^Name_Expr,
	^Placeholder_Expr,
	^FieldAccess_Expr,
	^Scalar_Literal_Expr,
	^Simple_Literal_Expr,
	^Implicit_Enum_Expr,
	^Move_Expr,
	^Binop_Expr,
	^Unary_Expr,
	^Address_Of_Expr,
	^Dereference_Expr,
	^Cast_Expr,
	^Unit_Conversion_Expr,
	^Unit_Reinterpret_Expr,
	^Index_Expr,
	^Callish_Expr,
	^Type_Expr_Expr,
	^Unit_Expr,
}

Name_Expr :: struct {
	span: Span,
	name: Name,
}

Placeholder_Expr :: struct {
	span: Span,
}

FieldAccess_Expr :: struct {
	span:  Span,
	base:  Expression,
	field: Name,
}

Scalar_Literal_Expr :: struct {
	span:   Span,
	value:  exact.Rat,
	format: lexer.Number_Format,
	digits: i32,
	scale:  i32,
	unit:   ^Compound_Unit,
}

Simple_Literal_Expr :: struct {
	span:  Span,
	value: common.Value,
}

Implicit_Enum_Expr :: struct {
	span:    Span,
	name:    Name,
	payload: Expression,
}

Move_Expr :: struct {
	span: Span,
	expr: Expression,
}
Binop_Expr :: struct {
	span: Span,
	op:   common.Binary_Op,
	lhs:  Expression,
	rhs:  Expression,
}

Unary_Expr :: struct {
	span: Span,
	op:   common.Unary_Op,
	expr: Expression,
}

Address_Of_Expr :: struct {
	span: Span,
	expr: Expression,
}

Dereference_Expr :: struct {
	span: Span,
	expr: Expression,
}

Cast_Expr :: struct {
	span: Span,
	expr: Expression,
	to:   Type_Expression,
}

Unit_Conversion_Expr :: struct {
	span: Span,
	expr: Expression,
	to:   ^Compound_Unit,
}

Unit_Reinterpret_Expr :: struct {
	span:     Span,
	expr:     Expression,
	new_unit: Declared_Unit,
}

Index_Expr :: struct {
	span:       Span,
	collection: Expression,
	args:       []Argument,
}

Callish_Expr :: struct {
	span:   Span,
	callee: Expression,
	args:   []Argument,
}

Type_Expr_Expr :: struct {
	span: Span,
	type: ^Type_Expression,
}

Unit_Expr :: struct {
	span: Span,
	unit: ^Compound_Unit,
}


expression_span :: proc "contextless" (expr: Expression) -> Span {
	switch expr in expr {
	case ^Name_Expr:
		return expr.span
	case ^Placeholder_Expr:
		return expr.span
	case ^FieldAccess_Expr:
		return expr.span
	case ^Scalar_Literal_Expr:
		return expr.span
	case ^Simple_Literal_Expr:
		return expr.span
	case ^Implicit_Enum_Expr:
		return expr.span
	case ^Move_Expr:
		return expr.span
	case ^Binop_Expr:
		return expr.span
	case ^Unary_Expr:
		return expr.span
	case ^Address_Of_Expr:
		return expr.span
	case ^Dereference_Expr:
		return expr.span
	case ^Cast_Expr:
		return expr.span
	case ^Unit_Conversion_Expr:
		return expr.span
	case ^Unit_Reinterpret_Expr:
		return expr.span
	case ^Index_Expr:
		return expr.span
	case ^Callish_Expr:
		return expr.span
	case ^Type_Expr_Expr:
		return expr.span
	case ^Unit_Expr:
		return expr.span
	}

	return {}
}
