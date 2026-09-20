package hir

import "../../common"
import "../../common/exact"


_Single_Value_Expression_Header :: struct {
	span: Span,
	type: Type,
	unit: Realized_Unit,
}

_Multi_Value_Expression_Header :: struct {
	span:  Span,
	types: []Type,
	units: []Realized_Unit,
}

Single_Value_Expression :: union {
	^Var_Expr,
	^Const_Expr,
	^Field_Access_Expr,
	^Enum_Value,
	^Move_Expr,
	^Condition_Expr,
	^Binop_Expr,
	^Unary_Expr,
	^Address_Of_Expr,
	^Dereference_Expr,
	^Cast_Expr,
	^Unit_Conversion_Expr,
	^Unit_Reinterpret_Expr,
	^Index_Expr,
}

Multi_Value_Expression :: union {
	^Func_Call_Expr,
}

Expression :: union {
	^Var_Expr,
	^Const_Expr,
	^Field_Access_Expr,
	^Enum_Value,
	^Move_Expr,
	^Condition_Expr,
	^Binop_Expr,
	^Unary_Expr,
	^Address_Of_Expr,
	^Dereference_Expr,
	^Cast_Expr,
	^Unit_Conversion_Expr,
	^Unit_Reinterpret_Expr,
	^Index_Expr,
	^Func_Call_Expr,
	^Poison,
}

singular_type_and_unit :: proc "contextless" (expr: Expression) -> (Type, Realized_Unit, bool) {
	switch node in expr {
	case ^Var_Expr:
		return node.type, node.unit, true
	case ^Const_Expr:
		return node.type, node.unit, true
	case ^Field_Access_Expr:
		return node.type, node.unit, true
	case ^Enum_Value:
		return node.type, node.unit, true
	case ^Move_Expr:
		return node.type, node.unit, true
	case ^Condition_Expr:
		return node.type, node.unit, true
	case ^Binop_Expr:
		return node.type, node.unit, true
	case ^Unary_Expr:
		return node.type, node.unit, true
	case ^Address_Of_Expr:
		return node.type, node.unit, true
	case ^Dereference_Expr:
		return node.type, node.unit, true
	case ^Cast_Expr:
		return node.type, node.unit, true
	case ^Unit_Conversion_Expr:
		return node.type, node.unit, true
	case ^Unit_Reinterpret_Expr:
		return node.type, node.unit, true
	case ^Index_Expr:
		return node.type, node.unit, true
	case ^Func_Call_Expr:
		if len(node.types) == 1 && len(node.units) == 1 {
			return node.types[0], node.units[0], true
		}
	case ^Poison, nil:
	}
	return nil, nil, false
}

value_count :: proc "contextless" (expr: Expression) -> int {
	switch node in expr {
	case ^Var_Expr:
		return 1
	case ^Const_Expr:
		return 1
	case ^Field_Access_Expr:
		return 1
	case ^Enum_Value:
		return 1
	case ^Move_Expr:
		return 1
	case ^Condition_Expr:
		return 1
	case ^Binop_Expr:
		return 1
	case ^Unary_Expr:
		return 1
	case ^Address_Of_Expr:
		return 1
	case ^Dereference_Expr:
		return 1
	case ^Cast_Expr:
		return 1
	case ^Unit_Conversion_Expr:
		return 1
	case ^Unit_Reinterpret_Expr:
		return 1
	case ^Index_Expr:
		return 1
	case ^Func_Call_Expr:
		return len(node.types)
	case ^Poison, nil:
		return 0
	}
	return 0
}

Nil_Of :: struct {
	type: Type,
}

Zero_Of :: struct {
	type: Type,
}

Value :: union {
	exact.Rat,
	rune,
	byte,
	string,
	bool,
	Nil_Of,
	Zero_Of,
}

Var_Expr :: struct {
	using _:    _Single_Value_Expression_Header,
	references: Symbol,
}

Const_Expr :: struct {
	using _: _Single_Value_Expression_Header,
	value:   Value,
}

Field_Access_Expr :: struct {
	using _: _Single_Value_Expression_Header,
	base:    Expression,
	field:   Identifier,
}

Enum_Value :: struct {
	using _:   _Single_Value_Expression_Header,
	enum_type: ^Enum_Type,
	variant:   int,
	payload:   Expression,
}

Move_Expr :: struct {
	using _: _Single_Value_Expression_Header,
	expr:    Expression,
}

Condition_Expr :: struct {
	using _:   _Single_Value_Expression_Header,
	condition: Expression,
	if_true:   Expression,
	if_false:  Expression,
}

Binop_Expr :: struct {
	using _: _Single_Value_Expression_Header,
	op:      common.Binary_Op,
	lhs:     Expression,
	rhs:     Expression,
}

Unary_Expr :: struct {
	using _: _Single_Value_Expression_Header,
	op:      common.Unary_Op,
	expr:    Expression,
}

Address_Of_Expr :: struct {
	using _: _Single_Value_Expression_Header,
	expr:    Expression,
}

Dereference_Expr :: struct {
	using _: _Single_Value_Expression_Header,
	expr:    Expression,
}

Cast_Expr :: struct {
	using _: _Single_Value_Expression_Header,
	expr:    Expression,
	to:      Type,
}

Unit_Conversion_Expr :: struct {
	using _: _Single_Value_Expression_Header,
	expr:    Expression,
	factor:  exact.Rat,
}

Unit_Reinterpret_Expr :: struct {
	using _: _Single_Value_Expression_Header,
	expr:    Expression,
}

Index_Expr :: struct {
	using _:    _Single_Value_Expression_Header,
	collection: Expression,
	args:       []Expression,
}

Func_Call_Expr :: struct {
	using _: _Multi_Value_Expression_Header,
	callee:  Expression,
	args:    []Argument,
}

Argument :: struct {
	span: Span,
	name: Maybe(Identifier),
	expr: Expression,
}
