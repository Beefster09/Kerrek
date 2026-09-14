package diagnostics

import "core:encoding/json"
import "core:fmt"
import "core:io"


Code :: enum {
	// Lexer diagnostics
	Invalid_Number_Literal,
	Invalid_Escape,
	Empty_Rune,
	Unclosed_Rune,
	Unclosed_String,
	// Parser diagnostics
	Syntax_Error,
	Empty_Statement,
	// Resolver diagnostics
	Unresolved_Name,
	Incomplete_Resolution,
	Invalid_Namespace_Access,
	Builtin_Shadowing,
	Duplicate_Global,
	Duplicate_Local,
	Dubious_Shadowing,
	Import_Conflict,
	Import_Not_Found,
	// TEST
	Test,
}

Code_Metadata :: struct {
	origin:        Origin,
	category:      Category,
	default_level: Level,
	stable_id:     string,
}

@(rodata)
CODE_METADATA := [Code]Code_Metadata {
	// Lexer diagnostics
	.Invalid_Number_Literal = {origin = .Lexer, default_level = .Error, stable_id = "L00"},
	.Invalid_Escape = {origin = .Lexer, default_level = .Error, stable_id = "L10"},
	.Empty_Rune = {origin = .Lexer, default_level = .Error, stable_id = "L11"},
	.Unclosed_Rune = {origin = .Lexer, default_level = .Error, stable_id = "L12"},
	.Unclosed_String = {origin = .Lexer, default_level = .Error, stable_id = "L13"},
	// Parser diagnostics
	.Syntax_Error = {origin = .Parser, default_level = .Error, stable_id = "P00"},
	.Empty_Statement = {origin = .Parser, default_level = .Notice, stable_id = "P10"},
	// Resolver diagnostics
	.Unresolved_Name = {origin = .Resolver, default_level = .Error, stable_id = "R00"},
	.Incomplete_Resolution = {origin = .Resolver, default_level = .Error, stable_id = "R01"},
	.Invalid_Namespace_Access = {origin = .Resolver, default_level = .Error, stable_id = "R02"},
	.Builtin_Shadowing = {origin = .Resolver, default_level = .Notice, stable_id = "R10"},
	.Duplicate_Global = {origin = .Resolver, default_level = .Error, stable_id = "R11"},
	.Duplicate_Local = {origin = .Resolver, default_level = .Error, stable_id = "R12"},
	.Dubious_Shadowing = {
		origin = .Resolver,
		category = .Dubious,
		default_level = .Warning,
		stable_id = "R13",
	},
	.Import_Conflict = {origin = .Resolver, default_level = .Error, stable_id = "R20"},
	.Import_Not_Found = {origin = .Resolver, default_level = .Error, stable_id = "R21"},
	// TEST
	.Test = {origin = .Resolver, default_level = .Notice, stable_id = "TEST"},
}


_fmt_kind :: proc(fi: ^fmt.Info, arg: any, verb: rune) -> bool {
	assert(arg.id == Code)
	switch verb {
	case 'v':
		fmt.fmt_enum(fi, arg, verb)
	case 's', 'q':
		code := (cast(^Code)arg.data)^
		meta := CODE_METADATA[code]
		fmt.fmt_string(fi, meta.stable_id, verb)
	case:
		return false
	}
	return true
}

_marshal_kind :: proc(w: io.Stream, v: any, opt: ^json.Marshal_Options) -> json.Marshal_Error {
	assert(v.id == Code)
	kind := (cast(^Code)v.data)^
	return json.marshal_to_writer(w, CODE_METADATA[kind].stable_id, opt)
}
