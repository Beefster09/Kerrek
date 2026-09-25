package analysis

import "../../common"
import "../../util"
import "../hir"
import "core:slice"

@(rodata)
PRIMITIVE_TYPE_METADATA := [hir.Primitive_Type]struct #all_or_none {
	implicitly_to:    bit_set[hir.Primitive_Type],
	explicit_group:   Explicit_Conversion_Group,
	// The number of bits the type takes up
	// -1 for "considered an implementation detail / system-dependent"
	size_bytes:       int,
	// The number of bits of absolute precision
	// -1 for unknown/not applicable
	significant_bits: int,
	// The number of base-10 significant digits representable without loss
	// -1 for unknown/not applicable
	decimal_digits:   int,
	signedness:       enum u8 {
		Not_Applicable,
		Unknown,
		Unsigned,
		Signed,
	},
	numeric_class:    enum u8 {
		Not_A_Number,
		Unknown,
		Float,
		Integer,
	},
} {
	.Int128 = {
		implicitly_to = {.Any, .Int128},
		explicit_group = .Numeric,
		size_bytes = 16,
		significant_bits = 127,
		decimal_digits = 38,
		signedness = .Signed,
		numeric_class = .Integer,
	},
	.Int64 = {
		implicitly_to = {.Any, .Int64, .Int128},
		explicit_group = .Numeric,
		size_bytes = 8,
		significant_bits = 63,
		decimal_digits = 18,
		signedness = .Signed,
		numeric_class = .Integer,
	},
	.Int32 = {
		implicitly_to = {.Any, .Int32, .Int64, .Int128, .Bin64},
		explicit_group = .Numeric,
		size_bytes = 4,
		significant_bits = 31,
		decimal_digits = 9,
		signedness = .Signed,
		numeric_class = .Integer,
	},
	.Int16 = {
		implicitly_to = {.Any, .Int16, .Int32, .Int64, .Int128, .Bin32, .Bin64},
		explicit_group = .Numeric,
		size_bytes = 2,
		significant_bits = 15,
		decimal_digits = 4,
		signedness = .Signed,
		numeric_class = .Integer,
	},
	.Int8 = {
		implicitly_to = {.Any, .Int8, .Int16, .Int32, .Int64, .Int128, .Bin16, .Bin32, .Bin64},
		explicit_group = .Numeric,
		size_bytes = 1,
		significant_bits = 7,
		decimal_digits = 2,
		signedness = .Signed,
		numeric_class = .Integer,
	},
	.UInt128 = {
		implicitly_to = {.Any, .UInt128},
		explicit_group = .Numeric,
		size_bytes = 16,
		significant_bits = 128,
		decimal_digits = 38,
		signedness = .Unsigned,
		numeric_class = .Integer,
	},
	.UInt64 = {
		implicitly_to = {.Any, .UInt64, .UInt128, .Int128},
		explicit_group = .Numeric,
		size_bytes = 8,
		significant_bits = 64,
		decimal_digits = 19,
		signedness = .Unsigned,
		numeric_class = .Integer,
	},
	.UInt32 = {
		implicitly_to = {.Any, .UInt32, .UInt64, .UInt128, .Int64, .Int128, .Bin64},
		explicit_group = .Numeric,
		size_bytes = 4,
		significant_bits = 32,
		decimal_digits = 9,
		signedness = .Unsigned,
		numeric_class = .Integer,
	},
	.UInt16 = {
		implicitly_to = {
			.Any,
			.UInt16,
			.UInt32,
			.UInt64,
			.UInt128,
			.Int32,
			.Int64,
			.Int128,
			.Bin32,
			.Bin64,
		},
		explicit_group = .Numeric,
		size_bytes = 2,
		significant_bits = 16,
		decimal_digits = 4,
		signedness = .Unsigned,
		numeric_class = .Integer,
	},
	.UInt8 = {
		implicitly_to = {
			.Any,
			.UInt8,
			.UInt16,
			.UInt32,
			.UInt64,
			.UInt128,
			.Int16,
			.Int32,
			.Int64,
			.Int128,
			.Bin16,
			.Bin32,
			.Bin64,
		},
		explicit_group = .Numeric,
		size_bytes = 1,
		significant_bits = 8,
		decimal_digits = 2,
		signedness = .Unsigned,
		numeric_class = .Integer,
	},
	.Bin64 = {
		implicitly_to = {.Any, .Bin64},
		explicit_group = .Numeric,
		size_bytes = 8,
		significant_bits = 53,
		decimal_digits = 15,
		signedness = .Signed,
		numeric_class = .Float,
	},
	.Bin32 = {
		implicitly_to = {.Any, .Bin32, .Bin64},
		explicit_group = .Numeric,
		size_bytes = 4,
		significant_bits = 24,
		decimal_digits = 6,
		signedness = .Signed,
		numeric_class = .Float,
	},
	.Bin16 = {
		implicitly_to = {.Any, .Bin16, .Bin32, .Bin64},
		explicit_group = .Numeric,
		size_bytes = 2,
		significant_bits = 11,
		decimal_digits = 3,
		signedness = .Signed,
		numeric_class = .Float,
	},
	.Boolean = {
		implicitly_to = {.Any, .Boolean},
		explicit_group = .Boolean,
		size_bytes = 1,
		significant_bits = 1,
		decimal_digits = 0,
		signedness = .Unsigned,
		numeric_class = .Not_A_Number,
	},
	.String = {
		implicitly_to = {.Any, .String},
		explicit_group = .String,
		size_bytes = -1,
		significant_bits = -1,
		decimal_digits = -1,
		signedness = .Not_Applicable,
		numeric_class = .Not_A_Number,
	},
	.Rune = {
		implicitly_to = {.Any, .Rune},
		explicit_group = .Numeric,
		size_bytes = 4,
		significant_bits = 21,
		decimal_digits = 6,
		signedness = .Unsigned,
		numeric_class = .Not_A_Number,
	},
	.Byte = {
		implicitly_to = {.Any, .Byte},
		explicit_group = .Numeric,
		size_bytes = 1,
		significant_bits = 8,
		decimal_digits = 2,
		signedness = .Unsigned,
		numeric_class = .Not_A_Number,
	},
	.Any = {
		implicitly_to = {.Any},
		explicit_group = .Unconvertible,
		size_bytes = -1,
		significant_bits = -1,
		decimal_digits = -1,
		signedness = .Unknown,
		numeric_class = .Unknown,
	},
	.Opaque = {
		implicitly_to = {.Any, .Opaque},
		explicit_group = .Unconvertible,
		size_bytes = -1,
		significant_bits = -1,
		decimal_digits = -1,
		signedness = .Unknown,
		numeric_class = .Not_A_Number,
	},
	.Opaque8 = {
		implicitly_to = {.Any, .Opaque8},
		explicit_group = .Unconvertible,
		size_bytes = 1,
		significant_bits = -1,
		decimal_digits = -1,
		signedness = .Unknown,
		numeric_class = .Not_A_Number,
	},
	.Opaque16 = {
		implicitly_to = {.Any, .Opaque16},
		explicit_group = .Unconvertible,
		size_bytes = 2,
		significant_bits = -1,
		decimal_digits = -1,
		signedness = .Unknown,
		numeric_class = .Not_A_Number,
	},
	.Opaque32 = {
		implicitly_to = {.Any, .Opaque32},
		explicit_group = .Unconvertible,
		size_bytes = 4,
		significant_bits = -1,
		decimal_digits = -1,
		signedness = .Unknown,
		numeric_class = .Not_A_Number,
	},
	.Opaque64 = {
		implicitly_to = {.Any, .Opaque64},
		explicit_group = .Unconvertible,
		size_bytes = 8,
		significant_bits = -1,
		decimal_digits = -1,
		signedness = .Unknown,
		numeric_class = .Not_A_Number,
	},
}


