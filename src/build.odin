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
		fmt.eprintln("loading source failed:", err)
	}

	if entry_pkg != nil {
		tu: hir.Translation_Unit
		hir.init(&tu)
		defer hir.destroy(&tu)

		translation: analysis.Translation_State
		analysis.init_state(&translation, &res, entry_pkg, &tu)
		defer analysis.destroy_state(&translation)
		analysis.prepare_declaration_graph(&translation)
		analysis.commit_hir_items(&translation)
	}

	diagnostics.report_and_exit()


}
