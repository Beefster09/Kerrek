package analysis

import "core:fmt"
import "core:io"
import "core:math/big"
import "core:reflect"

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
			} else if symbol.kind == .Parametric_Type {
				diagnostics.emit(
					.Invalid_Type,
					node.span,
					"builtin type '%s' requires arguments",
					node.type,
				)
				return nil, false
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

		// TEMP: Integer and Decimal are hard-coded as the only two parametric types

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

types_equal :: proc(a, b: Comptime_Type) -> bool {
	switch a in a {
	case Flexible_Type:
		b, ok := b.(Flexible_Type)
		return ok && a.affinity == b.affinity

	case hir.Type:
		b, ok := b.(hir.Type)
		if !ok {
			return false
		}

		switch a in a {
		case hir.Primitive_Type:
			b, ok := b.(hir.Primitive_Type)
			return ok && a == b

		case hir.Fixed_Decimal:
			b, ok := b.(hir.Fixed_Decimal)
			return ok && a == b

		case ^hir.Struct_Type:
			b, ok := b.(^hir.Struct_Type)
			return ok && a == b

		case ^hir.Enum_Type:
			b, ok := b.(^hir.Enum_Type)
			return ok && a == b

		case ^hir.Distinct_Type:
			b, ok := b.(^hir.Distinct_Type)
			return ok && a == b

		case ^hir.Interface:
			b, ok := b.(^hir.Interface)
			return ok && a == b

		case ^hir.Generic_Type:
			// TODO: Implement generic type equality.
			return false

		case ^hir.Fixed_Array_Type:
			b, ok := b.(^hir.Fixed_Array_Type)
			if !ok || !types_equal(a.elem, b.elem) || len(a.shape) != len(b.shape) {
				return false
			}
			for size, i in a.shape {
				if size != b.shape[i] {
					return false
				}
			}
			return true

		case ^hir.Dynamic_Array_Type:
			b, ok := b.(^hir.Dynamic_Array_Type)
			return ok && types_equal(a.elem, b.elem)

		case ^hir.View_Type:
			b, ok := b.(^hir.View_Type)
			return ok && a.dimensions == b.dimensions && types_equal(a.elem, b.elem)

		case ^hir.Map_Type:
			b, ok := b.(^hir.Map_Type)
			return ok && types_equal(a.key, b.key) && types_equal(a.value, b.value)

		case ^hir.Optional_Type:
			b, ok := b.(^hir.Optional_Type)
			return ok && types_equal(a.base, b.base)

		case ^hir.Pointer_Type:
			b, ok := b.(^hir.Pointer_Type)
			return(
				ok &&
				a.ownership == b.ownership &&
				a.nullable == b.nullable &&
				types_equal(a.to, b.to) \
			)

		case ^hir.Tagged_Type:
			b, ok := b.(^hir.Tagged_Type)
			if !ok || !types_equal(a.base, b.base) || len(a.tags) != len(b.tags) {
				return false
			}
			for tag, i in a.tags {
				if tag != b.tags[i] {
					return false
				}
			}
			return true
		}
	}

	return false
}

is_integer :: proc(t: Comptime_Type) -> bool {
	switch comptime_type in t {
	case Flexible_Type:
		#partial switch comptime_type.affinity {
		case .Unsigned_Integer, .Integer:
			return true
		}
	case hir.Type:
		#partial switch concrete in comptime_type {
		case ^hir.Distinct_Type:
			return is_integer(concrete.underlying)
		case hir.Fixed_Decimal:
			return concrete.scale == 0
		case hir.Primitive_Type:
			switch concrete {
			case .Int128,
			     .Int64,
			     .Int32,
			     .Int16,
			     .Int8,
			     .UInt128,
			     .UInt64,
			     .UInt32,
			     .UInt16,
			     .UInt8:
				return true
			case .Bin64,
			     .Bin32,
			     .Bin16,
			     .Boolean,
			     .String,
			     .Rune,
			     .Byte,
			     .Any,
			     .Opaque,
			     .Opaque8,
			     .Opaque16,
			     .Opaque32,
			     .Opaque64:
				return false
			}
		}
	}
	return false
}

is_decimal :: proc(t: Comptime_Type) -> bool {
	switch comptime_type in t {
	case Flexible_Type:
		return comptime_type.affinity == .Decimal
	case hir.Type:
		#partial switch concrete in comptime_type {
		case ^hir.Distinct_Type:
			return is_decimal(concrete.underlying)
		case hir.Fixed_Decimal:
			return concrete.scale != 0
		}
	}
	return false
}

is_binfloat :: proc(t: Comptime_Type) -> bool {
	switch comptime_type in t {
	case Flexible_Type:
		return comptime_type.affinity == .Binary_Float
	case hir.Type:
		#partial switch concrete in comptime_type {
		case ^hir.Distinct_Type:
			return is_binfloat(concrete.underlying)
		case hir.Primitive_Type:
			#partial switch concrete {
			case .Bin64, .Bin32, .Bin16:
				return true
			}
		}
	}
	return false
}

