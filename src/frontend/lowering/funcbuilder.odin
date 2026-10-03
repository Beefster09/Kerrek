package lowering

import "../hir"
import "../mir"
import "core:fmt"

Func_Builder :: struct {
	next_tmp: int,
	vars:     [dynamic]mir.Local_Var,
	blocks:   [dynamic]WIP_Block,
}

WIP_Block :: struct {
	id:  int,
	ops: [dynamic]mir.Instruction,
}

lower_func :: proc(fn: ^hir.Func_Definition) -> ^mir.Function {
	fmt.println("haldo")
	return nil
}
