package analysis


import "base:runtime"
import "core:fmt"
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

Operator_Compat_Category :: enum {
	Empty,
	Integer,
	Rational,
	Bin_Float,
	Boolean,
	Ordered,
	Opaque,
	Enum,
}

Operator_Compat_Data :: struct {
	name:              string,
	supported_binops:  bit_set[common.Binary_Op],
	supported_unops:   bit_set[common.Unary_Op],
	binop_diagnostics: proc(_: ^diagnostics.Diagnostic, _: common.Binary_Op),
	unop_diagnostics:  proc(_: ^diagnostics.Diagnostic, _: common.Unary_Op),
}

@(rodata)
OP_CATEGORY_DEFS := [Operator_Compat_Category]Operator_Compat_Data {
	.Integer = {
		name = "integer",
		supported_binops = {
			.Add,
			.Subtract,
			.Multiply,
			.Floor_Divide,
			.Power,
			.Modulo,
			.Remainder,
			.Equal,
			.Not_Equal,
			.Less,
			.Less_Equal,
			.Greater,
			.Greater_Equal,
		},
		supported_unops = {.Positive, .Negate},
		binop_diagnostics = proc(diag: ^diagnostics.Diagnostic, op: common.Binary_Op) {
			#partial switch op {
			case .True_Divide:
				diagnostics.suggest(diag, "did you mean to use // ? (the floor division operator)")
			}
		},
	},
	.Rational = {
		name = "rational",
		supported_binops = {
			.Add,
			.Subtract,
			.Multiply,
			.True_Divide,
			.Floor_Divide,
			.Power,
			.Modulo,
			.Remainder,
			.Equal,
			.Not_Equal,
			.Less,
			.Less_Equal,
			.Greater,
			.Greater_Equal,
		},
		supported_unops = {.Positive, .Negate},
	},
	.Bin_Float = {
		name = "binary floating point",
		supported_binops = {
			.Add,
			.Subtract,
			.Multiply,
			.True_Divide,
			.Floor_Divide,
			.Power,
			.Modulo,
			.Remainder,
			.Less,
			.Less_Equal,
			.Greater,
			.Greater_Equal,
		},
		supported_unops = {.Positive, .Negate},
		binop_diagnostics = proc(diag: ^diagnostics.Diagnostic, op: common.Binary_Op) {
			#partial switch op {
			case .Equal, .Not_Equal:
				diagnostics.suggest(
					diag,
					"consider using an approximate equality function from intrinsics:float",
				)
			}
		},
	},
	.Ordered = {
		name = "ordered",
		supported_binops = {.Equal, .Not_Equal, .Less, .Less_Equal, .Greater, .Greater_Equal},
	},
	.Boolean = {
		name = "boolean",
		supported_binops = {.Equal, .Not_Equal, .And, .Or},
		supported_unops = {.Not},
	},
	.Enum = {name = "enum", supported_binops = {.Is, .Is_Not}},
	.Opaque = {name = "opaque", supported_binops = {.Equal, .Not_Equal}},
	.Empty = {name = "no-operator", supported_binops = {}},
}

