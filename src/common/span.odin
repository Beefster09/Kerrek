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

Location :: struct {
	offset: u32,
	line:   u16,
	col:    u16,
}

tab_width: u16 = #config(DEFAULT_TAB_WIDTH, 4) // determines how col is counted with tabs; configurable at runtime

cursor_add :: proc {
	cursor_add_len,
	cursor_add_len_and_width,
}

cursor_to_span :: proc {
	cursor_to_span_len_same_line,
	cursor_to_span_len_and_width_same_line,
	cursor_to_span_other_span,
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
			cursor.line = intrinsics.saturating_add(cursor.line, 1)
		case '\t':
			cursor.col = intrinsics.saturating_add(
				cursor.col,
				tab_width - (cursor.col - 1) % tab_width,
			)
		case 0 ..= 0x1f:
		// other ASCII control; no need to increment col
		case ' ' ..< utf8.LOCB:
			cursor.col = intrinsics.saturating_add(cursor.col, 1)
		case utf8.LOCB ..= utf8.HICB:
		// continuation byte; no need to increment col
		case utf8.T2 ..< utf8.T5:
			r, n := utf8.decode_rune(src[i:])
			if n > 1 {
				cursor.col = intrinsics.saturating_add(
					cursor.col,
					u16(unicode.normalized_east_asian_width(r)),
				)
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
			col = curs.at.col + u16(length),
		},
	}
}

cursor_add_len_and_width :: proc "contextless" (curs: Cursor, length: int, width: int) -> Cursor {
	return {
		file = curs.file,
		at = {
			offset = curs.at.offset + u32(length),
			line = curs.at.line,
			col = curs.at.col + u16(width),
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
				col = curs.at.col + u16(length),
			},
		}
	} else {
		return {
			file = curs.file,
			start = {
				offset = curs.at.offset + u32(length),
				line = curs.at.line,
				col = curs.at.col + u16(length),
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
				col = curs.at.col + u16(width),
			},
		}
	} else {
		return {
			file = curs.file,
			start = {
				offset = curs.at.offset + u32(length),
				line = curs.at.line,
				col = curs.at.col + u16(width),
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
	return loc.line > 0 && loc.line < MAX_U16 && loc.col > 0 && loc.col < MAX_U16
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
		if location_in_bounds(span.start) {
			io.write_uint(fi.writer, uint(span.start.line))
			io.write_rune(fi.writer, ':')
			io.write_uint(fi.writer, uint(span.start.col))
		} else {
			io.write_string(fi.writer, "???")
		}
	}
	if show_start && show_end {
		io.write_string(fi.writer, " .. ")
	}
	if show_end {
		if location_in_bounds(span.end) {
			io.write_uint(fi.writer, uint(span.end.line))
			io.write_rune(fi.writer, ':')
			io.write_uint(fi.writer, uint(span.end.col))
		} else {
			io.write_string(fi.writer, "???")
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
