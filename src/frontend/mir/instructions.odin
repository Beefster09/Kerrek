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
	Indirect_Call,
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

Arithmetic_Mode :: struct {
	type:     Primitive_Type,
	overflow: Overflow_Mode,
}

Overflow_Mode :: enum u8 {
	None,
	Wrap,
	Panic,
	Saturate,
	Checked,
}

Add :: struct {
	mode: Arithmetic_Mode,
	dest: Writable,
	lhs:  Operand,
	rhs:  Operand,
}
Sub :: struct {
	mode: Arithmetic_Mode,
	dest: Writable,
	lhs:  Operand,
	rhs:  Operand,
}
Mul :: struct {
	mode: Arithmetic_Mode,
	dest: Writable,
	lhs:  Operand,
	rhs:  Operand,
}
Div :: struct {
	mode: Arithmetic_Mode,
	dest: Writable,
	lhs:  Operand,
	rhs:  Operand,
}
Rem :: struct {
	mode: Arithmetic_Mode,
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
	func: common.Symbol_ID,
	args: []Operand,
}

Indirect_Call :: struct {
	dest: Writable,
	func: Operand,
	args: []Operand,
}

Debug_Marker :: struct {
	span: common.Span,
}

@(rodata)
OVERFLOW_MODE_MNEMONICS := [Overflow_Mode]string {
	.None     = "",
	.Wrap     = ".wr",
	.Checked  = ".chk",
	.Saturate = ".sat",
	.Panic    = "!",
}
