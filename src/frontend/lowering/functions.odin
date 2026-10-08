package lowering

import "base:intrinsics"
import "core:fmt"
import "core:math/big"
import "core:reflect"

import "../../common"
import "../../common/exact"
import "../analysis"
import "../hir"
import "../mir"

Func_Builder :: struct {
	ctx:              ^Translation_Context,
	next_temp:        mir.Temp_Index,
	locals:           [dynamic]mir.Local_Var_Def,
	vars_by_sym_id:   map[common.Symbol_ID]mir.Local_Var,
	params_by_sym_id: map[common.Symbol_ID]mir.Parameter,
	blocks:           [dynamic]WIP_Block,
	current_block_id: mir.Block_ID,
}

WIP_Block :: struct {
	idx: mir.Block_ID,
	ops: [dynamic]mir.Instruction,
	end: mir.Terminator,
}

lower_func :: proc(ctx: ^Translation_Context, fn: ^hir.Func_Definition) -> mir.Function {
	fb := Func_Builder {
		ctx              = ctx,
		next_temp        = 1,
		locals           = make([dynamic]mir.Local_Var_Def, ctx.allocator),
		vars_by_sym_id   = make(map[common.Symbol_ID]mir.Local_Var, context.temp_allocator),
		params_by_sym_id = make(map[common.Symbol_ID]mir.Parameter, context.temp_allocator),
		blocks           = make([dynamic]WIP_Block, context.temp_allocator),
	}

	params := make([]mir.Parameter_Def, len(fn.params), ctx.allocator)
	for param, i in fn.params {
		index := mir.Parameter_Index(i)
		params[i] = {
			span  = param.span,
			index = index,
			name  = param.name.id,
			type  = lower_type(ctx, param.type),
		}
		fb.params_by_sym_id[param.id] = {
			index = index,
		}
	}

	_lower_block(&fb, fn.body)

	blocks := make([]mir.Block, len(fb.blocks), ctx.allocator)
	for block, i in fb.blocks {
		blocks[i] = {
			id  = block.idx,
			ops = block.ops[:],
			end = block.end,
		}
	}

	ret: mir.Type
	if fn.ret != nil {
		ret = lower_type(ctx, fn.ret.type)
	}

	err: mir.Type
	if fn.err != nil {
		err = lower_type(ctx, fn.err)
	}

	return {
		id = fn.id,
		name = fn.name.id,
		params = params,
		ret = ret,
		err = err,
		flags = fn.flags,
		locals = fb.locals[:],
		blocks = blocks,
	}
}

_new_tmp :: proc(fb: ^Func_Builder, typ: hir.Type) -> mir.New_Temp {
	tmp := mir.New_Temp {
		id   = fb.next_temp,
		type = lower_type(fb.ctx, typ),
	}
	fb.next_temp += 1
	return tmp
}

_new_mut_tmp :: proc(fb: ^Func_Builder, typ: hir.Type) -> mir.Local_Var {
	var_idx := mir.Local_Var_Index(len(fb.locals))
	append(
		&fb.locals,
		mir.Local_Var_Def{id = var_idx, name = "tmp", type = lower_type(fb.ctx, typ)},
	)
	var := mir.Local_Var {
		id = var_idx,
	}
	return var
}

_new_var :: proc(fb: ^Func_Builder, decl: ^hir.Local_Variable) -> mir.Local_Var {
	var_idx := mir.Local_Var_Index(len(fb.locals))
	append(
		&fb.locals,
		mir.Local_Var_Def {
			span = decl.name.span,
			id = var_idx,
			name = decl.name.id,
			type = lower_type(fb.ctx, decl.type),
		},
	)
	var := mir.Local_Var {
		id = var_idx,
	}
	fb.vars_by_sym_id[decl.id] = var
	return var
}

_new_block :: proc(fb: ^Func_Builder) -> mir.Block_ID {
	block_id := mir.Block_ID(len(fb.blocks))
	fb.current_block_id = block_id
	append(
		&fb.blocks,
		WIP_Block {
			idx = block_id,
			ops = make([dynamic]mir.Instruction, allocator = fb.ctx.allocator),
		},
	)
	return block_id
}

