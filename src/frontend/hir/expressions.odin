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
}

Nil_Of :: struct {
	type: Type,
}

Zero_Of :: struct {
	type: Type,
}

Value :: union #no_nil {
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
	using _:  _Single_Value_Expression_Header,
	enum_type: ^Enum_Type,
	variant:  int,
	payload:  Expression,
}

Move_Expr :: struct {
	using _: _Single_Value_Expression_Header,
	expr:    Expression,
}

Condition_Expr :: struct {
	using _:  _Single_Value_Expression_Header,
	condition: Expression,
	if_true:  Expression,
	if_false: Expression,
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
	using _:   _Single_Value_Expression_Header,
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