is_boolean :: proc(t: Comptime_Type) -> bool {
	switch comptime_type in t {
	case Flexible_Type:
		return comptime_type.affinity == .Boolean
	case hir.Type:
		#partial switch concrete in comptime_type {
		case ^hir.Distinct_Type:
			return is_boolean(concrete.underlying)
		case hir.Primitive_Type:
			return concrete == .Boolean
		}
	}
	return false
}

is_string :: proc(t: Comptime_Type) -> bool {
	switch comptime_type in t {
	case Flexible_Type:
		return comptime_type.affinity == .String
	case hir.Type:
		#partial switch concrete in comptime_type {
		case ^hir.Distinct_Type:
			return is_string(concrete.underlying)
		case hir.Primitive_Type:
			return concrete == .String
		}
	}
	return false
}

is_rune :: proc(t: Comptime_Type) -> bool {
	switch comptime_type in t {
	case Flexible_Type:
		return comptime_type.affinity == .Rune
	case hir.Type:
		#partial switch concrete in comptime_type {
		case ^hir.Distinct_Type:
			return is_rune(concrete.underlying)
		case hir.Primitive_Type:
			return concrete == .Rune
		}
	}
	return false
}

is_pointer :: proc(t: Comptime_Type) -> bool {
	switch comptime_type in t {
	case Flexible_Type:
		return false
	case hir.Type:
		#partial switch concrete in comptime_type {
		case ^hir.Distinct_Type:
			return is_pointer(concrete.underlying)
		case ^hir.Tagged_Type:
			return is_pointer(concrete.base)
		case ^hir.Pointer_Type:
			return true
		}
	}
	return false
}


fmt_comptime_type :: proc(fi: ^fmt.Info, arg: any, verb: rune) -> bool {
	assert(arg.id == Comptime_Type)
	switch verb {
	case 's':
		write_comptime_type(fi.writer, (cast(^Comptime_Type)arg.data)^)
		return true
	}

	return false
}

write_comptime_type :: proc(w: io.Writer, type: Comptime_Type) {
	switch type in type {
	case Flexible_Type:
		switch type.affinity {
		case .Contextual:
			io.write_string(w, "unknown type")
		case .Unsigned_Integer:
			io.write_string(w, "flexible unsigned integer")
		case .Integer:
			io.write_string(w, "flexible integer")
		case .Decimal:
			io.write_string(w, "flexible decimal")
		case .Binary_Float:
			io.write_string(w, "flexible binary float")
		case .Rational:
			io.write_string(w, "flexible rational number")
		case .Boolean:
			io.write_string(w, "flexible boolean")
		case .String:
			io.write_string(w, "flexible string")
		case .Rune:
			io.write_string(w, "flexible rune")
		case .Byte:
			io.write_string(w, "flexible byte")
		}
	case hir.Type:
		write_type(w, type)
	}
}

write_type :: proc(w: io.Writer, type: hir.Type) {
	switch type in type {
	case hir.Primitive_Type:
		io.write_string(w, reflect.enum_string(type))

	case hir.Fixed_Decimal:
		if type.scale == 0 {
			io.write_string(w, "Integer(")
			io.write_int(w, int(type.digits))
			io.write_rune(w, ')')
		} else {
			io.write_string(w, "Decimal(")
			io.write_int(w, int(type.digits))
			io.write_string(w, ", ")
			io.write_int(w, int(type.scale))
			io.write_rune(w, ')')
		}

	case ^hir.Struct_Type:
		io.write_string(w, string(type.name.id))
	case ^hir.Enum_Type:
		io.write_string(w, string(type.name.id))
	case ^hir.Distinct_Type:
		io.write_string(w, string(type.name.id))
	case ^hir.Interface:
		io.write_string(w, string(type.name.id))

	case ^hir.Fixed_Array_Type:
		io.write_rune(w, '[')
		for size, i in type.shape {
			if i > 0 {
				io.write_string(w, ", ")
			}
			io.write_int(w, int(size))
		}
		io.write_rune(w, ']')
		write_type(w, type.elem)

	case ^hir.Dynamic_Array_Type:
		io.write_string(w, "[dynamic]")
		write_type(w, type.elem)

	case ^hir.View_Type:
		io.write_rune(w, '[')
		if type.dimensions > 1 {
			io.write_rune(w, '#')
			io.write_int(w, type.dimensions)
		}
		io.write_rune(w, ']')
		write_type(w, type.elem)

	case ^hir.Map_Type:
		io.write_string(w, "map[")
		write_type(w, type.key)
		io.write_rune(w, ']')
		write_type(w, type.value)

	case ^hir.Optional_Type:
		io.write_rune(w, '?')
		write_type(w, type.base)

	case ^hir.Pointer_Type:
		switch type.ownership {
		case .Borrow:
			io.write_rune(w, '^')
		case .Owned:
			io.write_string(w, "owned ")
		case .Shared:
			io.write_string(w, "shared ")
		case .Weak:
			io.write_string(w, "weak ")
		case .Unsafe:
			io.write_string(w, "unsafe.Pointer(")
		}
		write_type(w, type.to)
		if type.ownership == .Unsafe {
			io.write_rune(w, ')')
		}

	case ^hir.Tagged_Type:
		write_type(w, type.base)
		for tag in type.tags {
			// TODO
		}

	case ^hir.Generic_Type:
	}
}
