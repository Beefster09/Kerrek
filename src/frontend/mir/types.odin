package mir

import "../../common"

Type :: union {
	Primitive_Type,
	^Struct_Type,
	^Union_Type, // as in raw union i.e. all fields have the same address
	^Array_Type, // as in fixed array
	^Pointer_Type,
}

Primitive_Type :: enum {
	Int256,
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
}

Struct_Type :: struct {
	name:   common.Identifier,
	fields: []Field,
}

Union_Type :: struct {
	name:     common.Identifier,
	variants: []Field,
}

Field :: struct {
	name: common.Identifier,
	type: Type,
}

Array_Type :: struct {
	elem: Type,
	size: int,
}

Pointer_Type :: struct {
	to: Type,
}


@(rodata)
PRIMITIVE_TYPE_NAMES := [Primitive_Type]string {
	.Int256  = "i256",
	.Int128  = "i128",
	.Int64   = "i64",
	.Int32   = "i32",
	.Int16   = "i16",
	.Int8    = "i8",
	.UInt128 = "u128",
	.UInt64  = "u64",
	.UInt32  = "u32",
	.UInt16  = "u16",
	.UInt8   = "u8",
	.Bin64   = "f64",
	.Bin32   = "f32",
	.Bin16   = "f16",
	.Boolean = "bool",
	.String  = "string",
}
