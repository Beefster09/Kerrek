package analysis

import "../../common"
import "../../common/exact"
import "../../util"
import "../hir"
import "../resolver"
import "core:math/big"
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
	.Type = {
		implicitly_to = {.Any},
		explicit_group = .Unconvertible,
		size_bytes = -1,
		significant_bits = -1,
		decimal_digits = -1,
		signedness = .Not_Applicable,
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
}


Explicit_Conversion_Group :: enum {
	Unconvertible,
	Numeric,
	String,
	Boolean,
}


coerce :: proc(ltype, rtype: Comptime_Type, type_hint: hir.Type = nil) -> (Comptime_Type, bool) {
	if type_hint != nil &&
	   _type_implicitly_converts(type_hint, ltype) &&
	   _type_implicitly_converts(type_hint, rtype) {
		return type_hint, true
	}

	// TODO: Merge flexible decimal digits and scales before affinity equality.
	if types_equal(ltype, rtype) {
		return ltype, true
	}

	if ldec, rdec, ok := util.chain_extract_pair(ltype, rtype, hir.Type, hir.Fixed_Decimal); ok {
		digits_before := max(
			i16(ldec.digits) - i16(ldec.scale),
			i16(rdec.digits) - i16(rdec.scale),
		)
		scale := max(ldec.scale, rdec.scale)
		digits := digits_before + i16(scale)
		if digits > hir.MAX_DECIMAL_DIGITS ||
		   scale > hir.MAX_DECIMAL_SCALE ||
		   scale < hir.MIN_DECIMAL_SCALE {
			return nil, false
		}
		return hir.Type(hir.Fixed_Decimal{digits = u8(digits), scale = i8(scale)}), true
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
			return _fixed_decimal_implicitly_converts(src, dest)
		case ^hir.Fixed_Array_Type:
			if d_arr, ok := dest.(^hir.Fixed_Array_Type); ok {
				return(
					slice.equal(src.shape, d_arr.shape) &&
					_type_implicitly_converts(d_arr.elem, src.elem) \
				)
			}
			return slice.all_of(src.shape, 1) && _type_implicitly_converts(dest, src.elem)
		case ^hir.Optional_Type:
			if d_opt, ok := dest.(^hir.Optional_Type); ok {
				return _type_implicitly_converts(d_opt.base, src.base)
			}
		case ^hir.Tagged_Type:
			return _type_implicitly_converts(dest, src.base)
		case ^hir.Generic_Type,
		     ^hir.Func_Type,
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


can_materialize_value :: proc(target: hir.Type, value: resolver.Comptime_Value) -> bool {
	// TODO: lossy flag?
	if target == nil || !_type_implicitly_converts(target, value.type) {
		return false
	}

	switch concrete in value.value {
	case common.Untyped_Nil:
		// TODO: Define which pointer-like types accept flexible nil.
		return false
	case common.Untyped_Zero:
		return is_zeroable(target)
	case exact.Rat:
		return _can_materialize_number(target, concrete, value.type)
	case rune:
		if primitive, ok := target.(hir.Primitive_Type); ok && primitive == .Byte {
			return concrete >= 0 && concrete <= 255
		}
	case byte, string, bool:
	}

	return true
}


_can_materialize_number :: proc(target: hir.Type, value: exact.Rat, type: Comptime_Type) -> bool {
	value := exact.reduce(value)
	#partial switch concrete in target {
	case hir.Fixed_Decimal:
		// TODO: test if it fits without actually materializing anything
		factor := exact.int_pow_int(
			exact.Int(10),
			uint(abs(int(concrete.scale))),
			context.temp_allocator,
		)
		scaled: exact.Rat
		if concrete.scale >= 0 {
			scaled = exact.mul(value, exact.Rat{factor, exact.Int(1)}, context.temp_allocator)
		} else {
			scaled = exact.div(value, exact.Rat{factor, exact.Int(1)}, context.temp_allocator)
		}

		magnitude := scaled.numerator
		if !exact.is_one(scaled.denominator) {
			if flex, ok := type.(resolver.Flexible_Type); ok && flex.affinity != .Rational {
				return false
			}
			// lossy is ok; maybe this should trigger a warning?
			magnitude = exact.div(scaled.numerator, scaled.denominator, context.temp_allocator)
		}

		if exact.is_negative(magnitude) {
			magnitude = exact.negate(magnitude, context.temp_allocator)
		}
		limit := exact.int_pow_int(exact.Int(10), uint(concrete.digits), context.temp_allocator)
		return exact.lt(magnitude, limit, context.temp_allocator)

	case hir.Primitive_Type:
		switch concrete {
		case .Bin64, .Bin32, .Bin16:
			return _rational_fits_binary(value, concrete)
		case .Any:
			return true
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
		     .Byte:
			if !exact.is_one(value.denominator) {
				return false
			}
			return _integer_fits_primitive(value.numerator, concrete)
		case .Boolean, .String, .Rune, .Type:
			return false
		}
	case:
		// TODO: Materialize wrapper types with explicit HIR nodes instead of retagging constants.
		return false
	}

	return false
}


_rational_fits_binary :: proc(value: exact.Rat, target: hir.Primitive_Type) -> bool {
	// TODO: test if it fits without actually materializing anything
	significand_bits, exponent_shift: uint
	#partial switch target {
	case .Bin16:
		significand_bits, exponent_shift = 11, 5
	case .Bin32:
		significand_bits, exponent_shift = 24, 104
	case .Bin64:
		significand_bits, exponent_shift = 53, 971
	case:
		return false
	}

	max_significand := exact.sub(
		exact.int_pow_int(exact.Int(2), significand_bits),
		exact.Int(1),
		context.temp_allocator,
	)
	max_value := exact.mul(
		max_significand,
		exact.int_pow_int(exact.Int(2), exponent_shift),
		context.temp_allocator,
	)
	magnitude := exact.negate(value, context.temp_allocator) if exact.is_negative(value) else value
	return exact.le(magnitude, exact.Rat{max_value, exact.Int(1)}, context.temp_allocator)
}


