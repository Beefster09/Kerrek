package analysis

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
			switch expr in evaluate(ts, stmt.expr, &locals) {
			case Comptime_Value:
				diagnostics.emit(
					.Unused_Value,
					ast.expression_span(stmt.expr),
					"this expression does nothing",
				)
			case hir.Expression:
				num_values := hir.value_count(expr)
				if num_values != 0 {
					if num_values == 1 {
						diagnostics.emit(
							.Unused_Value,
							ast.expression_span(stmt.expr),
							"this expression returns a value, but it was not used",
						)
					} else {
						diagnostics.emit(
							.Unused_Value,
							ast.expression_span(stmt.expr),
							"this expression returns %d values, but none were used",
							num_values,
						)
					}
				}
				out := new(hir.Expr_Statement)
				out.span = stmt.span
				out.expr = expr
				append(&body, out)
			}

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

			variable := build_local_var(ts, stmt, &locals)
			if variable != nil {
				append(&body, variable)

				symbol := resolver.new_symbol(
					ts.symbol_resolver,
					resolver.Local_Variable,
					stmt.name.id,
				)
				symbol.ast = stmt
				symbol.hir = variable
				symbol.state = .Done
				symbol.defined_in = func.defined_in
				resolver.define_local(
					&locals,
					stmt.name,
					symbol,
					warn_shadowing = {.Builtins, .Outer_Scopes} if same_name else {},
				)
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
			}
		case ^ast.Return_Statement:
			values := make([dynamic]hir.Expression, ts.output.allocator)
			value_count := 0

			for value in stmt.values {
				built, ok := build_expr(ts, value, &locals)
				if !ok {
					continue
				}
				append(&values, built)
				value_count += hir.value_count(built)
			}

			expected_count := len(func.hir.returns)
			if value_count != expected_count {
				diagnostics.emit(
					.Arity_Mismatch,
					stmt.span,
					"return statement has %d values, but the function returns %d",
					value_count,
					expected_count,
				)
				continue
			}

			ret := new(hir.Return_Statement, ts.output.allocator)
			ret^ = {
				span   = stmt.span,
				values = values[:],
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
) -> ^hir.Local_Variable {
	diagnostics.emit(.Not_Implemented, src.span, "local variable analysis is not yet implemented")
	return nil
}
