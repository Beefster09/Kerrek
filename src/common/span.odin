package common

import "base:intrinsics"
import "base:runtime"
import "core:fmt"
import "core:io"
import "core:unicode"
import "core:unicode/utf8"

Span :: struct {
	file:  Source_ID,
	start: Location,
	end:   Location,
}

Cursor :: struct {
	file:     Source_ID,
	using at: Location,
}

LINE_BITS :: 32 - COL_BITS
COL_BITS :: 10

MAX_LINE :: 1 << LINE_BITS - 1
MAX_COL :: 1 << COL_BITS - 1

Location :: struct {
	offset:         u32,
	using line_col: bit_field u32 {
		line: u32 | LINE_BITS,
		col:  u32 | COL_BITS,
	},
}
#assert(size_of(Location) == 8)

// determines how columns are counted on tabs; configurable at runtime
tab_width: u32 = 4

cursor_add :: proc {
	cursor_add_len,
	cursor_add_len_and_width,
}

cursor_to_span :: proc {
	cursor_to_span_len_same_line,
	cursor_to_span_len_and_width_same_line,
	cursor_to_span_other_span,
}

merge_spans :: proc "contextless" (a, b: Span) -> Span {
	return {
		file = a.file,
		start = {
			offset = min(a.start.offset, b.start.offset),
			line = min(a.start.line, b.start.line),
			col = min(a.start.col, b.start.col),
		},
		end = {
			offset = max(a.end.offset, b.end.offset),
			line = max(a.end.line, b.end.line),
			col = max(a.end.col, b.end.col),
		},
	}
}

collapse_span :: proc "contextless" (span: Span) -> Span {
	return {span.file, span.start, span.start}
}

collapse_span_to_end :: proc "contextless" (span: Span) -> Span {
	return {span.file, span.end, span.end}
}

cursor_advance :: proc(cursor: ^Cursor, src: string, advance_by: int) {
	for i in 0 ..< advance_by {
		switch c := src[i]; c {
		case '\n':
			cursor.col = 1
			cursor.line = min(cursor.line + 1, MAX_LINE)
		case '\t':
			width := tab_width - (cursor.col - 1) % tab_width
			cursor.col = min(cursor.col + width, MAX_COL)
		case 0 ..= 0x1f:
		// other ASCII control; no need to increment col
		case ' ' ..< utf8.LOCB:
			cursor.col = min(cursor.col + 1, MAX_COL)
		case utf8.LOCB ..= utf8.HICB:
		// continuation byte; no need to increment col
		case utf8.T2 ..< utf8.T5:
			r, n := utf8.decode_rune(src[i:])
			if n > 1 {
				width := u32(unicode.normalized_east_asian_width(r))
				cursor.col = min(cursor.col + width, MAX_COL)
			}
		}
	}
	cursor.offset += u32(advance_by)
}

cursor_add_len :: proc "contextless" (curs: Cursor, length: int) -> Cursor {
	return {
		file = curs.file,
		at = {
			offset = curs.at.offset + u32(length),
			line = curs.at.line,
			col = curs.at.col + u32(length),
		},
	}
}

cursor_add_len_and_width :: proc "contextless" (curs: Cursor, length: int, width: int) -> Cursor {
	return {
		file = curs.file,
		at = {
			offset = curs.at.offset + u32(length),
			line = curs.at.line,
			col = curs.at.col + u32(width),
		},
	}
}

cursor_to_span_len_same_line :: proc "contextless" (curs: Cursor, length: int) -> Span {
	if length >= 0 {
		return {
			file = curs.file,
			start = curs.at,
			end = {
				offset = curs.at.offset + u32(length),
				line = curs.at.line,
				col = curs.at.col + u32(length),
			},
		}
	} else {
		return {
			file = curs.file,
			start = {
				offset = curs.at.offset + u32(length),
				line = curs.at.line,
				col = curs.at.col + u32(length),
			},
			end = curs.at,
		}
	}
}

