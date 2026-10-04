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
	next: Block_ID,
}

Branch_Zero :: struct {
	value:     Operand,
	z_branch:  Block_ID,
	nz_branch: Block_ID,
}

Branch_Less :: struct {
	lhs:       Operand,
	rhs:       Operand,
	lt_branch: Block_ID,
	ge_branch: Block_ID,
}

Branch_Equal :: struct {
	lhs:       Operand,
	rhs:       Operand,
	eq_branch: Block_ID,
	ne_branch: Block_ID,
}

Weak_Ptr_Valid :: struct {
	value:          Operand,
	valid_branch:   Block_ID,
	invalid_branch: Block_ID,
}

Switch :: struct {
	value: Operand,
	cases: []Switch_Case,
}

Switch_Case :: struct {
	value:  Constant,
	branch: Block_ID,
}

Return :: struct {
	value: Operand,
}

Fail :: struct {
	err: Operand,
}
