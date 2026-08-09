from __future__ import annotations

import math
import operator
from dataclasses import dataclass
from decimal import Decimal
from enum import Enum, auto
from fractions import Fraction
from typing import Literal

from frontend import ast, diagnostics
from frontend.lexer import NumberLiteralForm
from frontend.resolver import (
    AnyType,
    CanonicalUnit,
    Constant,
    DistinctType,
    FixedDecimal,
    PrimitiveType,
    StaticArrayType,
    Unit,
    Variable,
)

type Num = int | float | Decimal | Fraction


@dataclass
class ScalarValue:
    value: Num
    unit: CanonicalUnit | None
    absolute: bool = False

    def __bool__(self) -> bool:
        return bool(self.value)


class FlexAffinity(Enum):
    Nil = auto()
    UInt = auto()
    Integer = auto()
    Float = auto()
    Decimal = auto()
    Boolean = auto()
    String = auto()
    Rune = auto()


@dataclass
class FlexType:
    affinity: FlexAffinity


class TypeKind(Enum):
    """defines the group of mutual convertability of types"""

    Numeric = (
        auto()
    )  # Numeric types + Rune and Byte and all distinct types backed by them
    String = auto()
    Boolean = auto()


@dataclass
class FixedArrayKind:
    shape: tuple[int, ...]
    inner_kind: ConversionClass


class _Unconv:
    def __eq__(self, other):
        return False


Unconvertable = _Unconv()

type ConversionClass = TypeKind | FixedArrayKind | _Unconv


type ComptimeValue = (
    ScalarValue | ast.RuneValue | str | bool | None | ast.ConstantFolding
)
type ComptimeType = (
    AnyType | FlexType | Literal[ast.TypeState.Impossible, ast.TypeState.Failed]
)
type RealizedType = AnyType | Literal[ast.TypeState.Impossible, ast.TypeState.Failed]
type ExprResult = tuple[ComptimeValue, ComptimeType]


def _ensure_const_evaluated(const_sym: Constant) -> ExprResult:
    const_def = const_sym.definition
    if const_def.expr.folded_value is ast.ConstantFolding.NotEvaluated:
        val, typ = evaluate(const_def.expr)
        if const_def.type is not None:
            typ = check_type(const_def.type, typ, const_def)

        return val, typ

    return const_def.expr.folded_value, const_def.expr.result_type


def _ensure_type_inferred(var: Variable) -> RealizedType:
    if isinstance(var.definition, ast.FormalParameter):
        assert var.definition.type.canonical, (
            f"parameter type should have been evaluated by now: {var.definition}"
        )
        return var.definition.type.canonical

    if var.definition.realized_type is None and isinstance(
        var.definition.expr, ast.Expression
    ):
        _, typ = evaluate(var.definition.expr)

        if var.definition.type is None:
            typ = infer_type(typ, var.definition)
            var.definition.realized_type = typ
        else:
            typ = check_type(var.definition.type, typ, var.definition)
            assert not isinstance(typ, FlexType)
            var.definition.realized_type = typ

    assert var.definition.realized_type, (
        f"variable type should have been evaluated by now: {var.definition}"
    )
    return var.definition.realized_type or ast.TypeState.Failed


def evaluate(node: ast.Expression) -> ExprResult:
    if node.folded_value is not ast.ConstantFolding.NotEvaluated:
        return node.folded_value

    try:
        value, typ = _evaluate(node)
    except Exception as err:
        import traceback

        traceback.print_exc()
        diagnostics.error(f"constant evaluation failed: {err}", node)
        value = ast.ConstantFolding.Failed
        typ = ast.TypeState.Failed
    else:
        if typ in (ast.TypeState.Failed, ast.TypeState.Impossible):
            if value is not ast.ConstantFolding.Failed:
                diagnostics.error(f"type evaluation resolved to .{typ.name} here", node)
            value = ast.ConstantFolding.Failed

    node.folded_value = value
    node.result_type = typ
    return value, typ


