package analysis

import "core:fmt"
import "core:reflect"
import "core:slice"

import "../../common"
import "../ast"
import "../diagnostics"
import "../hir"
import "../resolver"


process_toplevel_items :: proc(ts: ^Translation_State) -> bool {
	assert(ts != nil)

	symbol_count := 0
	malformed_count := 0
	for pkg in ts.symbol_resolver.loaded_packages {
		for file in pkg.files {
			for symbol in file.defined_symbols {
				switch ensure_symbol_processed(ts, symbol) {
				case .OK:
					symbol_count += 1
				case .Not_Implemented:
					fmt.eprintfln(
						"cannot process symbol '%s' because translation for %T is not yet implemented",
						resolver.symbol_name(symbol),
						reflect.get_union_variant(symbol),
					)
				case .Malformed, .Cyclical_Dependency:
					malformed_count += 1

				}
				free_all(context.temp_allocator)
			}
		}
	}

	if ts.output.entry_point == nil {
		diagnostics.emit(
			.Missing_Entry_Point,
			{},
			"entry package does not define a 'main' function",
		)
		return false
	} else if !_validate_entry_point(ts.output.entry_point) {
		return false
	}

	return malformed_count == 0
}

Symbol_Processing_Error :: enum {
	OK,
	Malformed,
	Cyclical_Dependency,
	Not_Implemented = -1,
}

ensure_symbol_processed :: proc(
	ts: ^Translation_State,
	symbol: resolver.Symbol,
) -> (
	ret_err: Symbol_Processing_Error,
) {
	header := resolver.symbol_header(symbol)
	if header == nil {
		return .OK
	}

	switch header.state {
	case .Unseen:
		header.state = .Processing
	case .Processing:
		header.state = .Failed
		_emit_cyclical_dependency_error(ts, symbol)
		return .Cyclical_Dependency
	case .Done:
		return .OK
	case .Failed:
		return .Malformed
	}

	append(&ts.processing_stack, symbol)
	defer pop(&ts.processing_stack)
	defer if ret_err == .OK && header.state != .Failed {
		header.state = .Done
	} else {
		header.state = .Failed
	}

	switch symbol in symbol {
	case ^resolver.Function:
		err := translate_function_signature(ts, symbol, symbol.defined_in)
		if err != .OK {
			return .Malformed
		}
		if symbol.hir == nil { 	// this will eventually become an assert
			return .Not_Implemented
		}

		if symbol.name == "main" &&
		   symbol.defined_in != nil &&
		   symbol.defined_in.own_package == ts.entry_package {
			ts.output.entry_point = symbol.hir
		}

	case ^resolver.Global_Variable:
		return .Not_Implemented
	case ^resolver.Constant:
		return .Not_Implemented
	case ^resolver.Struct_Type:
		return .Not_Implemented
	case ^resolver.Enum_Type:
		return .Not_Implemented
	case ^resolver.Type_Alias:
		return .Not_Implemented
	case ^resolver.Distinct_Type:
		return .Not_Implemented
	case ^resolver.Base_Unit:
		return .Not_Implemented
	case ^resolver.Unit_Alias:
		return .Not_Implemented
	case ^resolver.Capability:
		return .Not_Implemented
	case ^resolver.Annotation:
		return .Not_Implemented

	case ^resolver.Local_Variable, ^resolver.Formal_Parameter, ^resolver.Named_Return:
		// getting here is a logic error; locals should ALWAYS be pre-resolved and have their state set to .Done
		fmt.panicf(
			"%s(...) got a %T that wasn't already fully resolved",
			#location().procedure,
			reflect.get_union_variant(symbol),
		)

	case ^resolver.Builtin, ^resolver.Import:
		panic("unreachable")
	}

	return .OK
}

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

		ptype, pt_ok := build_type(ts, ast_param.type, symbol.defined_in)
		if ptype == nil {
			continue
		}

		punit: hir.Realized_Unit
		if ast_param.unit != nil {
			pu_ok: bool
			punit, pu_ok = build_unit(ts, ast_param.unit, symbol.defined_in)
			if !pu_ok {
				continue
			}
		} else {
			continue
		}

		pdefault: ^hir.Const_Expr
		if ast_param.default != nil {
			built_default, def_ok := build_expr(ts, ast_param.default, symbol.defined_in)
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
		rtype, rt_ok := build_type(ts, ret.type, symbol.defined_in)
		runit, ru_ok := build_unit(ts, ret.unit, symbol.defined_in)

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
		err_type = build_type(ts, func.error_type, symbol.defined_in) or_else nil
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
			ensure_symbol_processed(ts, resolved)
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

_emit_cyclical_dependency_error :: proc(ts: ^Translation_State, symbol: resolver.Symbol) {
	idx, found := slice.linear_search(ts.processing_stack[:], symbol)
	if !found {
		return
	}

	last_name := resolver.symbol_name(symbol)
	diag := diagnostics.emit(
		.Cyclical_Dependency,
		resolver.span_of_name(symbol) or_else {},
		"'%s' forms a cyclical dependency",
		last_name,
	)

	for dep in ts.processing_stack[idx + 1:] {
		dep_name := resolver.symbol_name(dep)
		diagnostics.reference(
			diag,
			resolver.span_of_name(dep) or_else {},
			"%s depends on the definition of %s",
			last_name,
			dep_name,
		)
		last_name = dep_name
	}
}


_primitive_type :: proc(builtin: ^resolver.Builtin) -> (hir.Primitive_Type, bool) {
	switch builtin.name {
	// The unsized language-level defaults use the widest required primitive
	// representation until range-driven narrowing is implemented.
	case "Int128":
		return .Int128, true
	case "Int64":
		return .Int64, true
	case "Int32":
		return .Int32, true
	case "Int16":
		return .Int16, true
	case "Int8":
		return .Int8, true
	case "UInt128":
		return .UInt128, true
	case "UInt64":
		return .UInt64, true
	case "UInt32":
		return .UInt32, true
	case "UInt16":
		return .UInt16, true
	case "UInt8":
		return .UInt8, true
	case "Float64":
		return .Bin64, true
	case "Float32":
		return .Bin32, true
	case "Float16":
		return .Bin16, true
	case "Boolean":
		return .Boolean, true
	case "String":
		return .String, true
	case "Rune":
		return .Rune, true
	case "Byte":
		return .Byte, true
	case "Any":
		return .Any, true
	case "Opaque":
		return .Opaque, true
	case "Opaque8":
		return .Opaque8, true
	case "Opaque16":
		return .Opaque16, true
	case "Opaque32":
		return .Opaque32, true
	case "Opaque64":
		return .Opaque64, true
	}

	return {}, false
}


_validate_entry_point :: proc(entry: ^hir.Func_Definition) -> bool {
	ok := true
	if len(entry.params) != 0 {
		diagnostics.emit(
			.Invalid_Entry_Point,
			common.merge_spans(entry.params[0].span, entry.params[len(entry.params) - 1].span),
			"func 'main' must not accept parameters",
		)
		ok = false
	}
	if len(entry.returns) != 0 {
		diagnostics.emit(
			.Invalid_Entry_Point,
			common.merge_spans(entry.returns[0].span, entry.returns[len(entry.returns) - 1].span),
			"func 'main' must not return values",
		)
		ok = false
	}
	if .Fallible in entry.flags {
		diagnostics.emit(.Invalid_Entry_Point, entry.name.span, "func 'main' must not be fallible")
		ok = false
	}
	return ok
}
