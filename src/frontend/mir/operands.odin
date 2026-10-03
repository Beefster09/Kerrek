package mir

import "../../common"


Primitive_Operand :: union {
	Constant,
	Temporary,
	Local_Var,
	Global_Var,
	Parameter,
}
Operand :: union {
	Constant,
	Temporary,
	Local_Var,
	Global_Var,
	Parameter,
	Field_Of,
	Index_Of,
	Dereferenced,
}
Writable :: union {
	Discard,
	Temporary,
	Local_Var,
	Global_Var,
	Field_Of,
	Index_Of,
	Dereferenced,
}


Discard :: struct {}

Global_Var :: struct {
	id:   int,
	name: common.Identifier,
	type: Type,
}


Local_Var :: struct {
	id:   int,
	name: common.Identifier,
	type: Type,
}


Temporary :: struct {
	id:   int,
	type: Type,
}

Parameter :: struct {
	index: int,
	name:  common.Identifier,
	type:  Type,
}


Field_Of :: struct {
	base:  Primitive_Operand,
	field: common.Identifier,
}

Index_Of :: struct {
	base: Primitive_Operand,
	elem: Primitive_Operand,
}

Constant :: union {
	i128,
	u128,
	f64,
	bool,
	string,
	// and nil, implicitly
}

Dereferenced :: struct {
	base:   Primitive_Operand,
	levels: int,
}
