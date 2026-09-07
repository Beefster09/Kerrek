package main

import "core:encoding/json"
import "core:flags"
import "core:fmt"
import "core:os"

import "common"
import "frontend/diagnostics"
import "frontend/units"

_user_formatters: map[typeid]fmt.User_Formatter
_json_marshalers: map[typeid]json.User_Marshaler

main :: proc() {
	_user_formatters = make(map[typeid]fmt.User_Formatter)
	fmt.set_user_formatters(&_user_formatters)
	_json_marshalers = make(map[typeid]json.User_Marshaler)
	json.set_user_marshalers(&_json_marshalers)

	common.initialize()
	diagnostics.initialize()
	units.initialize()

	cmd := os.args[1] if len(os.args) >= 2 else ""

	switch cmd {
	case "build":
		_cmd_build(os.args[1:])
	case "":
		fmt.eprintln("no subcommand given")
		_print_usage()
		os.exit(1)
	case:
		fmt.eprintln("invalid subcommand:", cmd)
		_print_usage()
		os.exit(1)
	}
}


_cmd_build :: proc(args: []string) {
	config: struct {
		entry_point: string `args:"name=main-file,pos=0,required" usage:"a Kerrek source file containing func main()"`,
		backend:     string `usage:"which backend to use for output"`,
		diag_format: string `args:"name=diag-fmt" usage:"the diagnostic printing format ('pretty', 'simple', or 'json')"`,
	}

	flags.parse_or_exit(&config, args, allocator = context.temp_allocator)

	entry_point, os_err := os.get_absolute_path(config.entry_point, context.allocator)
	if os_err != nil {
		fmt.eprintln("invalid entry_point:", config.entry_point, os_err)
		os.exit(1)
	}

	if config.backend == "" {
		config.backend = "c99"
	}

	diag_cfg: diagnostics.Report_Config

	switch config.diag_format {
	case "pretty":
		diag_cfg.format = .Pretty
	case "simple":
		diag_cfg.format = .Simple
	case "json":
		diag_cfg.format = .JSON
	}

	diagnostics.configure_reporting(diag_cfg)

	build(entry_point)
}

_print_usage :: proc() {}
