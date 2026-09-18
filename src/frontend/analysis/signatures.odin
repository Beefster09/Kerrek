package analysis

import "../../common"
import "../ast"
import "../diagnostics"
import "../hir"
import "../resolver"
import "core:slice"


process_toplevel_items :: proc(ts: ^Translation_State) -> bool {
	assert(ts != nil)

	symbol_count := 0
	malformed_count := 0
	for pkg in ts.symbol_resolver.loaded_packages {
		for file in pkg.files {
			for symbol in file.defined_symbols {
				switch ensure_symbol_processed(ts, symbol, file) {
				case .OK:
					symbol_count += 1
				case .Malformed, .Cyclical_Dependency:
					malformed_count += 1

				}
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
}

ensure_symbol_processed :: proc(
	ts: ^Translation_State,
	symbol: resolver.Symbol,
	scope: resolver.Scope,
) -> Symbol_Processing_Error {
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

	switch symbol in symbol {
	case ^resolver.Function:
		translate_function_signature(ts, symbol)
		queue_build_function_body(ts, symbol)
	case ^resolver.Global_Variable:
	case ^resolver.Local_Variable:
	case ^resolver.Constant:
	case ^resolver.Struct_Type:
	case ^resolver.Enum_Type:
	case ^resolver.Type_Alias:
	case ^resolver.Distinct_Type:
	case ^resolver.Unit_Type:
	case ^resolver.Base_Unit:
	case ^resolver.Unit_Type_Alias:
	case ^resolver.Unit_Alias:
	case ^resolver.Capability:
	case ^resolver.Annotation:
	case ^resolver.Formal_Parameter:
	case ^resolver.Named_Return:
	case ^resolver.Builtin, ^resolver.Import:
		panic("unreachable")
	}

	return .OK // TODO
}

Func_Translation_Error :: enum {
	OK,
	Invalid_Types,
}

translate_function_signature :: proc(
	ts: ^Translation_State,
	symbol: ^resolver.Function,
) -> Func_Translation_Error {
	return .OK // TODO
}

queue_build_function_body :: proc(
	ts: ^Translation_State,
	symbol: ^resolver.Function,
) -> Func_Translation_Error {
	return .OK // TODO
}

build_function_body :: proc(
	ts: ^Translation_State,
	symbol: ^resolver.Function,
) -> Func_Translation_Error {
	return .OK // TODO
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
	if entry.fallible {
		diagnostics.emit(.Invalid_Entry_Point, entry.name.span, "func 'main' must not be fallible")
		ok = false
	}
	return ok
}
