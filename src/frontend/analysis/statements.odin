package analysis

import "../../common"
import "../../util"
import "../ast"
import "../diagnostics"
import "../hir"
import "../resolver"


build_block :: proc(
	ts: ^Translation_State,
	src: ^ast.Block,
	func: ^resolver.Function,
	outer_scope: resolver.Scope,
) -> ^hir.Block {
	locals := resolver.temp_scope(outer_scope)

	block := new(hir.Block, ts.output.allocator)
	body := make([dynamic]hir.Statement, ts.output.allocator)

	all_ok := true

	process_stmts: for stmt in src.body {
		switch stmt in stmt {
		case ^ast.Block:
			inner := build_block(ts, stmt, func, &locals)
			if inner != nil {
				append(&body, inner)
			}

		case ^ast.Expr_Statement:
			expr, ok := build_expr(ts, stmt.expr, &locals)
			if !ok {
				continue process_stmts
			}
			if hir.has_value(expr) {
				diagnostics.emit(
					.Unused_Value,
					ast.expression_span(stmt.expr),
					"this expression returns a value, but it was not used",
				)
			}
			out := new(hir.Expr_Statement, ts.output.allocator)
			out.span = stmt.span
			out.expr = expr
			append(&body, out)


		case ^ast.Assign_Statement:
			dests := make([]hir.Expression, len(stmt.dests), ts.output.allocator)
			lhs_ok := true
			process_lhs: for dest, i in stmt.dests {
				switch d in evaluate(ts, dest, &locals) {
				case Comptime_Value:
					diagnostics.emit(
						.Invalid_Assign_Destination,
						ast.span(dest),
						"constants are not assignable",
					)
				case hir.Expression:
					if !_is_writable_here(ts, d, func, outer_scope) {
						lhs_ok = false
						continue process_lhs
					}
					dests[i] = d
				case ^resolver.Import:
					diagnostics.emit(
						.Invalid_Assign_Destination,
						ast.span(dest),
						"imports are not assignable",
					)
				}
			}

			values := make([]hir.Expression, len(stmt.exprs), ts.output.allocator)
			rhs_ok := true
			process_rhs: for expr, i in stmt.exprs {
				lhs_type, lhs_unit, lhs_type_ok := hir.type_and_unit(dests[i])
				value, value_ok := build_expr(
					ts,
					expr,
					&locals,
					type_hint = lhs_type if lhs_type_ok else nil,
				)
				rhs_type, _, rhs_type_ok := hir.type_and_unit(value)

				if !value_ok || !rhs_type_ok {
					rhs_ok = false
					continue process_rhs
				}

				if !is_assignable_to(lhs_type, rhs_type) {
					diag := diagnostics.emit(
						.Assignment_Type_Mismatch,
						ast.span(expr),
						"this expression is not assignable to %s",
						lhs_type,
					)
					diagnostics.note(diag, "the type of this expression is %s", rhs_type)
					if len(stmt.exprs) > 1 {
						diagnostics.reference(
							diag,
							hir.span(dests[i]),
							"this is the corresponding destination expression",
						)
					}
					rhs_ok = false
					continue process_rhs
				}

				if !types_equal(lhs_type, rhs_type) {
					cast_expr := new(hir.Cast_Expr, ts.output.allocator)
					cast_expr^ = {
						span = ast.span(expr),
						expr = value,
						to   = lhs_type,
						type = lhs_type,
						unit = lhs_unit,
					}
					value = cast_expr
				}

				values[i] = value
			}

			if lhs_ok && rhs_ok {
				assignment := new(hir.Assign_Statement, ts.output.allocator)
				assignment^ = {
					span  = stmt.span,
					dests = dests,
					exprs = values,
				}
				append(&body, assignment)
			}

		case ^ast.Local_Variable:
			same_name := false
			if name_expr, ok := util.chain_extract(stmt.expr, ast.Expression, ^ast.Name_Expr); ok {
				same_name = name_expr.name.id == stmt.name.id
			}

			symbol := resolver.new_symbol(
				ts.symbol_resolver,
				resolver.Local_Variable,
				stmt.name.id,
			)
			symbol.ast = stmt
			symbol.state = .Processing
			symbol.defined_in = func.defined_in

			resolver.define_local(
				&locals,
				stmt.name,
				symbol,
				warn_shadowing = {} if same_name else {.Builtins, .Outer_Scopes},
			)

			variable := build_local_var(ts, stmt, &locals, symbol.id)
			if variable != nil {
				append(&body, variable)

				symbol.hir = variable
				symbol.state = .Done
			} else {
				symbol.state = .Failed
			}

		case ^ast.Constant_Def:
			same_name := false
			if name_expr, ok := stmt.expr.(^ast.Name_Expr); ok {
				same_name = name_expr.name.id == stmt.name.id
			}

			switch value in evaluate(ts, stmt.expr, &locals) {
			case Comptime_Value:
				symbol := resolver.new_symbol(ts.symbol_resolver, resolver.Constant, stmt.name.id)
				symbol.ast = stmt
				symbol.value = value
				symbol.state = .Done
				symbol.defined_in = func.defined_in
				resolver.define_local(
					&locals,
					stmt.name,
					symbol,
					warn_shadowing = {.Builtins, .Outer_Scopes} if same_name else {},
				)
			case hir.Expression:
				if _, is_poison := value.(^hir.Poison); !is_poison {
					diagnostics.emit(
						.Not_Compile_Time_Known,
						ast.expression_span(stmt.expr),
						"this expression is not constant at compile time",
					)
				}
				all_ok = false
			case ^resolver.Import:
				diagnostics.emit(
					.Symbol_Not_Constant,
					ast.expression_span(stmt.expr),
					"imports cannot be aliased as constants",
				)
				all_ok = false
			}

		case ^ast.If_Statement:
			if_stmt := _build_if_stmt(ts, stmt, func, &locals)
			if if_stmt == nil {
				all_ok = false
				continue process_stmts
			}
			append(&body, if_stmt)

		case ^ast.Each_Loop:
			diagnostics.emit(.Not_Implemented, stmt.span, "TODO: loop i, x in c {...}")
		case ^ast.Step_Loop:
			diagnostics.emit(.Not_Implemented, stmt.span, "TODO: loop step while {...}")

		case ^ast.Return_Statement:
			ret := _build_return(ts, stmt, func, &locals)
			if ret == nil {
				all_ok = false
				continue process_stmts
			}

			append(&body, ret)
		}
	}

	block^ = {
		span = src.span,
		body = body[:],
	}
	return block
}