Explicit_Conversion_Group :: enum {
	Unconvertible,
	Numeric,
	String,
	Boolean,
}


coerce :: proc(ltype, rtype: Comptime_Type) -> (Comptime_Type, bool) {
	if types_equal(ltype, rtype) {
		return ltype, true
	}

	if ldec, rdec, ok := util.chain_extract_pair(ltype, rtype, hir.Type, hir.Fixed_Decimal); ok {
		digits_before := max(ldec.digits - ldec.scale, rdec.digits - rdec.scale)
		digits_after := max(ldec.scale, rdec.scale)
		digits := digits_before + digits_after
		scale := digits_after
		if digits > hir.MAX_DECIMAL_DIGITS ||
		   scale > hir.MAX_DECIMAL_SCALE ||
		   scale < hir.MIN_DECIMAL_SCALE {
			return nil, false
		}
		return hir.Type(hir.Fixed_Decimal{digits, scale}), true
	}

	if _type_implicitly_converts(ltype, rtype) {
		return ltype, true
	}

	if _type_implicitly_converts(rtype, ltype) {
		return rtype, true
	}

	return nil, false
}

_type_implicitly_converts :: proc(dest: Comptime_Type, src: Comptime_Type) -> bool {
	if types_equal(dest, src) {
		return true
	}

	if flex, ok := src.(Flexible_Type); ok {
		return _flex_converts_to(flex, dest)
	}

	if dest, src, ok := util.extract_pair(dest, src, hir.Type); ok {
		switch src in src {
		case hir.Primitive_Type:
			return _primitive_implicitly_converts(src, dest)
		case hir.Fixed_Decimal:
		case ^hir.Fixed_Array_Type:
		case ^hir.Optional_Type:
		case ^hir.Tagged_Type:
			return _type_implicitly_converts(src.base, dest)
		case ^hir.Generic_Type,
		     ^hir.Pointer_Type,
		     ^hir.Struct_Type,
		     ^hir.Enum_Type,
		     ^hir.Distinct_Type,
		     ^hir.Interface,
		     ^hir.Dynamic_Array_Type,
		     ^hir.View_Type,
		     ^hir.Map_Type:
			return false
		}
	}

	return false
}