def _evaluate(node: ast.Expression) -> ExprResult:
    match node:
        case ast.SimpleLiteralExpr():
            match node.value:
                case str():
                    return node.value, FlexType(FlexAffinity.String)
                case ast.RuneValue():
                    return node.value, FlexType(FlexAffinity.Rune)
                case bool():
                    return node.value, FlexType(FlexAffinity.Boolean)
                case None:
                    return node.value, FlexType(FlexAffinity.Nil)

        case ast.ScalarLiteralExpr():
            match node.value.form:
                case NumberLiteralForm.DecimalInteger:
                    typ = FlexType(FlexAffinity.Integer)
                case NumberLiteralForm.Decimal:
                    typ = FlexType(FlexAffinity.Decimal)
                case NumberLiteralForm.Float | NumberLiteralForm.HexFloat:
                    typ = FlexType(FlexAffinity.Float)
                case (
                    NumberLiteralForm.Hex
                    | NumberLiteralForm.Octal
                    | NumberLiteralForm.Binary
                ):
                    typ = FlexType(FlexAffinity.UInt)

            return ScalarValue(
                node.value.value, node.unit.canonical if node.unit else None
            ), typ

        case ast.BinopExpr():
            return _eval_binop(node)

        case ast.QualnameExpr():
            resolved = node.name.resolves_to
            if isinstance(resolved, Constant):
                return _ensure_const_evaluated(resolved)
            elif isinstance(resolved, Variable):
                return ast.ConstantFolding.RuntimeValue, _ensure_type_inferred(resolved)
            elif isinstance(resolved, Unit):
                if isinstance(resolved.definition, ast.UnitAlias):
                    return ScalarValue(1, resolved.definition.base.canonical), FlexType(
                        FlexAffinity.Integer
                    )
                else:
                    return ScalarValue(1, CanonicalUnit([resolved.id])), FlexType(
                        FlexAffinity.Integer
                    )

            diagnostics.error(
                f"qualname expression references unexpected symbol: {resolved}", node
            )
            return (
                ast.ConstantFolding.RuntimeValue,
                ast.TypeState.Impossible,
            )  # TODO: do something more sensible here

        case ast.CastExpr():
            assert node.to.canonical, "this should have been set by now"
            val, typ = evaluate(node.expr)

            if not _cast_allowed(node.to.canonical, typ):
                diagnostics.error(
                    f"{typ} is not convertible to {node.to.canonical}", node
                )

            return ast.ConstantFolding.RuntimeValue, node.to.canonical

        case _:
            raise NotImplementedError(
                f"no evaluation implemented for {type(node).__qualname__}"
            )


def infer_type(
    evaluated_type: ComptimeType,
    context: ast.Node,
) -> RealizedType:
    match evaluated_type:
        case FlexType(FlexAffinity.Integer):
            return PrimitiveType.Integer
        case FlexType(FlexAffinity.UInt):
            return PrimitiveType.UInt64
        case FlexType(FlexAffinity.Decimal):
            return PrimitiveType.Decimal
        case FlexType(FlexAffinity.Float):
            return PrimitiveType.Float64
        case FlexType(FlexAffinity.Boolean):
            return PrimitiveType.Boolean
        case FlexType(FlexAffinity.String):
            return PrimitiveType.String
        case FlexType(FlexAffinity.Rune):
            return PrimitiveType.Rune
        case FlexType(FlexAffinity.Nil):
            diagnostics.error("cannot infer type of nil", context)
            return ast.TypeState.Impossible
        case FlexType(affinity):
            raise NotImplementedError(f"missing a case for {affinity}")
        case _:
            return evaluated_type


def check_type(
    dest_type: ast.TypeExpression,
    evaluated_type: ComptimeType,
    context: ast.Node,
) -> ComptimeType:

    assert not isinstance(dest_type.canonical, ast.TypeState), (
        f"the dest type of {context} should have been evaluated by now"
    )

    if evaluated_type == dest_type.canonical:
        return evaluated_type

    return dest_type.canonical


