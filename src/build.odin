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
	fmt.printfln("%s %t", units.add_rat(a, b))
	units.register_unit_name(123, "man")
	units.register_unit_name(321, "month")
	fmt.printfln(
		"%s",
		units.Compound_Unit(
			units.Inline_Compound_Unit {
				components = {{123, {42, 1}}, {321, {-69, 1}}, {744, {2, 3}}, {}},
				count = 3,
			},
		),
	)
	tokens, err := lexer.tokenize(entry_point)
	if err != .OK {
		fmt.eprintln("lexing failed")
		os.exit(1)
	}
	diagnostics.report_and_exit()
}
