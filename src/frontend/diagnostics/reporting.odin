package diagnostics

import "base:intrinsics"
import "core:encoding/json"
import "core:fmt"
import "core:io"
import "core:math"
import "core:mem"
import "core:os"
import "core:strings"
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
	span = (ansi.CSI + ansi.BOLD + ";" + ansi.FG_BRIGHT_YELLOW + ansi.SGR),
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
				_render_span(sf, diag.span)
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

CONTEXT_LINES :: 5
_render_span :: proc(sf: ^common.Source_File, span: common.Span) {
	_line_arena: mem.Dynamic_Arena
	mem.dynamic_arena_init(&_line_arena)
	defer mem.dynamic_arena_destroy(&_line_arena)
	context.temp_allocator = mem.dynamic_arena_allocator(&_line_arena)

	n_lines := 1 + span.end.line - span.start.line

	gutter_width := max(2, math.count_digits_of_base(span.end.line, 10)) + 1

	if n_lines == 1 {
		lines: [1]string
		common.get_source_lines(lines[:], sf, span.start.line)

		expanded := strings.expand_tabs(
			strings.trim_right_space(lines[0]),
			int(common.tab_width),
			context.temp_allocator,
		)
		trimmed := strings.trim_left_space(expanded)
		_render_gutter(span.start.line, gutter_width)
		fmt.eprintfln(" %s", trimmed)
		_render_gutter("", gutter_width)
		for _ in len(expanded) - len(trimmed) ..< int(span.start.col) {
			os.write_rune(os.stderr, ' ')
		}
		os.write_string(os.stderr, _report_theme.span)
		for _ in 0 ..< max(1, span.end.col - span.start.col) {
			os.write_rune(os.stderr, '^')
		}
		fmt.eprintln(_report_theme.clear)
	} else {
		//
	}
}

GUTTER_SEP :: '│'
_render_gutter :: proc(prefix: $T, width: int) where intrinsics.type_is_integer(T) || T == string {
	w := os.to_writer(os.stderr)
	io.write_string(w, _report_theme.gutter)

	when intrinsics.type_is_integer(T) {
		for _ in 0 ..< width - math.count_digits_of_base(prefix, 10) {
			io.write_rune(w, ' ')
		}
		io.write_int(w, int(prefix))
	} else {
		for _ in 0 ..< width - len(prefix) {
			io.write_rune(w, ' ')
		}
		io.write_string(w, prefix)
	}

	io.write_rune(w, GUTTER_SEP)

	io.write_string(w, _report_theme.clear)
}