_append_ops :: proc(fb: ^Func_Builder, ops: ..mir.Instruction, to_block: mir.Block_ID = -1) {
	i := to_block if to_block >= 0 else fb.current_block_id
	assert(
		fb.blocks[i].end == nil,
		"attempted to append instructions to a block that has already been terminated",
	)
	append(&fb.blocks[i].ops, ..ops)
}

_end_block :: proc(fb: ^Func_Builder, end: mir.Terminator, to_block: mir.Block_ID = -1) {
	i := to_block if to_block >= 0 else fb.current_block_id
	assert(fb.blocks[i].end == nil, "attempted to end a block that has already been terminated")
	fb.blocks[i].end = end
}

_lower_block :: proc(fb: ^Func_Builder, src: ^hir.Block) {
	_new_block(fb)
	// TODO: defers, pointer cleanup

	for stmt in src.body {
		if fb.ctx.debug {
			_append_ops(fb, mir.Debug_Marker{hir.span(stmt)})
		}
		switch stmt in stmt {
		case ^hir.Local_Variable:
			var := _new_var(fb, stmt)
			if stmt.expr != nil {
				_append_ops(fb, mir.Set{dest = var, value = _lower_expression(fb, stmt.expr)})
			}
		case ^hir.Assign_Statement:
			panic("TODO")
		case ^hir.Return_Statement:
			result: mir.Operand
			if stmt.value != nil {
				result = _lower_expression(fb, stmt.value)
			}
			_end_block(fb, mir.Return{value = result})
		case ^hir.Expr_Statement:
			_lower_expression(fb, stmt.expr)
		case ^hir.Block:
			_lower_block(fb, stmt)
		case ^hir.Poison:
			panic("poison statement encountered during MIR lowering")
		}
	}
}

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
		return _lower_binop(fb, node^)

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

	case ^hir.Func_Call_Expr:
	// TODO: need distinction between static call and dynamic call, but it would go something like this:
	/*
		args := make([]mir.Operand, len(node.args))
		for src_arg, i in node.args {
			args[i] = _lower_expression(fb, src_arg)
		}
		dest: mir.Writable = _new_tmp(fb, node.type) if node.type != nil else mir.Discard{}
		_append_ops(fb, mir.Call{dest, node.callee, args})
		return mir.Temp{id = dest.id}
		*/

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

_lower_constant :: proc(fb: ^Func_Builder, constant: ^hir.Const_Expr) -> mir.Operand {
	switch value in constant.value {
	case exact.Decimal:
		as_int, ok := common.exact_int_to_i256(value.significand)
		assert(ok)
		if dec_type, is_dec := constant.type.(hir.Fixed_Decimal); is_dec {
			mag := max(f32(dec_type.digits), dec_type.magnitude)
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
		case .Bin64:
			return mir.Constant(exact.to_float(value, f64))
		case .Bin32:
			return mir.Constant(exact.to_float(value, f32))
		case .Bin16:
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

_lower_binop :: proc(fb: ^Func_Builder, binop: hir.Binop_Expr) -> mir.Operand {
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
		_append_ops(fb, mir.Add{mode = mode, dest = result, lhs = result, rhs = rhs})
		after := _new_block(fb)

		zero := _materialize_number(fb, exact.RAT_ZERO, binop.type)
		_end_block(
			fb,
			mir.Branch_Less{lhs = result, rhs = zero, lt_branch = negative, ge_branch = after},
			before,
		)
		_end_block(fb, mir.Jump{next = after}, negative)
		return result
	case .Equal, .Not_Equal, .Less, .Less_Equal, .Greater, .Greater_Equal, .Is, .Is_Not, .And, .Or:
		_lower_binop_cond(fb, binop)
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

_lower_binop_cond :: proc(fb: ^Func_Builder, cond: hir.Binop_Expr) {
	#partial switch cond.op {
	case .Equal, .Not_Equal, .Is, .Is_Not:
	case .Less, .Less_Equal, .Greater, .Greater_Equal:
	case .And, .Or:
	}
	fmt.panicf(
		"reaching a %s binary operator is not normally possible in conditionals",
		common.BINARY_OP_STRINGS[cond.op],
	)
}