_op_category_of :: proc(typ: Comptime_Type) -> Operator_Compat_Category {
	switch comptime_type in typ {
	case Flexible_Type:
		switch comptime_type.affinity {
		case .Boolean:
			return .Boolean
		case .String, .Rune:
			return .Ordered
		case .Integer, .Unsigned_Integer:
			return .Integer
		case .Decimal, .Rational:
			return .Rational
		case .Binary_Float:
			return .Bin_Float
		case .Byte:
			return .Opaque
		case .Nil, .Any_Zero:
			return .Opaque // maybe needs to be "unknown"?
		}

	case hir.Type:
		switch concrete in comptime_type {
		case ^hir.Distinct_Type:
			return _op_category_of(concrete.underlying)
		case ^hir.Tagged_Type:
			return _op_category_of(concrete.base)
		case ^hir.Enum_Type:
			return .Enum
		case ^hir.Struct_Type:
			return .Empty
		case ^hir.Fixed_Array_Type:
			return _op_category_of(concrete.elem)
		case hir.Fixed_Decimal:
			return .Rational
		case hir.Primitive_Type:
			switch concrete {
			case .Boolean:
				return .Boolean
			case .String, .Rune:
				return .Ordered
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
			     .UInt8:
				return .Integer
			case .Bin64, .Bin32, .Bin16:
				return .Bin_Float
			case .Byte, .Type:
				return .Opaque
			case .Any:
				return .Empty
			}
		case ^hir.Interface,
		     ^hir.Generic_Type,
		     ^hir.Dynamic_Array_Type,
		     ^hir.View_Type,
		     ^hir.Map_Type,
		     ^hir.Optional_Type,
		     ^hir.Pointer_Type,
		     ^hir.Func_Type:
			return .Opaque
		}
	}
	return .Opaque
}

