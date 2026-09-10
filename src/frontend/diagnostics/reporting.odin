package diagnostics

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:terminal"
import "core:terminal/ansi"

import "../../common"


Report_Format :: enum {
	Simple,
	Pretty,
	JSON,
}

Report_Config :: struct {
	format: Maybe(Report_Format),
	color:  Maybe(bool),
}

_report_format: Report_Format
_report_theme: Color_Scheme

Color_Scheme :: struct #all_or_none {
	levels:     [Level]string,
	message:    string,
	location:   string,
	gutter:     string,
	span:       string,
	suggestion: string,
	reference:  string,
	clear:      string,
}

@(rodata)
DEFAULT_THEME_3BIT := Color_Scheme {
	levels = {
		.Error = ansi.CSI + ansi.FG_RED + ansi.SGR,
		.Warning = ansi.CSI + ansi.FG_YELLOW + ansi.SGR,
		.Notice = ansi.CSI + ansi.FG_CYAN + ansi.SGR,
	},
	message = (ansi.CSI + ansi.FG_DEFAULT + ansi.SGR),
	location = (ansi.CSI + ansi.FG_DEFAULT + ansi.SGR),
	gutter = (ansi.CSI + ansi.FG_BLUE + ansi.SGR),
	span = (ansi.CSI + ansi.FG_YELLOW + ansi.SGR),
	suggestion = (ansi.CSI + ansi.FG_GREEN + ansi.SGR),
	reference = (ansi.CSI + ansi.FG_MAGENTA + ansi.SGR),
	clear = (ansi.CSI + ansi.RESET + ansi.SGR),
}

@(rodata)
DEFAULT_THEME_4BIT := Color_Scheme {
	levels = {
		.Error = ansi.CSI + ansi.FG_BRIGHT_RED + ansi.SGR,
		.Warning = ansi.CSI + ansi.FG_YELLOW + ansi.SGR,
		.Notice = ansi.CSI + ansi.FG_CYAN + ansi.SGR,
	},
	message = (ansi.CSI + ansi.BOLD + ";" + ansi.FG_DEFAULT + ansi.SGR),
	location = (ansi.CSI + ansi.FAINT + ";" + ansi.FG_DEFAULT + ansi.SGR),
	gutter = (ansi.CSI + ansi.FG_BLUE + ansi.SGR),
	span = (ansi.CSI + ansi.FG_BRIGHT_YELLOW + ansi.SGR),
	suggestion = (ansi.CSI + ansi.FG_BRIGHT_GREEN + ansi.SGR),
	reference = (ansi.CSI + ansi.FG_BRIGHT_MAGENTA + ansi.SGR),
	clear = (ansi.CSI + ansi.RESET + ansi.SGR),
}

@(rodata)
LEVEL_STRINGS := [Level]string {
	.Notice  = "notice",
	.Warning = "warning",
	.Error   = "error",
}


configure_reporting :: proc(conf: Report_Config) {
	stderr_is_tty := os.is_tty(os.stderr)

	if conf.format != nil {
		_report_format = conf.format.?
	} else {
		_report_format = .Pretty if stderr_is_tty else .Simple
	}

	color_enabled: bool
	if conf.color != nil {
		color_enabled = conf.color.?
	} else {
		color_enabled = terminal.color_enabled && _report_format == .Pretty
	}

	if color_enabled {
		switch terminal.color_depth {
		case .None:
		case .Three_Bit:
			_report_theme = DEFAULT_THEME_3BIT
		case .Four_Bit, .Eight_Bit, .True_Color:
			_report_theme = DEFAULT_THEME_4BIT
		}
	}
}

EXIT_REPORT_ERRORS :: 1

report_and_exit :: proc() {
	defer free_all(_msg_allocator)
	defer clear(&_current_diagnostics)

	switch _report_format {
	case .Simple:
		_report_simple()
	case .Pretty:
		_report_pretty()
	case .JSON:
		_report_json()
	}

	err_count := 0
	warn_count := 0
	for diag in _current_diagnostics {
		#partial switch diag.level {
		case .Error:
			err_count += 1
		case .Warning:
			warn_count += 1
		}
	}

	if _report_format == .JSON && err_count > 0 {
		os.exit(EXIT_REPORT_ERRORS)
	}

	if err_count > 0 {
		if warn_count > 0 {
			fmt.eprintfln(
				"%sencountered %d error%s and %d warning%s%s",
				_report_theme.levels[.Error],
				err_count,
				"s" if err_count != 1 else "",
				warn_count,
				"s" if warn_count != 1 else "",
				_report_theme.clear,
			)
		} else {
			fmt.eprintfln(
				"%sencountered %d error%s%s",
				_report_theme.levels[.Error],
				err_count,
				"s" if err_count != 1 else "",
				_report_theme.clear,
			)
		}
		os.exit(EXIT_REPORT_ERRORS)
	} else if warn_count > 0 {
		fmt.eprintfln(
			"%sencountered %d warning%s%s",
			_report_theme.levels[.Warning],
			warn_count,
			"s" if warn_count != 1 else "",
			_report_theme.clear,
		)
	}
}

_report_pretty :: proc() {
	for diag in _current_diagnostics {
		fmt.eprintfln(
			"%s%s (%s)%s: %s%s%s",
			_report_theme.levels[diag.level],
			LEVEL_STRINGS[diag.level],
			diag.code,
			_report_theme.clear,
			_report_theme.message,
			diag.message,
			_report_theme.clear,
		)
		if diag.span.file != 0 {
			sf, _ := common.load_source(diag.span.file)
			if sf != nil {
				fmt.eprintfln("\t%s@ %s%s", _report_theme.location, diag.span, _report_theme.clear)
			}
		}
	}
}

_report_simple :: proc() {
	for diag in _current_diagnostics {
		fmt.eprintfln("%s (%s): %s", LEVEL_STRINGS[diag.level], diag.code, diag.message)
		if diag.span.file != 0 {
			fmt.eprintfln("\t@ %b", diag.span)
		}
	}
}

_report_json :: proc() {
	// IMPORTANT: json diagnostic reports reports go to *stdout*
	// as such, this should not be allowed if the backend output is directed to stdout
	json_opts := json.Marshal_Options {
		use_enum_names = true,
	}
	json.marshal_to_writer(os.to_writer(os.stdout), _current_diagnostics, &json_opts)
	fmt.println()
}
