package diagnostics

import "base:runtime"
import "core:fmt"

import "../../common"

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

Diagnostic :: struct {
	level:     Level,
	code:      Code,
	message:   string,
	span:      common.Span,
	addendums: [dynamic]Addendum,
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


_format_code :: proc(fi: ^fmt.Info, arg: any, verb: rune) -> bool {
	assert(arg.id == Code)
	switch verb {
	case 'v':
		fmt.fmt_enum(fi, arg, verb)
	case 's', 'q':
		code := (cast(^Code)arg.data)^
		meta := CODE_METADATA[code]
		fmt.fmt_string(fi, meta.code, verb)
	case:
		return false
	}
	return true
}
