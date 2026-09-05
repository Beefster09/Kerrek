package diagnostics

Kind :: enum {
	// Lexer diagnostics
	Invalid_Number_Literal,
	Invalid_Escape,
	Empty_Rune,
	Unclosed_Rune,
	Unclosed_String,
	Signed_Unsigned_Literal,
	Dubious_Punctuation,
	// Parser diagnostics
	Syntax_Error,
}

@(rodata)
CODE_METADATA := [Kind]Diagnostic_Metadata {
	.Invalid_Number_Literal = {origin = .Lexer, default_level = .Error, code = "L00"},
	.Signed_Unsigned_Literal = {
		origin = .Lexer,
		category = .Dubious,
		default_level = .Warning,
		code = "L01",
	},
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
}
