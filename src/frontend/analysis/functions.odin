package analysis

import "core:slice"

import "../../common"
import "../../util"
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
	params_scope := resolver.new_scope(symbol.defined_in, ts.allocator)

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
		param.hir = new(hir.Formal_Parameter, ts.output.allocator)
		param.hir^ = {
			span    = ast_param.span,
			id      = param.id,
			name    = ast_param.name,
			type    = ptype,
			unit    = punit,
			default = pdefault,
		}

		append(&params, param)
		resolver.define_local(params_scope, ast_param.name, param, warn_shadowing = {.Builtins})
	}

	returns := [dynamic]^hir.Func_Return{}
	named_returns := resolver.temp_scope(params_scope)
	// named returns are only visible in the function header, namely `defer with` clauses

	for ret, i in func.returns {
		rtype, rt_ok := build_type(ts, ret.type, scope)
		runit, ru_ok := build_unit(ts, ret.unit, scope)

		if !rt_ok || !ru_ok {
			return .Invalid_Types
		}

		hir_ret := new(hir.Func_Return)
		hir_ret^ = {
			span = ret.span,
			type = rtype,
			unit = runit,
		}

		if ret.name != nil {
			named_return := resolver.new_symbol(
				ts.symbol_resolver,
				resolver.Named_Return,
				ret.name.?.id,
			)
			named_return.ast = ret
			named_return.hir = hir_ret
			resolver.define_local(&named_returns, ret.name.?, named_return)
		}

		append(&returns, hir_ret)
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

	requires: hir.Capability_Expression = nil
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
	append(&ts.pending_bodies, Pending_Function_Body{func = symbol, root_scope = params_scope})
	append(&ts.hir_items.funcs, symbol.hir)

	hir.func_derive_type(symbol.hir, ts.output.allocator)
	return .OK
}

build_function_body :: proc(
	ts: ^Translation_State,
	symbol: ^resolver.Function,
	scope: resolver.Scope,
) -> Func_Translation_Error {
	assert(symbol != nil)
	assert(symbol.ast != nil)
	assert(symbol.hir != nil)
	body := build_block(ts, symbol.ast.body, symbol, scope)
	assert(body != nil)
	symbol.hir.body = body
	return .OK
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
			case "doc":
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

_Argument :: struct {
	span:  common.Span,
	value: Eval_Result,
	name:  Maybe(common.Identifier),
}

_arg_list :: proc(
	ts: ^Translation_State,
	in_args: []ast.Argument,
	scope: resolver.Scope,
) -> (
	[]_Argument,
	[]int,
	bool,
) {
	args := make([dynamic]_Argument, 0, len(in_args), ts.output.allocator)
	indices := make([dynamic]int, context.temp_allocator)

	ok := true
	passing_names := false
	for arg, i in in_args {
		value := evaluate(ts, arg.expr, scope)
		if _, is_poison := util.chain_extract(value, hir.Expression, ^hir.Poison);
		   is_poison || value == nil {
			ok = false
			continue
		}

		value_count := 0
		#partial switch value in value {
		case hir.Expression:
			value_count = hir.value_count(value)
		case Comptime_Value:
			value_count = 1
		case ^resolver.Import:
			diagnostics.emit(.Wrong_Symbol_Kind, arg.span, "imports are not valid as arguments")
			ok = false
			continue
		}

		if passing_names && arg.name == nil {
			diagnostics.emit(
				.Unnamed_Arg_After_Named_Arg,
				arg.span,
				"cannot pass an unnamed argument after a named argument",
			)
			ok = false
		}
		if arg.name != nil {
			if value_count != 1 {
				diagnostics.emit(
					.Arity_Mismatch,
					ast.span(arg.expr),
					"this expression was used for a named argument, but it returns %d values",
					value_count,
				)
				ok = false
			}
			passing_names = true
		} else if value_count == 0 {
			diagnostics.emit(
				.Dubious_Nullary_Expression,
				ast.span(arg.expr),
				"this expression was used in a argument list but it returns no values",
			)
		}

		append(
			&args,
			_Argument {
				span = arg.span,
				name = arg.name.?.id if arg.name != nil else nil,
				value = value,
			},
		)
		for _ in 0 ..< value_count {
			append(&indices, i)
		}
	}

	if !ok {
		return nil, nil, false
	}

	shrink(&args)
	return args[:], indices[:], true
}

