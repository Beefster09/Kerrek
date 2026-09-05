package diagnostics

import "base:runtime"
import "core:fmt"

import "../../common"


emit :: proc {
	emit_with_level_override,
	emit_with_default_level,
}

suggest :: proc(diag: ^Diagnostic, fmtstr: string, args: ..any) {
	msg := fmt.aprintf(fmtstr, ..args, allocator = _msg_allocator)
	if diag.addendums == nil {
		diag.addendums = make([dynamic]Addendum)
	}
	append(&diag.addendums, Suggestion(msg))
}

reference :: proc(diag: ^Diagnostic, span: common.Span, fmtstr: string, args: ..any) {
	msg := fmt.aprintf(fmtstr, ..args, allocator = _msg_allocator)
	if diag.addendums == nil {
		diag.addendums = make([dynamic]Addendum)
	}
	append(&diag.addendums, Reference{message = msg, span = span})
}


emit_with_default_level :: proc(
	code: Code,
	span: common.Span,
	fmtstr: string,
	args: ..any,
) -> ^Diagnostic {
	meta := CODE_METADATA[code]
	diag := Diagnostic {
		level   = meta.default_level,
		code    = code,
		message = fmt.aprintf(fmtstr, ..args, allocator = _msg_allocator),
		span    = span,
	}
	append(&_current_diagnostics, diag)
	return &_current_diagnostics[len(_current_diagnostics) - 1]
}

emit_with_level_override :: proc(
	code: Code,
	level: Level,
	span: common.Span,
	fmtstr: string,
	args: ..any,
) -> ^Diagnostic {
	diag := Diagnostic {
		level   = level,
		code    = code,
		message = fmt.aprintf(fmtstr, ..args, allocator = _msg_allocator),
		span    = span,
	}
	append(&_current_diagnostics, diag)
	return &_current_diagnostics[len(_current_diagnostics) - 1]
}
