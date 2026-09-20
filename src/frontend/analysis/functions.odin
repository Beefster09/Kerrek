package analysis

import "core:slice"

import "../../common"
import "../ast"
import "../diagnostics"
import "../hir"
import "../resolver"


Func_Translation_Error :: enum {
	OK,
	Invalid_Types,
}

translate_function_signature :: proc(
	ts: ^Translation_State,
	symbol: ^resolver.Function,
	scope: resolver.Scope,
) -> (
	err: Func_Translation_Error,
) {
	err = .Invalid_Types
	func := symbol.ast

	flags, annotations := _process_func_annotations(ts, symbol)

	params := make([dynamic]^resolver.Formal_Parameter, 0, len(symbol.ast.params))

	process_params: for ast_param in func.params {
		for prev_param in params {
			if ast_param.name.id == prev_param.name {
				diagnostics.emit(
					.Duplicate_Local,
					ast_param.name.span,
					"duplicate parameter name '%s'",
					ast_param.name.id,
				)
				continue process_params
			}
		}

		ptype, pt_ok := build_type(ts, ast_param.type, scope)
		if ptype == nil {
			continue
		}

		punit: hir.Realized_Unit
		if ast_param.unit != nil {
			pu_ok: bool
			punit, pu_ok = build_unit(ts, ast_param.unit, scope)
			if !pu_ok {
				continue
			}
		} else {
			continue
		}

		pdefault: ^hir.Const_Expr
		if ast_param.default != nil {
			built_default, def_ok := build_expr(ts, ast_param.default, scope)
			if const_default, ok := built_default.(^hir.Const_Expr); ok {
				pdefault = const_default
			} else {
				diagnostics.emit(
					.Invalid_Type,
					resolver.expression_span(ast_param.default),
					"default value for '%s' is not known at compile-time",
					ast_param.name.id,
				)
				continue
			}
		} else {
			pdefault = nil
		}

		param := resolver.new_symbol(
			ts.symbol_resolver,
			resolver.Formal_Parameter,
			ast_param.name.id,
		)
		param.ast = ast_param
		param.state = .Done
		param.hir = new(hir.Formal_Parameter)
		param.hir^ = {
			span    = ast_param.span,
			id      = param.id,
			name    = ast_param.name,
			type    = ptype,
			unit    = punit,
			default = pdefault,
		}

		append(&params, param)
	}

	returns := [dynamic]^hir.Func_Return{}

	for ret in func.returns {
		rtype, rt_ok := build_type(ts, ret.type, scope)
		runit, ru_ok := build_unit(ts, ret.unit, scope)

		if rtype == nil {
			diagnostics.emit(.Invalid_Unit, ret.span, "type missing on func return")
			continue
		}

		if runit == nil {
			continue
		}

		hir_ret := new(hir.Func_Return)
		hir_ret^ = {
			span = ret.span,
			type = rtype,
			unit = runit,
		}
		append(&returns, hir_ret)

		if ret.name != nil {
			named_return := resolver.new_symbol(
				ts.symbol_resolver,
				resolver.Named_Return,
				ret.name.?.id,
			)
			named_return.ast = ret
			named_return.hir = hir_ret
		}
	}

	err_type: hir.Type
	if func.error_type != nil {
		err_type = build_type(ts, func.error_type, scope) or_else nil
	} else {
		err_type = nil
	}
	if func.fallible {
		flags |= {.Fallible}
	}

	requires: ^hir.Capability_Expression = nil
	if func.requires != nil {
	}

	symbol.hir = new(hir.Func_Definition)
	symbol.hir^ = {
		span        = func.span,
		id          = symbol.id,
		name        = func.name,
		params      = slice.mapper(
			params[:],
			proc(p: ^resolver.Formal_Parameter) -> ^hir.Formal_Parameter {
				return p.hir
			},
			ts.output.allocator,
		),
		returns     = returns[:],
		error_type  = err_type,
		flags       = flags,
		requires    = requires,
		annotations = annotations[:],
	}
	queue_build_function_body(ts, symbol)
	append(&ts.hir_items.funcs, symbol.hir)

	return .OK
}

queue_build_function_body :: proc(ts: ^Translation_State, symbol: ^resolver.Function) {
	return // TODO
}

build_function_body :: proc(
	ts: ^Translation_State,
	symbol: ^resolver.Function,
	scope: resolver.Scope,
) -> Func_Translation_Error {
	return .OK // TODO
}

_process_func_annotations :: proc(
	ts: ^Translation_State,
	symbol: ^resolver.Function,
) -> (
	hir.Func_Flags,
	[]^hir.Annotation,
) {
	annotations := make([dynamic]^hir.Annotation)
	flags: hir.Func_Flags

	process_annotations: for annotation in symbol.ast.annotations {
		resolved := resolver.resolve(symbol.defined_in, annotation.base)
		if resolved != nil {
			ensure_toplevel_symbol_processed(ts, resolved)
		}
		#partial switch anno in resolved {
		case ^resolver.Builtin:
			if anno.kind != .Annotation {
				diagnostics.emit(
					.Invalid_Annotation,
					annotation.base.span,
					"builtin '%s' is not an annotation",
					anno.name,
				)
				continue process_annotations
			}
			switch anno.name {
			case "pure":
				if len(annotation.args) > 0 {
					diagnostics.emit(
						.Invalid_Annotation,
						annotation.base.span,
						"builtin annotation @pure does not take arguments",
					)
					continue process_annotations
				}
				flags |= {.Pure}
				diagnostics.emit(
					.Not_Implemented,
					diagnostics.Level.Notice,
					annotation.span,
					"pure function verification is not yet implemented",
				)
			case "deprecated":
				switch len(annotation.args) {
				case 0:
					symbol.deprecated_msg = ""
				case 1:
					symbol.deprecated_msg = "TODO: this needs to be handled properly"
				}
			case "calling_convention":
			case:
				diagnostics.emit(
					.Invalid_Annotation,
					annotation.base.span,
					"builtin annotation '%s' cannot be applied to functions",
					anno.name,
				)
			}

		case ^resolver.Annotation:
			anno_hir := new(hir.Annotation)
			anno_hir^ = {
				span       = annotation.span,
				definition = anno.hir,
				args       = {},
			}
			append(&annotations, anno_hir)

		case:
			diagnostics.emit(
				.Invalid_Annotation,
				annotation.base.span,
				"'%s' is not an annotation",
				annotation.base,
			)
		}
	}

	shrink(&annotations)
	return flags, annotations[:]
}
