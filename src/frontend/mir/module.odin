package mir

import "../../common"


// Modules aka translation units
Module :: struct {
	types:     []Type,
	globals:   []Global_Var,
	functions: []^Function,
}

Function :: struct {
	id:        common.Symbol_ID,
	name:      common.Identifier,
	no_mangle: bool,
	params:    []Parameter,
	ret:       Type,
	err:       Type,
	fallible:  bool,
	locals:    []Local_Var,
	blocks:    []^Block,
}

Block :: struct {
	id:  int,
	ops: []Instruction,
	end: Terminator,
}
