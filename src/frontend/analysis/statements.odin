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
			switch num_values := hir.value_count(expr); num_values {
			case 0:
			case 1:
				diagnostics.emit(
					.Unused_Value,
					ast.expression_span(stmt.expr),
					"this expression returns a value, but it was not used",
				)
			case:
				diagnostics.emit(
					.Unused_Value,
					ast.expression_span(stmt.expr),
					"this expression returns %d values, but none were used",
					num_values,
				)
			}
			out := new(hir.Expr_Statement, ts.output.allocator)
			out.span = stmt.span
			out.expr = expr
			append(&body, out)


		case ^ast.Assign_Statement:
			for dest in stmt.dests {
				evaluate(ts, dest, &locals)
			}
			for expr in stmt.exprs {
				evaluate(ts, expr, &locals)
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
		case ^ast.Return_Statement:
			ret := _build_return(ts, stmt, func, &locals)
			if ret == nil {
				all_ok = false
				continue process_stmts
			}

			append(&body, ret)
		}
	}

	block := new(hir.Block, ts.output.allocator)
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
			diagnostics.emit(.Missing_Variable_Type, src.span, "unbound variables must have a type")
			return nil
		}
		if unit_is_inferred {
			unit = hir.Indeterminate_Unit.No_Unit
		}
	} else if expr != nil {
		built, ok := build_expr(ts, expr, scope)
		if !ok {
			return nil
		}
		if _, is_poison := built.(^hir.Poison); is_poison {
			return nil
		}

		types_and_units := hir.expression_types_and_units(built)
		if len(types_and_units) != 1 {
			diagnostics.emit(
				.Assignment_Arity_Mismatch,
				ast.span(expr),
				"this expression results in %d values and therefore cannot be assigned to '%s'",
				len(types_and_units),
				src.name,
			)
			return nil
		}

		inferred: bool
		var_type, inferred = infer_type(types_and_units[0].type, src.span)
		if !inferred {
			return nil
		}
		if unit_is_inferred {
			unit = types_and_units[0].unit
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
			diagnostics.emit(.Unbound_Global_Variable, src.span, "global variables may not be unbound")
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

_build_return :: proc(
	ts: ^Translation_State,
	stmt: ^ast.Return_Statement,
	func: ^resolver.Function,
	scope: resolver.Scope,
) -> ^hir.Return_Statement {
	exprs, expr_idxs, types_and_units := _value_list(ts, stmt.values, scope)

	value_count := len(expr_idxs)
	expected_count := len(func.hir.returns)
	if value_count != expected_count {
		diagnostics.emit(
			.Return_Arity_Mismatch,
			stmt.span,
			"return statement produces %d value%s, but the func '%s' returns %d value%s",
			value_count,
			"s" if value_count != 1 else "",
			func.name,
			expected_count,
			"s" if expected_count != 1 else "",
		)
		return nil
	}

	for expr_idx, i in expr_idxs {
		expected := func.hir.returns[i]
		type_and_unit := types_and_units[i]

		if !_type_implicitly_converts(expected.type, type_and_unit.type) {
			diagnostics.emit(
				.Return_Type_Mismatch,
				ast.span(stmt.values[expr_idx]),
				"the func signature requires this value to be a %s, but it was a %s",
				expected.type,
				type_and_unit.type,
			)
		}
	}

	ret := new(hir.Return_Statement, ts.output.allocator)
	ret^ = {
		span   = stmt.span,
		values = exprs[:],
	}

	return ret
}

_value_list :: proc(
	ts: ^Translation_State,
	in_values: []ast.Expression,
	scope: resolver.Scope,
) -> (
	[]hir.Expression,
	[]int,
	[]hir.Type_And_Unit,
) {
	exprs := make([dynamic]hir.Expression, 0, len(in_values), ts.output.allocator)
	indices := make([dynamic]int, context.temp_allocator)
	types_and_units := make([dynamic]hir.Type_And_Unit, context.temp_allocator)

	poisoned := false
	for value, i in in_values {
		built, ok := build_expr(ts, value, scope)
		if _, is_poison := built.(^hir.Poison); !ok || is_poison {
			poisoned = true
			continue
		}
		append(&exprs, built)

		tus := hir.expression_types_and_units(built)
		if len(tus) == 0 {
			diagnostics.emit(
				.Dubious_Nullary_Expression,
				ast.span(value),
				"this expression was used in a value list context but it returns no values",
			)
		}
		append(&types_and_units, ..tus)
		for _ in tus {
			append(&indices, i)
		}
	}

	if poisoned {
		return nil, nil, nil
	}
	assert(len(types_and_units) == len(indices))

	shrink(&exprs)
	return exprs[:], indices[:], types_and_units[:]
}
