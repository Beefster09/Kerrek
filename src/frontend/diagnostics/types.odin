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
	Resolver,
	TypeCheck,
	UnitCheck,
	FactCheck,
	CapCheck,
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
	code:    Kind,
	message: string,
	span:    common.Span,
	extra:   [dynamic]Addendum `json:",omitempty"`,
}

Diagnostic_Metadata :: struct {
	origin:        Origin,
	category:      Category,
	default_level: Level,
	code:          string,
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
