package analysis

import "../../common"
import "../ast"
import "../diagnostics"
import "../hir"
import "../resolver"


process_toplevel_items :: proc(ts: ^Translation_State) -> bool {
	assert(ts != nil)

	symbol_count := 0
	incoherent_symbols_count := 0
	for pkg in ts.symbol_resolver.loaded_packages {
		for file in pkg.files {
			for symbol in file.defined_symbols {
				switch check_toplevel_declaration(ts, symbol) {
				case .OK:
					symbol_count += 1
				case .Incoherent:
					incoherent_symbols_count += 1

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

	return incoherent_symbols_count == 0
}

Signature_Error :: enum {
	OK,
	Incoherent,
}

check_toplevel_declaration :: proc(
	ts: ^Translation_State,
	symbol: resolver.Symbol,
) -> Signature_Error {
	return .OK // TODO
}

Func_Translation_Error :: enum {
	OK,
	Invalid_Types,
}

translate_function :: proc(
	ts: ^Translation_State,
	symbol: resolver.Symbol,
) -> Func_Translation_Error {
	return .OK // TODO
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
