package ast

import "base:runtime"
import "core:fmt"
import "core:io"

import "../../common"

Span :: common.Span
Name :: common.Name

Qualified_Name :: struct {
	span: Span,
	path: []Name,
}

fmt_qualname :: proc(fi: ^fmt.Info, arg: any, verb: rune) -> bool {
	assert(arg.id == Qualified_Name)

	switch verb {
	case 'v':
		fmt.fmt_struct(
			fi,
			arg,
			verb,
			type_info_of(Qualified_Name).variant.(runtime.Type_Info_Named).base.variant.(runtime.Type_Info_Struct),
			"Qualified_Name",
		)
	case 's':
		for name, i in (cast(^Qualified_Name)arg.data).path {
			if i > 0 {
				io.write_rune(fi.writer, '.')
			}
			io.write_string(fi.writer, string(name.id))
		}
	case:
		return false
	}
	return true
}
