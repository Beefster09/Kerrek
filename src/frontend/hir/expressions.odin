package hir

import "../../common"
import "../../common/exact"


_Expr_Header :: struct {
	span:      Span,
	using _tu: Type_And_Unit,
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
	^Static_Func_Expr,
	^Static_Call_Expr,
	^Dynamic_Call_Expr,
	Type,
	^Poison,
}

type_and_unit :: proc "contextless" (expr: Expression) -> (Type, Realized_Unit, bool) {
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
	case ^Static_Func_Expr:
		return node.func.type, Indeterminate_Unit.No_Unit, true
	case ^Static_Call_Expr:
		return node.type, node.unit, node.type != nil && node.unit != nil
	case ^Dynamic_Call_Expr:
		return node.type, node.unit, node.type != nil && node.unit != nil
	case Type:
		return Primitive_Type.Type, Indeterminate_Unit.No_Unit, true
	case ^Poison, nil:
	}
	return nil, nil, false
}

set_unit :: proc "contextless" (expr: ^Expression, unit: Realized_Unit) {
	switch &node in expr {
	case ^Var_Expr:
		node.unit = unit
	case ^Const_Expr:
		node.unit = unit
	case ^Field_Access_Expr:
		node.unit = unit
	case ^Enum_Value:
		node.unit = unit
	case ^Move_Expr:
		node.unit = unit
	case ^Condition_Expr:
		node.unit = unit
	case ^Binop_Expr:
		node.unit = unit
	case ^Unary_Expr:
		node.unit = unit
	case ^Address_Of_Expr:
		node.unit = unit
	case ^Dereference_Expr:
		node.unit = unit
	case ^Cast_Expr:
		node.unit = unit
	case ^Unit_Conversion_Expr:
		node.unit = unit
	case ^Unit_Reinterpret_Expr:
		node.unit = unit
	case ^Index_Expr:
		node.unit = unit
	case ^Static_Call_Expr:
		node.unit = unit
	case ^Dynamic_Call_Expr:
		node.unit = unit
	case ^Poison, ^Static_Func_Expr, Type, nil:
	}
}

has_value :: proc "contextless" (expr: Expression) -> bool {
	#partial switch node in expr {
	case ^Dynamic_Call_Expr:
		return node.type != nil && node.unit != nil
	case ^Poison, nil:
		return false
	case:
		return true
	}
}

Nil_Of :: struct {
	type: Type,
}

Zero_Of :: struct {
	type: Type,
}

Value :: union {
	i8,
	u8,
	i16,
	u16,
	i32,
	u32,
	i64,
	u64,
	i128,
	u128,
	exact.Decimal,
	f16,
	f32,
	f64,
	string,
	bool,
	Nil_Of,
	Zero_Of,
}

Var_Expr :: struct {
	using _:    _Expr_Header,
	references: Symbol,
}

Const_Expr :: struct {
	using _: _Expr_Header,
	value:   Value,
}

Field_Access_Expr :: struct {
	using _: _Expr_Header,
	base:    Expression,
	field:   Identifier,
}

Enum_Value :: struct {
	using _:   _Expr_Header,
	enum_type: ^Enum_Type,
	variant:   int,
	payload:   Expression,
}

Move_Expr :: struct {
	using _: _Expr_Header,
	expr:    Expression,
}

Condition_Expr :: struct {
	using _:   _Expr_Header,
	condition: Expression,
	if_true:   Expression,
	if_false:  Expression,
}

Binop_Expr :: struct {
	using _: _Expr_Header,
	op:      common.Binary_Op,
	lhs:     Expression,
	rhs:     Expression,
}

Unary_Expr :: struct {
	using _: _Expr_Header,
	op:      common.Unary_Op,
	expr:    Expression,
}

Address_Of_Expr :: struct {
	using _: _Expr_Header,
	expr:    Expression,
}

Dereference_Expr :: struct {
	using _: _Expr_Header,
	expr:    Expression,
}

Cast_Expr :: struct {
	using _: _Expr_Header,
	expr:    Expression,
	to:      Type,
}

Unit_Conversion_Expr :: struct {
	using _: _Expr_Header,
	expr:    Expression,
	factor:  exact.Rat,
}

Unit_Reinterpret_Expr :: struct {
	using _: _Expr_Header,
	expr:    Expression,
}

Index_Expr :: struct {
	using _:    _Expr_Header,
	collection: Expression,
	args:       []Expression,
}

Static_Func_Expr :: struct {
	span: Span,
	func: ^Func_Definition,
}

Static_Call_Expr :: struct {
	using _: _Expr_Header,
	func:    ^Func_Definition,
	args:    []Expression,
}

Dynamic_Call_Expr :: struct {
	using _: _Expr_Header,
	callee:  Expression,
	args:    []Expression,
}
