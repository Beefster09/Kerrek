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
	case exact.Rat:
		if analysis.is_binfloat(constant.type) {
			fmt.println("binfloat", reflect.get_union_variant(constant.type), value)
			numerator: f64
			switch integer in value.numerator {
			case i128:
				numerator = f64(integer)
			case ^big.Int:
				err: big.Error
				numerator, err = big.int_get_float(integer, context.temp_allocator)
				assert(err == nil)
			}

			denominator: f64
			switch integer in value.denominator {
			case i128:
				denominator = f64(integer)
			case ^big.Int:
				err: big.Error
				denominator, err = big.int_get_float(integer, context.temp_allocator)
				assert(err == nil)
			}
			return mir.Constant(numerator / denominator)
		}

		if analysis.is_integer(constant.type) {
			fmt.println("integer", reflect.get_union_variant(constant.type), value)
			assert(exact.is_one(value.denominator))
			prim_type := analysis.underlying_type(constant.type).(hir.Type).(hir.Primitive_Type)
			unsigned := analysis.PRIMITIVE_TYPE_METADATA[prim_type].signedness != .Signed

			switch integer in value.numerator {
			case i128:
				if unsigned {
					assert(integer >= 0)
					return mir.Constant(u128(integer))
				} else {
					return mir.Constant(integer)
				}
			case ^big.Int:
				if unsigned {
					result, err := big.int_get(integer, u128, context.temp_allocator)
					assert(err == nil)
					return mir.Constant(result)
				} else {
					result, err := big.int_get(integer, i128, context.temp_allocator)
					assert(err == nil)
					return mir.Constant(result)
				}
			}
		}

		if dec_type, ok := constant.type.(hir.Fixed_Decimal); ok {
			fmt.println("decimal", reflect.get_union_variant(constant.type), value)
			scale_power_of_ten := exact.Int(1)
			if dec_type.scale >= 0 {
				scale_power_of_ten = exact.int_pow_int(
					exact.Int(10),
					uint(dec_type.scale),
					context.temp_allocator,
				)
			}

			result := exact.div(
				exact.mul(value.numerator, scale_power_of_ten, context.temp_allocator),
				value.denominator,
				fb.ctx.allocator,
			)

			if dec_type.scale < 0 {
				result = exact.div(
					result,
					exact.int_pow_int(exact.Int(10), uint(dec_type.scale), context.temp_allocator),
				)
			}

			switch result in result {
			case i128:
				return mir.Constant(result)
			case ^big.Int:
				bits, err := big.int_log(result, 2, context.temp_allocator)
				assert(err == nil && bits <= 255)
				u256_result: [4]big.DIGIT
				copy(u256_result[:], result.digit[:])
				if result.sign == .Negative {
					// do two's complement over multiple legs
					overflow_one := true
					#unroll for i in 0 ..< 4 {
						u256_result[i] = ~u256_result[i]
						if overflow_one {
							u256_result[i], overflow_one = intrinsics.overflow_add(
								u256_result[i],
								1,
							)
						}
					}
				}

				return mir.Constant(transmute([4]i64)u256_result)
			}
		}
	case rune:
		return mir.Constant(i128(value))
	case byte:
		return mir.Constant(u128(value))
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
		if analysis.is_binfloat(constant.type) || analysis.is_decimal(constant.type) {
			return mir.Constant(f64(0))
		}
		if analysis.is_boolean(constant.type) {
			return mir.Constant(false)
		}
		if analysis.is_integer(constant.type) {
			return mir.Constant(i128(0))
		}
	}
	fmt.panicf(
		"cannot lower %T as a constant of type %s",
		reflect.get_union_variant(constant.value),
		constant.type,
	)
}

_lower_binop :: proc(fb: ^Func_Builder, binop: hir.Binop_Expr) -> mir.Operand {
	switch binop.op {
	case .Add:
		lhs := _lower_expression(fb, binop.lhs)
		rhs := _lower_expression(fb, binop.rhs)
		result := _new_tmp(fb, binop.type)
		_append_ops(fb, mir.Add{dest = result, lhs = lhs, rhs = rhs})
		return mir.Temp{id = result.id}
	case .Subtract:
		lhs := _lower_expression(fb, binop.lhs)
		rhs := _lower_expression(fb, binop.rhs)
		result := _new_tmp(fb, binop.type)
		_append_ops(fb, mir.Sub{dest = result, lhs = lhs, rhs = rhs})
		return mir.Temp{id = result.id}
	case .Multiply:
		lhs := _lower_expression(fb, binop.lhs)
		rhs := _lower_expression(fb, binop.rhs)
		result := _new_tmp(fb, binop.type)
		_append_ops(fb, mir.Mul{dest = result, lhs = lhs, rhs = rhs})
		return mir.Temp{id = result.id}
	case .True_Divide:
		lhs := _lower_expression(fb, binop.lhs)
		rhs := _lower_expression(fb, binop.rhs)
		result := _new_tmp(fb, binop.type)
		_append_ops(fb, mir.Div{dest = result, lhs = lhs, rhs = rhs})
		return mir.Temp{id = result.id}
	case .Floor_Divide:
		lhs := _lower_expression(fb, binop.lhs)
		rhs := _lower_expression(fb, binop.rhs)
		result := _new_mut_tmp(fb, binop.type)
		_append_ops(fb, mir.Div{dest = result, lhs = lhs, rhs = rhs})

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
		_append_ops(fb, mir.Rem{dest = result, lhs = lhs, rhs = rhs})
		return mir.Temp{id = result.id}
	case .Modulo:
		lhs := _lower_expression(fb, binop.lhs)
		rhs := _lower_expression(fb, binop.rhs)
		result := _new_mut_tmp(fb, binop.type)
		_append_ops(fb, mir.Rem{dest = result, lhs = lhs, rhs = rhs})

		before := fb.current_block_id
		negative := _new_block(fb)
		_append_ops(fb, mir.Add{dest = result, lhs = result, rhs = rhs})
		after := _new_block(fb)

		zero := mir.Constant(i128(0))
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
