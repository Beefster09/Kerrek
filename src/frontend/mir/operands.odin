package mir

import "../../common"


Primitive_Operand :: union #no_nil {
	Constant,
	Temp,
	Local_Var,
	Global_Var,
	Parameter,
}
Operand :: union #no_nil {
	Constant,
	Temp,
	Local_Var,
	Global_Var,
	Parameter,
	Field_Of,
	Index_Of,
	Dereferenced,
}
Writable :: union #no_nil {
	Discard,
	New_Temp,
	Local_Var,
	Global_Var,
	Field_Of,
	Index_Of,
	Dereferenced,
}


Discard :: struct {}

Global_Var :: struct {
	id: Global_Var_ID,
}

Local_Var :: struct {
	id: Local_Var_Index,
}

Temp_Index :: distinct int
New_Temp :: struct {
	id:   Temp_Index,
	type: Type,
}
Temp :: struct {
	id: Temp_Index,
}

Parameter :: struct {
	index: Parameter_Index,
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
	[4]i64,
	i128,
	u128,
	f64,
	bool,
	string,
	// and nil, implicitly
}

Dereferenced :: struct {
	base: Primitive_Operand,
}
