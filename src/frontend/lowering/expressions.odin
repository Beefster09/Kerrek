package lowering

import "base:intrinsics"
import "core:fmt"
import "core:log"
import "core:math/big"
import "core:reflect"

import "../../common"
import "../../common/exact"
import "../analysis"
import "../hir"
import "../mir"

_lower_expression :: proc(fb: ^Func_Builder, expr: hir.Expression) -> mir.Operand {
	switch node in expr {
	case ^hir.Const_Expr:
		return _lower_constant(fb, node)

	case ^hir.Var_Expr:
		#partial switch referenced in node.references {
		case ^hir.Local_Variable:
			return fb.vars_by_sym_id[referenced.id]
		case ^hir.Formal_Parameter:
			return fb.params_by_sym_id[referenced.id]
		}
		fmt.panicf(
			"mir lowering does not support variables referencing %T",
			reflect.get_union_variant(node.references),
		)

	case ^hir.Binop_Expr:
		return _lower_binop(fb, node)

	case ^hir.Power_Expr:
		if node.exponent == 0 {
			return mir.Constant(f64(1))
		}
		type, _, ok := hir.type_and_unit(node.base)
		assert(ok, "expected type on lhs of ** operator")
		base := _lower_expression(fb, node.base)
		mode := _arithmetic_mode(fb, node.base)
		result := base

		BITS_IN_EXP :: size_of(type_of(node.exponent)) * 8
		bit_count := BITS_IN_EXP - intrinsics.count_leading_zeros(node.exponent)
		for offset in 1 ..< bit_count {
			bit_index := bit_count - offset - 1
			bit := (node.exponent >> u8(bit_index)) & 1

			next_result := _new_tmp(fb, type)
			_append_ops(fb, mir.Mul{mode = mode, dest = next_result, lhs = result, rhs = result})
			result = mir.Temp{next_result.id}

			if bit == 1 {
				next_square := _new_tmp(fb, type)
				_append_ops(fb, mir.Mul{mode = mode, dest = next_square, lhs = result, rhs = base})
				result = mir.Temp{next_square.id}
			}
		}

		return result

	case ^hir.Unit_Reinterpret_Expr:
		return _lower_expression(fb, node.expr)

	case ^hir.Cast_Expr:
		expr := _lower_expression(fb, node.expr)
		type, _, ok := hir.type_and_unit(node.expr)
		assert(ok)
		dest := _new_tmp(fb, type)
		_append_ops(fb, mir.Convert{dest, expr, lower_type(fb.ctx, node.to)})
		return mir.Temp{id = dest.id}

	case ^hir.Field_Access_Expr:
		switch expr in _lower_expression(fb, node.base) {
		case mir.Constant:
			panic("cannot take a field of a MIR constant")
		case mir.Temp:
			return mir.Field_Of{base = expr, field = node.field}
		case mir.Local_Var:
			return mir.Field_Of{base = expr, field = node.field}
		case mir.Global_Var:
			return mir.Field_Of{base = expr, field = node.field}
		case mir.Parameter:
			return mir.Field_Of{base = expr, field = node.field}
		case mir.Field_Of:
		case mir.Index_Of:
		case mir.Dereferenced:
		}

	case ^hir.Enum_Value:
	case ^hir.Move_Expr:
		// TODO: this factors into escape analysis, but that's it
		return _lower_expression(fb, node.expr)

	case ^hir.Dynamic_Call_Expr:
	case ^hir.Static_Call_Expr:
		args := make([]mir.Operand, len(node.args))
		for src_arg, i in node.args {
			args[i] = _lower_expression(fb, src_arg)
		}
		dest: mir.Writable = _new_tmp(fb, node.type) if node.type != nil else mir.Discard{}
		_append_ops(fb, mir.Call{dest, node.func.id, args})
		if tmp, ok := dest.(mir.New_Temp); ok {
			return mir.Temp{id = tmp.id}
		} else {
			return nil
		}

	case ^hir.Condition_Expr:
	case ^hir.Unary_Expr:
	case ^hir.Address_Of_Expr:
	case ^hir.Dereference_Expr:
	case ^hir.Unit_Conversion_Expr:
	case ^hir.Index_Expr:
	case ^hir.Static_Func_Expr:
	case hir.Type:
	case ^hir.Poison:
		panic("poison expression encountered during MIR lowering")
	}

	fmt.panicf("MIR lowering not yet implemented for %T", reflect.get_union_variant(expr))
}

