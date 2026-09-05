package common


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

cursor_add_len :: proc(curs: Cursor, length: int) -> Cursor {
	return {
		file = curs.file,
		at = {
			offset = curs.at.offset + u32(length),
			line = curs.at.line,
			col = curs.at.col + u16(length),
		},
	}
}

cursor_add_len_and_width :: proc(curs: Cursor, length: int, width: int) -> Cursor {
	return {
		file = curs.file,
		at = {
			offset = curs.at.offset + u32(length),
			line = curs.at.line,
			col = curs.at.col + u16(width),
		},
	}
}

cursor_to_span_len_same_line :: proc(curs: Cursor, length: int) -> Span {
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

cursor_to_span_len_and_width_same_line :: proc(curs: Cursor, length: int, width: int) -> Span {
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
