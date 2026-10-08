package analysis

import "base:runtime"
import "core:reflect"
import "core:strings"

import "../../common"
import "../../common/exact"
import "../../util"
import "../ast"
import "../diagnostics"
import "../hir"
import "../resolver"
import "../units"

Untyped_Nil :: common.Untyped_Nil
Untyped_Zero :: common.Untyped_Zero
Comptime_Value :: resolver.Comptime_Value
Comptime_Type :: resolver.Comptime_Type
Flexible_Type :: resolver.Flexible_Type
Flexible_Affinity :: resolver.Flexible_Affinity

Eval_Result :: union {
	Comptime_Value,
	hir.Expression,
	^resolver.Import,
}

INT64_DECIMAL_DIGITS :: 18

infer_type :: proc(evaluated_type: Comptime_Type, span: common.Span) -> (hir.Type, bool) {
	switch typ in evaluated_type {
	case Flexible_Type:
		switch typ.affinity {
		case .Integer:
			return hir.Primitive_Type.Int, true
		case .Unsigned_Integer:
			return hir.Primitive_Type.UInt64, true
		case .Decimal:
			dec := hir.Fixed_Decimal {
				digits    = u8(typ.digits),
				scale     = i8(typ.scale),
				flags     = {.Inferred},
				magnitude = f32(typ.digits),
			}
			if dec.digits > INT64_DECIMAL_DIGITS {
				diagnostics.emit(
					.Large_Decimal,
					span,
					"this expression is inferred as Decimal(%d, %d) and may be slower than expected",
				)
			}
			return dec, true
		case .Binary_Float:
			return hir.Primitive_Type.Bin64, true
		case .Boolean:
			return hir.Primitive_Type.Boolean, true
		case .String:
			return hir.Primitive_Type.String, true
		case .Rune:
			return hir.Primitive_Type.Rune, true
		case .Byte:
			return hir.Primitive_Type.Byte, true
		case .Rational, .Nil, .Any_Zero:
			diagnostics.emit(
				.Cannot_Infer_Type,
				span,
				"no singular type can be inferred from this expression",
			)
			return nil, false
		}
	case hir.Type:
		return typ, true
	}
	return nil, false
}

build_expr :: proc(
	ts: ^Translation_State,
	expr: ast.Expression,
	scope: resolver.Scope,
	type_hint: hir.Type = nil,
) -> (
	hir.Expression,
	bool,
) {
	switch result in evaluate(ts, expr, scope, type_hint) {
	case Comptime_Value:
		return materialize_value(ts, result, ast.span(expr), type_hint)
	case hir.Expression:
		return result, true
	case ^resolver.Import:
		diagnostics.emit(.Symbol_Not_Value, ast.span(expr), "imports are not valid as values")
	}

	return nil, false
}