_one :: proc(fb: ^Func_Builder, t: hir.Type) -> mir.Operand {
	#partial switch type in t {
	case hir.Fixed_Decimal:
		return mir.Constant(i64(1))
	case hir.Primitive_Type:
		switch type {
		case .Int128:
			return mir.Constant(i128(1))
		case .UInt128:
			return mir.Constant(u128(1))
		case .Int64:
			return mir.Constant(i64(1))
		case .UInt64:
			return mir.Constant(u64(1))
		case .Int32:
			return mir.Constant(i32(1))
		case .UInt32:
			return mir.Constant(u32(1))
		case .Int16:
			return mir.Constant(i16(1))
		case .UInt16:
			return mir.Constant(u16(1))
		case .Int8:
			return mir.Constant(i8(1))
		case .UInt8:
			return mir.Constant(u8(1))
		case .Real64:
			return mir.Constant(f64(1))
		case .Real32:
			return mir.Constant(f32(1))
		case .Real16:
			return mir.Constant(f16(1))
		case .Boolean:
			return mir.Constant(true)
		case .Int, .String, .Rune, .Byte, .Type, .Any:
		}
	}
	fmt.panicf("unsupported type for one: %s", t)
}

_lower_constant :: proc(fb: ^Func_Builder, constant: ^hir.Const_Expr) -> mir.Operand {
	switch value in constant.value {
	case exact.Decimal:
		as_int, ok := common.exact_int_to_i256(value.significand)
		assert(ok)
		if dec_type, is_dec := constant.type.(hir.Fixed_Decimal); is_dec {
			mag := dec_type.magnitude
			if mag == 0 && as_int != {0, 0, 0, 0} {
				log.warnf(
					"encountered a decimal constant without its magnitude set (at %s)",
					constant.span,
				)
				mag = f32(dec_type.digits)
			}
			if mag < common.INT64_DECIMAL_MAX_MAGNITUDE {
				return mir.Constant(i64(as_int[0]))
			} else if mag < common.INT128_DECIMAL_MAX_MAGNITUDE {
				return mir.Constant((transmute([2]i128)as_int)[0])
			}
		}
		return mir.Constant(as_int)
	case i128:
		return mir.Constant(value)
	case u128:
		return mir.Constant(value)
	case i64:
		return mir.Constant(value)
	case u64:
		return mir.Constant(value)
	case i32:
		return mir.Constant(value)
	case u32:
		return mir.Constant(value)
	case i16:
		return mir.Constant(value)
	case u16:
		return mir.Constant(value)
	case i8:
		return mir.Constant(value)
	case u8:
		return mir.Constant(value)
	case f64:
		return mir.Constant(value)
	case f32:
		return mir.Constant(value)
	case f16:
		return mir.Constant(value)
	case string:
		return mir.Constant(value)
	case bool:
		return mir.Constant(value)
	case hir.Nil_Of:
		assert(analysis.is_pointer(constant.type))
		return mir.Constant(nil)
	case hir.Zero_Of:
		if analysis.is_pointer(constant.type) {
			return mir.Constant(nil)
		}
		if analysis.is_boolean(constant.type) {
			return mir.Constant(false)
		}
		if primitive, ok := analysis.underlying_type(
			   constant.type,
		   ).(hir.Type).(hir.Primitive_Type); ok {
			#partial switch primitive {
			case .Byte:
				return mir.Constant(u8(0))
			case .Rune:
				return mir.Constant(u32(0))
			}
		}
		_, fixed_decimal := constant.type.(hir.Fixed_Decimal)
		if fixed_decimal ||
		   analysis.is_binfloat(constant.type) ||
		   analysis.is_decimal(constant.type) ||
		   analysis.is_integer(constant.type) {
			return _materialize_number(fb, exact.RAT_ZERO, constant.type)
		}
	}
	fmt.panicf(
		"cannot lower %T as a constant of type %s",
		reflect.get_union_variant(constant.value),
		constant.type,
	)
}

