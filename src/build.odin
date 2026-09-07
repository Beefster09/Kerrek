package main

import "core:fmt"
import "core:os"
import "core:reflect"

import "frontend/diagnostics"
import "frontend/lexer"
import "frontend/units"

build :: proc(entry_point: string, backend_id: string = "c99") {
	a := units.Small_Rat{22, 7}
	b := units.Small_Rat{2, 5}
	fmt.println(units.add_rat(a, b))
	fmt.println(size_of(units.Inline_Compound_Unit))
	tokens, err := lexer.tokenize(entry_point)
	if err != .OK {
		fmt.eprintln("lexing failed")
		os.exit(1)
	}
	diagnostics.report_and_exit()
}
