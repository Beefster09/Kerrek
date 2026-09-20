package diagnostics

import "base:runtime"
import "core:encoding/json"
import "core:io"

import "../../common"

Level :: enum u8 {
	Notice  = 0,
	Warning = 1,
	Error   = 2,
}

Origin :: enum u8 {
	Unknown = 0,
	Lexer,
	Parser,
	Resolution,
	Semantic,
}

Category :: enum u8 {
	General = 0,
	Unused,
	Deprecated,
	Dubious,
	Performance,
	Portability,
	Style,
}

Diagnostic :: struct {
	level:   Level,
	code:    Code,
	message: string,
	span:    common.Span,
	extra:   [dynamic]Addendum `json:",omitempty"`,
}

Addendum :: union {
	Suggestion,
	Reference,
}

Suggestion :: distinct string

Reference :: struct {
	message: string,
	span:    common.Span,
}

_marshal_level :: proc(w: io.Stream, v: any, opt: ^json.Marshal_Options) -> json.Marshal_Error {
	assert(v.id == Level)
	level := (cast(^Level)v.data)^
	return json.marshal_to_writer(w, LEVEL_STRINGS[level], opt)
}
