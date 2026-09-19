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
				switch ensure_toplevel_symbol_processed(ts, symbol) {
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

ensure_toplevel_symbol_processed :: proc(
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