evaluate :: proc(
	ts: ^Translation_State,
	node: ast.Expression,
	scope: resolver.Scope,
	type_hint: hir.Type = nil,
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
			panic("simple literal expression contained a rational")
		case string:
			return Comptime_Value {
				value = value,
				type = Flexible_Type{affinity = .String},
				unit = .No_Unit,
			}
		case rune:
			return Comptime_Value {
				value = value,
				type = Flexible_Type{affinity = .Rune},
				unit = .No_Unit,
			}
		case byte:
			return Comptime_Value {
				value = value,
				type = Flexible_Type{affinity = .Byte},
				unit = .No_Unit,
			}
		case bool:
			return Comptime_Value {
				value = value,
				type = Flexible_Type{affinity = .Boolean},
				unit = .No_Unit,
			}
		case Untyped_Nil:
			return Comptime_Value {
				value = value,
				type = Flexible_Type{affinity = .Nil},
				unit = .No_Unit,
			}
		case Untyped_Zero:
			return Comptime_Value {
				value = value,
				type = Flexible_Type{affinity = .Any_Zero},
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

		out_unit: hir.Realized_Unit
		if unit, ok := get_canonical_unit(ts, node.unit, scope, ts.allocator); ok {
			out_unit = unit
		} else {
			out_unit = .Flexible
		}

		return Comptime_Value {
			value = exact.clone(node.value, ts.output.allocator),
			type = Flexible_Type{affinity = affinity, digits = node.digits, scale = node.scale},
			unit = out_unit,
		}

	case ^ast.Binop_Expr:
		return _eval_binop(ts, node, scope, type_hint)

	case ^ast.Unary_Expr:
		return _eval_unary(ts, node, scope, type_hint)

	case ^ast.Name_Expr:
		return _eval_name_expr(ts, node, scope)

	case ^ast.Unit_Reinterpret_Expr:
		new_unit: hir.Realized_Unit
		switch unit in node.new_unit {
		case ^ast.No_Unit:
			new_unit = hir.Indeterminate_Unit.No_Unit
		case ^ast.Flexible_Unit:
			diagnostics.emit(
				.Invalid_Unit_Reinterpretation,
				unit.span,
				"cannot reinterpret units as flexible",
			)
		case ^ast.Inferred_Unit:
			// might be a panic("unreachable")
			diagnostics.emit(
				.Invalid_Unit_Reinterpretation,
				node.span,
				"inferred units are not valid for unit reinterpret expressions",
			)
		case ^ast.Compound_Unit:
			new_unit = get_canonical_unit(ts, unit, scope, ts.allocator) or_else nil
		}

		if new_unit == nil {
			return hir.Expression(poison(ts, node.span))
		}

		switch result in evaluate(ts, node.expr, scope, type_hint) {
		case Comptime_Value:
			return Comptime_Value{value = result.value, type = result.type, unit = new_unit}
		case hir.Expression:
			if type, _, ok := hir.type_and_unit(result); ok {
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
					.Expected_Single_Value,
					ast.expression_span(node.expr),
					"this expression does not return a value",
				)
			}
		case ^resolver.Import:
			diagnostics.emit(
				.Symbol_Not_Value,
				node.span,
				"this is an import, which is not a valid value",
			)
		}

		return hir.Expression(poison(ts, node.span))

	case ^ast.Placeholder_Expr:
		return _not_implemented(ts, node)
	case ^ast.Typed_Zero_Expr:
		return _not_implemented(ts, node)
	case ^ast.Field_Access_Expr:
		return _not_implemented(ts, node)
	case ^ast.Implicit_Enum_Expr:
		return _not_implemented(ts, node)
	case ^ast.Move_Expr:
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
		return _eval_callish_expr(ts, node, scope)
	case ^ast.Type_Expr_Expr:
		return _not_implemented(ts, node)
	case ^ast.Unit_Expr:
		return _not_implemented(ts, node)
	}

	panic("unreachable")
}

