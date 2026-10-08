package mir

import "../../common"


Primitive_Operand :: union {
	Constant,
	Temp,
	Local_Var,
	Global_Var,
	Parameter,
}
Operand :: union {
	Constant,
	Temp,
	Local_Var,
	Global_Var,
	Parameter,
	Field_Of,
	Index_Of,
	Dereferenced,
}
Writable :: union {
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

i256 :: common.i256
Constant :: union {
	i256,
	i128,
	i64,
	i32,
	i16,
	i8,
	u128,
	u64,
	u32,
	u16,
	u8,
	f64,
	f32,
	f16,
	bool,
	string,
	// and nil, implicitly
}

Dereferenced :: struct {
	base: Primitive_Operand,
}
