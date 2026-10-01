package diagnostics

import "core:encoding/json"
import "core:fmt"
import "core:io"
import "core:reflect"


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
	// A type name does not resolve to a type.
	Invalid_Type_Name,
	// A parametric type is used without its required arguments.
	Missing_Type_Arguments,
	// Type arguments are applied to a type that is not parametric.
	Not_Parametric_Type,
	// A parametric type receives the wrong number of arguments.
	Type_Argument_Count_Mismatch,
	// A type argument is passed by name where only positional arguments are allowed.
	Named_Type_Argument,
	// A type argument has an invalid value or cannot be evaluated at compile time.
	Invalid_Type_Argument,
	// A Decimal type specifies an invalid number of digits.
	Invalid_Decimal_Digits,
	// A Decimal type specifies a scale outside the supported range.
	Invalid_Decimal_Scale,
	// A symbol cannot be used as a type tag.
	Invalid_Type_Tag,
	// A value's type does not match a function parameter.
	Argument_Type_Mismatch,
	// A returned value's type does not match the function signature.
	Return_Type_Mismatch,
	// A variable's type has no zero value where one is required.
	Nonzeroable_Variable,
	// An operand's type has no zero value required by the operation.
	Nonzeroable_Operand,
	// A variable declaration omits a required type.
	Missing_Variable_Type,
	// A global variable is declared unbound.
	Unbound_Global_Variable,
	// A flexible value cannot be assigned a concrete type in this context.
	Cannot_Infer_Type,
	// A name does not denote a unit.
	Invalid_Unit_Name,
	// A unit exponent cannot be represented by the compiler.
	Unit_Exponent_Not_Representable,
	// A unit reinterpretation specifies an invalid target unit.
	Invalid_Unit_Reinterpretation,
	// Two values have incompatible units.
	Unit_Mismatch,
	// A function argument has units incompatible with its parameter.
	Argument_Unit_Mismatch,
	// An operator cannot combine the supplied units.
	Invalid_Unit_Operation,
	// A unit exponent is not valid for exponentiation.
	Invalid_Unit_Exponent,
	// A unit conversion references a target that is not a unit.
	Invalid_Unit_Conversion_Target,
	// A unit conversion factor is not a valid compile-time numeric value.
	Invalid_Unit_Conversion_Factor,
	// A capability expression refers to something that is not a capability.
	Invalid_Capability,
	// An applied annotation name does not denote an annotation.
	Invalid_Annotation_Name,
	// An annotation cannot be applied to the declaration it annotates.
	Invalid_Annotation_Target,
	// An annotation receives the wrong number of arguments.
	Annotation_Arity_Mismatch,
	// The entry package does not define a main function.
	Missing_Entry_Point,
	// The entry point accepts parameters.
	Entry_Point_Has_Parameters,
	// The entry point returns values.
	Entry_Point_Returns_Values,
	// The entry point is fallible.
	Fallible_Entry_Point,
	// A symbol cannot be used as a runtime or compile-time value.
	Symbol_Not_Value,
	// A symbol cannot be used as a constant definition's value.
	Symbol_Not_Constant,
	// A symbol cannot be passed as a function argument.
	Symbol_Not_Argument,
	// A symbol cannot be used as an operator operand.
	Symbol_Not_Operand,
	// An expression or symbol is not callable.
	Not_Callable,
	// A context requires exactly one value.
	Expected_Single_Value,
	// An assignment receives the wrong number of values.
	Assignment_Arity_Mismatch,
	// A return statement produces the wrong number of values.
	Return_Arity_Mismatch,
	// A function call passes the wrong number of values.
	Call_Arity_Mismatch,
	// A named argument expression produces the wrong number of values.
	Named_Argument_Arity_Mismatch,
	// A named argument does not match a parameter.
	Unknown_Named_Argument,
	// A parameter is passed more than once.
	Duplicate_Argument,
	// An unnamed argument was passed after a named one
	Unnamed_Arg_After_Named_Arg,
	// Named arguments are used with a callee whose parameters are not statically known.
	Named_Argument_Requires_Static_Callee,
	// A call-style cast receives a named argument.
	Named_Cast_Argument,
	// An expression that returns no values was used in a context where values are expected
	Invalid_Nullary_Expression,
	// An expression produces a value that isn't used
	Unused_Value,
	// The value needed to be known at compile time, but wasn't
	Not_Compile_Time_Known,
	// A decimal type was defined or inferred to require more than 64 bits
	Large_Decimal,
	// A binary operator is not defined for the type(s)
	Binop_Not_Defined,
	// A unary operator is not defined for the type
	Unop_Not_Defined,
	// == MISC ==

	// this part of the compiler is not yet implemented
	Not_Implemented,

	// == TEST ==

	// A test-only diagnostic used to exercise diagnostic reporting.
	Test,
}