_materialize_number :: proc(fb: ^Func_Builder, value: exact.Rat, type: hir.Type) -> mir.Constant {
	if dec_type, ok := type.(hir.Fixed_Decimal); ok {
		factor := exact.int_pow_int(
			exact.Int(10),
			uint(abs(int(dec_type.scale))),
			context.temp_allocator,
		)
		result: exact.Int
		if dec_type.scale >= 0 {
			result = exact.int_div_half_even(
				exact.mul(value.numerator, factor, context.temp_allocator),
				value.denominator,
				fb.ctx.allocator,
			)
		} else {
			result = exact.int_div_half_even(
				value.numerator,
				exact.mul(value.denominator, factor, context.temp_allocator),
				fb.ctx.allocator,
			)
		}

		switch integer in result {
		case i128:
			if i128(min(i64)) <= integer && integer <= i128(max(i64)) {
				return i64(integer)
			} else {
				return integer
			}
		case ^big.Int:
			bits, err := big.int_log(integer, 2, context.temp_allocator)
			assert(err == nil && bits <= 255)
			result: [4]big.DIGIT
			copy(result[:], integer.digit[:])
			if integer.sign == .Negative {
				overflow_one := true
				#unroll for i in 0 ..< 4 {
					result[i] = ~result[i]
					if overflow_one {
						result[i], overflow_one = intrinsics.overflow_add(result[i], 1)
					}
				}
			}
			return transmute(mir.i256)result
		}
		unreachable()
	}

	if analysis.is_binfloat(type) {
		prim_type := analysis.underlying_type(type).(hir.Type).(hir.Primitive_Type)
		#partial switch prim_type {
		case .Real64:
			return mir.Constant(exact.to_float(value, f64))
		case .Real32:
			return mir.Constant(exact.to_float(value, f32))
		case .Real16:
			return mir.Constant(exact.to_float(value, f16))
		}
		unreachable()
	}

	if analysis.is_integer(type) {
		assert(exact.is_one(value.denominator))
		prim_type := analysis.underlying_type(type).(hir.Type).(hir.Primitive_Type)
		#partial switch prim_type {
		case .Int128:
			return mir.Constant(_exact_int_get(value.numerator, i128))
		case .Int64, .Int:
			return mir.Constant(_exact_int_get(value.numerator, i64))
		case .Int32:
			return mir.Constant(_exact_int_get(value.numerator, i32))
		case .Int16:
			return mir.Constant(_exact_int_get(value.numerator, i16))
		case .Int8:
			return mir.Constant(_exact_int_get(value.numerator, i8))
		case .UInt128:
			return mir.Constant(_exact_int_get(value.numerator, u128))
		case .UInt64:
			return mir.Constant(_exact_int_get(value.numerator, u64))
		case .UInt32:
			return mir.Constant(_exact_int_get(value.numerator, u32))
		case .UInt16:
			return mir.Constant(_exact_int_get(value.numerator, u16))
		case .UInt8:
			return mir.Constant(_exact_int_get(value.numerator, u8))
		}
		unreachable()
	}

	primitive := analysis.underlying_type(type).(hir.Type).(hir.Primitive_Type)
	if primitive == .Byte {
		assert(exact.is_one(value.denominator))
		return mir.Constant(_exact_int_get(value.numerator, u8))
	}
	unreachable()
}

_exact_int_get :: proc(value: exact.Int, $T: typeid) -> T {
	switch integer in value {
	case i128:
		return T(integer)
	case ^big.Int:
		result, err := big.int_get(integer, T, context.temp_allocator)
		assert(err == nil)
		return result
	}
	unreachable()
}

