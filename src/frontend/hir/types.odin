package hir

import "../../common"


Type :: union {
	^Simple_Type,
	^Generic_Type,
	^Fixed_Array_Type,
	^Dynamic_Array_Type,
	^Dimensioned_Array_Type,
	^Map_Type,
	^Optional_Type,
	^Pointer_Type,
	^Type_With_Tags,
}

Simple_Type :: struct {
	type: Simple_Type_Value,
}

Simple_Type_Value :: union {
	Primitive_Type,
	Fixed_Decimal,
	^Struct_Type,
	^Enum_Type,
	^Distinct_Type,
	^Interface,
}

Primitive_Type :: enum {
	Integer,
	Int64,
	Int32,
	Int16,
	Int8,
	UInt64,
	UInt32,
	UInt16,
	UInt8,
	Decimal,
	Dec64,
	Dec32,
	Float64,
	Float32,
	Boolean,
	String,
	Rune,
	Byte,
	Opaque,
	Opaque8,
	Opaque16,
	Opaque32,
	Opaque64,
}

Fixed_Decimal :: struct {
	digits:    int,
	precision: int,
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

Dimensioned_Array_Type :: struct {
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

Type_With_Tags :: struct {
	base: Type,
	tags: []Symbol_ID,
}
