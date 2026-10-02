package mir

import "../../common"

TranslationUnit :: struct {
	types:     []Type,
	globals:   []Global_Var,
	functions: []Function,
}


Function :: struct {
	id:        common.Symbol_ID,
	name:      common.Identifier,
	no_mangle: bool,
	params:    []Parameter,
	returns:   Type,
	error:     Type,
	fallible:  bool,
	locals:    []Local_Var,
	blocks:    []Block,
}


Block :: struct {
	id:  int,
	ops: []Operation,
	end: Terminator,
}
