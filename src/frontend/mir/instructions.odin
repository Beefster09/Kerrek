package mir

import "../../common"

Instruction :: union {
	Set,
	Clear,
	Convert,
	Alloc,
	Free,
	New_RC,
	Inc_RC,
	Dec_RC,
	Derive_Weak,
	Get_Addr,
	Add,
	Sub,
	Mul,
	Div,
	Rem,
	Truncate,
	Call,
	Debug_Marker,
}

Set :: struct {
	dest:  Writable,
	value: Operand,
}

Clear :: struct {
	dest: Writable,
}

Convert :: struct {
	dest:  Writable,
	value: Operand,
	type:  Type,
}

Alloc :: struct {
	ptr:  Writable,
	size: Operand,
}
Free :: struct {
	ptr: Writable,
}

New_RC :: struct {
	ptr:  Writable,
	size: Operand,
}
Inc_RC :: struct {
	ptr: Writable,
}
Dec_RC :: struct {
	ptr: Writable,
}

Derive_Weak :: struct {
	dest: Writable,
	ptr:  Operand,
}

Get_Addr :: struct {
	dest: Writable,
	of:   Operand,
}

Add :: struct {
	dest: Writable,
	lhs:  Operand,
	rhs:  Operand,
}
Sub :: struct {
	dest: Writable,
	lhs:  Operand,
	rhs:  Operand,
}
Mul :: struct {
	dest: Writable,
	lhs:  Operand,
	rhs:  Operand,
}
Div :: struct {
	dest: Writable,
	lhs:  Operand,
	rhs:  Operand,
}
Rem :: struct {
	dest: Writable,
	lhs:  Operand,
	rhs:  Operand,
}

Truncate :: struct {
	dest:  Writable,
	value: Operand,
}

Call :: struct {
	dest: Writable,
	func: Function,
	args: []Operand,
}

Debug_Marker :: struct {
	span: common.Span,
}