_eval_name_expr :: proc(
	ts: ^Translation_State,
	node: ^ast.Name_Expr,
	scope: resolver.Scope,
) -> Eval_Result {
	var_expr :: #force_inline proc(
		ts: ^Translation_State,
		node: ^ast.Name_Expr,
		symbol: $S,
	) -> hir.Expression {
		if symbol.hir == nil {
			return poison(ts, node.span)
		}
		expr := new(hir.Var_Expr, ts.output.allocator)
		expr^ = {
			span       = node.span,
			references = symbol.hir,
			type       = symbol.hir.type,
			unit       = symbol.hir.unit,
		}
		return expr
	}

	switch resolved in resolve(ts, scope, node.name) {
	case ^resolver.Constant:
		if resolved.state == .Done {
			return resolved.value
		} else {
			return hir.Expression(poison(ts, node.span))
		}

	case ^resolver.Local_Variable:
		return var_expr(ts, node, resolved)
	case ^resolver.Global_Variable:
		return var_expr(ts, node, resolved)
	case ^resolver.Formal_Parameter:
		return var_expr(ts, node, resolved)
	case ^resolver.Base_Unit:
		return Comptime_Value {
			value = exact.RAT_ONE,
			type = Flexible_Type{affinity = .Integer, scale = 0},
			unit = units.base_unit(resolved.id),
		}

	case ^resolver.Unit_Alias:
		if resolved.canonical != nil {
			return Comptime_Value {
				value = exact.RAT_ONE,
				type = Flexible_Type{affinity = .Integer, scale = 0},
				unit = resolved.canonical,
			}
		} else {
			return hir.Expression(poison(ts, node.span))
		}

	case ^resolver.Function:
		func_expr := new(hir.Static_Func_Expr, ts.output.allocator)
		func_expr^ = {
			span = node.span,
			func = resolved.hir,
		}

		return hir.Expression(func_expr)
	case ^resolver.Type_Alias:
		return hir.Expression(hir.Type(resolved.hir))
	case ^resolver.Distinct_Type:
		return hir.Expression(hir.Type(resolved.hir))
	case ^resolver.Struct_Type:
		return hir.Expression(hir.Type(resolved.hir))
	case ^resolver.Enum_Type:
		return hir.Expression(hir.Type(resolved.hir))
	case ^resolver.Import:
		return resolved
	case ^resolver.Builtin:
		switch resolved.kind {
		case .Primitive_Type:
			if prim, ok := _primitive_type(resolved); ok {
				return hir.Expression(hir.Type(prim))
			}
			panic("could not resolve primitive type")
		case .Parametric_Type:
		case .Function:
		case .Annotation:
			diag := diagnostics.emit(
				.Symbol_Not_Value,
				node.name.span,
				"'%s' references a builtin annotation, which is not valid anywhere in an expression context",
				node.name.id,
			)
		}

	case ^resolver.Annotation, ^resolver.Capability:
		diag := diagnostics.emit(
			.Symbol_Not_Value,
			node.name.span,
			"'%s' references a %T, which is not valid anywhere in an expression context",
			node.name.id,
			reflect.get_union_variant(resolved),
		)
		if name_span, ok := resolver.span_of_name(resolved); ok {
			diagnostics.reference(diag, name_span, "defined here")
		}
	}

	// no diagnostic message required for nil; was already emitted by resolve proc

	return hir.Expression(poison(ts, node.span))
}

_eval_callish_expr :: proc(
	ts: ^Translation_State,
	callish: ^ast.Callish_Expr,
	scope: resolver.Scope,
) -> hir.Expression {
	evaluated_callee := evaluate(ts, callish.callee, scope)

	switch callee in evaluated_callee {
	case Comptime_Value:
		diagnostics.emit(.Not_Callable, ast.span(callish.callee), "cannot call a %s", callee.type)
		return poison(ts, callish.span)
	case hir.Expression:
		if c, is_poison := callee.(^hir.Poison); is_poison {
			c.span = callish.span
			return c
		}
	case ^resolver.Import:
		diagnostics.emit(.Not_Callable, ast.span(callish.callee), "imports are not callable")
		return poison(ts, callish.span)
	}

	callee := evaluated_callee.(hir.Expression)
	type, _, ok := hir.type_and_unit(callee)

	if !ok {
		diagnostics.emit(
			.Expected_Single_Value,
			ast.span(callish.callee),
			"cannot call an expression that does not return a value",
		)
		return poison(ts, callish.span)
	}

	arg_exprs, args_ok := _arg_list(ts, callish.args, scope)
	if !args_ok {
		return poison(ts, callish.span)
	}

	#partial switch type in type {
	case ^hir.Func_Type:
		return _build_func_call(ts, callish.span, callee, type, arg_exprs)
	case hir.Primitive_Type:
		if comptime_known_type, ok := callee.(hir.Type); ok && type == .Type {
			if len(arg_exprs) != 1 {
				diagnostics.emit(
					.Call_Arity_Mismatch,
					callish.span,
					"call-style casts can only take one argument (this one got %d)",
					len(arg_exprs),
				)
				return poison(ts, callish.span)
			}
			if arg_exprs[0].name != nil {
				diagnostics.emit(
					.Named_Cast_Argument,
					arg_exprs[0].span,
					"call-style cast argument cannot be passed by name",
				)
				return poison(ts, callish.span)
			}
			arg: hir.Expression
			switch value in arg_exprs[0].value {
			case Comptime_Value:
				arg, ok = materialize_value(ts, value, arg_exprs[0].span)
				if !ok {
					return poison(ts, callish.span)
				}
			case hir.Expression:
				arg = value
			case ^resolver.Import:
				panic("unreachable")
			}
			_, unit, _ := hir.type_and_unit(arg)
			cast_expr := new(hir.Cast_Expr, ts.output.allocator)
			cast_expr^ = {
				span = callish.span,
				expr = arg,
				to   = comptime_known_type,
				type = comptime_known_type,
				unit = unit,
			}
			return cast_expr
		}
	}

	diagnostics.emit(.Not_Callable, ast.span(callish.callee), "cannot call a %s", type)
	return poison(ts, callish.span)
}