_flex_converts_to :: proc(flex: Flexible_Type, to: Comptime_Type) -> bool {
	if flex.affinity == .Contextual {
		// TODO: Split Contextual into Nil and Zero affinities.
		return false
	}

	switch dest in to {
	case Flexible_Type:
		if flex.affinity == dest.affinity {
			return true
		}
		switch dest.affinity {
		case .Contextual:
			// TODO: Split Contextual into Nil and Zero affinities.
			return false
		case .Integer:
			return flex.affinity == .Unsigned_Integer
		case .Decimal, .Binary_Float:
			#partial switch flex.affinity {
			case .Unsigned_Integer, .Integer, .Rational:
				return true
			}
		case .Rational:
			switch flex.affinity {
			case .Unsigned_Integer, .Integer, .Decimal, .Binary_Float, .Rational:
				return true
			case .Contextual, .Boolean, .String, .Rune, .Byte:
				return false
			}
		case .Byte:
			#partial switch flex.affinity {
			case .Unsigned_Integer, .Integer, .Rune:
				return true
			}
		case .Unsigned_Integer, .Boolean, .String, .Rune:
		}

	case hir.Type:
		#partial switch concrete in dest {
		case hir.Fixed_Decimal:
			switch flex.affinity {
			case .Unsigned_Integer, .Integer:
				return true
			case .Decimal, .Rational:
				return concrete.scale != 0
			case .Contextual, .Binary_Float, .Boolean, .String, .Rune, .Byte:
				return false
			}

		case hir.Primitive_Type:
			switch flex.affinity {
			case .Unsigned_Integer, .Integer:
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
				     .UInt8,
				     .Bin64,
				     .Bin32,
				     .Bin16,
				     .Byte,
				     .Any:
					return true

				case .Boolean, .String, .Rune, .Opaque, .Opaque8, .Opaque16, .Opaque32, .Opaque64:
					return false
				}
			case .Decimal:
				return concrete == .Any
			case .Binary_Float:
				return(
					concrete == .Bin64 ||
					concrete == .Bin32 ||
					concrete == .Bin16 ||
					concrete == .Any \
				)
			case .Rational:
				return concrete == .Bin64 || concrete == .Bin32 || concrete == .Bin16
			case .Boolean:
				return concrete == .Boolean || concrete == .Any
			case .String:
				return concrete == .String || concrete == .Any
			case .Rune:
				return concrete == .Rune || concrete == .Byte || concrete == .Any
			case .Byte:
				return concrete == .Byte || concrete == .Any
			case .Contextual:
				return false
			}
		}
	}

	return false
}


_primitive_implicitly_converts :: proc(prim: hir.Primitive_Type, to: hir.Type) -> bool {
	meta := PRIMITIVE_TYPE_METADATA[prim]

	#partial switch to in to {
	case hir.Primitive_Type:
		return to in meta.implicitly_to
	case hir.Fixed_Decimal:
		return(
			meta.numeric_class == .Integer &&
			to.scale >= 0 &&
			meta.decimal_digits < int(to.digits - to.scale) \
		)

	case ^hir.Optional_Type:
		return _primitive_implicitly_converts(prim, to.base)
	case ^hir.Fixed_Array_Type:
		if _primitive_implicitly_converts(prim, to.elem) {
			return slice.all_of(to.shape, 1) // fixed array is actually a scalar
		}
	}

	return false
}