def remainder(lhs, rhs):
    if isinstance(lhs, int):
        return lhs % rhs
    else:
        return lhs - (math.floor(lhs / rhs) * rhs)


def modulo(lhs, rhs):
    rem = remainder(lhs, rhs)

    if rem >= 0:
        return rem
    else:
        return rhs + rem


BINOP_FUNCS = {
    ast.BinaryOp.Add: operator.add,
    ast.BinaryOp.Subtract: operator.sub,
    ast.BinaryOp.Multiply: operator.mul,
    ast.BinaryOp.Divide: operator.truediv,
    ast.BinaryOp.FloorDivide: operator.floordiv,
    ast.BinaryOp.Power: operator.pow,
    ast.BinaryOp.Modulo: modulo,
    ast.BinaryOp.Remainder: remainder,
    ast.BinaryOp.Equal: operator.eq,
    ast.BinaryOp.NotEqual: operator.ne,
    ast.BinaryOp.Less: operator.lt,
    ast.BinaryOp.LessEqual: operator.le,
    ast.BinaryOp.Greater: operator.gt,
    ast.BinaryOp.GreaterEqual: operator.ge,
}


def _eval_binop(binop: ast.BinopExpr) -> ExprResult:
    lhs, lhs_type = evaluate(binop.lhs)
    rhs, rhs_type = evaluate(binop.rhs)
    return _eval_binop_value(binop, lhs, rhs), _eval_binop_type(
        binop, lhs_type, rhs_type
    )


def _eval_binop_value(
    binop: ast.BinopExpr, lhs: ComptimeValue, rhs: ComptimeValue
) -> ComptimeValue:
    if lhs is ast.ConstantFolding.Failed or rhs is ast.ConstantFolding.Failed:
        return ast.ConstantFolding.Failed

    if (
        lhs is ast.ConstantFolding.RuntimeValue
        or rhs is ast.ConstantFolding.RuntimeValue
    ):
        return (
            ast.ConstantFolding.RuntimeValue
        )  # might still be invalid depending on typechecking result

    op = binop.op

    match op, lhs, rhs:
        case (ast.BinaryOp.Equal, None, _) | (ast.BinaryOp.Equal, _, None):
            return lhs is None and rhs is None

        case (ast.BinaryOp.NotEqual, None, _) | (ast.BinaryOp.NotEqual, _, None):
            return not (lhs is None and rhs is None)

        case (_, None, _) | (_, _, None):
            return None

        case ast.BinaryOp.Multiply, bool(), _:
            return rhs if lhs else _zero(rhs)

        case ast.BinaryOp.Multiply, _, bool():
            return lhs if rhs else _zero(lhs)

        case ast.BinaryOp.Add, str(), str():
            return lhs + rhs

        case ast.BinaryOp.And, _, _:
            return _truthy(lhs) and _truthy(rhs)

        case ast.BinaryOp.Or, _, _:
            return _truthy(lhs) or _truthy(rhs)

        case (
            (
                ast.BinaryOp.Add
                | ast.BinaryOp.Subtract
                | ast.BinaryOp.Remainder
                | ast.BinaryOp.Modulo
                | ast.BinaryOp.Equal
                | ast.BinaryOp.NotEqual
                | ast.BinaryOp.Less
                | ast.BinaryOp.Greater
                | ast.BinaryOp.LessEqual
                | ast.BinaryOp.GreaterEqual
            ),
            ScalarValue(),
            ScalarValue(),
        ):
            if lhs.unit == rhs.unit:
                opfunc = BINOP_FUNCS[op]
                return ScalarValue(opfunc(*_coerce(lhs.value, rhs.value)), lhs.unit)
            else:
                raise ValueError(f"incompatible units: ({lhs.unit}) and ({rhs.unit})")

        case ast.BinaryOp.Multiply, ScalarValue(), ScalarValue():
            return ScalarValue(
                operator.mul(*_coerce(lhs.value, rhs.value)),
                CanonicalUnit.combine(lhs.unit, 1, rhs.unit, 1),
            )

        case ast.BinaryOp.Divide, ScalarValue(), ScalarValue():
            return ScalarValue(
                Fraction(lhs.value) / Fraction(rhs.value),
                CanonicalUnit.combine(lhs.unit, 1, rhs.unit, -1),
            )

        case ast.BinaryOp.FloorDivide, ScalarValue(), ScalarValue():
            return ScalarValue(
                operator.floordiv(*_coerce(lhs.value, rhs.value)),
                CanonicalUnit.combine(lhs.unit, 1, rhs.unit, -1),
            )

        case ast.BinaryOp.Power, ScalarValue(), ScalarValue():
            if rhs.unit:
                raise ValueError("exponents must be unitless")

            if lhs.unit:
                frac_exp = Fraction(rhs.value)
                if frac_exp.is_integer():
                    new_unit = lhs.unit * frac_exp.numerator

                else:
                    raise ValueError(
                        "fractional exponents not yet supported for values with units"
                    )
            else:
                new_unit = None

            return ScalarValue(
                operator.pow(*_coerce(lhs.value, rhs.value)),
                new_unit,
            )

        case _:
            diagnostics.error(
                f"no evaluation defined for operator {op.value}"
                + f" on types {type(lhs).__name__} and {type(rhs).__name__}",
                binop,
            )

            return ast.ConstantFolding.Failed


