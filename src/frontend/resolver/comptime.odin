package resolver

import "../../common"
import "../hir"

// I don't *love* defining these here but it's necessary for constants


Comptime_Value :: struct {
	value: common.Primitive_Value,
	type:  Comptime_Type,
	unit:  hir.Realized_Unit,
}

Comptime_Type :: union {
	hir.Type,
	Flexible_Type,
}

Flexible_Type :: struct {
	affinity: Flexible_Affinity,
	digits:   i32,
	scale:    i32,
}

Flexible_Affinity :: enum {
	Nil,
	Any_Zero,
	Unsigned_Integer,
	Integer,
	Decimal,
	Binary_Float,
	Rational,
	Boolean,
	String,
	Rune,
	Byte,
}
