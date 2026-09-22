package analysis

import "core:math/big"

import "../../common"
import "../../common/exact"
import "../ast"
import "../diagnostics"
import "../hir"
import "../resolver"


build_type :: proc(
	ts: ^Translation_State,
	type_ast: ast.Type_Expression,
	scope: resolver.Scope,
) -> (
	hir.Type,
	bool,
) {
	switch node in type_ast {
	case ^ast.Simple_Type:
		#partial switch symbol in resolve(ts, scope, node.type) {
		case ^resolver.Builtin:
			if primitive, ok := _primitive_type(symbol); ok {
				return primitive, true
			}
		case ^resolver.Type_Alias:
			if symbol.hir != nil {
				return symbol.hir, true
			}
		case ^resolver.Struct_Type:
			if symbol.hir != nil {
				return symbol.hir, true
			}
		case ^resolver.Enum_Type:
			if symbol.hir != nil {
				return symbol.hir, true
			}
		case ^resolver.Distinct_Type:
			if symbol.hir != nil {
				return symbol.hir, true
			}
		case nil:
			return nil, false
		case:
		}

		diagnostics.emit(.Invalid_Type, node.span, "'%s' does not name a type", node.type)

	case ^ast.Type_With_Args:
		symbol := resolve(ts, scope, node.base)
		builtin, is_builtin := symbol.(^resolver.Builtin)
		if !is_builtin || builtin.kind != .Parametric_Type {
			if symbol != nil {
				diagnostics.emit(
					.Invalid_Type,
					node.base.span,
					"'%s' is not a parametric type",
					node.base,
				)
			}
			return nil, false
		}

		// TEMP: Integer and Decimal are hard-coded as the only two types

		expected_args := 1 if builtin.name == "Integer" else 2
		if len(node.args) != expected_args {
			diagnostics.emit(
				.Invalid_Type,
				node.span,
				"'%s' expects %d type arguments, got %d",
				builtin.name,
				expected_args,
				len(node.args),
			)
			return nil, false
		}

		digits: int
		scale: int
		args_ok := true
		for arg, index in node.args {
			if arg.name != nil {
				diagnostics.emit(.Invalid_Type, arg.span, "type arguments must be positional")
				args_ok = false
				continue
			}

			argument_value: int
			argument_ok := false
			switch evaluated in evaluate(ts, arg.expr, scope) {
			case Comptime_Value:
				#partial switch value in evaluated.value {
				case exact.Rat:
					if exact.is_one(value.denominator) {
						switch integer in value.numerator {
						case i128:
							if integer >= i128(min(int)) && integer <= i128(max(int)) {
								argument_value = int(integer)
								argument_ok = true
							}
						case ^big.Int:
							converted, err := big.get(integer, int)
							if err == nil {
								argument_value = converted
								argument_ok = true
							}
						}
					}
				case:
				}
			case hir.Expression:
			}

			if !argument_ok {
				diagnostics.emit(
					.Invalid_Type,
					arg.span,
					"type argument must be a compile-time integer in the representable range",
				)
				args_ok = false
				continue
			}

			if index == 0 {
				digits = argument_value
			} else {
				scale = argument_value
			}
		}

		if !args_ok {
			return nil, false
		}
		if digits <= 0 {
			diagnostics.emit(.Invalid_Type, node.args[0].span, "digits must be positive")
			return nil, false
		}
		if digits > hir.MAX_DECIMAL_DIGITS {
			diagnostics.emit(
				.Invalid_Type,
				node.args[0].span,
				"exceeds maximum digits (%d > %d)",
				digits,
				hir.MAX_DECIMAL_DIGITS,
			)
			return nil, false
		}
		if scale < hir.MIN_DECIMAL_SCALE || scale > hir.MAX_DECIMAL_SCALE {
			diagnostics.emit(
				.Invalid_Type,
				node.args[0].span,
				"decimal scale is outside valid range (%d not_in %d ..= %d",
				scale,
				hir.MIN_DECIMAL_SCALE,
				hir.MAX_DECIMAL_SCALE,
			)
			return nil, false
		}

		return hir.Fixed_Decimal{digits = i32(digits), scale = i32(scale)}, true

	case ^ast.Generic_Type:
		bound: hir.Type
		if node.bound != nil {
			bound_ok: bool
			bound, bound_ok = build_type(ts, node.bound, scope)
			if !bound_ok {
				return nil, false
			}
		}

		generic := new(hir.Generic_Type, ts.output.allocator)
		generic^ = {
			name  = node.name.id,
			bound = bound,
		}
		return generic, true

	case ^ast.Optional_Type:
		base, ok := build_type(ts, node.base, scope)
		if !ok {
			return nil, false
		}

		optional := new(hir.Optional_Type, ts.output.allocator)
		optional.base = base
		return optional, true

	case ^ast.Pointer_Type:
		to, ok := build_type(ts, node.to, scope)
		if !ok {
			return nil, false
		}

		pointer := new(hir.Pointer_Type, ts.output.allocator)
		pointer^ = {
			to        = to,
			ownership = node.ownership,
			nullable  = false,
		}
		return pointer, true

	case ^ast.Type_With_Tags:
		base, ok := build_type(ts, node.base, scope)
		if !ok {
			return nil, false
		}

		tags := make([]hir.Symbol_ID, len(node.tags), ts.output.allocator)
		for tag, index in node.tags {
			symbol := resolve(ts, scope, tag)
			if symbol == nil {
				return nil, false
			}

			if header := resolver.symbol_header(symbol); header != nil {
				tags[index] = header.id
			} else if builtin, is_builtin := symbol.(^resolver.Builtin); is_builtin {
				tags[index] = builtin.id
			} else {
				diagnostics.emit(.Invalid_Type, tag.span, "'%s' cannot be used as a type tag", tag)
				return nil, false
			}
		}

		tagged := new(hir.Tagged_Type, ts.output.allocator)
		tagged^ = {
			base = base,
			tags = tags,
		}
		return tagged, true

	case nil:
	}

	return nil, false
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

is_boolean :: proc(t: Comptime_Type) -> bool {
	return false // TODO
}

is_string :: proc(t: Comptime_Type) -> bool {
	return false // TODO
}
