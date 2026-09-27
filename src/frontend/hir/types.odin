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
	Any,
	Opaque,
	Opaque8,
	Opaque16,
	Opaque32,
	Opaque64,
}

Fixed_Decimal :: struct {
	digits:    u8,
	scale:     i8,
	flags:     bit_set[enum {
		Inferred,
		Intermediate,
	};u16],
	magnitude: f32,
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
	nullable:  bool,
}

Tagged_Type :: struct {
	base: Type,
	tags: []Symbol_ID,
}
