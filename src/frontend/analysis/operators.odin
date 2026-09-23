package analysis

import "../../common"
import "../../common/exact"
import "../diagnostics"
import "../hir"
import "core:fmt"
import "core:reflect"
import "core:strings"

Operator_Compat_Category :: enum {
	Empty,
	Integer,
	Rational,
	Bin_Float,
	Boolean,
	Ordered,
	Opaque,
	Enum,
}

Operator_Compat_Data :: struct {
	name:              string,
	supported_binops:  bit_set[common.Binary_Op],
	binop_diagnostics: proc(_: ^diagnostics.Diagnostic, _: common.Binary_Op),
}

@(rodata)
OP_CATEGORY_DEFS := [Operator_Compat_Category]Operator_Compat_Data {
	.Integer = {
		name = "integer",
		supported_binops = {
			.Add,
			.Subtract,
			.Multiply,
			.Floor_Divide,
			.Power,
			.Modulo,
			.Remainder,
			.Equal,
			.Not_Equal,
			.Less,
			.Less_Equal,
			.Greater,
			.Greater_Equal,
		},
		binop_diagnostics = proc(diag: ^diagnostics.Diagnostic, op: common.Binary_Op) {
			#partial switch op {
			case .True_Divide:
				diagnostics.suggest(diag, "did you mean to use // ? (the floor division operator)")
			}
		},
	},
	.Rational = {
		name = "rational",
		supported_binops = {
			.Add,
			.Subtract,
			.Multiply,
			.True_Divide,
			.Floor_Divide,
			.Power,
			.Modulo,
			.Remainder,
			.Equal,
			.Not_Equal,
			.Less,
			.Less_Equal,
			.Greater,
			.Greater_Equal,
		},
	},
	.Bin_Float = {
		name = "binary floating point",
		supported_binops = {
			.Add,
			.Subtract,
			.Multiply,
			.True_Divide,
			.Floor_Divide,
			.Power,
			.Modulo,
			.Remainder,
			.Less,
			.Less_Equal,
			.Greater,
			.Greater_Equal,
		},
		binop_diagnostics = proc(diag: ^diagnostics.Diagnostic, op: common.Binary_Op) {
			#partial switch op {
			case .Equal, .Not_Equal:
				diagnostics.suggest(
					diag,
					"consider using an approximate equality function from intrinsics:float",
				)
			}
		},
	},
	.Ordered = {
		name = "ordered",
		supported_binops = {.Equal, .Not_Equal, .Less, .Less_Equal, .Greater, .Greater_Equal},
	},
	.Boolean = {name = "boolean", supported_binops = {.Equal, .Not_Equal, .And, .Or}},
	.Enum = {name = "enum", supported_binops = {.Is, .Is_Not}},
	.Opaque = {name = "opaque", supported_binops = {.Equal, .Not_Equal}},
	.Empty = {name = "no-operator", supported_binops = {}},
}

_op_category_of :: proc(typ: Comptime_Type) -> Operator_Compat_Category {
	switch comptime_type in typ {
	case Flexible_Type:
		switch comptime_type.affinity {
		case .Contextual, .Boolean:
			return .Boolean
		case .String, .Rune:
			return .Ordered
		case .Integer, .Unsigned_Integer:
			return .Integer
		case .Decimal, .Rational:
			return .Rational
		case .Binary_Float:
			return .Bin_Float
		case .Byte:
			return .Opaque
		}

	case hir.Type:
		switch concrete in comptime_type {
		case ^hir.Distinct_Type:
			return _op_category_of(concrete.underlying)
		case ^hir.Enum_Type:
			return .Enum
		case ^hir.Struct_Type:
			return .Empty
		case ^hir.Fixed_Array_Type:
			return _op_category_of(concrete.elem)
		case hir.Fixed_Decimal:
			if concrete.scale == 0 {
				return .Integer
			}
			return .Rational
		case hir.Primitive_Type:
			switch concrete {
			case .Boolean:
				return .Boolean
			case .String, .Rune:
				return .Ordered
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
				return .Integer
			case .Bin64, .Bin32, .Bin16:
				return .Bin_Float
			case .Byte, .Opaque, .Opaque8, .Opaque16, .Opaque32, .Opaque64:
				return .Opaque
			case .Any:
				return .Empty
			}
		case ^hir.Interface,
		     ^hir.Generic_Type,
		     ^hir.Dynamic_Array_Type,
		     ^hir.View_Type,
		     ^hir.Map_Type,
		     ^hir.Optional_Type,
		     ^hir.Pointer_Type,
		     ^hir.Tagged_Type:
			return .Opaque
		}
	}
	return .Opaque
}

_comptime_binop :: proc(op: common.Binary_Op, lhs, rhs: common.Value) -> common.Value {
	switch op {
	case .Add:
		return exact.add(lhs.(exact.Rat), rhs.(exact.Rat))
	case .Subtract:
		return exact.sub(lhs.(exact.Rat), rhs.(exact.Rat))
	case .Multiply:
		return exact.mul(lhs.(exact.Rat), rhs.(exact.Rat))
	case .True_Divide:
		return exact.div(lhs.(exact.Rat), rhs.(exact.Rat))
	case .Floor_Divide:
		return exact.floordiv(lhs.(exact.Rat), rhs.(exact.Rat))
	case .Remainder:
		return exact.rem(lhs.(exact.Rat), rhs.(exact.Rat))
	case .Modulo:
		return exact.mod(lhs.(exact.Rat), rhs.(exact.Rat))
	case .Power:
	case .Equal:
		return _comptime_equal(lhs, rhs)
	case .Not_Equal:
		return !_comptime_equal(lhs, rhs)
	case .Less:
		return _comptime_less(lhs, rhs)
	case .Less_Equal:
		return !_comptime_less(rhs, lhs)
	case .Greater:
		return _comptime_less(rhs, lhs)
	case .Greater_Equal:
		return !_comptime_less(lhs, rhs)
	case .Is:
	case .Is_Not:
	case .And:
		return lhs.(bool) && rhs.(bool)
	case .Or:
		return lhs.(bool) || rhs.(bool)
	}

	fmt.panicf(
		"missing implementation of %T %s %T",
		reflect.get_union_variant(lhs),
		common.BINARY_OP_STRINGS[op],
		reflect.get_union_variant(rhs),
	)
}

_comptime_equal :: proc(lhs, rhs: common.Value) -> bool {
	switch l in lhs {
	case exact.Rat:
		return exact.eq(l, rhs.(exact.Rat))
	case string:
		return l == rhs.(string)
	case rune:
		return l == rhs.(rune)
	case byte:
		return l == rhs.(byte)
	case bool:
		return l == rhs.(bool)
	case common.Untyped_Value:
		panic("untyped values should have already been coerced")
	}
	return false
}

_comptime_less :: proc(lhs, rhs: common.Value) -> bool {
	switch l in lhs {
	case exact.Rat:
		return exact.lt(l, rhs.(exact.Rat))
	case string:
		return strings.compare(l, rhs.(string)) < 0
	case rune:
		return l < rhs.(rune)
	case byte:
		return l < rhs.(byte)
	case bool, common.Untyped_Value:
		panic("value does not support ordering")
	}
	return false
}