def _zero(value):
    match value:
        case ScalarValue():
            return ScalarValue(type(value.value)(), value.unit)
        case str():
            return ""
        case bool():
            return False
        case None:
            return None
        case _:
            raise TypeError(f"cannot determine zero value for {type(value)}")


def _truthy(value) -> bool:
    match value:
        case bool():
            return value
        case None:
            return False
        case _:
            raise TypeError("compile-time truthiness is only defined for bool and nil")


def _coerce(
    a: Num, b: Num
) -> (
    tuple[int, int]
    | tuple[float, float]
    | tuple[Decimal, Decimal]
    | tuple[Fraction, Fraction]
):
    match a, b:
        case int(), int():
            return a, b
        case int(), float():
            return float(a), b
        case int(), Decimal():
            return Decimal(a), b
        case int(), Fraction():
            return Fraction(a), b

        case float(), int():
            return a, float(b)
        case float(), float():
            return a, b
        case float(), Decimal():
            return Decimal(a), b
        case float(), Fraction():
            return Fraction(a), b

        case Decimal(), int():
            return a, Decimal(b)
        case Decimal(), float():
            return a, Decimal(b)
        case Decimal(), Decimal():
            return a, b
        case Decimal(), Fraction():
            return Fraction(a), b

        case Fraction(), int():
            return a, Fraction(b)
        case Fraction(), float():
            return a, Fraction(b)
        case Fraction(), Decimal():
            return a, Fraction(b)
        case Fraction(), Fraction():
            return a, b


