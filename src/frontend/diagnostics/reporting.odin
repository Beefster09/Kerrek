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
import "core:unicode"

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
	levels:     [Level]string, // the color of the level and error code of each diagnostic
	message:    string, // the base message
	location:   string, // the file path + numeric span
	gutter:     string, // the line number gutter for showing files
	span:       string, // the color of the pointer of the span
	addendum:   string, // each addendum message
	suggestion: string, // the color of 'suggestion' in suggestion addendum messages
	reference:  string, // the color of 'note' in reference addendum messages
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
	addendum = (ansi.CSI + ansi.FG_DEFAULT + ansi.SGR),
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
	addendum = (ansi.CSI + ansi.FG_DEFAULT + ansi.SGR),
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

				for addendum in diag.extra {
					switch a in addendum {
					case Suggestion:
						fmt.eprintfln(
							"\t%ssuggestion%s: %s%s%s",
							_report_theme.suggestion,
							_report_theme.clear,
							_report_theme.addendum,
							a,
							_report_theme.clear,
						)
					case Reference:
						fmt.eprintfln(
							"\t%snote%s: %s%s%s",
							_report_theme.reference,
							_report_theme.clear,
							_report_theme.addendum,
							a.message,
							_report_theme.clear,
						)
						ref_sf, _ := common.load_source(a.span.file)
						if ref_sf != nil {
							fmt.eprintfln(
								"\t\t%s@ %s%s",
								_report_theme.location,
								diag.span,
								_report_theme.clear,
							)
							_render_span(ref_sf, a.span)
						}
					}
				}
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

MULTILINE_SPAN_TOP :: '╭'
MULTILINE_SPAN_MIDDLE :: '│'
MULTILINE_SPAN_BOTTOM :: '╰'
MULTILINE_SPAN_TOP_RUNNER :: '╴'
MULTILINE_SPAN_TOP_POINTER :: "┰──┄┄>"
MULTILINE_SPAN_BOTTOM_RUNNER :: '─'
MULTILINE_SPAN_BOTTOM_POINTER :: "┚"

SINGLE_LINE_SPAN_POINTER :: '^'

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
		_render_gutter(' ', gutter_width)
		for _ in len(expanded) - len(trimmed) ..< int(span.start.col) {
			os.write_rune(os.stderr, ' ')
		}
		os.write_string(os.stderr, _report_theme.span)
		for _ in 0 ..< max(1, span.end.col - span.start.col) {
			os.write_rune(os.stderr, '^')
		}
		fmt.eprintln(_report_theme.clear)
	} else {
		lines: [CONTEXT_LINES * 2 + 1]string
		n_lines_snipped := max(int(n_lines) - len(lines), 0)
		if n_lines_snipped == 0 {
			common.get_source_lines(lines[:n_lines], sf, span.start.line)
		} else {
			common.get_source_lines(lines[:CONTEXT_LINES], sf, span.start.line)
			common.get_source_lines(
				lines[CONTEXT_LINES + 1:],
				sf,
				span.end.line - CONTEXT_LINES + 1,
			)
		}

		l := min(n_lines, len(lines))
		min_indent := 999_999_999_999
		for i in 0 ..< l {
			expanded := strings.expand_tabs(
				strings.trim_right_space(lines[i]),
				int(common.tab_width),
				context.temp_allocator,
			)
			lines[i] = expanded
			leading_space := -1
			for c, i in expanded {
				if c != ' ' {
					leading_space = i
					break
				}
			}

			if leading_space >= 0 && leading_space < min_indent {
				min_indent = leading_space
			}
		}

		w := os.to_writer(os.stderr)

		_render_gutter(' ', gutter_width)

		io.write_string(w, _report_theme.span)
		io.write_rune(w, MULTILINE_SPAN_TOP)
		for _ in 1 ..< span.start.col {
			io.write_rune(w, MULTILINE_SPAN_TOP_RUNNER)
		}
		io.write_rune(w, MULTILINE_SPAN_TOP_RUNNER)
		io.write_string(w, MULTILINE_SPAN_TOP_POINTER)
		fmt.eprintln(_report_theme.clear)

		for i in 0 ..< l {
			trimmed: string
			if n_lines_snipped > 0 && i == CONTEXT_LINES {
				_render_gutter('⋮', gutter_width)
				trimmed = "\\\\ ... snipped ..."
			} else {
				line_no := span.start.line + i
				if i > CONTEXT_LINES {
					line_no += u32(n_lines_snipped)
				}
				_render_gutter(line_no, gutter_width)
				trimmed = lines[i][min_indent:] if len(lines[i]) > min_indent else ""
			}

			fmt.eprintfln(
				"%s%c%s %s",
				_report_theme.span,
				MULTILINE_SPAN_MIDDLE,
				_report_theme.clear,
				trimmed,
			)
		}

		_render_gutter(' ', gutter_width)
		io.write_string(w, _report_theme.span)
		io.write_rune(w, MULTILINE_SPAN_BOTTOM)
		for _ in 1 ..< span.end.col {
			io.write_rune(w, MULTILINE_SPAN_BOTTOM_RUNNER)
		}
		io.write_rune(w, MULTILINE_SPAN_BOTTOM_RUNNER)
		io.write_string(w, MULTILINE_SPAN_BOTTOM_POINTER)
		fmt.eprintln(_report_theme.clear)
	}
}

GUTTER_SEP :: '║'
_render_gutter :: proc(prefix: $T, width: int) where intrinsics.type_is_integer(T) || T == rune {
	w := os.to_writer(os.stderr)
	io.write_string(w, _report_theme.gutter)

	when T == rune {
		for _ in 0 ..< width - unicode.normalized_east_asian_width(prefix) {
			io.write_rune(w, ' ')
		}
		io.write_rune(w, prefix)
	} else {
		for _ in 0 ..< width - math.count_digits_of_base(prefix, 10) {
			io.write_rune(w, ' ')
		}
		io.write_int(w, int(prefix))
	}

	io.write_rune(w, GUTTER_SEP)

	io.write_string(w, _report_theme.clear)
}
