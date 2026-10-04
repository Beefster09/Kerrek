package main

import "core:fmt"
import "core:os"

import "frontend/analysis"
import "frontend/diagnostics"
import "frontend/lowering"
import "frontend/mir"
import "frontend/resolver"

build :: proc(entry_point: string, backend_id: string = "c99") {
	resolver_alive := true
	res: resolver.Resolver
	resolver.init(&res)
	defer if resolver_alive {
		resolver.destroy(&res)
	}

	entry_pkg, load_err := resolver.load_package(&res, entry_point, file_as_package = true)
	diagnostics.report_and_exit()
	if load_err != .OK {
		os.exit(1)
	}

	tu, sem_err := analysis.build_hir(&res, entry_pkg)
	diagnostics.report_and_exit()
	if sem_err != .OK {
		os.exit(1)
	}

	resolver.destroy(&res)
	resolver_alive = false

	mod := lowering.hir_to_mir(tu)
	for func in mod.functions {
		stdout := os.to_writer(os.stdout)
		fmt.println()
		fmt.printfln("; === func %s ===", func.name)
		for block in func.blocks {
			mir.dump_block(stdout, block)
		}
	}
}
