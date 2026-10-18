package lowering

import "core:fmt"
import "core:slice"

import "../../common"
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
	next_order_key:   u64,
}

WIP_Block :: struct {
	idx:       mir.Block_ID,
	ops:       [dynamic]mir.Instruction,
	end:       mir.Terminator,
	order_key: u64,
}

lower_func :: proc(ctx: ^Translation_Context, fn: ^hir.Func_Definition) -> mir.Function {
	fb := Func_Builder {
		ctx              = ctx,
		next_temp        = 1,
		locals           = make([dynamic]mir.Local_Var_Def, ctx.allocator),
		vars_by_sym_id   = make(map[common.Symbol_ID]mir.Local_Var, context.temp_allocator),
		params_by_sym_id = make(map[common.Symbol_ID]mir.Parameter, context.temp_allocator),
		blocks           = make([dynamic]WIP_Block, context.temp_allocator),
		next_order_key   = 1,
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
	if fb.blocks[fb.current_block_id].end == nil {
		_end_block(&fb, mir.Return{})
	}

	slice.sort_by_cmp(fb.blocks[:], proc(a, b: WIP_Block) -> slice.Ordering {
		if a.order_key < b.order_key {
			return .Less
		} else if a.order_key > b.order_key {
			return .Greater
		}

		if a.idx < b.idx {
			return .Less
		} else if a.idx > b.idx {
			return .Greater
		}

		return .Equal
	})

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

_new_block :: proc(fb: ^Func_Builder, order_next := true) -> mir.Block_ID {
	block_id := mir.Block_ID(len(fb.blocks))
	append(
		&fb.blocks,
		WIP_Block {
			idx = block_id,
			ops = make([dynamic]mir.Instruction, allocator = fb.ctx.allocator),
		},
	)
	if order_next {
		fb.blocks[block_id].order_key = fb.next_order_key
		fb.next_order_key += 1
	}
	return block_id
}

_append_block :: proc(fb: ^Func_Builder, block_id: mir.Block_ID) {
	assert(fb.blocks[block_id].order_key == 0, "block order already assigned")
	fb.blocks[block_id].order_key = fb.next_order_key
	fb.next_order_key += 1
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

_lower_block :: proc(
	fb: ^Func_Builder,
	src: ^hir.Block,
) -> (
	first_block, last_block: mir.Block_ID,
) {
	first_block = _new_block(fb)
	fb.current_block_id = first_block
	// TODO: defers, pointer escape analysis

	for stmt in src.body {
		if fb.ctx.debug {
			_append_ops(fb, mir.Debug_Marker{hir.span(stmt)})
		}

		switch stmt in stmt {
		case ^hir.If_Statement:
			_lower_if_stmt(fb, stmt)

		case ^hir.Each_Loop:
			panic("TODO: Each_Loop")
		case ^hir.Step_Loop:
			panic("TODO: Step_Loop")

		case ^hir.Local_Variable:
			var := _new_var(fb, stmt)
			if stmt.expr != nil {
				_append_ops(fb, mir.Set{dest = var, value = _lower_expression(fb, stmt.expr)})
			}
		case ^hir.Assign_Statement:
			_lower_assign(fb, stmt)

		case ^hir.Return_Statement:
			result: mir.Operand
			if stmt.value != nil {
				result = _lower_expression(fb, stmt.value)
			}
			last_block = fb.current_block_id
			_end_block(fb, mir.Return{value = result})
			return

		case ^hir.Expr_Statement:
			_lower_expression(fb, stmt.expr)
		case ^hir.Block:
			_lower_block(fb, stmt)
		case ^hir.Poison:
			panic("poison statement encountered during MIR lowering")
		}
	}

	last_block = fb.current_block_id
	return
}

_lower_if_stmt :: proc(fb: ^Func_Builder, stmt: ^hir.If_Statement) -> (after_block: mir.Block_ID) {
	before := fb.current_block_id
	true_start, true_end := _lower_block(fb, stmt.body)
	false_start, false_end: mir.Block_ID
	after := _new_block(fb, order_next = false)

	switch alt in stmt.alt {
	case ^hir.Block:
		false_start, false_end = _lower_block(fb, alt)
	case ^hir.If_Statement:
		false_start = _new_block(fb)
		fb.current_block_id = false_start
		false_end = _lower_if_stmt(fb, alt)
	case nil:
		false_start = after
		false_end = after
	case:
		unreachable()
	}

	fb.current_block_id = before
	_lower_condition(fb, stmt.condition, true_start, false_start)

	if fb.blocks[true_end].end == nil {
		_end_block(fb, mir.Jump{after}, true_end)
	}
	if false_end != after && fb.blocks[false_end].end == nil {
		_end_block(fb, mir.Jump{after}, false_end)
	}

	_append_block(fb, after)
	fb.current_block_id = after
	return after
}

_lower_assign :: proc(fb: ^Func_Builder, stmt: ^hir.Assign_Statement) {
	if len(stmt.dests) != 1 || len(stmt.exprs) != 1 {
		panic("TODO: multiple assignment")
	}

	dest: mir.Writable
	switch lowered in _lower_expression(fb, stmt.dests[0]) {
	case mir.Local_Var:
		dest = lowered
	case mir.Global_Var:
		dest = lowered
	case mir.Field_Of:
		dest = lowered
	case mir.Index_Of:
		dest = lowered
	case mir.Dereferenced:
		dest = lowered
	case mir.Constant, mir.Temp, mir.Parameter:
		unreachable()
	}

	_append_ops(fb, mir.Set{dest = dest, value = _lower_expression(fb, stmt.exprs[0])})
}