Code_Metadata :: struct {
	origin:        Origin,
	category:      Category,
	default_level: Level,
	description:   string,
}

@(rodata)
CODE_METADATA := [Code]Code_Metadata {
	.TBD = {},
	// Lexer diagnostics
	.Invalid_Number_Literal = {origin = .Lexer, default_level = .Error},
	.Number_Followed_By_Identifier = {
		origin = .Lexer,
		category = .Style,
		default_level = .Warning,
	},
	.Invalid_Escape = {origin = .Lexer, default_level = .Error},
	.Empty_Rune = {origin = .Lexer, default_level = .Error},
	.Unclosed_Rune = {origin = .Lexer, default_level = .Error},
	.Unclosed_String = {origin = .Lexer, default_level = .Error},
	// Parser diagnostics
	.Syntax_Error = {origin = .Parser, default_level = .Error},
	.Empty_Statement = {origin = .Parser, default_level = .Notice},
	// Resolver diagnostics
	.Unresolved_Name = {origin = .Resolution, default_level = .Error},
	.Incomplete_Resolution = {origin = .Resolution, default_level = .Error},
	.Invalid_Namespace_Access = {origin = .Resolution, default_level = .Error},
	.Builtin_Shadowing = {origin = .Resolution, default_level = .Notice},
	.Duplicate_Global = {origin = .Resolution, default_level = .Error},
	.Duplicate_Local = {origin = .Resolution, default_level = .Error},
	.Dubious_Shadowing = {origin = .Resolution, category = .Dubious, default_level = .Warning},
	.Import_Conflict = {origin = .Resolution, default_level = .Error},
	.Import_Not_Found = {origin = .Resolution, default_level = .Error},
	// Semantic analysis diagnostics
	.Cyclical_Dependency = {origin = .Semantic, default_level = .Error},
	.Invalid_Type_Name = {origin = .Semantic, default_level = .Error},
	.Missing_Type_Arguments = {origin = .Semantic, default_level = .Error},
	.Not_Parametric_Type = {origin = .Semantic, default_level = .Error},
	.Type_Argument_Count_Mismatch = {origin = .Semantic, default_level = .Error},
	.Named_Type_Argument = {origin = .Semantic, default_level = .Error},
	.Invalid_Type_Argument = {origin = .Semantic, default_level = .Error},
	.Invalid_Decimal_Digits = {origin = .Semantic, default_level = .Error},
	.Invalid_Decimal_Scale = {origin = .Semantic, default_level = .Error},
	.Invalid_Type_Tag = {origin = .Semantic, default_level = .Error},
	.Argument_Type_Mismatch = {origin = .Semantic, default_level = .Error},
	.Return_Type_Mismatch = {origin = .Semantic, default_level = .Error},
	.Nonzeroable_Variable = {origin = .Semantic, default_level = .Error},
	.Nonzeroable_Operand = {origin = .Semantic, default_level = .Error},
	.Missing_Variable_Type = {origin = .Semantic, default_level = .Error},
	.Unbound_Global_Variable = {origin = .Semantic, default_level = .Error},
	.Cannot_Infer_Type = {origin = .Semantic, default_level = .Error},
	.Invalid_Unit_Name = {origin = .Semantic, default_level = .Error},
	.Unit_Exponent_Not_Representable = {origin = .Semantic, default_level = .Error},
	.Invalid_Unit_Reinterpretation = {origin = .Semantic, default_level = .Error},
	.Unit_Mismatch = {origin = .Semantic, default_level = .Error},
	.Argument_Unit_Mismatch = {origin = .Semantic, default_level = .Error},
	.Invalid_Unit_Operation = {origin = .Semantic, default_level = .Error},
	.Invalid_Unit_Exponent = {origin = .Semantic, default_level = .Error},
	.Invalid_Unit_Conversion_Target = {origin = .Semantic, default_level = .Error},
	.Invalid_Unit_Conversion_Factor = {origin = .Semantic, default_level = .Error},
	.Invalid_Annotation_Name = {origin = .Semantic, default_level = .Error},
	.Invalid_Annotation_Target = {origin = .Semantic, default_level = .Error},
	.Annotation_Arity_Mismatch = {origin = .Semantic, default_level = .Error},
	.Invalid_Nullary_Expression = {origin = .Semantic, default_level = .Error},
	.Symbol_Not_Value = {origin = .Semantic, default_level = .Error},
	.Symbol_Not_Constant = {origin = .Semantic, default_level = .Error},
	.Symbol_Not_Argument = {origin = .Semantic, default_level = .Error},
	.Symbol_Not_Operand = {origin = .Semantic, default_level = .Error},
	.Not_Callable = {origin = .Semantic, default_level = .Error},
	.Expected_Single_Value = {origin = .Semantic, default_level = .Error},
	.Assignment_Arity_Mismatch = {origin = .Semantic, default_level = .Error},
	.Return_Arity_Mismatch = {origin = .Semantic, default_level = .Error},
	.Call_Arity_Mismatch = {origin = .Semantic, default_level = .Error},
	.Named_Argument_Arity_Mismatch = {origin = .Semantic, default_level = .Error},
	.Unknown_Named_Argument = {origin = .Semantic, default_level = .Error},
	.Duplicate_Argument = {origin = .Semantic, default_level = .Error},
	.Unnamed_Arg_After_Named_Arg = {origin = .Semantic, default_level = .Error},
	.Named_Argument_Requires_Static_Callee = {origin = .Semantic, default_level = .Error},
	.Named_Cast_Argument = {origin = .Semantic, default_level = .Error},
	.Unused_Value = {origin = .Semantic, default_level = .Warning},
	.Not_Compile_Time_Known = {origin = .Semantic, default_level = .Error},
	.Binop_Not_Defined = {origin = .Semantic, default_level = .Error},
	.Unop_Not_Defined = {origin = .Semantic, default_level = .Error},
	.Invalid_Capability = {origin = .Semantic, default_level = .Error},
	.Large_Decimal = {origin = .Semantic, default_level = .Warning},
	.Missing_Entry_Point = {origin = .Semantic, default_level = .Error},
	.Entry_Point_Has_Parameters = {origin = .Semantic, default_level = .Error},
	.Entry_Point_Returns_Values = {origin = .Semantic, default_level = .Error},
	.Fallible_Entry_Point = {origin = .Semantic, default_level = .Error},
	// MISC
	.Not_Implemented = {origin = .Unknown, default_level = .Error},
	// TEST
	.Test = {origin = .Resolution, default_level = .Notice},
}


_fmt_code :: proc(fi: ^fmt.Info, arg: any, verb: rune) -> bool {
	assert(arg.id == Code)
	switch verb {
	case 'v':
		fmt.fmt_enum(fi, arg, verb)
	case 's':
		code := (cast(^Code)arg.data)^
		meta := CODE_METADATA[code]
		fmt.fmt_string(fi, reflect.enum_name_from_value(code) or_else "???", verb)
	case:
		return false
	}
	return true
}

_marshal_code :: proc(w: io.Stream, v: any, opt: ^json.Marshal_Options) -> json.Marshal_Error {
	assert(v.id == Code)
	code := (cast(^Code)v.data)^
	return json.marshal_to_writer(w, reflect.enum_name_from_value(code) or_else "???", opt)
}
