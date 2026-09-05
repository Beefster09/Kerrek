package main

import "core:fmt"
import "core:os"
import "core:reflect"

import "frontend/lexer"

build :: proc(entry_point: string, backend_id: string = "c99") {
	tokens, err := lexer.tokenize(entry_point)
	if err != .OK {
		fmt.eprintln("lexing failed")
		os.exit(1)
	}
	fmt.println(len(tokens), "tokens emitted")
	for tok in tokens {
		fmt.printfln("{0:T}({0:v})", reflect.get_union_variant(tok.what))
	}
}
