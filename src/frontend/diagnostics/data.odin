package diagnostics

import "base:runtime"
import "core:fmt"
import "core:mem"

_current_diagnostics: [dynamic]Diagnostic
_msg_allocator: runtime.Allocator
_msg_arena: mem.Arena

DIAGNOSTIC_MSG_ARENA_SIZE_BYTES :: #config(DIAG_MSG_ARENA_KB, 300) * mem.Kilobyte

initialize :: proc() {
	fmt.register_user_formatter(Code, _format_code)
	mem.arena_init(&_msg_arena, make([]byte, DIAGNOSTIC_MSG_ARENA_SIZE_BYTES))
	_msg_allocator = mem.arena_allocator(&_msg_arena)
	_current_diagnostics = make([dynamic]Diagnostic, 0, 100)
}
