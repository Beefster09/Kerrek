package main

import "core:fmt"
import "core:mem"

import "frontend/diagnostics"

_user_formatters: map[typeid]fmt.User_Formatter

main :: proc() {
	_user_formatters = make(map[typeid]fmt.User_Formatter)
	fmt.set_user_formatters(&_user_formatters)
	diagnostics.initialize()

	fmt.printfln(
		"testing the diagnostic code formatter: %s %q %v",
		diagnostics.Code{'E', 5},
		diagnostics.Code{'P', 001},
		diagnostics.Code{'L', 321},
	)
}
