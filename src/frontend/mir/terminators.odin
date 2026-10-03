package mir

Terminator :: union {
	Jump,
	Branch_Zero,
	Branch_Less,
	Branch_Equal,
	Weak_Ptr_Valid,
	Switch,
	Return,
	Fail,
}


Jump :: struct {
	next: int,
}

Branch_Zero :: struct {
	value:     Operand,
	z_branch:  int,
	nz_branch: int,
}

Branch_Less :: struct {
	lhs:       Operand,
	rhs:       Operand,
	lt_branch: int,
	ge_branch: int,
}

Branch_Equal :: struct {
	lhs:       Operand,
	rhs:       Operand,
	eq_branch: int,
	ne_branch: int,
}

Weak_Ptr_Valid :: struct {
	value:          Operand,
	valid_branch:   int,
	invalid_branch: int,
}

Switch :: struct {
	value: Operand,
	cases: []Switch_Case,
}

Switch_Case :: struct {
	value:  Constant,
	branch: int,
}

Return :: struct {
	value: Operand,
}

Fail :: struct {
	err: Operand,
}
