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

Color_Scheme :: struct {
	error:      string,
	warning:    string,
	notice:     string,
	gutter:     string,
	span:       string,
	suggestion: string,
	reference:  string,
	clear:      string,
}

THEME_3BIT :: Color_Scheme {
	error      = ansi.CSI + ansi.FG_RED + ansi.SGR,
	warning    = ansi.CSI + ansi.FG_YELLOW + ansi.SGR,
	notice     = ansi.CSI + ansi.FG_CYAN + ansi.SGR,
	gutter     = ansi.CSI + ansi.FG_BLUE + ansi.SGR,
	span       = ansi.CSI + ansi.FG_YELLOW + ansi.SGR,
	suggestion = ansi.CSI + ansi.FG_GREEN + ansi.SGR,
	reference  = ansi.CSI + ansi.FG_MAGENTA + ansi.SGR,
	clear      = ansi.CSI + ansi.RESET + ansi.SGR,
}

THEME_4BIT :: Color_Scheme {
	error      = ansi.CSI + ansi.FG_BRIGHT_RED + ansi.SGR,
	warning    = ansi.CSI + ansi.FG_YELLOW + ansi.SGR,
	notice     = ansi.CSI + ansi.FG_CYAN + ansi.SGR,
	gutter     = ansi.CSI + ansi.FG_BLUE + ansi.SGR,
	span       = ansi.CSI + ansi.FG_BRIGHT_YELLOW + ansi.SGR,
	suggestion = ansi.CSI + ansi.FG_BRIGHT_GREEN + ansi.SGR,
	reference  = ansi.CSI + ansi.FG_BRIGHT_MAGENTA + ansi.SGR,
	clear      = ansi.CSI + ansi.RESET + ansi.SGR,
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
			_report_theme = THEME_3BIT
		case .Four_Bit, .Eight_Bit, .True_Color:
			_report_theme = THEME_4BIT
		}
	}
}

report_and_exit :: proc() {
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

	if err_count > 0 {
		if warn_count > 0 {
			fmt.eprintfln(
				"%sencountered %d error%s and %d warning%s%s",
				_report_theme.error,
				err_count,
				"s" if err_count != 1 else "",
				warn_count,
				"s" if warn_count != 1 else "",
				_report_theme.clear,
			)
		} else {
			fmt.eprintfln(
				"%sencountered %d error%s%s",
				_report_theme.error,
				err_count,
				"s" if err_count != 1 else "",
				_report_theme.clear,
			)
		}
		os.exit(1)
	} else if warn_count > 0 {
		fmt.eprintfln(
			"%sencountered %d warning%s%s",
			_report_theme.warning,
			warn_count,
			"s" if warn_count != 1 else "",
			_report_theme.clear,
		)
	}
}

_report_pretty :: proc() {
	_report_simple()
}

_report_simple :: proc() {
	for diag in _current_diagnostics {
		fmt.eprintfln("%s[%s]: %s", diag.level, diag.code, diag.message)
		if diag.span.file != 0 {
			sf, _ := common.load_source(diag.span.file)
			if sf != nil {
				fmt.eprintfln(
					"\t(in %s, line %d, column %d)",
					sf.file,
					diag.span.start.row,
					diag.span.start.col,
				)
			}
		}
	}
}

_report_json :: proc() {
	// IMPORTANT: json diagnostic reports reports go to stdout
	// as such, this is not allowed if the backend output is directed to stdout
	json.marshal_to_writer(os.to_writer(os.stdout), _current_diagnostics, nil)
}
