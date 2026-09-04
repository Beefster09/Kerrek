package diagnostics

import "base:runtime"
import "core:fmt"

import "../common"


error :: proc {
	error_with_span,
	error_without_span,
}

warning :: proc {
	warning_with_span,
	warning_without_span,
}

notice :: proc {
	notice_with_span,
	notice_without_span,
}

suggest :: proc(diag: ^Diagnostic, fmtstr: string, args: ..any) {
	msg := fmt.aprintf(fmtstr, ..args, allocator = _msg_allocator)
	append(&diag.addendums, Suggestion(msg))
}

reference :: proc(diag: ^Diagnostic, span: common.Span, fmtstr: string, args: ..any) {
	msg := fmt.aprintf(fmtstr, ..args, allocator = _msg_allocator)
	append(&diag.addendums, Reference{message = msg, span = span})
}


emit :: proc(
	level: Level,
	span: common.Span,
	fmtstr: string,
	args: ..any,
	origin: Origin = .Unknown,
	category: Category = .Default,
	code: Code = {'?', 0xBADF00D},
) -> ^Diagnostic {
	diag := Diagnostic {
		level    = level,
		origin   = origin,
		category = category,
		code     = code,
		message  = fmt.aprintf(fmtstr, ..args, allocator = _msg_allocator),
		span     = span,
	}
	append(&_current_diagnostics, diag)
	return &_current_diagnostics[len(_current_diagnostics) - 1]
}

notice_with_span :: proc(
	span: common.Span,
	fmtstr: string,
	args: ..any,
	origin: Origin = .Unknown,
	category: Category = .Default,
	code: Code = {'?', 0xBADF00D},
) -> ^Diagnostic {
	return emit(.Notice, span, fmtstr, ..args, origin = origin, category = category, code = code)
}

notice_without_span :: proc(
	fmtstr: string,
	args: ..any,
	origin: Origin = .Unknown,
	category: Category = .Default,
	code: Code = {'?', 0xBADF00D},
) -> ^Diagnostic {
	return emit(
		.Notice,
		common.Span{},
		fmtstr,
		..args,
		origin = origin,
		category = category,
		code = code,
	)
}

warning_with_span :: proc(
	span: common.Span,
	fmtstr: string,
	args: ..any,
	origin: Origin = .Unknown,
	category: Category = .Default,
	code: Code = {'?', 0xBADF00D},
) -> ^Diagnostic {
	return emit(.Warning, span, fmtstr, ..args, origin = origin, category = category, code = code)
}

warning_without_span :: proc(
	fmtstr: string,
	args: ..any,
	origin: Origin = .Unknown,
	category: Category = .Default,
	code: Code = {'?', 0xBADF00D},
) -> ^Diagnostic {
	return emit(
		.Warning,
		common.Span{},
		fmtstr,
		..args,
		origin = origin,
		category = category,
		code = code,
	)
}

error_with_span :: proc(
	span: common.Span,
	fmtstr: string,
	args: ..any,
	origin: Origin = .Unknown,
	category: Category = .Default,
	code: Code = {'?', 0xBADF00D},
) -> ^Diagnostic {
	return emit(.Error, span, fmtstr, ..args, origin = origin, category = category, code = code)
}

error_without_span :: proc(
	fmtstr: string,
	args: ..any,
	origin: Origin = .Unknown,
	category: Category = .Default,
	code: Code = {'?', 0xBADF00D},
) -> ^Diagnostic {
	return emit(
		.Error,
		common.Span{},
		fmtstr,
		..args,
		origin = origin,
		category = category,
		code = code,
	)
}
