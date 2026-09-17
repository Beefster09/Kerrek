package main

import "core:fmt"
import "core:os"

import "frontend/analysis"
import "frontend/diagnostics"
import "frontend/hir"
import "frontend/resolver"

build :: proc(entry_point: string, backend_id: string = "c99") {
	res: resolver.Resolver
	resolver.init(&res)
	defer resolver.destroy(&res)

	entry_pkg, err := resolver.load_package(&res, entry_point, file_as_package = true)
	if err != .OK {
		diagnostics.report_and_exit()
		os.exit(1)
	}

	tu, sem_err := analysis.build_hir(&res, entry_pkg)

	diagnostics.report_and_exit()


}
