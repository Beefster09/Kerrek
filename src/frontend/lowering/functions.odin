package lowering

import "core:fmt"

import "../../common"
import "../hir"
import "../mir"

Func_Builder :: struct {
	next_temp:         mir.Temp_Index,
	locals:            [dynamic]mir.Local_Var_Def,
	vars_by_sym_id:    map[common.Symbol_ID]mir.Local_Var,
	params_by_sym_id:  map[common.Symbol_ID]mir.Parameter,
	blocks:            [dynamic]WIP_Block,
	current_block_idx: int,
}

WIP_Block :: struct {
	id:  int,
	ops: [dynamic]mir.Instruction,
	end: mir.Terminator,
}

lower_func :: proc(fn: ^hir.Func_Definition) -> ^mir.Function {
	return nil
}
