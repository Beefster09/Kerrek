package diagnostics

import "base:runtime"
import "core:encoding/json"
import "core:fmt"
import "core:mem"

_current_diagnostics: [dynamic]Diagnostic
_msg_allocator: runtime.Allocator
_msg_arena: mem.Dynamic_Arena

initialize :: proc() {
	fmt.register_user_formatter(Kind, _fmt_kind)
	mem.dynamic_arena_init(&_msg_arena)
	_msg_allocator = mem.dynamic_arena_allocator(&_msg_arena)
	_current_diagnostics = make([dynamic]Diagnostic, 0, 100)

	json.register_user_marshaler(Kind, _marshal_kind)
	json.register_user_marshaler(Level, _marshal_level)
}