_lower_binop :: proc(fb: ^Func_Builder, binop: ^hir.Binop_Expr) -> mir.Operand {
	mode: mir.Arithmetic_Mode
	if binop.op in common.ARITHMETIC_BINOPS {
		mode = _arithmetic_mode(fb, binop.lhs)
	}

	switch binop.op {
	case .Add:
		lhs := _lower_expression(fb, binop.lhs)
		rhs := _lower_expression(fb, binop.rhs)
		result := _new_tmp(fb, binop.type)
		_append_ops(fb, mir.Add{mode = mode, dest = result, lhs = lhs, rhs = rhs})
		return mir.Temp{id = result.id}

	case .Subtract:
		lhs := _lower_expression(fb, binop.lhs)
		rhs := _lower_expression(fb, binop.rhs)
		result := _new_tmp(fb, binop.type)
		_append_ops(fb, mir.Sub{mode = mode, dest = result, lhs = lhs, rhs = rhs})
		return mir.Temp{id = result.id}

	case .Multiply:
		lhs := _lower_expression(fb, binop.lhs)
		rhs := _lower_expression(fb, binop.rhs)
		result := _new_tmp(fb, binop.type)
		_append_ops(fb, mir.Mul{mode = mode, dest = result, lhs = lhs, rhs = rhs})
		return mir.Temp{id = result.id}

	case .True_Divide:
		lhs := _lower_expression(fb, binop.lhs)
		rhs := _lower_expression(fb, binop.rhs)
		result := _new_tmp(fb, binop.type)
		_append_ops(fb, mir.Div{mode = mode, dest = result, lhs = lhs, rhs = rhs})
		return mir.Temp{id = result.id}

	case .Floor_Divide:
		lhs := _lower_expression(fb, binop.lhs)
		rhs := _lower_expression(fb, binop.rhs)
		result := _new_mut_tmp(fb, binop.type)
		_append_ops(fb, mir.Div{mode = mode, dest = result, lhs = lhs, rhs = rhs})

		lhs_type, _, _ := hir.type_and_unit(binop.lhs)
		rhs_type, _, _ := hir.type_and_unit(binop.rhs)
		if !(analysis.is_integer(lhs_type) && analysis.is_integer(rhs_type)) {
			_append_ops(fb, mir.Truncate{dest = result, value = result})
		}
		return result

	case .Remainder:
		lhs := _lower_expression(fb, binop.lhs)
		rhs := _lower_expression(fb, binop.rhs)
		result := _new_tmp(fb, binop.type)
		_append_ops(fb, mir.Rem{mode = mode, dest = result, lhs = lhs, rhs = rhs})
		return mir.Temp{id = result.id}

	case .Modulo:
		lhs := _lower_expression(fb, binop.lhs)
		rhs := _lower_expression(fb, binop.rhs)
		result := _new_mut_tmp(fb, binop.type)
		_append_ops(fb, mir.Rem{mode = mode, dest = result, lhs = lhs, rhs = rhs})

		before := fb.current_block_id
		negative := _new_block(fb)
		_append_ops(
			fb,
			mir.Add{mode = mode, dest = result, lhs = result, rhs = rhs},
			to_block = negative,
		)
		after := _new_block(fb)

		zero := _materialize_number(fb, exact.RAT_ZERO, binop.type)
		_end_block(
			fb,
			mir.Branch_Less{lhs = result, rhs = zero, lt_branch = negative, ge_branch = after},
			before,
		)
		_end_block(fb, mir.Jump{next = after}, negative)

		fb.current_block_id = after
		return result

	case .Equal, .Not_Equal, .Less, .Less_Equal, .Greater, .Greater_Equal, .Is, .Is_Not, .And, .Or:
		mat_bool := _new_mut_tmp(fb, hir.Primitive_Type.Boolean)

		true_block := _new_block(fb)
		_append_ops(
			fb,
			mir.Set{dest = mat_bool, value = mir.Constant(true)},
			to_block = true_block,
		)

		false_block := _new_block(fb)
		_append_ops(
			fb,
			mir.Set{dest = mat_bool, value = mir.Constant(false)},
			to_block = false_block,
		)

		_lower_binop_cond(fb, binop, true_block, false_block)
		after := _new_block(fb)

		_end_block(fb, mir.Jump{after}, true_block)
		_end_block(fb, mir.Jump{after}, false_block)

		fb.current_block_id = after
		return mat_bool

	case .Power:
	}
	fmt.panicf("mir lowering not implemented for binop %s", common.BINARY_OP_STRINGS[binop.op])
}

