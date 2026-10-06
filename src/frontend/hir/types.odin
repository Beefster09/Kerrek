package hir

import "../../common"


INT256_DECIMAL_DIGITS :: 76
MAX_DECIMAL_DIGITS :: INT256_DECIMAL_DIGITS
MAX_DECIMAL_SCALE :: INT256_DECIMAL_DIGITS
MIN_DECIMAL_SCALE :: -INT256_DECIMAL_DIGITS


Type :: union {
	Primitive_Type,
	Fixed_Decimal,
	^Struct_Type,
	^Enum_Type,
	^Distinct_Type,
	^Interface,
	^Generic_Type,
	^Fixed_Array_Type,
	^Dynamic_Array_Type,
	^View_Type,
	^Map_Type,
	^Optional_Type,
	^Pointer_Type,
	^Tagged_Type,
	^Func_Type,
}

Primitive_Type :: enum {
	Int128,
	Int64,
	Int32,
	Int16,
	Int8,
	UInt128,
	UInt64,
	UInt32,
	UInt16,
	UInt8,
	Bin64,
	Bin32,
	Bin16,
	Boolean,
	String,
	Rune,
	Byte,
	Type,
	Any,
}

Fixed_Decimal :: struct {
	digits:    u8,
	scale:     i8,
	flags:     Decimal_Flags,
	magnitude: f32,
}
Decimal_Flags :: bit_set[Decimal_Flag;u16]
Decimal_Flag :: enum {
	Inferred,
	Intermediate,
}

Generic_Type :: struct {
	name:  Identifier,
	bound: Type,
}

Fixed_Array_Type :: struct {
	elem:  Type,
	shape: []int,
}

Dynamic_Array_Type :: struct {
	elem: Type,
}

View_Type :: struct {
	elem:       Type,
	dimensions: int,
	ownership:  common.Pointer_Ownership,
}

Map_Type :: struct {
	key:   Type,
	value: Type,
}

Optional_Type :: struct {
	base: Type,
}

Pointer_Type :: struct {
	to:        Type,
	ownership: common.Pointer_Ownership,
}

Tagged_Type :: struct {
	base: Type,
	tags: []Symbol_ID,
}

Func_Type :: struct {
	params:   []Type_And_Unit,
	ret:      ^Type_And_Unit,
	err:      Type,
	flags:    Func_Flags,
	requires: Capability_Expression,
}

Type_And_Unit :: struct {
	type: Type,
	unit: Realized_Unit,
}