def _eval_binop_type(
    binop: ast.BinopExpr, lhs: ComptimeType, rhs: ComptimeType
) -> ComptimeType:
    op = binop.op

    match op, lhs, rhs:
        case (
            (ast.BinaryOp.Equal | ast.BinaryOp.NotEqual),
            (
                PrimitiveType.Float32
                | PrimitiveType.Float64
                | FlexType(FlexAffinity.Float)
            ),
            (
                PrimitiveType.Float32
                | PrimitiveType.Float64
                | FlexType(FlexAffinity.Float)
            ),
        ):
            diagnostics.error(f"binary floats do not support {op.value}", binop)
            return ast.TypeState.Impossible

        case (
            (
                ast.BinaryOp.Equal
                | ast.BinaryOp.NotEqual
                | ast.BinaryOp.Less
                | ast.BinaryOp.Greater
                | ast.BinaryOp.LessEqual
                | ast.BinaryOp.GreaterEqual
            ),
            _,
            _,
        ):
            # TODO: actually check type compatibility of the comparison operator
            return PrimitiveType.Boolean

        case ast.BinaryOp.Multiply, PrimitiveType.Boolean, _:
            return rhs

        case ast.BinaryOp.Multiply, _, PrimitiveType.Boolean:
            return lhs

        case ast.BinaryOp.Add, PrimitiveType.String, PrimitiveType.String:
            return PrimitiveType.String

        case (
            (ast.BinaryOp.And | ast.BinaryOp.Or),
            PrimitiveType.Boolean,
            PrimitiveType.Boolean,
        ):
            return PrimitiveType.Boolean

        case (
            ast.BinaryOp.Divide,
            FlexType(FlexAffinity.Integer | FlexAffinity.UInt),
            FlexType(FlexAffinity.Integer | FlexAffinity.UInt),
        ):
            # This is supported for comptime integers, but not runtime integers
            return FlexType(FlexAffinity.Decimal)

        case ast.BinaryOp.Divide, _, _ if _is_integer_type(lhs) and _is_integer_type(
            rhs
        ):
            diagnostics.error(
                "true division is not supported for integer types."
                + " use // if you meant to do floor division",
                binop,
            )
            return ast.TypeState.Impossible

        case (
            ast.BinaryOp.FloorDivide,
            FlexType(
                FlexAffinity.Integer
                | FlexAffinity.UInt
                | FlexAffinity.Decimal
                | FlexAffinity.Float
            ),
            FlexType(
                FlexAffinity.Integer
                | FlexAffinity.UInt
                | FlexAffinity.Decimal
                | FlexAffinity.Float
            ),
        ):
            return FlexType(FlexAffinity.Integer)

        case (
            (
                ast.BinaryOp.Add
                | ast.BinaryOp.Subtract
                | ast.BinaryOp.Remainder
                | ast.BinaryOp.Modulo
                | ast.BinaryOp.Multiply
                | ast.BinaryOp.Power
                | ast.BinaryOp.Divide
                | ast.BinaryOp.FloorDivide
            ),
            _,
            _,
        ) if _is_numeric_type(lhs) and _is_numeric_type(rhs):
            if (
                coerced_left := _implicit_convert(lhs, rhs)
            ) is not ast.TypeState.Impossible:
                return coerced_left
            if (
                coerced_right := _implicit_convert(rhs, lhs)
            ) is not ast.TypeState.Impossible:
                return coerced_right
            else:
                diagnostics.error(f"cannot implicitly coalesce {lhs} and {rhs}", binop)
                return ast.TypeState.Impossible

        case _:
            diagnostics.error(
                f"operator {op.value} is not defined for types {lhs} and {rhs}", binop
            )
            return ast.TypeState.Impossible


def _cast_allowed(dest: ComptimeType, src: ComptimeType) -> bool:
    if src == dest:
        return True

    dest_kind = _conversion_class(dest)
    src_kind = _conversion_class(src)

    return dest_kind == src_kind


def _conversion_class(typ: ComptimeType) -> ConversionClass:
    match typ:
        case DistinctType():
            assert typ.definition.underlying.canonical
            return _conversion_class(typ.definition.underlying.canonical)

        case StaticArrayType():
            return FixedArrayKind(typ.shape, _conversion_class(typ.elem))

        case FlexType(FlexAffinity.Boolean) | PrimitiveType.Boolean:
            return TypeKind.Boolean

        case FlexType(FlexAffinity.String) | PrimitiveType.String:
            return TypeKind.String

        case (
            FlexType(
                FlexAffinity.Integer
                | FlexAffinity.UInt
                | FlexAffinity.Decimal
                | FlexAffinity.Float
            )
            | FixedDecimal()
            | PrimitiveType.Integer
            | PrimitiveType.Int64
            | PrimitiveType.Int32
            | PrimitiveType.Int16
            | PrimitiveType.Int8
            | PrimitiveType.UInt64
            | PrimitiveType.UInt32
            | PrimitiveType.UInt16
            | PrimitiveType.UInt8
            | PrimitiveType.Decimal
            | PrimitiveType.Dec64
            | PrimitiveType.Dec32
            | PrimitiveType.Float64
            | PrimitiveType.Float32
            | PrimitiveType.Rune
            | PrimitiveType.Byte
        ):
            return TypeKind.Numeric

        case _:
            return Unconvertable


