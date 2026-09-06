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
	for tok in tokens {
		fmt.printfln(
			"{1}:{2} - {3}:{4} = {0:T}({0:v})",
			reflect.get_union_variant(tok.what),
			tok.span.start.line,
			tok.span.start.col,
			tok.span.end.line,
			tok.span.end.col,
		)
	}
}
