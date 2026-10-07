package analysis

import "base:runtime"
import "core:fmt"
import "core:math/big"
import "core:reflect"
import "core:strings"

import "../../common"
import "../../common/exact"
import "../../util"
import "../diagnostics"
import "../hir"
import "../resolver"


materialize_value :: proc(
	ts: ^Translation_State,
	value: Comptime_Value,
	span: common.Span,
	target: hir.Type = nil,
	loc := #caller_location,
) -> (
	hir.Expression,
	bool,
) {
	_fail :: proc(
		ts: ^Translation_State,
		real_type: hir.Type,
		span: common.Span,
	) -> (
		hir.Expression,
		bool,
	) {
		diagnostics.emit(
			.Cannot_Materialize_Value,
			span,
			"this value cannot be represented as %s",
			real_type,
		)
		return poison(ts, span), false
	}

	real_type := target
	if real_type == nil {
		ok: bool
		real_type, ok = infer_type(value.type, span)
		if !ok {
			// infer_type already emitted the diagnostic
			return poison(ts, span), false
		}
	}

	if real_type == nil {
		return _fail(ts, real_type, span)
	}

	real_value: hir.Value
	switch v in value.value {

	case Untyped_Nil:
		if !is_nilable(real_type) {
			return _fail(ts, real_type, span)
		}
		real_value = hir.Nil_Of {
			type = real_type,
		}

	case Untyped_Zero:
		if !is_zeroable(real_type) {
			return _fail(ts, real_type, span)
		}
		real_value = hir.Zero_Of {
			type = real_type,
		}

	case exact.Rat:
		ok := false
		#partial switch t in real_type {
		case hir.Primitive_Type:
			real_value, ok = _materialize_primitive(t, v)
		case hir.Fixed_Decimal:
			if flex, flex_ok := value.type.(resolver.Flexible_Type); flex_ok {
				real_value, ok = _materialize_decimal(t, v, flex)
			}
		}

		if !ok {
			return _fail(ts, real_type, span)
		}

	case string:
		real_value = strings.clone(v, ts.output.allocator)

	case rune:
		if !_type_implicitly_converts(real_type, value.type) {
			return _fail(ts, real_type, span)
		}
		prim, ok := util.chain_extract(underlying_type(real_type), hir.Type, hir.Primitive_Type)
		if !ok {
			return _fail(ts, real_type, span)
		}
		#partial switch prim {
		case .Rune:
			if v < 0 || v > 0x10_ffff {
				return _fail(ts, real_type, span)
			}
			real_value = u32(v)
		case .Byte:
			if v < 0 || v > 0xff {
				return _fail(ts, real_type, span)
			}
			real_value = u8(v)
		case:
			unreachable()
		}

	case byte:
		real_value = v

	case bool:
		real_value = v
	}

	expr := new(hir.Const_Expr, ts.output.allocator)
	expr^ = {
		span  = span,
		value = real_value,
		type  = real_type,
		unit  = value.unit,
	}
	return hir.Expression(expr), true
}


_materialize_decimal :: proc(
	target: hir.Fixed_Decimal,
	value: exact.Rat,
	spec: Flexible_Type,
) -> (
	hir.Value,
	bool,
) {
	if spec.affinity == .Binary_Float {
		return nil, false
	}
	if spec.affinity == .Decimal {
		if int(spec.digits) > int(target.digits) || int(spec.scale) > int(target.digits) {
			// FIXME: this won't handle negative scale destinations correctly
			return nil, false
		}
	}

	factor := exact.int_pow_int(
		exact.Int(10),
		uint(abs(int(target.scale))),
		context.temp_allocator,
	)
	result: exact.Int
	if target.scale >= 0 {
		result = exact.int_div_half_even(
			exact.mul(value.numerator, factor, context.temp_allocator),
			value.denominator,
			context.temp_allocator,
		)
	} else {
		result = exact.int_div_half_even(
			value.numerator,
			exact.mul(value.denominator, factor, context.temp_allocator),
			context.temp_allocator,
		)
	}

	return common.exact_int_to_i256(result)
}

_materialize_primitive :: proc(prim: hir.Primitive_Type, value: exact.Rat) -> (hir.Value, bool) {
	switch prim {
	case .Bin64:
		return exact.to_float(value, f64), true
	case .Bin32:
		return exact.to_float(value, f32), true
	case .Bin16:
		return exact.to_float(value, f16), true

	case .Int128:
		return _materialize_int(value, i128)
	case .Int64, .Int:
		return _materialize_int(value, i64)
	case .Int32:
		return _materialize_int(value, i32)
	case .Int16:
		return _materialize_int(value, i16)
	case .Int8:
		return _materialize_int(value, i8)
	case .UInt128:
		return _materialize_int(value, u128)
	case .UInt64:
		return _materialize_int(value, u64)
	case .UInt32, .Rune:
		return _materialize_int(value, u32)
	case .UInt16:
		return _materialize_int(value, u16)
	case .UInt8, .Byte:
		return _materialize_int(value, u8)

	case .Boolean, .String, .Type, .Any:
		return nil, false
	}

	unreachable()
}

_materialize_int :: proc(value: exact.Rat, $I: typeid) -> (hir.Value, bool) {
	if !exact.is_one(value.denominator) {
		return nil, false
	}

	num_bits :: size_of(I) * 8
	is_unsigned :: I == u8 || I == u16 || I == u32 || I == u64 || I == u128

	switch integer in value.numerator {
	case i128:
		when I == u128 {
			if integer >= 0 {
				return I(integer), true
			}
		} else {
			if i128(min(I)) <= integer && integer <= i128(max(I)) {
				return I(integer), true
			}
		}
	case ^big.Int:
		when is_unsigned {
			if integer.sign == .Negative {
				return nil, false
			}
		}

		bit_length, ble := big.count_bits(integer, context.temp_allocator)
		assert(ble == nil)

		if bit_length > (num_bits - (0 when is_unsigned else 1)) {
			return nil, false
		}

		result, err := big.int_get(integer, I, context.temp_allocator)
		return result, err == nil
	}

	return nil, false
}