def _implicit_convert(dest: ComptimeType, src: ComptimeType) -> ComptimeType:
    if src == dest:
        return src

    match dest, src:
        # TODO: composite types

        case FlexType(FlexAffinity.Integer), FlexType(FlexAffinity.UInt):
            return dest

        case FlexType(FlexAffinity.Float), FlexType(
            FlexAffinity.Integer | FlexAffinity.UInt
        ):
            return dest

        case FlexType(FlexAffinity.Decimal), FlexType(
            FlexAffinity.Integer | FlexAffinity.UInt
        ):
            return dest

        case (
            (PrimitiveType.Integer | FlexType(FlexAffinity.Integer)),
            (
                FlexType(FlexAffinity.Integer | FlexAffinity.UInt)
                | FixedDecimal(_, 0)
                | PrimitiveType.Int64
                | PrimitiveType.Int32
                | PrimitiveType.Int16
                | PrimitiveType.Int8
                | PrimitiveType.UInt64
                | PrimitiveType.UInt32
                | PrimitiveType.UInt16
                | PrimitiveType.UInt8
            ),
        ):
            return PrimitiveType.Integer

        case PrimitiveType.Int64, (
            FlexType(FlexAffinity.Integer | FlexAffinity.UInt)
            | PrimitiveType.Int32
            | PrimitiveType.Int16
            | PrimitiveType.Int8
            | PrimitiveType.UInt32
            | PrimitiveType.UInt16
            | PrimitiveType.UInt8
        ):
            return dest

        case PrimitiveType.Int32, (
            FlexType(FlexAffinity.Integer | FlexAffinity.UInt)
            | PrimitiveType.Int16
            | PrimitiveType.Int8
            | PrimitiveType.UInt16
            | PrimitiveType.UInt8
        ):
            return dest

        case PrimitiveType.Int16, (
            FlexType(FlexAffinity.Integer | FlexAffinity.UInt)
            | PrimitiveType.Int8
            | PrimitiveType.UInt8
        ):
            return dest

        case PrimitiveType.Int8, (FlexType(FlexAffinity.Integer | FlexAffinity.UInt)):
            return dest

        case PrimitiveType.UInt64, (
            FlexType(FlexAffinity.Integer | FlexAffinity.UInt)
            | PrimitiveType.UInt32
            | PrimitiveType.UInt16
            | PrimitiveType.UInt8
        ):
            return dest

        case PrimitiveType.UInt32, (
            FlexType(FlexAffinity.Integer | FlexAffinity.UInt)
            | PrimitiveType.UInt16
            | PrimitiveType.UInt8
        ):
            return dest

        case PrimitiveType.UInt16, (
            FlexType(FlexAffinity.Integer | FlexAffinity.UInt) | PrimitiveType.UInt8
        ):
            return dest

        case PrimitiveType.UInt8, (FlexType(FlexAffinity.Integer | FlexAffinity.UInt)):
            return dest

        case (
            (PrimitiveType.Decimal | FlexType(FlexAffinity.Decimal)),
            (
                FlexType(
                    FlexAffinity.Integer | FlexAffinity.UInt | FlexAffinity.Decimal
                )
                | FixedDecimal()
                | PrimitiveType.Integer
                | PrimitiveType.Int64
                | PrimitiveType.Int32
                | PrimitiveType.Int16
                | PrimitiveType.Int8
                | PrimitiveType.UInt64
                | PrimitiveType.UInt32
                | PrimitiveType.UInt16
                | PrimitiveType.UInt8
                | PrimitiveType.Decimal
                | PrimitiveType.Dec64
                | PrimitiveType.Dec32
            ),
        ):
            return PrimitiveType.Decimal

        case PrimitiveType.Dec64, (
            FlexType(FlexAffinity.Integer | FlexAffinity.UInt | FlexAffinity.Decimal)
            | PrimitiveType.Int32
            | PrimitiveType.Int16
            | PrimitiveType.Int8
            | PrimitiveType.UInt32
            | PrimitiveType.UInt16
            | PrimitiveType.UInt8
            | PrimitiveType.Dec32
        ):
            return dest

        case PrimitiveType.Dec32, (
            FlexType(FlexAffinity.Integer | FlexAffinity.UInt | FlexAffinity.Decimal)
            | PrimitiveType.Int16
            | PrimitiveType.Int8
            | PrimitiveType.UInt16
            | PrimitiveType.UInt8
        ):
            return dest

        case FixedDecimal(dig_dest, prec_dest), FixedDecimal(dig_src, prec_src):
            if prec_dest >= prec_src and dig_dest - prec_dest >= dig_src - prec_src:
                return dest
            else:
                return ast.TypeState.Impossible

        case FixedDecimal(), (
            FlexType(FlexAffinity.Integer | FlexAffinity.UInt | FlexAffinity.Decimal)
            # TODO: conversion from primitive types (it needs to factor in digits to the left of the decimal point)
        ):
            return dest

        case PrimitiveType.Float64, (
            FlexType(FlexAffinity.Integer | FlexAffinity.UInt | FlexAffinity.Float)
            | PrimitiveType.Integer
            | PrimitiveType.Int32
            | PrimitiveType.Int16
            | PrimitiveType.Int8
            | PrimitiveType.UInt32
            | PrimitiveType.UInt16
            | PrimitiveType.UInt8
            | PrimitiveType.Float32
        ):
            return dest

        case PrimitiveType.Float32, (
            FlexType(FlexAffinity.Integer | FlexAffinity.UInt | FlexAffinity.Float)
            | PrimitiveType.Integer
            | PrimitiveType.Int16
            | PrimitiveType.Int8
            | PrimitiveType.UInt16
            | PrimitiveType.UInt8
        ):
            return dest

        case _:
            return ast.TypeState.Impossible


