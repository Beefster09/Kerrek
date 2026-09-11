package diagnostics

import "core:encoding/json"
import "core:fmt"
import "core:io"


Kind :: enum {
	// Lexer diagnostics
	Invalid_Number_Literal,
	Invalid_Escape,
	Empty_Rune,
	Unclosed_Rune,
	Unclosed_String,
	Dubious_Punctuation,
	// Parser diagnostics
	Syntax_Error,
	Empty_Statement,
}

@(rodata)
CODE_METADATA := [Kind]Diagnostic_Metadata {
	.Invalid_Number_Literal = {origin = .Lexer, default_level = .Error, code = "L01"},
	.Invalid_Escape = {origin = .Lexer, default_level = .Error, code = "L10"},
	.Empty_Rune = {origin = .Lexer, default_level = .Error, code = "L11"},
	.Unclosed_Rune = {origin = .Lexer, default_level = .Error, code = "L12"},
	.Unclosed_String = {origin = .Lexer, default_level = .Error, code = "L13"},
	.Dubious_Punctuation = {
		origin = .Lexer,
		category = .Dubious,
		default_level = .Warning,
		code = "L20",
	},
	.Syntax_Error = {origin = .Parser, default_level = .Error, code = "P00"},
	.Empty_Statement = {origin = .Parser, default_level = .Notice, code = "P10"},
}


_fmt_kind :: proc(fi: ^fmt.Info, arg: any, verb: rune) -> bool {
	assert(arg.id == Kind)
	switch verb {
	case 'v':
		fmt.fmt_enum(fi, arg, verb)
	case 's', 'q':
		code := (cast(^Kind)arg.data)^
		meta := CODE_METADATA[code]
		fmt.fmt_string(fi, meta.code, verb)
	case:
		return false
	}
	return true
}

_marshal_kind :: proc(w: io.Stream, v: any, opt: ^json.Marshal_Options) -> json.Marshal_Error {
	assert(v.id == Kind)
	kind := (cast(^Kind)v.data)^
	return json.marshal_to_writer(w, CODE_METADATA[kind].code, opt)
}