build_local_var :: proc(
	ts: ^Translation_State,
	src: ^ast.Local_Variable,
	scope: resolver.Scope,
	id: hir.Symbol_ID,
) -> ^hir.Local_Variable {
	return #force_inline _build_var(ts, src, scope, id, hir.Local_Variable)
}

_build_var :: proc(
	ts: ^Translation_State,
	src: ^$A,
	scope: resolver.Scope,
	id: hir.Symbol_ID,
	$H: typeid,
) -> ^H where (A == ast.Local_Variable || A == ast.Global_Variable) &&
	(H == hir.Local_Variable when A == ast.Local_Variable else H == hir.Global_Variable) {
	IS_LOCAL :: A == ast.Local_Variable

	var_type: hir.Type
	if src.type != nil {
		ok: bool
		var_type, ok = build_type(ts, src.type, scope)
		if !ok {
			return nil
		}
	}

	unit: hir.Realized_Unit
	unit_is_inferred := false
	switch declared_unit in src.unit {
	case ^ast.Inferred_Unit:
		unit_is_inferred = true
	case ^ast.No_Unit, ^ast.Flexible_Unit, ^ast.Compound_Unit:
		ok: bool
		unit, ok = build_unit(ts, declared_unit, scope)
		if !ok {
			return nil
		}
	}

	expr: ast.Expression
	unbound := false
	when IS_LOCAL {
		switch value in src.expr {
		case ast.Expression:
			expr = value
		case ast.Unbound_Var:
			unbound = true
		}
	} else {
		expr = src.expr
	}

	value: hir.Expression
	if unbound {
		if var_type == nil {
			diagnostics.emit(
				.Missing_Variable_Type,
				src.span,
				"unbound variables must have a type",
			)
			return nil
		}
		if unit_is_inferred {
			unit = hir.Indeterminate_Unit.No_Unit
		}
	} else if expr != nil {
		built, ok := build_expr(ts, expr, scope, var_type)
		if !ok {
			return nil
		}
		if _, is_poison := built.(^hir.Poison); is_poison {
			return nil
		}

		value_type, value_unit, has_value := hir.type_and_unit(built)
		if !has_value {
			diagnostics.emit(
				.Assignment_Arity_Mismatch,
				ast.span(expr),
				"this expression does not return a value and therefore cannot be assigned to '%s'",
				src.name,
			)
			return nil
		}

		if var_type == nil {
			inference_ok: bool
			var_type, inference_ok = infer_type(value_type, src.span)
			if !inference_ok {
				return nil
			}
		}
		if unit_is_inferred {
			unit = value_unit
		}
		value = built
	} else {
		if var_type == nil {
			diagnostics.emit(
				.Missing_Variable_Type,
				src.span,
				"variables must specify a type or an initial value that implies a type",
			)
			return nil
		}
		if !is_zeroable(var_type) {
			diagnostics.emit(
				.Nonzeroable_Variable,
				src.span,
				"variable '%s' has a non-zeroable type and therefore must be given an initial value or be explicitly unbound",
				src.name,
			)
			return nil
		}
		if unit_is_inferred {
			unit = hir.Indeterminate_Unit.Flexible
		}

		zero := new(hir.Const_Expr, ts.output.allocator)
		zero^ = {
			span = common.collapse_span_to_end(src.span),
			value = hir.Zero_Of{type = var_type},
			type = var_type,
			unit = unit,
		}
		value = zero
	}

	when !IS_LOCAL {
		if value == nil {
			diagnostics.emit(
				.Unbound_Global_Variable,
				src.span,
				"global variables may not be unbound",
			)
			return nil
		}
	}

	result := new(H, ts.output.allocator)
	result^ = {
		span = src.span,
		id   = id,
		name = src.name,
		type = var_type,
		unit = unit,
		expr = value,
	}
	return result
}