_integer_fits_primitive :: proc(value: exact.Int, target: hir.Primitive_Type) -> bool {
	switch integer in value {
	case i128:
		#partial switch target {
		case .Int128:
			return true
		case .Int64:
			return integer >= i128(min(i64)) && integer <= i128(max(i64))
		case .Int32:
			return integer >= i128(min(i32)) && integer <= i128(max(i32))
		case .Int16:
			return integer >= i128(min(i16)) && integer <= i128(max(i16))
		case .Int8:
			return integer >= i128(min(i8)) && integer <= i128(max(i8))
		case .UInt128:
			return integer >= 0
		case .UInt64:
			return integer >= 0 && u128(integer) <= u128(max(u64))
		case .UInt32:
			return integer >= 0 && u128(integer) <= u128(max(u32))
		case .UInt16:
			return integer >= 0 && u128(integer) <= u128(max(u16))
		case .UInt8, .Byte:
			return integer >= 0 && u128(integer) <= u128(max(u8))
		case:
			return false
		}

	case ^big.Int:
		bits, err := big.count_bits(integer)
		assert(err == nil)
		#partial switch target {
		case .Int128:
			if bits < 128 {
				return true
			}
			if integer.sign == .Negative && bits == 128 {
				return integer.digit[1] == 1 << 63
			}
		case .Int64:
			if bits < 64 {
				return true
			}
			if integer.sign == .Negative && bits == 64 {
				return integer.digit[0] == 1 << 63
			}
		case .Int32:
			if bits < 32 {
				return true
			}
			if integer.sign == .Negative && bits == 32 {
				return integer.digit[0] == 1 << 31
			}
		case .Int16:
			if bits < 16 {
				return true
			}
			if integer.sign == .Negative && bits == 16 {
				return integer.digit[0] == 1 << 15
			}
		case .Int8:
			if bits < 8 {
				return true
			}
			if integer.sign == .Negative && bits == 8 {
				return integer.digit[0] == 1 << 7
			}
		case .UInt128:
			return bits <= 128
		case .UInt64:
			return bits <= 64
		case .UInt32:
			return bits <= 32
		case .UInt16:
			return bits <= 16
		case .UInt8, .Byte:
			return bits <= 8
		}
	}

	return false
}

