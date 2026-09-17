package analysis

import "../../common"
import "../hir"

Comptime_Value :: struct {
	span:  common.Span,
	value: common.Value,
	type:  Comptime_Type,
	unit:  hir.Realized_Unit,
}

Comptime_Type :: union {
	hir.Type,
	Flexible_Type,
}

Flexible_Type :: struct {
	affinity: Flexible_Affinity,
}

Flexible_Affinity :: enum {
	Nil,
	Unsigned_Integer,
	Integer,
	Rational,
	Binary_Float,
	Boolean,
	String,
	Rune,
}
