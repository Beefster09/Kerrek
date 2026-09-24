package analysis

import "base:runtime"
import "core:reflect"
import "core:slice"
import "core:strings"

import "../../common"
import "../../common/exact"
import "../../util"
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

materialize :: proc(
	ts: ^Translation_State,
	value: Comptime_Value,
	span: common.Span,
) -> (
	hir.Expression,
	bool,
) {
	real_type, ok := infer_type(value.type, span)
	if !ok {
		return nil, false
	}

	real_value: hir.Value
	switch v in value.value {
	case Untyped_Value:
		switch v {
		case .Nil:
			real_value = hir.Nil_Of {
				type = real_type,
			}
		case .Zero:
			real_value = hir.Zero_Of {
				type = real_type,
			}
		}
	case exact.Rat:
		real_value = v
	case string:
		real_value = v
	case rune:
		real_value = v
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

INT64_DECIMAL_DIGITS :: 18

infer_type :: proc(
	evaluated_type: Comptime_Type,
	diagnostic_span: common.Span,
) -> (
	hir.Type,
	bool,
) {
	switch typ in evaluated_type {
	case Flexible_Type:
		switch typ.affinity {
		case .Integer:
			return hir.Primitive_Type.Int64, true
		case .Unsigned_Integer:
			return hir.Primitive_Type.UInt64, true
		case .Decimal:
			dec := hir.Fixed_Decimal{max(INT64_DECIMAL_DIGITS, typ.digits), typ.scale}
			if dec.digits > INT64_DECIMAL_DIGITS {
				diagnostics.emit(
					.Large_Decimal,
					diagnostic_span,
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
		case .Rational, .Contextual:
			diagnostics.emit(
				.Inference_Failed,
				diagnostic_span,
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
) -> (
	hir.Expression,
	bool,
) {
	switch result in evaluate(ts, expr, scope) {
	case Comptime_Value:
		return materialize(ts, result, ast.span(expr))
	case hir.Expression:
		return result, true
	}

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
		case Untyped_Value:
			return Comptime_Value {
				value = value,
				type = Flexible_Type{affinity = .Contextual},
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
		if unit, ok := get_canonical_unit(ts, node.unit, scope); ok {
			out_unit = unit
		} else {
			out_unit = .No_Unit
		}

		return Comptime_Value {
			value = node.value,
			type = Flexible_Type{affinity = affinity, digits = node.digits, scale = node.scale},
			unit = out_unit,
		}

	case ^ast.Binop_Expr:
		return _eval_binop(ts, node, scope)

	case ^ast.Name_Expr:
		var_expr :: #force_inline proc(
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

		#partial switch resolved in resolve(ts, scope, node.name) {
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

		case nil:
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
		switch unit in node.new_unit {
		case ^ast.No_Unit:
			new_unit = hir.Indeterminate_Unit.No_Unit
		case ^ast.Flexible_Unit:
			diagnostics.emit(.TBD, unit.span, "cannot reinterpret units as flexible")
		case ^ast.Inferred_Unit:
			// might be a panic("unreachable")
			diagnostics.emit(
				.TBD,
				node.span,
				"inferred units are not valid for unit reinterpret expressions",
			)
		case ^ast.Compound_Unit:
			new_unit = get_canonical_unit(ts, unit, scope) or_else nil
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
					"this expression evaluates to %d values, but exactly 1 is expected in this context",
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

_singular_type_and_unit :: proc(er: Eval_Result) -> (Comptime_Type, hir.Realized_Unit, bool) {
	switch er in er {
	case Comptime_Value:
		return er.type, er.unit, true
	case hir.Expression:
		return hir.singular_type_and_unit(er)
	}

	return nil, nil, false
}

_eval_binop :: proc(
	ts: ^Translation_State,
	binop: ^ast.Binop_Expr,
	scope: resolver.Scope,
) -> Eval_Result {
	lhs := evaluate(ts, binop.lhs, scope)
	rhs := evaluate(ts, binop.rhs, scope)
	if lhs == nil || rhs == nil {
		return nil
	}

	ltype, lunit, lok := _singular_type_and_unit(lhs)
	rtype, runit, rok := _singular_type_and_unit(rhs)

	if !lok {
		diagnostics.emit(
			.Arity_Mismatch,
			ast.expression_span(binop.lhs),
			"this expression does not return exactly one value",
		)
		return nil
	}

	if !rok {
		diagnostics.emit(
			.Arity_Mismatch,
			ast.expression_span(binop.rhs),
			"this expression does not return exactly one value",
		)
		return nil
	}

	if binop.op == .Multiply && is_boolean(ltype) {
		return _eval_boolean_multiply(ts, lhs, rhs, rtype, binop, binop.rhs)
	}

	if binop.op == .Multiply && is_boolean(rtype) {
		return _eval_boolean_multiply(ts, rhs, lhs, ltype, binop, binop.lhs)
	}

	coerced_type, coerce_ok := _coerce(ts, ltype, rtype)
	if !coerce_ok {
		diagnostics.emit(
			.Binop_Not_Defined,
			binop.span,
			"operator %s is not supported for types %s and %s" +
			" and no implicit conversion between them exists",
			common.BINARY_OP_STRINGS[binop.op],
			ltype,
			rtype,
		)
		return nil
	}

	if binop.op == .Add {
		if l, r, ok := util.extract_pair(lhs, rhs, Comptime_Value); ok {
			if lstr, rstr, str_ok := util.extract_pair(l.value, r.value, string); str_ok {
				return Comptime_Value {
					value = strings.concatenate({lstr, rstr}, ts.output.allocator),
					type = coerced_type,
					unit = hir.Indeterminate_Unit.No_Unit,
				}
			}
		}
	}

	op_compat := OP_CATEGORY_DEFS[_op_category_of(coerced_type)]
	if binop.op not_in op_compat.supported_binops {
		diag := diagnostics.emit(
			.Binop_Not_Defined,
			binop.span,
			"operator %s is not supported for type %s",
			common.BINARY_OP_STRINGS[binop.op],
			coerced_type,
		)
		if op_compat.binop_diagnostics != nil {
			op_compat.binop_diagnostics(diag, binop.op)
		}
		return nil
	}

	res_unit, u_lhs, u_rhs, unit_ok := _eval_binop_unit(ts, binop, lhs, lunit, rhs, runit)
	if !unit_ok {
		return nil
	}

	if l, l_ok := u_lhs.(Comptime_Value); l_ok {
		if r, r_ok := u_rhs.(Comptime_Value); r_ok {
			return Comptime_Value {
				value = _comptime_binop(binop.op, l.value, r.value),
				type = coerced_type,
				unit = res_unit,
			}
		}
	}

	l: hir.Expression
	l_ok := true
	switch value in u_lhs {
	case Comptime_Value:
		l, l_ok = materialize(ts, value, ast.expression_span(binop.lhs))
	case hir.Expression:
		l = value
	}
	r: hir.Expression
	r_ok := true
	switch value in u_rhs {
	case Comptime_Value:
		r, r_ok = materialize(ts, value, ast.expression_span(binop.rhs))
	case hir.Expression:
		r = value
	}
	if !l_ok || !r_ok {
		return nil
	}

	inferred_type, inferred := infer_type(coerced_type, binop.span)
	if !inferred {
		return nil
	}

	if _, flexible := ltype.(Flexible_Type); !flexible && ltype != coerced_type {
		_, unit, singular := hir.singular_type_and_unit(l)
		assert(singular)
		cast_expr := new(hir.Cast_Expr, ts.output.allocator)
		cast_expr^ = {
			span = ast.expression_span(binop.lhs),
			type = inferred_type,
			to   = inferred_type,
			unit = unit,
			expr = l,
		}
		l = cast_expr
	}

	if _, flexible := rtype.(Flexible_Type); !flexible && rtype != coerced_type {
		_, unit, singular := hir.singular_type_and_unit(r)
		assert(singular)
		cast_expr := new(hir.Cast_Expr, ts.output.allocator)
		cast_expr^ = {
			span = ast.expression_span(binop.rhs),
			type = inferred_type,
			to   = inferred_type,
			unit = unit,
			expr = r,
		}
		r = cast_expr
	}

	result := new(hir.Binop_Expr, ts.output.allocator)
	result^ = {
		span = binop.span,
		op   = binop.op,
		lhs  = l,
		rhs  = r,
		type = inferred_type,
		unit = res_unit,
	}
	return hir.Expression(result)
}

_eval_boolean_multiply :: proc(
	ts: ^Translation_State,
	boolval: Eval_Result,
	nonbool: Eval_Result,
	nonbool_type: Comptime_Type,
	binop: ^ast.Binop_Expr,
	nonbool_ast: ast.Expression,
) -> Eval_Result {
	if !is_zeroable(nonbool_type) {
		diagnostics.emit(
			.TBD,
			binop.span,
			"cannot multiply Boolean and %v because %v does not have a well-defined zero value",
			nonbool_type,
			nonbool_type,
		)
		return nil
	}

	switch boolean in boolval {
	case Comptime_Value:
		value := boolean.value.(bool)
		if value {
			return nonbool
		} else {
			_, unit, singular := _singular_type_and_unit(nonbool)
			assert(singular)
			return Comptime_Value{value = zero_of(nonbool_type), type = nonbool_type, unit = unit}
		}

	case hir.Expression:
		if known, ok := nonbool.(Comptime_Value); ok {
			if_true, mat_ok := materialize(ts, known, ast.expression_span(nonbool_ast))
			if !mat_ok {
				return nil
			}
			typ, unit, singular := hir.singular_type_and_unit(if_true)
			assert(singular)
			if_false := new(hir.Const_Expr, ts.output.allocator)
			if_false^ = {
				span = ast.expression_span(nonbool_ast),
				value = hir.Zero_Of{type = typ},
				type = typ,
				unit = unit,
			}
			result := new(hir.Condition_Expr, ts.output.allocator)
			result^ = {
				span      = binop.span,
				condition = boolean,
				if_true   = if_true,
				if_false  = if_false,
				type      = typ,
				unit      = unit,
			}
			return hir.Expression(result)

		} else {
			nonbool_expr := nonbool.(hir.Expression)
			typ, unit, singular := hir.singular_type_and_unit(nonbool_expr)
			assert(singular)
			if_false := new(hir.Const_Expr, ts.output.allocator)
			if_false^ = {
				span = ast.expression_span(nonbool_ast),
				value = hir.Zero_Of{type = typ},
				type = typ,
				unit = unit,
			}
			result := new(hir.Condition_Expr, ts.output.allocator)
			result^ = {
				span      = binop.span,
				condition = boolean,
				if_true   = nonbool_expr,
				if_false  = if_false,
				type      = typ,
				unit      = unit,
			}
			return hir.Expression(result)
		}
	}

	panic("unreachable")
}

zero_of :: proc(typ: Comptime_Type) -> common.Value {
	switch comptime_type in typ {
	case Flexible_Type:
		switch comptime_type.affinity {
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
		case .Contextual:
			panic("zero_of(...) should only be called with zeroable types")
		}
	case hir.Type:
		#partial switch concrete in comptime_type {
		case hir.Fixed_Decimal:
			return exact.RAT_ZERO
		case hir.Primitive_Type:
			switch concrete {
			case .Int128,
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

			case .Any, .Opaque, .Opaque8, .Opaque16, .Opaque32, .Opaque64:
				panic("zero_of(...) should only be called with zeroable types")
			}
		case ^hir.Pointer_Type, ^hir.Optional_Type:
			return Untyped_Value.Nil
		case:
			panic("zero_of(...) should only be called with zeroable types")
		}
	}
	panic("zero_of(...) should only be called with zeroable types")
}

_eval_binop_unit :: proc(
	ts: ^Translation_State,
	binop: ^ast.Binop_Expr,
	lhs: Eval_Result,
	lunit: hir.Realized_Unit,
	rhs: Eval_Result,
	runit: hir.Realized_Unit,
) -> (
	result_unit: hir.Realized_Unit,
	result_lhs: Eval_Result,
	result_rhs: Eval_Result,
	all_ok: bool,
) {
	_maybe_convert_rhs :: proc(
		ts: ^Translation_State,
		binop: ^ast.Binop_Expr,
		rhs: Eval_Result,
		rmult: exact.Rat,
	) -> (
		Eval_Result,
		bool,
	) {
		if exact.is_one(rmult) || rhs == nil {
			return rhs, true
		}

		value := rhs
		if comptime, ok := value.(Comptime_Value); ok {
			materialized, mat_ok := materialize(ts, comptime, ast.expression_span(binop.rhs))
			if !mat_ok {
				return nil, false
			}
			value = materialized
		}

		type, unit, is_single := _singular_type_and_unit(value)
		if !is_single {
			return nil, false
		}
		realized_type, rt_ok := type.(hir.Type)
		if !rt_ok {
			return nil, false
		}

		expr := new(hir.Unit_Conversion_Expr, ts.output.allocator)
		expr^ = {
			span   = ast.expression_span(binop.rhs),
			expr   = value.(hir.Expression),
			type   = realized_type,
			unit   = unit,
			factor = rmult,
		}
		return hir.Expression(expr), true
	}

	if lhs == nil || rhs == nil {
		return
	}

	if _is_no_unit(lunit) && _is_no_unit(runit) {
		return hir.Indeterminate_Unit.No_Unit, lhs, rhs, true
	}

	switch binop.op {
	case .And, .Or:
		return hir.Indeterminate_Unit.No_Unit, lhs, rhs, true

	case .Equal, .Not_Equal, .Less, .Greater, .Less_Equal, .Greater_Equal, .Is, .Is_Not:
		_, rmult, coerced := _coerce_units(lunit, runit)
		if !coerced {
			diagnostics.emit(
				.Invalid_Unit,
				binop.span,
				"units (%v) and (%v) do not match and do not have any known conversions",
				lunit,
				runit,
			)
		}
		converted_rhs, ok := _maybe_convert_rhs(ts, binop, rhs, rmult)
		return hir.Indeterminate_Unit.No_Unit, lhs, converted_rhs, ok

	case .Add, .Subtract, .Remainder, .Modulo:
		coerced_unit, rmult, coerced := _coerce_units(lunit, runit)
		if !coerced {
			diagnostics.emit(
				.Invalid_Unit,
				binop.span,
				"units (%v) and (%v) do not match and do not have any known conversions",
				lunit,
				runit,
			)
			return
		}
		converted_rhs, ok := _maybe_convert_rhs(ts, binop, rhs, rmult)
		return coerced_unit, lhs, converted_rhs, ok

	case .Multiply:
		lcanonical, l_has_unit := lunit.(units.Compound_Unit)
		rcanonical, r_has_unit := runit.(units.Compound_Unit)
		if l_has_unit && r_has_unit {
			context.allocator = ts.allocator
			unit, err := units.combine_units(lcanonical, units.RAT_ONE, rcanonical, units.RAT_ONE)
			if err != .OK {
				return
			}
			return unit, lhs, rhs, true
		} else if l_has_unit && _unit_is_flexible(runit) {
			return lunit, lhs, rhs, true
		} else if r_has_unit && _unit_is_flexible(lunit) {
			return runit, lhs, rhs, true
		} else if _unit_is_flexible(lunit) && _unit_is_flexible(runit) {
			return hir.Indeterminate_Unit.Flexible, lhs, rhs, true
		} else if (_is_no_unit(lunit) || _unit_is_flexible(lunit)) &&
		   (_is_no_unit(runit) || _unit_is_flexible(runit)) {
			return hir.Indeterminate_Unit.No_Unit, lhs, rhs, true
		}
		diagnostics.emit(
			.Invalid_Unit,
			binop.span,
			"you cannot multiply a unitless value with a value with units (|%v| %s |%v|)",
			lunit,
			common.BINARY_OP_STRINGS[binop.op],
			runit,
		)
		return

	case .True_Divide, .Floor_Divide:
		lcanonical, l_has_unit := lunit.(units.Compound_Unit)
		rcanonical, r_has_unit := runit.(units.Compound_Unit)
		if l_has_unit && r_has_unit {
			context.allocator = ts.allocator
			unit, err := units.combine_units(
				lcanonical,
				units.RAT_ONE,
				rcanonical,
				units.Small_Rat{n = -1},
			)
			if err != .OK {
				return
			}
			return unit, lhs, rhs, true
		} else if l_has_unit && _unit_is_flexible(runit) {
			return lunit, lhs, rhs, true
		} else if r_has_unit && _unit_is_flexible(lunit) {
			context.allocator = ts.allocator
			unit, err := units.combine_units(
				rcanonical,
				units.Small_Rat{n = -1},
				units.Inline_Compound_Unit{},
				units.RAT_ONE,
			)
			if err != .OK {
				return
			}
			return unit, lhs, rhs, true
		} else if _unit_is_flexible(lunit) && _unit_is_flexible(runit) {
			return hir.Indeterminate_Unit.Flexible, lhs, rhs, true
		} else if (_is_no_unit(lunit) || _unit_is_flexible(lunit)) &&
		   (_is_no_unit(runit) || _unit_is_flexible(runit)) {
			return hir.Indeterminate_Unit.No_Unit, lhs, rhs, true
		}
		diagnostics.emit(
			.Invalid_Unit,
			binop.span,
			"you cannot divide a unitless value by a value with units or vice-versa (|%v| %s |%v|)",
			lunit,
			common.BINARY_OP_STRINGS[binop.op],
			runit,
		)
		return

	case .Power:
		if canonical, is_canonical := lunit.(units.Compound_Unit);
		   is_canonical && units.num_components(canonical) > 0 {
			if exponent, known := rhs.(Comptime_Value); known {
				if exponent_value, numeric := exponent.value.(exact.Rat); numeric {
					rhs_is_unitless := _is_no_unit(runit) || _unit_is_flexible(runit)
					if rhs_unit, rhs_canonical := runit.(units.Compound_Unit); rhs_canonical {
						rhs_is_unitless = units.num_components(rhs_unit) == 0
					}
					if rhs_is_unitless {
						if exponent_units, representable := units.rat_from_exact(exponent_value);
						   representable && exponent_units.d == 0 {
							context.allocator = ts.allocator
							unit, err := units.combine_units(
								canonical,
								exponent_units,
								units.Inline_Compound_Unit{},
								units.RAT_ONE,
							)
							if err == .OK {
								return unit, lhs, rhs, true
							}
						} else {
							diagnostics.emit(
								.Invalid_Unit,
								ast.expression_span(binop.rhs),
								"fractional exponents are not currently supported for values with units",
							)
							return
						}
					}
				}
			}
			diagnostics.emit(
				.Invalid_Unit,
				ast.expression_span(binop.rhs),
				"exponents of unit expressions must be statically known unitless integers",
			)
			return
		}

		if rhs_unit, rhs_canonical := runit.(units.Compound_Unit);
		   rhs_canonical && units.num_components(rhs_unit) > 0 {
			diagnostics.emit(
				.Invalid_Unit,
				ast.expression_span(binop.rhs),
				"exponents must be unitless or ratios",
			)
			return
		}
		return lunit, lhs, rhs, true
	}

	panic("missing branch for binary operator")
}

_coerce_units :: proc(
	lhs: hir.Realized_Unit,
	rhs: hir.Realized_Unit,
) -> (
	hir.Realized_Unit,
	exact.Rat,
	bool,
) {
	if _unit_is_flexible(lhs) {
		return rhs, exact.RAT_ONE, true
	} else if _unit_is_flexible(rhs) {
		return lhs, exact.RAT_ONE, true
	}

	if _units_equal(lhs, rhs) {
		return lhs, exact.RAT_ONE, true
	}

	// TODO: find conversion from one to the other

	return nil, {}, false
}
