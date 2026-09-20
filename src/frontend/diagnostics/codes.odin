package diagnostics

import "core:encoding/json"
import "core:fmt"
import "core:io"


Code :: enum {
	TBD,
	// == Lexer diagnostics ==

	// The source contains a malformed numeric literal.
	Invalid_Number_Literal,
	// A numeric literal and identifier are not separated by whitespace.
	Number_Followed_By_Identifier,
	// An escape sequence is unknown or malformed.
	Invalid_Escape,
	// A rune literal does not contain a code point.
	Empty_Rune,
	// A rune literal is missing its closing single quote.
	Unclosed_Rune,
	// A string literal is missing its closing quote or quotes.
	Unclosed_String,

	// == Parser diagnostics ==

	// The source does not conform to the language grammar.
	Syntax_Error,
	// A standalone semicolon forms an empty statement.
	Empty_Statement,

	// == Resolver diagnostics ==

	// A referenced name or qualified-name component cannot be found.
	Unresolved_Name,
	// A name resolves at first, but its remaining field path does not.
	Incomplete_Resolution,
	// A field is accessed on a symbol kind that cannot have a namespace.
	Invalid_Namespace_Access,
	// A declaration reuses the name of a builtin.
	Builtin_Shadowing,
	// A package-level name is defined more than once.
	Duplicate_Global,
	// A local, parameter, return, or annotation parameter name is repeated.
	Duplicate_Local,
	// A declaration shadows an outer name in a way that is likely accidental.
	Dubious_Shadowing,
	// An import collides with another import or a defined name.
	Import_Conflict,
	// An imported package or module cannot be loaded.
	Import_Not_Found,

	// == Semantic analysis diagnostics ==

	// Declarations form a recursive dependency cycle.
	Cyclical_Dependency,
	// A name or type expression is not valid in a type position.
	Invalid_Type,
	// A unit reference, expression, or exponent is invalid.
	Invalid_Unit,
	// A capability expression refers to something that is not a capability.
	Invalid_Capability,
	// An applied annotation name does not denote an annotation.
	Invalid_Annotation,
	// The entry package does not define a main function.
	Missing_Entry_Point,
	// The entry point is duplicated or has an unsupported signature.
	Invalid_Entry_Point,
	// A name resolved to a kind of symbol that cannot be used in this context.
	Wrong_Symbol_Kind,
	// The number of expected values does not match the actual number of values
	Arity_Mismatch,

	// == MISC ==
	Not_Implemented,

	// == TEST ==

	// A test-only diagnostic used to exercise diagnostic reporting.
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
	.TBD = {stable_id = "0000"},
	// Lexer diagnostics
	.Invalid_Number_Literal = {origin = .Lexer, default_level = .Error, stable_id = "L00"},
	.Number_Followed_By_Identifier = {
		origin = .Lexer,
		category = .Style,
		default_level = .Warning,
		stable_id = "L01",
	},
	.Invalid_Escape = {origin = .Lexer, default_level = .Error, stable_id = "L10"},
	.Empty_Rune = {origin = .Lexer, default_level = .Error, stable_id = "L11"},
	.Unclosed_Rune = {origin = .Lexer, default_level = .Error, stable_id = "L12"},
	.Unclosed_String = {origin = .Lexer, default_level = .Error, stable_id = "L13"},
	// Parser diagnostics
	.Syntax_Error = {origin = .Parser, default_level = .Error, stable_id = "P00"},
	.Empty_Statement = {origin = .Parser, default_level = .Notice, stable_id = "P10"},
	// Resolver diagnostics
	.Unresolved_Name = {origin = .Resolution, default_level = .Error, stable_id = "R00"},
	.Incomplete_Resolution = {origin = .Resolution, default_level = .Error, stable_id = "R01"},
	.Invalid_Namespace_Access = {origin = .Resolution, default_level = .Error, stable_id = "R02"},
	.Builtin_Shadowing = {origin = .Resolution, default_level = .Notice, stable_id = "R10"},
	.Duplicate_Global = {origin = .Resolution, default_level = .Error, stable_id = "R11"},
	.Duplicate_Local = {origin = .Resolution, default_level = .Error, stable_id = "R12"},
	.Dubious_Shadowing = {
		origin = .Resolution,
		category = .Dubious,
		default_level = .Warning,
		stable_id = "R13",
	},
	.Import_Conflict = {origin = .Resolution, default_level = .Error, stable_id = "R20"},
	.Import_Not_Found = {origin = .Resolution, default_level = .Error, stable_id = "R21"},
	// Semantic analysis diagnostics
	.Cyclical_Dependency = {origin = .Semantic, default_level = .Error, stable_id = "A001"},
	.Wrong_Symbol_Kind = {origin = .Semantic, default_level = .Error, stable_id = "A002"},
	.Invalid_Annotation = {origin = .Semantic, default_level = .Error, stable_id = "A003"},
	.Arity_Mismatch = {origin = .Semantic, default_level = .Error, stable_id = "A003"},
	.Invalid_Type = {origin = .Semantic, default_level = .Error, stable_id = "AT01"},
	.Invalid_Unit = {origin = .Semantic, default_level = .Error, stable_id = "AU01"},
	.Invalid_Capability = {origin = .Semantic, default_level = .Error, stable_id = "AC01"},
	.Missing_Entry_Point = {origin = .Semantic, default_level = .Error, stable_id = "MAIN0"},
	.Invalid_Entry_Point = {origin = .Semantic, default_level = .Error, stable_id = "MAIN1"},
	// MISC
	.Not_Implemented = {origin = .Unknown, default_level = .Error, stable_id = "NOIMPL"},
	// TEST
	.Test = {origin = .Resolution, default_level = .Notice, stable_id = "TEST"},
}


_fmt_code :: proc(fi: ^fmt.Info, arg: any, verb: rune) -> bool {
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

_marshal_code :: proc(w: io.Stream, v: any, opt: ^json.Marshal_Options) -> json.Marshal_Error {
	assert(v.id == Code)
	kind := (cast(^Code)v.data)^
	return json.marshal_to_writer(w, CODE_METADATA[kind].stable_id, opt)
}