_is_writable_here :: proc(
	ts: ^Translation_State,
	expr: hir.Expression,
	func: ^resolver.Function,
	scope: resolver.Scope,
) -> bool {
	switch node in expr {
	case ^hir.Var_Expr:
		if _, ok := node.references.(^hir.Local_Variable); ok {
			return true
		}
		diagnostics.emit(
			.Invalid_Assign_Destination,
			node.span,
			"only local variables are assignable here",
		)
		return false
	case ^hir.Dereference_Expr:
		return true
	case ^hir.Field_Access_Expr:
		return _is_writable_here(ts, node.base, func, scope)
	case ^hir.Index_Expr:
		return _is_writable_here(ts, node.collection, func, scope)
	case ^hir.Const_Expr:
		diagnostics.emit(
			.Invalid_Assign_Destination,
			node.span,
			"constant values are not assignable",
		)
		return false
	case ^hir.Enum_Value:
		diagnostics.emit(.Invalid_Assign_Destination, node.span, "enum values are not assignable")
		return false
	case ^hir.Move_Expr:
		diagnostics.emit(
			.Invalid_Assign_Destination,
			node.span,
			"move expressions are not assignable",
		)
		return false
	case ^hir.Condition_Expr:
		diagnostics.emit(
			.Invalid_Assign_Destination,
			node.span,
			"conditional expressions are not assignable",
		)
		return false
	case ^hir.Binop_Expr:
		diagnostics.emit(
			.Invalid_Assign_Destination,
			node.span,
			"binary expressions are not assignable",
		)
		return false
	case ^hir.Unary_Expr:
		diagnostics.emit(
			.Invalid_Assign_Destination,
			node.span,
			"unary expressions are not assignable",
		)
		return false
	case ^hir.Power_Expr:
		diagnostics.emit(
			.Invalid_Assign_Destination,
			node.span,
			"power expressions are not assignable",
		)
		return false
	case ^hir.Address_Of_Expr:
		diagnostics.emit(
			.Invalid_Assign_Destination,
			node.span,
			"address expressions are not assignable",
		)
		return false
	case ^hir.Cast_Expr:
		diagnostics.emit(
			.Invalid_Assign_Destination,
			node.span,
			"cast expressions are not assignable",
		)
		return false
	case ^hir.Unit_Conversion_Expr:
		diagnostics.emit(
			.Invalid_Assign_Destination,
			node.span,
			"unit conversions are not assignable",
		)
		return false
	case ^hir.Unit_Reinterpret_Expr:
		diagnostics.emit(
			.Invalid_Assign_Destination,
			node.span,
			"unit reinterpretations are not assignable",
		)
		return false
	case ^hir.Static_Func_Expr:
		diagnostics.emit(.Invalid_Assign_Destination, node.span, "functions are not assignable")
		return false
	case ^hir.Static_Call_Expr:
		diagnostics.emit(.Invalid_Assign_Destination, node.span, "call results are not assignable")
		return false
	case ^hir.Dynamic_Call_Expr:
		diagnostics.emit(.Invalid_Assign_Destination, node.span, "call results are not assignable")
		return false
	case hir.Type, nil:
		diagnostics.emit(.Invalid_Assign_Destination, {}, "types are not assignable")
		return false
	case ^hir.Poison:
		diagnostics.emit(
			.Invalid_Assign_Destination,
			node.span,
			"invalid expressions are not assignable",
		)
		return false
	}

	unreachable()
}

