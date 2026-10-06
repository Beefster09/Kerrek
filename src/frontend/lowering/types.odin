package lowering

import "core:fmt"
import "core:reflect"

import "../hir"
import "../mir"

lower_type_def :: proc(ctx: ^Translation_Context, type: hir.Type_Definition) -> mir.Type {
	return nil
}

INT64_DECIMAL_MAX_MAGNITUDE :: 18.964889726830815
INT128_DECIMAL_MAX_MAGNITUDE :: 38.23080944932561
INT256_DECIMAL_MAX_MAGNITUDE :: 76.7626488943152

lower_type :: proc(ctx: ^Translation_Context, type: hir.Type) -> mir.Type {
	switch type in type {
	case hir.Primitive_Type:
		switch type {
		case .Int128:
			return mir.Primitive_Type.Int128
		case .Int64:
			return mir.Primitive_Type.Int64
		case .Int32:
			return mir.Primitive_Type.Int32
		case .Int16:
			return mir.Primitive_Type.Int16
		case .Int8:
			return mir.Primitive_Type.Int8
		case .UInt128:
			return mir.Primitive_Type.UInt128
		case .UInt64:
			return mir.Primitive_Type.UInt64
		case .UInt32:
			return mir.Primitive_Type.UInt32
		case .UInt16:
			return mir.Primitive_Type.UInt16
		case .UInt8:
			return mir.Primitive_Type.UInt8
		case .Bin64:
			return mir.Primitive_Type.Bin64
		case .Bin32:
			return mir.Primitive_Type.Bin32
		case .Bin16:
			return mir.Primitive_Type.Bin16
		case .Boolean:
			return mir.Primitive_Type.Boolean
		case .String:
			return mir.Primitive_Type.String
		case .Rune:
			return mir.Primitive_Type.UInt32
		case .Byte:
			return mir.Primitive_Type.UInt8
		case .Type:
		case .Any:
		}

	case hir.Fixed_Decimal:
		switch {
		case type.magnitude < INT64_DECIMAL_MAX_MAGNITUDE:
			return mir.Primitive_Type.Int64
		case type.magnitude < INT128_DECIMAL_MAX_MAGNITUDE:
			return mir.Primitive_Type.Int128
		case type.magnitude < INT256_DECIMAL_MAX_MAGNITUDE:
			return mir.Primitive_Type.Int256
		}

	case ^hir.Struct_Type:
	case ^hir.Enum_Type:
	case ^hir.Distinct_Type:
	case ^hir.Interface:
	case ^hir.Generic_Type:
	case ^hir.Fixed_Array_Type:
	case ^hir.Dynamic_Array_Type:
	case ^hir.View_Type:
	case ^hir.Map_Type:
	case ^hir.Optional_Type:
	case ^hir.Pointer_Type:
	case ^hir.Tagged_Type:
	case ^hir.Func_Type:
	}

	fmt.panicf("MIR type lowering not yet implemented for %T", reflect.get_union_variant(type))
}