cursor_to_span_len_and_width_same_line :: proc "contextless" (
	curs: Cursor,
	length: int,
	width: int,
) -> Span {
	if length >= 0 {
		return {
			file = curs.file,
			start = curs.at,
			end = {
				offset = curs.at.offset + u32(length),
				line = curs.at.line,
				col = curs.at.col + u32(width),
			},
		}
	} else {
		return {
			file = curs.file,
			start = {
				offset = curs.at.offset + u32(length),
				line = curs.at.line,
				col = curs.at.col + u32(width),
			},
			end = curs.at,
		}
	}
}

cursor_to_span_other_span :: proc(a: Cursor, b: Cursor) -> Span {
	assert(a.file == b.file)
	if a.at.offset <= b.at.offset {
		return {file = a.file, start = a.at, end = b.at}
	} else {
		return {file = a.file, start = b.at, end = a.at}
	}
}

MAX_U16 :: 1 << 16 - 1

location_in_bounds :: proc "contextless" (loc: Location) -> bool {
	return loc.line > 0 && loc.line < MAX_LINE && loc.col > 0 && loc.col < MAX_COL
}

fmt_span :: proc(fi: ^fmt.Info, arg: any, verb: rune) -> bool {
	assert(arg.id == Span)

	show_file: bool
	file_only: bool
	brackets: bool
	show_start: bool
	show_end: bool

	switch verb {
	case 'v':
		fmt.fmt_struct(
			fi,
			arg,
			verb,
			// insane incantation to get the type info of the struct itself
			type_info_of(Span).variant.(runtime.Type_Info_Named).base.variant.(runtime.Type_Info_Struct),
			"Span",
		)
		return true

	case 's':
		show_file = true
		brackets = true
		show_start = true
		show_end = true

	case 'f':
		show_file = true
		file_only = true

	case 'b':
		show_file = true
		brackets = true
		show_start = true
		show_end = false

	case 'e':
		show_file = true
		brackets = true
		show_start = false
		show_end = true

	case 'd', 'i':
		show_file = false
		brackets = false
		show_start = true
		show_end = true

	case 'a':
		show_file = false
		brackets = false
		show_start = true
		show_end = false

	case 'z':
		show_file = false
		brackets = false
		show_start = false
		show_end = true

	case:
		return false
	}

	span := cast(^Span)arg.data

	if show_file {
		sf, _ := load_source(span.file)
		if sf != nil {
			io.write_string(fi.writer, sf.file)
		} else {
			io.write_string(fi.writer, "<unknown file>")
		}
	}

	if file_only {
		return true
	}

	if brackets {
		io.write_rune(fi.writer, '[')
	}
	if show_start {
		if span.start.line > 0 && span.start.line < MAX_LINE {
			io.write_uint(fi.writer, uint(span.start.line))
		} else {
			io.write_string(fi.writer, "???")
		}
		if span.start.col > 0 && span.start.col < MAX_COL {
			io.write_rune(fi.writer, ':')
			io.write_uint(fi.writer, uint(span.start.col))
		}
	}
	if span.end != span.start {
		if show_start && show_end {
			io.write_string(fi.writer, " .. ")
		}

		if span.end.line > 0 && span.end.line < MAX_LINE {
			io.write_uint(fi.writer, uint(span.end.line))
		} else {
			io.write_string(fi.writer, "???")
		}
		if span.end.col > 0 && span.end.col < MAX_COL {
			io.write_rune(fi.writer, ':')
			io.write_uint(fi.writer, uint(span.end.col))
		}
	}
	if brackets {
		io.write_rune(fi.writer, ']')
	}

	return true
}

fmt_cursor :: proc(fi: ^fmt.Info, arg: any, verb: rune) -> bool {
	assert(arg.id == Cursor)
	cursor := cast(^Cursor)arg.data
	switch verb {
	case 'v':
		fmt.fmt_struct(
			fi,
			arg,
			verb,
			// insane incantation to get the type info of the struct itself
			type_info_of(Cursor).variant.(runtime.Type_Info_Named).base.variant.(runtime.Type_Info_Struct),
			"Cursor",
		)
		return true
	}
	return false
}
