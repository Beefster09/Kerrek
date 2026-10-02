package mir

Operation :: union {
	Set,
	Clear,
	Convert,
	Alloc,
	Free,
	NewRC,
	IncRC,
	DecRC,
	Derive_Weak,
	Pin_Weak,
	Get_Addr,
	Add,
	Sub,
	Mul,
	Div,
	Rem,
	Truncate,
	Call,
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
	ptr:   Writable,
	count: Operand,
}

Free :: struct {
	ptr: Writable,
}
NewRC :: struct {
	ptr:  Writable,
	size: Operand,
}


IncRC :: struct {
	ptr: Writable,
}
DecRC :: struct {
	ptr: Writable,
}

Derive_Weak :: struct {
	dest: Writable,
	ptr:  Operand,
}

Get_Addr :: struct {
	dest: Writable,
	of:   Addressible,
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
