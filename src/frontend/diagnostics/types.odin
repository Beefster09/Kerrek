package diagnostics

import "base:runtime"
import "core:fmt"
import "core:io"

import "../common"

Level :: enum u8 {
	Notice  = 0,
	Warning = 1,
	Error   = 2,
}

Origin :: enum u8 {
	Unknown = 0,
	Lexical,
	Parser,
	Resolver,
	TypeCheck,
	UnitCheck,
	FactCheck,
	CapCheck,
}

Category :: enum u8 {
	Default = 0,
	Unused,
	Deprecated,
	Suspicious,
	Performance,
	Portability,
	Style,
}

Code :: struct {
	letter: rune,
	number: u32,
}

Diagnostic :: struct {
	level:     Level,
	origin:    Origin,
	category:  Category,
	code:      Code,
	message:   string,
	span:      common.Span,
	addendums: [dynamic]Addendum,
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


_format_code :: proc(fi: ^fmt.Info, arg: any, verb: rune) -> bool {
	assert(arg.id == Code)
	switch verb {
	case 'v':
		fmt.fmt_struct(
			fi,
			arg,
			verb,
			type_info_of(Code).variant.(runtime.Type_Info_Named).base.variant.(runtime.Type_Info_Struct),
			"Code",
		)
	case 's':
		code := (cast(^Code)arg.data)^
		fmt.fmt_rune(fi, code.letter, 'c')
		if !fi.width_set {
			fi.width = 3
			fi.width_set = true
		}
		fmt.fmt_int(fi, u64(code.number), false, 32, 'd')
	case 'q':
		code := (cast(^Code)arg.data)^
		io.write_rune(fi.writer, '"')
		fmt.fmt_rune(fi, code.letter, 'c')
		if !fi.width_set {
			fi.width = 3
			fi.width_set = true
		}
		fmt.fmt_int(fi, u64(code.number), false, 32, 'd')
		io.write_rune(fi.writer, '"')
	case:
		return false
	}
	return true
}
