package main

import "core:fmt"
import "core:os"

import "frontend/diagnostics"
import "frontend/resolver"

build :: proc(entry_point: string, backend_id: string = "c99") {
	res: resolver.Resolver
	resolver.init(&res)
	defer resolver.destroy(&res)

	_, err := resolver.require(&res, entry_point)
	if err != .OK {
		fmt.eprintln("loading source failed:", err)
	}
	resolver.finish_imports()
	diagnostics.report_and_exit()


}
