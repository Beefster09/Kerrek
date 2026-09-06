package diagnostics

import "base:runtime"
import "core:encoding/json"
import "core:fmt"
import "core:mem"

_current_diagnostics: [dynamic]Diagnostic
_msg_allocator: runtime.Allocator
_msg_arena: mem.Arena

DIAGNOSTIC_MSG_ARENA_SIZE_BYTES :: #config(DIAG_MSG_ARENA_KB, 300) * mem.Kilobyte

initialize :: proc() {
	fmt.register_user_formatter(Kind, _fmt_kind)
	mem.arena_init(&_msg_arena, make([]byte, DIAGNOSTIC_MSG_ARENA_SIZE_BYTES))
	_msg_allocator = mem.arena_allocator(&_msg_arena)
	_current_diagnostics = make([dynamic]Diagnostic, 0, 100)

	json.register_user_marshaler(Kind, _marshal_kind)
	json.register_user_marshaler(Level, _marshal_level)
}