_build_func_call :: proc(
	ts: ^Translation_State,
	span: common.Span,
	callee: hir.Expression,
	signature: ^hir.Func_Type,
	arg_exprs: []_Argument,
	arg_indices: []int,
) -> hir.Expression {
	param_value_idxs := make([]int, len(signature.params), context.temp_allocator)
	for &idx in param_value_idxs {
		idx = -1
	}

	static_func, is_static := callee.(^hir.Static_Func_Expr)
	next_param := 0
	for arg_idx, value_idx in arg_indices {
		arg := arg_exprs[arg_idx]
		param_idx := next_param
		if arg.name != nil {
			if !is_static {
				diagnostics.emit(
					.Invalid_Type,
					arg.span,
					"named arguments require a statically known function",
				)
				return poison(ts, span)
			}
			param_idx = -1
			for param, i in static_func.func.params {
				if param.name.id == arg.name.? {
					param_idx = i
					break
				}
			}
			if param_idx < 0 {
				diagnostics.emit(
					.Arity_Mismatch,
					arg.span,
					"function has no parameter named '%s'",
					arg.name.?,
				)
				return poison(ts, span)
			}
		} else {
			next_param += 1
		}

		if param_idx >= len(signature.params) {
			diagnostics.emit(
				.Arity_Mismatch,
				span,
				"function expects %d values, but the call passes %d",
				len(signature.params),
				len(arg_indices),
			)
			return poison(ts, span)
		}
		if param_value_idxs[param_idx] >= 0 {
			diagnostics.emit(
				.Arity_Mismatch,
				arg.span,
				"parameter '%s' is passed more than once",
				static_func.func.params[param_idx].name.id,
			)
			return poison(ts, span)
		}
		param_value_idxs[param_idx] = value_idx
	}

	for value_idx, param_idx in param_value_idxs {
		if value_idx < 0 && (!is_static || static_func.func.params[param_idx].default == nil) {
			diagnostics.emit(
				.Arity_Mismatch,
				span,
				"function expects %d values, but the call passes %d",
				len(signature.params),
				len(arg_indices),
			)
			return poison(ts, span)
		}
	}

	converted := make([]hir.Expression, len(arg_exprs), ts.output.allocator)
	for arg, i in arg_exprs {
		if value, ok := arg.value.(hir.Expression); ok {
			converted[i] = value
		}
	}
	for value_idx, param_idx in param_value_idxs {
		if value_idx < 0 {
			continue
		}
		expected := signature.params[param_idx]
		arg_idx := arg_indices[value_idx]
		arg := arg_exprs[arg_idx]
		actual_type: Comptime_Type
		actual_unit: hir.Realized_Unit
		switch value in arg.value {
		case Comptime_Value:
			actual_type = value.type
			actual_unit = value.unit
		case hir.Expression:
			tus := hir.expression_types_and_units(value)
			first_value_idx := value_idx
			for first_value_idx > 0 && arg_indices[first_value_idx - 1] == arg_idx {
				first_value_idx -= 1
			}
			actual_type = tus[value_idx - first_value_idx].type
			actual_unit = tus[value_idx - first_value_idx].unit
		case ^resolver.Import:
			panic("unreachable")
		}
		if !_type_implicitly_converts(expected.type, actual_type) {
			diagnostics.emit(
				.Invalid_Type,
				arg.span,
				"parameter requires a %s, but the argument is a %s",
				expected.type,
				actual_type,
			)
			return poison(ts, span)
		}

		_, factor, unit_ok := _coerce_units(expected.unit, actual_unit)
		if !unit_ok {
			diagnostics.emit(
				.Invalid_Unit,
				arg.span,
				"parameter unit (%v) does not match argument unit (%v)",
				expected.unit,
				actual_unit,
			)
			return poison(ts, span)
		}

		singular :=
			(value_idx == 0 || arg_indices[value_idx - 1] != arg_idx) &&
			(value_idx + 1 == len(arg_indices) || arg_indices[value_idx + 1] != arg_idx)
		if value, comptime := arg.value.(Comptime_Value); comptime {
			ok: bool
			converted[arg_idx], ok = materialize(ts, value, arg.span, expected.type)
			if !ok {
				return poison(ts, span)
			}
		} else if singular && !types_equal(expected.type, actual_type) {
			cast_expr := new(hir.Cast_Expr, ts.output.allocator)
			cast_expr^ = {
				span = arg.span,
				expr = converted[arg_idx],
				to   = expected.type,
				type = expected.type,
				unit = actual_unit,
			}
			converted[arg_idx] = cast_expr
		}
		if singular && !_units_equal(expected.unit, actual_unit) {
			conversion := new(hir.Unit_Conversion_Expr, ts.output.allocator)
			conversion^ = {
				span   = arg.span,
				expr   = converted[arg_idx],
				type   = expected.type,
				unit   = expected.unit,
				factor = factor,
			}
			converted[arg_idx] = conversion
		}
	}

	args := make([dynamic]hir.Expression, 0, len(signature.params), ts.output.allocator)
	appended := make([]bool, len(arg_exprs), context.temp_allocator)
	for value_idx, param_idx in param_value_idxs {
		if value_idx < 0 {
			append(&args, static_func.func.params[param_idx].default)
			continue
		}
		arg_idx := arg_indices[value_idx]
		if !appended[arg_idx] {
			append(&args, converted[arg_idx])
			appended[arg_idx] = true
		}
	}
	shrink(&args)

	call := new(hir.Func_Call_Expr, ts.output.allocator)
	call^ = {
		span            = span,
		types_and_units = signature.returns,
		callee          = callee,
		args            = args[:],
	}
	return call
}
