package analysis

import "core:reflect"

import "../../common"
import "../../common/exact"
import "../ast"
import "../diagnostics"
import "../hir"
import "../resolver"
import "../units"

Untyped_Value :: common.Untyped_Value
Comptime_Value :: resolver.Comptime_Value
Comptime_Type :: resolver.Comptime_Type
Flexible_Type :: resolver.Flexible_Type
Flexible_Affinity :: resolver.Flexible_Affinity

Eval_Result :: union {
	Comptime_Value,
	hir.Expression,
}

build_expr :: proc(
	ts: ^Translation_State,
	type_ast: ast.Expression,
	scope: resolver.Scope,
) -> (
	hir.Expression,
	bool,
) {
	return nil, false
}


evaluate :: proc(
	ts: ^Translation_State,
	node: ast.Expression,
	scope: resolver.Scope,
) -> Eval_Result {
	_not_implemented :: proc(ts: ^Translation_State, node: $S) -> hir.Expression {
		diagnostics.emit(
			.Not_Implemented,
			node.span,
			"evaluation not yet implemented for %T",
			node,
		)
		return poison(ts, node.span)
	}

	switch node in node {
	case ^ast.Simple_Literal_Expr:
		switch value in node.value {
		case exact.Rat:
		case string:
			return Comptime_Value{value = value, type = Flexible_Type{.String}, unit = .No_Unit}
		case rune:
			return Comptime_Value{value = value, type = Flexible_Type{.Rune}, unit = .No_Unit}
		case byte:
			return Comptime_Value{value = value, type = Flexible_Type{.Byte}, unit = .No_Unit}
		case bool:
			return Comptime_Value{value = value, type = Flexible_Type{.Boolean}, unit = .No_Unit}
		case Untyped_Value:
			return Comptime_Value {
				value = value,
				type = Flexible_Type{.Contextual},
				unit = .No_Unit,
			}
		}

	case ^ast.Scalar_Literal_Expr:
		affinity: Flexible_Affinity

		switch node.format {
		case .Decimal_Integer:
			affinity = .Integer
		case .Decimal:
			affinity = .Decimal
		case .Float, .Hex_Float:
			affinity = .Binary_Float
		case .Hex_Integer, .Octal_Integer, .Binary_Integer:
			affinity = .Unsigned_Integer
		}

		if unit, ok := get_canonical_unit(ts, node.unit, scope); ok {
			return Comptime_Value{value = node.value, type = Flexible_Type{affinity}, unit = unit}
		} else {
			return Comptime_Value {
				value = node.value,
				type = Flexible_Type{affinity},
				unit = .No_Unit,
			}
		}

	case ^ast.Binop_Expr:
		return _eval_binop(ts, node, scope)

	case ^ast.Name_Expr:
		var_expr :: proc(
			ts: ^Translation_State,
			node: ^ast.Name_Expr,
			symbol: $S,
		) -> hir.Expression {
			expr := new(hir.Var_Expr, ts.output.allocator)
			expr^ = {
				span       = node.span,
				references = symbol.hir,
				type       = symbol.hir.type,
				unit       = symbol.hir.unit,
			}
			return expr
		}

		#partial switch resolved in resolve(ts, scope, node.name.id) {
		case ^resolver.Constant:
			return resolved.value

		case ^resolver.Local_Variable:
			return var_expr(ts, node, resolved)
		case ^resolver.Global_Variable:
			return var_expr(ts, node, resolved)
		case ^resolver.Formal_Parameter:
			return var_expr(ts, node, resolved)

		case ^resolver.Base_Unit:
			return Comptime_Value {
				value = exact.RAT_ONE,
				type = Flexible_Type{.Integer},
				unit = units.base_unit(resolved.id),
			}

		case ^resolver.Unit_Alias:
			if resolved.canonical != nil {
				return Comptime_Value {
					value = exact.RAT_ONE,
					type = Flexible_Type{.Integer},
					unit = resolved.canonical,
				}
			} else {
				return hir.Expression(poison(ts, node.span))
			}

		case nil:
			diagnostics.emit(
				.Wrong_Symbol_Kind,
				node.name.span,
				"'%s' could not be resolved",
				node.name.id,
			)
			return hir.Expression(poison(ts, node.span))

		case:
			diag := diagnostics.emit(
				.Wrong_Symbol_Kind,
				node.name.span,
				"'%s' references a %T",
				node.name.id,
				reflect.get_union_variant(resolved),
			)
			if name_span, ok := resolver.span_of_name(resolved); ok {
				diagnostics.reference(diag, name_span, "defined here")
			}
			return hir.Expression(poison(ts, node.span))
		}

	case ^ast.Unit_Reinterpret_Expr:
		new_unit: hir.Realized_Unit
		switch node.new_unit {
		case ast.Indeterminate_Unit.No_Unit:
			new_unit = hir.Indeterminate_Unit.No_Unit
		case ast.Indeterminate_Unit.Flexible:
			diagnostics.emit(.TBD, node.span, "cannot reinterpret units as flexible")
		case ast.Indeterminate_Unit.Inferred:
			// might be a panic("unreachable")
			diagnostics.emit(
				.TBD,
				node.span,
				"inferred units are not valid for unit reinterpret expressions",
			)
		case:
			new_unit = build_unit(ts, node.new_unit, scope) or_else nil
		}

		if new_unit == nil {
			return hir.Expression(poison(ts, node.span))
		}

		switch result in evaluate(ts, node.expr, scope) {
		case Comptime_Value:
			return Comptime_Value{value = result.value, type = result.type, unit = new_unit}
		case hir.Expression:
			if type, _, ok := hir.singular_type_and_unit(result); ok {
				expr := new(hir.Unit_Reinterpret_Expr, ts.output.allocator)
				expr^ = {
					span = node.span,
					type = type,
					unit = new_unit,
					expr = result,
				}
				return hir.Expression(expr)
			} else {
				diagnostics.emit(
					.Arity_Mismatch,
					ast.expression_span(node.expr),
					"this expression returns %d values, but it requires exactly one to be used in a unit reinterpretation",
					hir.value_count(result),
				)
			}
		}

		return hir.Expression(poison(ts, node.span))

	case ^ast.Placeholder_Expr:
		return _not_implemented(ts, node)
	case ^ast.FieldAccess_Expr:
		return _not_implemented(ts, node)
	case ^ast.Implicit_Enum_Expr:
		return _not_implemented(ts, node)
	case ^ast.Move_Expr:
		return _not_implemented(ts, node)
	case ^ast.Unary_Expr:
		return _not_implemented(ts, node)
	case ^ast.Address_Of_Expr:
		return _not_implemented(ts, node)
	case ^ast.Dereference_Expr:
		return _not_implemented(ts, node)
	case ^ast.Cast_Expr:
		return _not_implemented(ts, node)
	case ^ast.Unit_Conversion_Expr:
		return _not_implemented(ts, node)
	case ^ast.Index_Expr:
		return _not_implemented(ts, node)
	case ^ast.Callish_Expr:
		return _not_implemented(ts, node)
	case ^ast.Type_Expr_Expr:
		return _not_implemented(ts, node)
	case ^ast.Unit_Expr:
		return _not_implemented(ts, node)
	}

	panic("unreachable")
}

_eval_binop :: proc(
	ts: ^Translation_State,
	node: ^ast.Binop_Expr,
	scope: resolver.Scope,
) -> Eval_Result {
	diagnostics.emit(.Not_Implemented, node.span, "binop evaluation not yet implemented")
	return hir.Expression(poison(ts, node.span))
}