_arithmetic_mode :: proc(fb: ^Func_Builder, input: hir.Expression) -> mir.Arithmetic_Mode {
	type, _, ok := hir.type_and_unit(input)
	assert(ok)
	underlying := analysis.underlying_type(type).(hir.Type)
	primitive := lower_type(fb.ctx, underlying).(mir.Primitive_Type)
	overflow: mir.Overflow_Mode = .None
	if hir_primitive, primitive_ok := underlying.(hir.Primitive_Type);
	   primitive_ok && hir_primitive == .Int {
		overflow = .Panic
	} else if analysis.is_integer(type) {
		overflow = .Wrap
	}
	return {type = primitive, overflow = overflow}
}

_lower_condition :: proc(
	fb: ^Func_Builder,
	cond: hir.Expression,
	true_block, false_block: mir.Block_ID,
) {
	#partial switch node in cond {
	case ^hir.Binop_Expr:
		if _lower_binop_cond(fb, node, true_block, false_block) {
			return
		}
	}

	value := _lower_expression(fb, cond)

	type, _, cond_ok := hir.type_and_unit(cond)

	#partial switch t in type {
	case hir.Primitive_Type:
		assert(t == .Boolean, "tried to lower condition of non-boolean expression")
		_end_block(
			fb,
			mir.Branch_Zero{value = value, z_branch = false_block, nz_branch = true_block},
		)
	case ^hir.Pointer_Type:
		assert(t.ownership == .Weak, "tried to lower condition of non-weak pointer")
		_end_block(
			fb,
			mir.Weak_Ptr_Valid {
				value = value,
				valid_branch = true_block,
				invalid_branch = false_block,
			},
		)
	case ^hir.Optional_Type:
		_end_block(
			fb,
			mir.Branch_Zero{value = value, z_branch = false_block, nz_branch = true_block},
		)
	case:
		fmt.panicf("cannot lower condition of type %s", type)
	}
}

_lower_binop_cond :: proc(
	fb: ^Func_Builder,
	cond: ^hir.Binop_Expr,
	true_block, false_block: mir.Block_ID,
) -> bool {
	lhs := _lower_expression(fb, cond.lhs)
	rhs := _lower_expression(fb, cond.rhs)

	#partial switch cond.op {
	case .Equal:
		_end_block(
			fb,
			mir.Branch_Equal {
				lhs = lhs,
				rhs = rhs,
				eq_branch = true_block,
				ne_branch = false_block,
			},
		)
	case .Not_Equal:
		_end_block(
			fb,
			mir.Branch_Equal {
				lhs = lhs,
				rhs = rhs,
				eq_branch = false_block,
				ne_branch = true_block,
			},
		)
	case .Is:
		panic("TODO: is")
	case .Is_Not:
		panic("TODO: is_not")
	case .Less:
		_end_block(
			fb,
			mir.Branch_Less{lhs = lhs, rhs = rhs, lt_branch = true_block, ge_branch = false_block},
		)
	case .Less_Equal:
		_end_block(
			fb,
			mir.Branch_Less{lhs = rhs, rhs = lhs, lt_branch = false_block, ge_branch = true_block},
		)
	case .Greater:
		_end_block(
			fb,
			mir.Branch_Less{lhs = rhs, rhs = lhs, lt_branch = true_block, ge_branch = false_block},
		)
	case .Greater_Equal:
		_end_block(
			fb,
			mir.Branch_Less{lhs = lhs, rhs = rhs, lt_branch = false_block, ge_branch = true_block},
		)
	case .And:
		panic("TODO: and")
	case .Or:
		panic("TODO: or")
	case:
		return false
	}

	return true
}