def _is_integer_type(typ: ComptimeType) -> bool:
    match typ:
        case (
            FlexType(FlexAffinity.Integer | FlexAffinity.UInt)
            | PrimitiveType.Integer
            | PrimitiveType.Int64
            | PrimitiveType.Int32
            | PrimitiveType.Int16
            | PrimitiveType.Int8
            | PrimitiveType.UInt64
            | PrimitiveType.UInt32
            | PrimitiveType.UInt16
            | PrimitiveType.UInt8
        ):
            return True

        case DistinctType():
            assert typ.definition.underlying.canonical, (
                f"underlying type of distinct type should have been evaluated by now: {typ.definition}"
            )
            return _is_integer_type(typ.definition.underlying.canonical)

        case _:
            return False


def _is_numeric_type(typ: ComptimeType) -> bool:
    match typ:
        case (
            FlexType(
                FlexAffinity.Integer
                | FlexAffinity.UInt
                | FlexAffinity.Decimal
                | FlexAffinity.Float
            )
            | PrimitiveType.Integer
            | PrimitiveType.Int64
            | PrimitiveType.Int32
            | PrimitiveType.Int16
            | PrimitiveType.Int8
            | PrimitiveType.UInt64
            | PrimitiveType.UInt32
            | PrimitiveType.UInt16
            | PrimitiveType.UInt8
            | PrimitiveType.Decimal
            | PrimitiveType.Dec64
            | PrimitiveType.Dec32
            | PrimitiveType.Float64
            | PrimitiveType.Float32
        ):
            return True

        case DistinctType():
            assert typ.definition.underlying.canonical, (
                f"underlying type of distinct type should have been evaluated by now: {typ.definition}"
            )
            return _is_numeric_type(typ.definition.underlying.canonical)

        case _:
            return False
