package common

import "core:container/xar"
import "core:encoding/json"
import "core:io"
import "core:os"
import "core:strings"
import "core:sync"


Source_ID :: distinct u32
Source_File :: struct {
	id:              Source_ID,
	file:            string, // location of file; owned
	contents:        []u8, // contents of file; owned, may be purged when not in use
	newline_offsets: []u32, // offsets where each newline character is; owned, treat as immutable after initialization
	_lock:           sync.Mutex, // protects contents from being loaded twice by race condition
}
Load_Source_Error :: enum {
	OK,
	Not_Found,
	Cannot_Read,
	Other_Error,
}

load_source :: proc {
	load_source_from_path,
	load_source_by_id,
}

_next_id: Source_ID = 1
_sources: xar.Array(Source_File, 4)
_sources_by_path: map[string]^Source_File
_source_lock: sync.Mutex // protects the above three globals


AVG_CHARS_PER_LINE :: 15 // very conservative estimate of number of characters per source line

load_source_from_path :: proc(file: string) -> (sf: ^Source_File, ret_err: Load_Source_Error) {
	sync.lock(&_source_lock)
	defer sync.unlock(&_source_lock)

	if sf, ok := _sources_by_path[file]; ok {
		return sf, .OK
	}

	contents, os_err := os.read_entire_file(file, context.allocator)
	if os_err != nil {
		#partial switch sub_err in os_err {
		case os.General_Error:
			if sub_err == .Not_Exist {
				return nil, .Not_Found
			}
		case io.Error:
			return nil, .Cannot_Read
		}
		return nil, .Other_Error
	}

	defer if ret_err != .OK {
		delete(contents)
	}

	line_offsets := make([dynamic]u32, 0, len(contents) / AVG_CHARS_PER_LINE + 16)
	for c, i in contents {
		if c == '\n' {
			append(&line_offsets, u32(i))
		}
	}

	shrink(&line_offsets)

	_, xar_err := xar.append(
		&_sources,
		Source_File {
			id = _next_id,
			file = strings.clone(file),
			contents = contents,
			newline_offsets = line_offsets[:],
		},
	)
	assert(xar_err == nil)

	sf = xar.get_ptr(&_sources, xar.len(_sources) - 1)

	_next_id += 1
	_sources_by_path[sf.file] = sf

	return sf, .OK
}

load_source_by_id :: proc(id: Source_ID) -> (^Source_File, Load_Source_Error) {
	sync.lock(&_source_lock)
	defer sync.unlock(&_source_lock)

	// this uses a dumb linear search
	// I *should* be able to index into id - 1 and always get the source,
	// but I don't want to assume that just yet (and probably don't need to)
	// because this is only actually needed for diagnostic printing

	iterator := xar.iterator(&_sources)
	for sf, _ in xar.iterate_by_ptr(&iterator) {
		if sf.id == id {
			if !_ensure_contents_loaded(sf) {
				return nil, .Cannot_Read
			}
			return sf, .OK
		}
	}

	return nil, .Not_Found
}

_ensure_contents_loaded :: proc(sf: ^Source_File) -> bool {
	sync.lock(&sf._lock)
	defer sync.unlock(&sf._lock)

	if sf.contents == nil {
		os_err: os.Error
		sf.contents, os_err = os.read_entire_file(sf.file, context.allocator)
		if os_err != nil {
			return false
		}
	}
	return true
}

unload_source :: proc(sf: ^Source_File) {
	sync.lock(&_source_lock)
	defer sync.unlock(&_source_lock)
	sync.lock(&sf._lock)
	defer sync.unlock(&sf._lock)

	delete(sf.contents)
	sf.contents = nil
	// CONSIDER: put the file contents in a free list to be freed later
}

// get the lines of the source file starting at first_line and loading at most len(dest) lines
// returns the number of lines actually loaded
get_source_lines :: proc(dest: []string, sf: ^Source_File, #any_int first_line: int) -> int {
	if first_line <= 0 {
		return 0 // this is incorrect usage
	}
	if !_ensure_contents_loaded(sf) {
		return 0
	}

	zero_indexed_first_line := first_line - 1
	for i in 0 ..< len(dest) {
		j := zero_indexed_first_line + i
		if j >= len(sf.newline_offsets) {
			return i
		}

		// the line goes from right after the previous newline to the current newline
		start := 0 if j - 1 < 0 else sf.newline_offsets[j - 1] + 1
		end := sf.newline_offsets[j]

		dest[i] = transmute(string)sf.contents[start:end]
	}
	return len(dest)
}


marshal_source_id :: proc(w: io.Stream, v: any, opt: ^json.Marshal_Options) -> json.Marshal_Error {
	assert(v.id == Source_ID)
	sf, err := load_source_by_id((cast(^Source_ID)v.data)^)
	if err != nil {
		return json.Marshal_Data_Error.Unsupported_Type // not really the right thing to return but it'll do
	}
	return json.marshal_to_writer(w, sf.file, opt)
}
