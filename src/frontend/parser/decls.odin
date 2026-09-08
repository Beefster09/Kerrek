package parser

import "../ast"

_const_or_var :: proc(ps: ^Parsing_State, $MODE: enum {
		Local,
		Global,
	}) -> union {
		^ast.Global_Variable,
		^ast.Global_Constant,
		^ast.Local_Variable,
		^ast.Local_Constant,
	} {
	return nil
}