_eval_binop :: proc(
	ts: ^Translation_State,
	binop: ^ast.Binop_Expr,
	scope: resolver.Scope,
	type_hint: hir.Type = nil,
) -> Eval_Result {
	lhs := evaluate(ts, binop.lhs, scope)
	rhs := evaluate(ts, binop.rhs, scope)
	assert(lhs != nil && rhs != nil)
	if poison, is_poison := util.chain_extract(lhs, hir.Expression, ^hir.Poison); is_poison {
		poison.span = binop.span
		return hir.Expression(poison)
	}
	if poison, is_poison := util.chain_extract(rhs, hir.Expression, ^hir.Poison); is_poison {
		poison.span = binop.span
		return hir.Expression(poison)
	}

	ltype, lunit, lok := _type_and_unit(lhs)
	rtype, runit, rok := _type_and_unit(rhs)

	if !lok {
		diagnostics.emit(
			.Expected_Single_Value,
			ast.expression_span(binop.lhs),
			"this expression does not return a value",
		)
		return hir.Expression(poison(ts, binop.span))
	}

	if !rok {
		diagnostics.emit(
			.Expected_Single_Value,
			ast.expression_span(binop.rhs),
			"this expression does not return a value",
		)
		return hir.Expression(poison(ts, binop.span))
	}

	if binop.op == .Multiply && is_boolean(ltype) {
		return _eval_boolean_multiply(ts, lhs, rhs, rtype, binop, binop.rhs)
	}

	if binop.op == .Multiply && is_boolean(rtype) {
		return _eval_boolean_multiply(ts, rhs, lhs, ltype, binop, binop.lhs)
	}

	calculation_hint := type_hint
	if calculation_hint != nil &&
	   binop.op not_in OP_CATEGORY_DEFS[_op_category_of(calculation_hint)].supported_binops {
		calculation_hint = nil
	}
	if binop.op == .Power {
		// FIXME: Propagate result context to the base without coercing the exponent.
		calculation_hint = nil
	}

	if dec_result, dec_ok := _try_decimal_binop(ts, binop.op, binop.span, lhs, rhs); dec_ok {
		return dec_result
	}

	coerced_type, coerce_ok := coerce(
		ltype,
		rtype,
		calculation_hint if binop.op in common.ARITHMETIC_BINOPS else nil,
	)
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
		return hir.Expression(poison(ts, binop.span))
	}

	if binop.op == .Add {
		if l, r, ok := util.extract_pair(lhs, rhs, Comptime_Value); ok {
			if lstr, rstr, str_ok := util.extract_pair(l.value, r.value, string); str_ok {
				return Comptime_Value {
					value = strings.concatenate({lstr, rstr}, ts.allocator),
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
		return hir.Expression(poison(ts, binop.span))
	}

	res_unit, u_lhs, u_rhs, unit_ok := _eval_binop_unit(ts, binop, lhs, lunit, rhs, runit)
	if !unit_ok {
		return hir.Expression(poison(ts, binop.span))
	}

	if l, r, ok := util.extract_pair(u_lhs, u_rhs, Comptime_Value); ok {
		result_type := coerced_type
		if binop.op not_in common.ARITHMETIC_BINOPS {
			result_type = resolver.Flexible_Type {
				affinity = .Boolean,
			}
		} else if _, _, both_flex := util.extract_pair(l.type, r.type, resolver.Flexible_Type);
		   both_flex {
			if binop.op == .True_Divide {
				result_type = resolver.Flexible_Type {
					affinity = .Rational,
				}
			} else if binop.op == .Floor_Divide {
				result_type = resolver.Flexible_Type {
					affinity = .Integer,
				}
			}
		}

		return Comptime_Value {
			value = _comptime_binop(binop.op, l.value, r.value, ts.output.allocator),
			type = result_type,
			unit = res_unit if binop.op in common.ARITHMETIC_BINOPS else hir.Indeterminate_Unit.No_Unit,
		}
	}

	l: hir.Expression
	l_ok := true
	switch value in u_lhs {
	case Comptime_Value:
		l, l_ok = materialize_value(
			ts,
			value,
			ast.expression_span(binop.lhs),
			coerced_type.(hir.Type) or_else nil,
		)
	case hir.Expression:
		l = value
	case ^resolver.Import:
		diagnostics.emit(
			.Symbol_Not_Operand,
			binop.span,
			"this is an import, which is not a valid operand of %s",
			common.BINARY_OP_STRINGS[binop.op],
		)
		return hir.Expression(poison(ts, binop.span))
	}
	r: hir.Expression
	r_ok := true
	switch value in u_rhs {
	case Comptime_Value:
		r, r_ok = materialize_value(
			ts,
			value,
			ast.expression_span(binop.rhs),
			coerced_type.(hir.Type) or_else nil,
		)
	case hir.Expression:
		r = value
	case ^resolver.Import:
		diagnostics.emit(
			.Symbol_Not_Operand,
			binop.span,
			"this is an import, which is not a valid operand of %s",
			common.BINARY_OP_STRINGS[binop.op],
		)
		return hir.Expression(poison(ts, binop.span))
	}
	if !l_ok || !r_ok {
		return hir.Expression(poison(ts, binop.span))
	}

	inferred_type, inferred := infer_type(coerced_type, binop.span)
	if !inferred {
		return hir.Expression(poison(ts, binop.span))
	}

	if _, flexible := ltype.(Flexible_Type); !flexible && ltype != coerced_type {
		_, unit, has_value := hir.type_and_unit(l)
		assert(has_value)
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
		_, unit, has_value := hir.type_and_unit(r)
		assert(has_value)
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
		type = inferred_type if binop.op in common.ARITHMETIC_BINOPS else .Boolean,
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
			.Nonzeroable_Operand,
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
			_, unit, has_value := _type_and_unit(nonbool)
			assert(has_value)
			return Comptime_Value {
				value = _primitive_zero(nonbool_type),
				type = nonbool_type,
				unit = unit,
			}
		}

	case hir.Expression:
		if known, ok := nonbool.(Comptime_Value); ok {
			if_true, mat_ok := materialize_value(ts, known, ast.expression_span(nonbool_ast))
			if !mat_ok {
				return nil
			}
			typ, unit, has_value := hir.type_and_unit(if_true)
			assert(has_value)
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
			typ, unit, has_value := hir.type_and_unit(nonbool_expr)
			assert(has_value)
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
	case ^resolver.Import:
		diagnostics.emit(
			.Symbol_Not_Operand,
			ast.expression_span(nonbool_ast),
			"imports cannot participate in boolean multiplication",
			common.BINARY_OP_STRINGS[binop.op],
		)
		return hir.Expression(poison(ts, binop.span))
	}

	unreachable()
}

_try_decimal_binop :: proc(
	ts: ^Translation_State,
	op: common.Binary_Op,
	span: common.Span,
	lhs, rhs: Eval_Result,
) -> (
	Eval_Result,
	bool,
) {
	return nil, false // TODO
}

_comptime_unop :: proc(
	op: common.Unary_Op,
	value: common.Primitive_Value,
	allocator: runtime.Allocator,
) -> common.Primitive_Value {
	switch op {
	case .Positive:
		return exact.clone(value.(exact.Rat), allocator)
	case .Negate:
		return exact.negate(value.(exact.Rat), allocator)
	case .Not:
		return !value.(bool)
	}

	fmt.panicf(
		"missing implementation of %s %T",
		common.UNARY_OP_STRINGS[op],
		reflect.get_union_variant(value),
	)
}

_comptime_binop :: proc(
	op: common.Binary_Op,
	lhs, rhs: common.Primitive_Value,
	allocator: runtime.Allocator,
) -> common.Primitive_Value {
	switch op {
	case .Add:
		return exact.add(lhs.(exact.Rat), rhs.(exact.Rat), allocator)
	case .Subtract:
		return exact.sub(lhs.(exact.Rat), rhs.(exact.Rat), allocator)
	case .Multiply:
		return exact.mul(lhs.(exact.Rat), rhs.(exact.Rat), allocator)
	case .True_Divide:
		return exact.div(lhs.(exact.Rat), rhs.(exact.Rat), allocator)
	case .Floor_Divide:
		return exact.floordiv(lhs.(exact.Rat), rhs.(exact.Rat), allocator)
	case .Remainder:
		return exact.rem(lhs.(exact.Rat), rhs.(exact.Rat), allocator)
	case .Modulo:
		return exact.mod(lhs.(exact.Rat), rhs.(exact.Rat), allocator)
	case .Power:
		r := rhs.(exact.Rat)
		if exact.is_one(r.denominator) &&
		   r.numerator.(i128) >= -i128(max(int)) &&
		   r.numerator.(i128) <= i128(max(int)) {
			return exact.pow(lhs.(exact.Rat), int(r.numerator.(i128)), allocator)
		} else {
			fmt.panicf(
				"%T %s %T is only supported for integer exponents in 64-bit signed integer range",
				reflect.get_union_variant(lhs),
				common.BINARY_OP_STRINGS[op],
				reflect.get_union_variant(rhs),
			)
		}
	case .Equal:
		return _comptime_equal(lhs, rhs)
	case .Not_Equal:
		return !_comptime_equal(lhs, rhs)
	case .Less:
		return _comptime_less(lhs, rhs)
	case .Less_Equal:
		return !_comptime_less(rhs, lhs)
	case .Greater:
		return _comptime_less(rhs, lhs)
	case .Greater_Equal:
		return !_comptime_less(lhs, rhs)
	case .Is:
	case .Is_Not:
	case .And:
		return lhs.(bool) && rhs.(bool)
	case .Or:
		return lhs.(bool) || rhs.(bool)
	}

	fmt.panicf(
		"missing implementation of %T %s %T",
		reflect.get_union_variant(lhs),
		common.BINARY_OP_STRINGS[op],
		reflect.get_union_variant(rhs),
	)
}

_comptime_equal :: proc(lhs, rhs: common.Primitive_Value) -> bool {
	switch l in lhs {
	case exact.Rat:
		return exact.eq(l, rhs.(exact.Rat))
	case string:
		return l == rhs.(string)
	case rune:
		return l == rhs.(rune)
	case byte:
		return l == rhs.(byte)
	case bool:
		return l == rhs.(bool)
	case Untyped_Nil, Untyped_Zero:
		panic("untyped values should have already been coerced")
	}
	return false
}

_comptime_less :: proc(lhs, rhs: common.Primitive_Value) -> bool {
	switch l in lhs {
	case exact.Rat:
		return exact.lt(l, rhs.(exact.Rat))
	case string:
		return strings.compare(l, rhs.(string)) < 0
	case rune:
		return l < rhs.(rune)
	case byte:
		return l < rhs.(byte)
	case bool, Untyped_Nil, Untyped_Zero:
		panic("value does not support ordering")
	}
	return false
}
