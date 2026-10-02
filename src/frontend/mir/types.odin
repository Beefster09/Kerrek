package mir

Type :: union {
	Primitive_Type,
	Struct_Type,
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
}

Struct_Type :: struct {}
