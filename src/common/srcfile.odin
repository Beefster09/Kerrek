package common

import "core:container/xar"
import "core:io"
import "core:os"
import "core:strings"
import "core:sync"


Source_ID :: distinct u32
Source_File :: struct {
	id:           Source_ID,
	file:         string, // location of file; owned
	contents:     []u8, // contents of file; owned, may be purged when not in use
	line_offsets: [dynamic]u32, // offsets where the beginning of each line is; owned
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
_source_lock: sync.Mutex

load_source_from_path :: proc(file: string) -> (sfptr: ^Source_File, ret_err: Load_Source_Error) {
	sync.lock(&_source_lock)
	defer sync.unlock(&_source_lock)

	if sfptr, ok := _sources_by_path[file]; ok {
		return sfptr, .OK
	}
	sf: Source_File
	os_err: os.Error

	sf.contents, os_err = os.read_entire_file(file, context.allocator)
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
		delete(sf.contents)
	}

	sf.id = _next_id
	sf.file = strings.clone(file)

	defer if ret_err != .OK {
		delete(sf.file)
	}

	_, xar_err := xar.append(&_sources, sf)
	assert(xar_err == nil)

	sfptr = xar.get_ptr(&_sources, xar.len(_sources) - 1)

	_next_id += 1
	_sources_by_path[sf.file] = sfptr

	return sfptr, .OK
}

load_source_by_id :: proc(id: Source_ID) -> (^Source_File, Load_Source_Error) {
	sync.lock(&_source_lock)
	defer sync.unlock(&_source_lock)

	iterator := xar.iterator(&_sources)
	for sf, _ in xar.iterate_by_ptr(&iterator) {
		if sf.id == id {

			if sf.contents == nil {
				os_err: os.Error
				sf.contents, os_err = os.read_entire_file(sf.file, context.allocator)
				if os_err != nil {
					return nil, .Cannot_Read
				}
			}
			return sf, .OK
		}
	}

	return nil, .Not_Found
}

initialize :: proc() {
	xar.array_init(&_sources)
	_sources_by_path = make(map[string]^Source_File)
}
