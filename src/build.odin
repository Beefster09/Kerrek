package main

import "core:fmt"
import "core:os"

import "frontend/diagnostics"
import "frontend/resolver"

build :: proc(entry_point: string, backend_id: string = "c99") {
	res: resolver.Resolver
	resolver.init(&res)
	defer resolver.destroy(&res)

	entry_pkg, err := resolver.load_package(&res, entry_point, file_as_package = true)
	if err != .OK {
		fmt.eprintln("loading source failed:", err)
	}
	diagnostics.emit(
		.Test,
		{1, {50, {line = 1, col = 6}}, {50, {line = 1, col = 6}}},
		"test diagnostic",
	)
	diagnostics.emit(
		.Test,
		{1, {50, {line = 5, col = 6}}, {50, {line = 11, col = 6}}},
		"test diagnostic",
	)
	d := diagnostics.emit(
		.Test,
		{1, {50, {line = 5, col = 2}}, {50, {line = 45, col = 15}}},
		"test diagnostic",
	)
	diagnostics.suggest(d, "eat my shorts")
	diagnostics.reference(
		d,
		{1, {50, {line = 5, col = 6}}, {50, {line = 5, col = 20}}},
		"other thing",
	)
	diagnostics.report_and_exit()


}