_flex_converts_to :: proc(flex: Flexible_Type, to: Comptime_Type) -> bool {
	switch dest in to {
	case Flexible_Type:
		if flex.affinity == dest.affinity {
			return true
		}
		switch dest.affinity {
		case .Nil, .Any_Zero:
			return false
		case .Integer:
			#partial switch flex.affinity {
			case .Unsigned_Integer, .Any_Zero:
				return true
			}
		case .Decimal, .Binary_Float:
			#partial switch flex.affinity {
			case .Unsigned_Integer, .Integer, .Rational, .Any_Zero:
				return true
			}
		case .Rational:
			switch flex.affinity {
			case .Unsigned_Integer, .Integer, .Decimal, .Binary_Float, .Rational, .Any_Zero:
				return true
			case .Nil, .Boolean, .String, .Rune, .Byte:
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
			case .Unsigned_Integer, .Integer, .Decimal, .Rational, .Any_Zero:
				return true
			case .Nil, .Binary_Float, .Boolean, .String, .Rune, .Byte:
				return false
			}

		case hir.Primitive_Type:
			switch flex.affinity {
			case .Any_Zero:
				return is_zeroable(dest)
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

				case .Boolean, .String, .Rune, .Type:
					return false
				}
			case .Decimal:
				// maybe: warning about precision loss
				fallthrough
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
			case .Nil:
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
			meta.decimal_digits < int(i16(to.digits) - i16(to.scale)) \
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

_fixed_decimal_implicitly_converts :: proc(dec: hir.Fixed_Decimal, to: hir.Type) -> bool {
	#partial switch to in to {
	case hir.Primitive_Type:
		if to == .Any {
			return true
		}
		meta := PRIMITIVE_TYPE_METADATA[to]
		switch meta.numeric_class {
		case .Integer:
			return(
				meta.signedness == .Signed &&
				dec.scale <= 0 &&
				int(dec.digits) - int(dec.scale) <= meta.decimal_digits \
			)
		case .Float:
			return _fixed_decimal_fits_binary_precision(dec, meta.significant_bits)
		case .Not_A_Number, .Unknown:
			return false
		}

	case hir.Fixed_Decimal:
		return(
			int(dec.scale) <= int(to.scale) &&
			int(dec.digits) - int(dec.scale) <= int(to.digits) - int(to.scale) \
		)

	case ^hir.Optional_Type:
		return _fixed_decimal_implicitly_converts(dec, to.base)
	case ^hir.Fixed_Array_Type:
		if _fixed_decimal_implicitly_converts(dec, to.elem) {
			return slice.all_of(to.shape, 1) // fixed array is actually a scalar
		}
	}

	return false
}

_fixed_decimal_fits_binary_precision :: proc(
	dec: hir.Fixed_Decimal,
	significant_bits: int,
) -> bool {
	if dec.scale > 0 {
		return false
	}

	limit := u64(1) << uint(significant_bits)
	max_significand: u64
	for _ in 0 ..< dec.digits {
		if max_significand > (limit - 10) / 10 {
			return false
		}
		max_significand = max_significand * 10 + 9
	}
	// The power of two in 10^-scale changes the exponent without consuming precision.
	for _ in 0 ..< -dec.scale {
		if max_significand > (limit - 1) / 5 {
			return false
		}
		max_significand *= 5
	}
	return true
}