_build_if_stmt :: proc(
	ts: ^Translation_State,
	src: ^ast.If_Statement,
	func: ^resolver.Function,
	scope: resolver.Scope,
) -> ^hir.If_Statement {
	cond, cond_ok := build_expr(ts, src.condition, scope, type_hint = hir.Primitive_Type.Boolean)

	// evaluate and typecheck the body of the if and else even if the condition
	// couldn't be evaluated or is otherwise invalid
	// it's not very useful if one bad if suppresses other checks within the block
	body := build_block(ts, src.body, func, scope)

	alt: type_of(hir.If_Statement{}.alt) = nil
	switch alt_src in src.alt {
	case ^ast.Block:
		alt = build_block(ts, alt_src, func, scope)
	case ^ast.If_Statement:
		alt = _build_if_stmt(ts, alt_src, func, scope)
	}

	if !cond_ok {
		// error diagnostic already emitted
		return nil
	}

	cond_type, _, has_value := hir.type_and_unit(cond)
	if !has_value {
		diagnostics.emit(
			.Invalid_Condition,
			ast.span(src.condition),
			"expressions used in conditions must return a value",
		)
		return nil
	}

	cond_type_ok := false
	#partial switch ct in cond_type {
	case hir.Primitive_Type:
		cond_type_ok = ct == .Boolean
	case ^hir.Optional_Type:
		cond_type_ok = true
	case ^hir.Pointer_Type:
		cond_type_ok = ct.ownership == .Weak
	}

	if !cond_type_ok {
		diagnostics.emit(
			.Invalid_Condition,
			ast.span(src.condition),
			"condition must be a boolean, optional, or weak pointer (got %s)",
			cond_type,
		)
		return nil
	}

	result := new(hir.If_Statement, ts.output.allocator)
	result^ = {
		span      = src.span,
		condition = cond,
		body      = body,
		alt       = alt,
	}

	return result
}

_build_return :: proc(
	ts: ^Translation_State,
	stmt: ^ast.Return_Statement,
	func: ^resolver.Function,
	scope: resolver.Scope,
) -> ^hir.Return_Statement {
	expected := func.hir.ret
	value: hir.Expression
	type: hir.Type
	unit: hir.Realized_Unit
	has_value := false
	if stmt.value != nil {
		built, ok := build_expr(ts, stmt.value, scope)
		if _, is_poison := built.(^hir.Poison); !ok || is_poison {
			return nil
		}
		value = built
		type, _, has_value = hir.type_and_unit(built)
		if !has_value {
			diagnostics.emit(
				.Invalid_Nullary_Expression,
				ast.span(stmt.value),
				"this expression does not return a value",
			)
			return nil
		}
	}

	if has_value != (expected != nil) {
		diagnostics.emit(
			.Return_Arity_Mismatch,
			stmt.span,
			"return statement %s a value, but the func '%s' %s a value",
			"produces" if has_value else "does not produce",
			func.name,
			"returns" if expected != nil else "does not return",
		)
		return nil
	}

	if has_value && !_type_implicitly_converts(expected.type, type) {
		diagnostics.emit(
			.Return_Type_Mismatch,
			ast.span(stmt.value),
			"the func signature requires this value to be a %s, but it was a %s",
			expected.type,
			type,
		)
	}

	ret := new(hir.Return_Statement, ts.output.allocator)
	ret^ = {
		span  = stmt.span,
		value = value,
	}

	return ret
}
