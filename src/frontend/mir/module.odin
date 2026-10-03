package mir

import "../../common"
import "../hir"


// Modules aka translation units
Module :: struct {
	types:     []Type,
	globals:   []Global_Var_Def,
	functions: []^Function,
}

Function :: struct {
	id:     common.Symbol_ID,
	name:   common.Identifier,
	params: []Parameter_Def,
	ret:    Type,
	err:    Type,
	flags:  hir.Func_Flags,
	locals: []Local_Var_Def,
	blocks: []Block,
}

Block :: struct {
	id:  int,
	ops: []Instruction,
	end: Terminator,
}


Global_Var_ID :: distinct int
Global_Var_Def :: struct {
	span: common.Span,
	id:   Global_Var_ID,
	name: common.Identifier,
	type: Type,
}

Local_Var_Index :: distinct int
Local_Var_Def :: struct {
	span: common.Span,
	id:   Local_Var_Index,
	name: common.Identifier,
	type: Type,
}

Parameter_Index :: distinct int
Parameter_Def :: struct {
	span:  common.Span,
	index: Parameter_Index,
	name:  common.Identifier,
	type:  Type,
}
