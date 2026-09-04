package common

import "core:container/xar"
import "core:os"


Source_File :: struct {
	id:           Source_ID,
	path:         string,
	contents:     []u8,
	line_offsets: [dynamic]u32,
}

_next_id: Source_ID = 1
_sources: xar.Array(Source_File, 4)

load_source :: proc(file: string) -> (^Source_File, bool) {
	sf: Source_File
	os_err: os.Error
	sf.contents, os_err = os.read_entire_file(file, context.allocator)
	if os_err != nil {
		return nil, false // TODO? inspect the error
	}

	sf.id = _next_id
	_next_id += 1

	n, err := xar.append(&_sources, sf)
	if err != nil {
		return nil, false
	}

	return xar.get_ptr(&_sources, sf.id - 1), true
}

initialize :: proc() {
	xar.array_init(&_sources)
}
