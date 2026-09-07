package common

import "core:container/xar"
import "core:encoding/json"
import "core:fmt"
import "core:mem"
import "core:strings"

import "./exact"

initialize :: proc() {
	xar.array_init(&_sources)
	_sources_by_path = make(map[string]^Source_File)

	mem.dynamic_arena_init(&_intern_arena, block_size = 64 * mem.Kilobyte)
	strings.intern_init(&ident_intern, allocator = mem.dynamic_arena_allocator(&_intern_arena))

	mem.dynamic_arena_init(&exact._bigint_arena, block_size = 8 * mem.Kilobyte)
	exact.bigint_allocator = mem.dynamic_arena_allocator(&exact._bigint_arena)

	fmt.register_user_formatter(exact.Rat, exact.fmt_rat)
	fmt.register_user_formatter(exact.Int, exact.fmt_int)
	fmt.register_user_formatter(Span, fmt_span)
	fmt.register_user_formatter(Cursor, fmt_cursor)

	json.register_user_marshaler(Cursor, marshal_source_id)
}
