package common

import "core:container/xar"
import "core:fmt"
import "core:mem/virtual"
import "core:strings"

import "./exact"

initialize :: proc() {
	xar.array_init(&_sources)
	_sources_by_path = make(map[string]^Source_File)
	strings.intern_init(&ident_intern)
	err := virtual.arena_init_growing(&exact._bigint_arena)
	assert(err == nil)
	exact.bigint_allocator = virtual.arena_allocator(&exact._bigint_arena)
	fmt.register_user_formatter(exact.Rat, exact.fmt_rat)
	fmt.register_user_formatter(exact.Int, exact.fmt_int)
}
