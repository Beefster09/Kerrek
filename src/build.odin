package main

import "core:fmt"
import "core:os"

import "frontend/diagnostics"
import "frontend/parser"

build :: proc(entry_point: string, backend_id: string = "c99") {

	ast_file, err := parser.parse(entry_point)
	if err != .OK {
		fmt.eprintln("parsing failed")
	}
	diagnostics.report_and_exit()


}
