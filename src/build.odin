package main

import "core:fmt"
import "core:os"
import "core:reflect"

import "frontend/diagnostics"
import "frontend/lexer"

build :: proc(entry_point: string, backend_id: string = "c99") {
	tokens, err := lexer.tokenize(entry_point)
	if err != .OK {
		fmt.eprintln("lexing failed")
		os.exit(1)
	}
	diagnostics.report_and_exit()
	fmt.println(len(tokens), "tokens emitted")
	fmt.printfln("%%v: %v", tokens[0].span)
	fmt.printfln("%%s: %s", tokens[0].span)
	fmt.printfln("%%f: %f", tokens[0].span)
	fmt.printfln("%%b: %b", tokens[0].span)
	fmt.printfln("%%e: %e", tokens[0].span)
	fmt.printfln("%%d: %d", tokens[0].span)
	fmt.printfln("%%a: %a", tokens[0].span)
	fmt.printfln("%%z: %z", tokens[0].span)

	// for tok in tokens {
	// 	fmt.printfln("{1:d} {0:T}({0:v})", reflect.get_union_variant(tok.what), tok.span)
	// }

}