_type_and_unit :: proc(er: Eval_Result) -> (Comptime_Type, hir.Realized_Unit, bool) {
	switch er in er {
	case Comptime_Value:
		return er.type, er.unit, true
	case hir.Expression:
		return hir.type_and_unit(er)
	case ^resolver.Import:
	}

	return nil, nil, false
}

_eval_unary :: proc(
	ts: ^Translation_State,
	unary: ^ast.Unary_Expr,
	scope: resolver.Scope,
	type_hint: hir.Type = nil,
) -> Eval_Result {
	expr := evaluate(ts, unary.expr, scope)

	assert(expr != nil)
	if poison, is_poison := util.chain_extract(expr, hir.Expression, ^hir.Poison); is_poison {
		poison.span = unary.span
		return hir.Expression(poison)
	}

	type, unit, has_value := _type_and_unit(expr)

	if !has_value {
		diagnostics.emit(
			.Expected_Single_Value,
			ast.span(unary.expr),
			"this expression does not return a value",
		)
		return hir.Expression(poison(ts, unary.span))
	}

	op_compat := OP_CATEGORY_DEFS[_op_category_of(type)]
	if unary.op not_in op_compat.supported_unops {
		diag := diagnostics.emit(
			.Unop_Not_Defined,
			unary.span,
			"operator %s is not supported for type %s",
			common.UNARY_OP_STRINGS[unary.op],
			type,
		)
		if op_compat.unop_diagnostics != nil {
			op_compat.unop_diagnostics(diag, unary.op)
		}
		return hir.Expression(poison(ts, unary.span))
	}

	switch expr in expr {
	case Comptime_Value:
		return Comptime_Value {
			value = _comptime_unop(unary.op, expr.value, ts.output.allocator),
			type = type,
			unit = unit,
		}
	case hir.Expression:
		inferred_type, inferred := infer_type(type, unary.span)
		if !inferred {
			return hir.Expression(poison(ts, unary.span))
		}
		result := new(hir.Unary_Expr, ts.output.allocator)
		result^ = {
			span = unary.span,
			op   = unary.op,
			expr = expr,
			type = inferred_type,
			unit = unit,
		}
		return hir.Expression(result)
	case ^resolver.Import:
		diagnostics.emit(
			.Symbol_Not_Operand,
			unary.span,
			"this is an import, which is not a valid operand of unary %s",
			common.UNARY_OP_STRINGS[unary.op],
		)
		return hir.Expression(poison(ts, unary.span))
	}

	unreachable()
}

_primitive_zero :: proc(type: Comptime_Type) -> common.Primitive_Value {
	switch type in type {
	case Flexible_Type:
		switch type.affinity {
		case .Integer, .Unsigned_Integer, .Decimal, .Binary_Float, .Rational:
			return exact.RAT_ZERO
		case .Boolean:
			return false
		case .String:
			return ""
		case .Rune:
			return rune(0)
		case .Byte:
			return u8(0)
		case .Nil:
			return Untyped_Nil{}
		case .Any_Zero:
			return Untyped_Zero{}
		}
	case hir.Type:
		#partial switch concrete in type {
		case hir.Fixed_Decimal:
			return exact.RAT_ZERO
		case hir.Primitive_Type:
			switch concrete {
			case .Int,
			     .Int128,
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
			     .Bin16:
				return exact.RAT_ZERO
			case .Rune:
				return rune(0)
			case .Byte:
				return byte(0)
			case .Boolean:
				return false
			case .String:
				return ""

			case .Any:
				return Untyped_Nil{}
			case .Type:
				panic("_primitive_zero(...) should only be called with zeroable types")
			}
		case ^hir.Pointer_Type, ^hir.Optional_Type:
			return Untyped_Nil{}
		case:
			panic("_primitive_zero(...) should only be called with zeroable types")
		}
	}
	panic("_primitive_zero(...) should only be called with zeroable types")
}
