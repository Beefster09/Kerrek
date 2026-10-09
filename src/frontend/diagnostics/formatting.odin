package diagnostics

import "base:runtime"
import "core:fmt"

import "../../common"


emit :: proc {
	emit_with_level_override,
	emit_with_default_level,
}

suggest :: proc(diag: ^Diagnostic, fmtstr: string, args: ..any) {
	#force_inline note(diag, fmtstr, ..args, label = "suggestion", disposition = .Positive)
}

note :: proc(
	diag: ^Diagnostic,
	fmtstr: string,
	args: ..any,
	label: string = "note",
	disposition: Note_Disposition = .Neutral,
) {
	msg := fmt.aprintf(fmtstr, ..args, allocator = _msg_allocator)
	if diag.extra == nil {
		diag.extra = make([dynamic]Addendum, _msg_allocator)
	}
	append(&diag.extra, Note{message = msg, label = label, disposition = disposition})
}

reference :: proc(diag: ^Diagnostic, span: common.Span, fmtstr: string, args: ..any) {
	msg := fmt.aprintf(fmtstr, ..args, allocator = _msg_allocator)
	if diag.extra == nil {
		diag.extra = make([dynamic]Addendum, _msg_allocator)
	}
	append(&diag.extra, Reference{message = msg, span = span})
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
