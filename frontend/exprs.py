from __future__ import annotations

import math
import operator
from collections.abc import Callable
from dataclasses import dataclass
from decimal import Decimal
from enum import Enum, auto
from fractions import Fraction
from typing import Any, Never

from frontend import ast, diagnostics
from frontend.lexer import NumberLiteralForm
from frontend.resolver import (
    AnyType,
    CanonicalUnit,
    Constant,
    DistinctType,
    EnumType,
    FixedDecimal,
    InterfaceType,
    OptionalType,
    PointerType,
    PrimitiveType,
    StaticArrayType,
    StructType,
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


@dataclass
class NilOf:
    type: ComptimeType


@dataclass
class ByteValue:
    value: int
    # TODO: validation


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
    Fraction | ast.RuneValue | ByteValue | str | bool | NilOf | ast.ValueSentinels
)
type RealizedType = AnyType | ast.TypeSentinels
type ComptimeType = RealizedType | FlexType
type ComptimeUnit = CanonicalUnit | ast.UnitSentinels


@dataclass
class EvalResult:
    value: ComptimeValue
    type: ComptimeType
    unit: ComptimeUnit


def _ensure_const_evaluated(const_sym: Constant) -> EvalResult:
    const_def = const_sym.definition
    if const_def.expr.evaluated_value is ast.ValueSentinels.NotEvaluated:
        result = evaluate(const_def.expr)
        if const_def.type is not None:
            check_type(const_def.type, result.type, const_def)

        return result

    return EvalResult(
        const_def.expr.evaluated_value,
        const_def.expr.evaluated_type,
        const_def.expr.evaluated_unit,
    )


def _ensure_type_inferred(var: Variable) -> RealizedType:
    if isinstance(var.definition, ast.FormalParameter):
        assert var.definition.type.canonical, (
            f"parameter type should have been evaluated by now: {var.definition}"
        )
        return var.definition.type.canonical

    if var.definition.realized_type is None and isinstance(
        var.definition.expr, ast.Expression
    ):
        result = evaluate(var.definition.expr)

        if var.definition.type is None:
            var.definition.realized_type = infer_type(result.type, var.definition)
        else:
            typ = check_type(var.definition.type, result.type, var.definition)
            assert not isinstance(typ, FlexType)
            var.definition.realized_type = typ

    assert var.definition.realized_type, (
        f"variable type should have been evaluated by now: {var.definition}"
    )
    return var.definition.realized_type


def _ensure_unit_known(var: Variable) -> ComptimeUnit:
    if isinstance(var.definition, ast.FormalParameter):
        if var.definition.unit is None:
            return ast.UnitSentinels.NoUnit

        assert var.definition.unit.canonical is not None, (
            f"parameter unit should have been evaluated by now: {var.definition}"
        )
        return var.definition.unit.canonical

    if var.definition.realized_unit is ast.UnitSentinels.NotDetermined and isinstance(
        var.definition.expr, ast.Expression
    ):
        if var.definition.unit in (
            ast.UnitSentinels.NoUnit,
            ast.UnitSentinels.Flexible,
        ):
            var.definition.realized_unit = var.definition.unit
            return var.definition.unit

        result = evaluate(var.definition.expr)

        if var.definition.unit is ast.UnitSentinels.NotDetermined:
            if result.unit is ast.UnitSentinels.Flexible:
                var.definition.realized_unit = ast.UnitSentinels.NoUnit
            else:
                var.definition.realized_unit = result.unit
        else:
            if isinstance(var.definition.unit, ast.UnitSentinels):
                var.definition.realized_unit = var.definition.unit
            else:
                assert var.definition.unit.canonical is not None, (
                    "this should have been evaluated by now"
                )
                if var.definition.unit != result.unit:  # TODO: type conversions
                    diagnostics.error(
                        "evaluated unit does not match the declared unit"
                        + f" (got |{result.unit}|, expected |{var.definition.unit}|)",
                        var.definition,
                    )
                var.definition.realized_unit = var.definition.unit.canonical

    assert var.definition.realized_unit is not ast.UnitSentinels.NotDetermined, (
        f"variable unit should have been evaluated by now: {var.definition}"
    )
    return var.definition.realized_unit


def evaluate(node: ast.Expression) -> EvalResult:
    if node.evaluated_value is not ast.ValueSentinels.NotEvaluated:
        assert node.evaluated_type is not ast.TypeSentinels.NotDetermined
        return EvalResult(
            node.evaluated_value,
            node.evaluated_type,
            node.evaluated_unit,
        )

    try:
        result = _evaluate(node)
    except Exception as err:  # noqa: BLE001 - catching all exceptions is intended
        import traceback

        traceback.print_exc()
        diagnostics.error(f"constant evaluation failed: {err}", node)
        result = EvalResult(
            ast.ValueSentinels.CannotEvaluate,
            ast.TypeSentinels.Impossible,
            ast.UnitSentinels.Incoherent,
        )
    else:
        if result.type is ast.TypeSentinels.Impossible:
            if result.value is not ast.ValueSentinels.CannotEvaluate:
                diagnostics.error(
                    f"type evaluation resolved to .{result.type.name} here", node
                )
            result.value = ast.ValueSentinels.CannotEvaluate

    node.evaluated_value = result.value
    node.evaluated_type = result.type
    node.evaluated_unit = result.unit

    return result


def _evaluate(node: ast.Expression) -> EvalResult:
    match node:
        case ast.SimpleLiteralExpr():
            match node.value:
                case str():
                    return EvalResult(
                        node.value,
                        FlexType(FlexAffinity.String),
                        ast.UnitSentinels.NoUnit,
                    )
                case ast.RuneValue():
                    return EvalResult(
                        node.value,
                        FlexType(FlexAffinity.Rune),
                        ast.UnitSentinels.NoUnit,
                    )
                case bool():
                    return EvalResult(
                        node.value,
                        FlexType(FlexAffinity.Boolean),
                        ast.UnitSentinels.NoUnit,
                    )
                case None:
                    return EvalResult(
                        NilOf(FlexType(FlexAffinity.Nil)),
                        FlexType(FlexAffinity.Nil),
                        ast.UnitSentinels.NoUnit,
                    )

        case ast.ScalarLiteralExpr():
            match node.value.form:
                case NumberLiteralForm.DecimalInteger:
                    affinity = FlexAffinity.Integer
                case NumberLiteralForm.Decimal:
                    affinity = FlexAffinity.Decimal
                case NumberLiteralForm.Float | NumberLiteralForm.HexFloat:
                    affinity = FlexAffinity.Float
                case (
                    NumberLiteralForm.Hex
                    | NumberLiteralForm.Octal
                    | NumberLiteralForm.Binary
                ):
                    affinity = FlexAffinity.UInt

            return EvalResult(
                Fraction(node.value.value),
                FlexType(affinity),
                node.unit.canonical
                if node.unit and node.unit.canonical
                else ast.UnitSentinels.Flexible,
            )

        case ast.BinopExpr():
            return _eval_binop(node)

        case ast.QualnameExpr():
            resolved = node.name.resolves_to
            if isinstance(resolved, Constant):
                return _ensure_const_evaluated(resolved)
            elif isinstance(resolved, Variable):
                return EvalResult(
                    ast.ValueSentinels.RuntimeValue,
                    _ensure_type_inferred(resolved),
                    _ensure_unit_known(resolved),
                )
            elif isinstance(resolved, Unit):
                if isinstance(resolved.definition, ast.UnitAlias):
                    assert resolved.definition.base.canonical is not None
                    return EvalResult(
                        Fraction(1),
                        FlexType(FlexAffinity.Integer),
                        resolved.definition.base.canonical,
                    )
                else:
                    return EvalResult(
                        Fraction(1),
                        FlexType(FlexAffinity.Integer),
                        CanonicalUnit([resolved.id]),
                    )

            diagnostics.error(
                f"qualified name references unexpected symbol: {resolved}", node
            )
            return EvalResult(
                ast.ValueSentinels.CannotEvaluate,
                ast.TypeSentinels.Impossible,
                ast.UnitSentinels.Incoherent,
            )

        case ast.UnitReinterpretExpr():
            result = evaluate(node.expr)
            return EvalResult(
                result.value,
                result.type,
                node.new_unit.canonical or ast.UnitSentinels.NotDetermined
                if result.unit is not ast.UnitSentinels.Incoherent
                else ast.UnitSentinels.Incoherent,
            )

        case ast.CastExpr():
            assert node.to.canonical, "this should have been set by now"
            result = evaluate(node.expr)

            if _cast_allowed(node.to.canonical, result.type):
                return EvalResult(
                    ast.ValueSentinels.RuntimeValue,  # TODO: This might be comptime-evaluatable
                    node.to.canonical,
                    result.unit,
                )
            else:
                diagnostics.error(
                    f"{result.type} is not convertible to {node.to.canonical}", node
                )
                return EvalResult(
                    ast.ValueSentinels.CannotEvaluate,
                    ast.TypeSentinels.Impossible,
                    ast.UnitSentinels.Incoherent,
                )

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
            return ast.TypeSentinels.Impossible
        case FlexType(affinity):
            raise NotImplementedError(f"missing a case for {affinity}")
        case _:
            return evaluated_type


def check_type(
    dest_type: ast.TypeExpression,
    evaluated_type: ComptimeType,
    context: ast.Node,
) -> ComptimeType:

    assert dest_type.canonical is not None, (
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


def floordiv(lhs, rhs):
    return Fraction(lhs // rhs)


BINOP_FUNCS: dict[ast.BinaryOp, Callable[[Any, Any], Any]] = {
    ast.BinaryOp.Add: operator.add,
    ast.BinaryOp.Subtract: operator.sub,
    ast.BinaryOp.Multiply: operator.mul,
    ast.BinaryOp.TrueDivide: operator.truediv,
    ast.BinaryOp.FloorDivide: floordiv,
    ast.BinaryOp.Power: lambda b, e: Fraction(b**e),
    ast.BinaryOp.Modulo: modulo,
    ast.BinaryOp.Remainder: remainder,
    ast.BinaryOp.Equal: operator.eq,
    ast.BinaryOp.NotEqual: operator.ne,
    ast.BinaryOp.Less: operator.lt,
    ast.BinaryOp.LessEqual: operator.le,
    ast.BinaryOp.Greater: operator.gt,
    ast.BinaryOp.GreaterEqual: operator.ge,
    ast.BinaryOp.And: lambda l, r: bool(l and r),
    ast.BinaryOp.Or: lambda l, r: bool(l or r),
}


def _eval_binop(binop: ast.BinopExpr) -> EvalResult:
    lhs = evaluate(binop.lhs)
    rhs = evaluate(binop.rhs)

    # Well-defined non-coercing special cases
    match binop.op, lhs.type, rhs.type:
        case (
            ast.BinaryOp.Multiply,
            (PrimitiveType.Boolean | FlexType(FlexAffinity.Boolean)),
            _,
        ):
            return _eval_boolean_multiply(lhs.value, rhs, binop)

        case (
            ast.BinaryOp.Multiply,
            _,
            (PrimitiveType.Boolean | FlexType(FlexAffinity.Boolean)),
        ):
            return _eval_boolean_multiply(rhs.value, lhs, binop)

        case (
            ast.BinaryOp.Add,
            (PrimitiveType.String | FlexType(FlexAffinity.String)),
            (PrimitiveType.String | FlexType(FlexAffinity.String)),
        ) if isinstance(lhs.value, str) and isinstance(rhs.value, str):
            typ = _coerce(lhs, rhs)
            assert not isinstance(typ, ConversionSentinels), (
                "_coerce is probably broken"
            )
            return EvalResult(
                lhs.value + rhs.value,
                typ,
                ast.UnitSentinels.NoUnit,
            )

    coerced_type = _coerce(lhs, rhs)

    if coerced_type is ConversionSentinels.NoImplicitConversion:
        diagnostics.error(
            f"operator {binop.op.value} is not supported for types {lhs.type} and {rhs.type}"
            + " and no implicit conversion between them exists",
            binop,
        )
        return EvalResult(
            ast.ValueSentinels.CannotEvaluate,
            ast.TypeSentinels.Impossible,
            ast.UnitSentinels.Incoherent,
        )

    op_compat = _op_category_of(coerced_type)

    if binop.op not in op_compat.supported_binops:
        diagnostics.error(
            f"operator {binop.op} is not supported for type {coerced_type}",
            binop,
        )
        # TODO: suggestions based on the type and its semantics
        return EvalResult(
            ast.ValueSentinels.CannotEvaluate,
            ast.TypeSentinels.Impossible,
            ast.UnitSentinels.Incoherent,
        )

    if (
        lhs.value is ast.ValueSentinels.RuntimeValue
        or rhs.value is ast.ValueSentinels.RuntimeValue
    ):
        val = ast.ValueSentinels.RuntimeValue
    else:
        op_func = BINOP_FUNCS[binop.op]
        val = op_func(lhs.value, rhs.value)

    return EvalResult(
        val,
        coerced_type,
        _eval_binop_unit(binop, lhs, rhs),
    )


def _eval_boolean_multiply(
    boolval: ComptimeValue, nonbool: EvalResult, binop: ast.BinopExpr
) -> EvalResult:
    if not is_zeroable(nonbool.type):
        diagnostics.error(
            f"cannot multiply Boolean and {nonbool.type} because {nonbool.type} does not have a well-defined zero value",
            binop,
        )
        return EvalResult(
            ast.ValueSentinels.CannotEvaluate,
            ast.TypeSentinels.Impossible,
            ast.UnitSentinels.Incoherent,
        )

    if boolval is True:
        return nonbool

    elif boolval is False:
        return EvalResult(
            zero_of(nonbool.type),
            nonbool.type,
            nonbool.unit,
        )

    elif boolval is ast.ValueSentinels.RuntimeValue:
        return EvalResult(
            ast.ValueSentinels.RuntimeValue,
            nonbool.type,
            nonbool.unit,
        )

    else:
        raise TypeError(
            f"{boolval} is not a compile-time known boolean or runtime value"
        )


def is_zeroable(typ: ComptimeType) -> bool:
    match typ:
        case InterfaceType():
            return False

        case EnumType() | StructType():
            # return typ.is_zeroable()
            return False

        case StaticArrayType():
            return is_zeroable(typ.elem)

        case PointerType():
            return typ.ownership in (
                ast.PointerOwnership.Weak,
                ast.PointerOwnership.Unsafe,
            )

        case DistinctType():
            assert typ.definition.underlying.canonical
            return is_zeroable(typ.definition.underlying.canonical)

        case _:
            return True


def zero_of(typ: ComptimeType) -> ComptimeValue:
    match typ:
        case PointerType() | OptionalType():
            return NilOf(typ)

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
        ):
            return Fraction(0)

        case PrimitiveType.Rune:
            return ast.RuneValue(0)

        case PrimitiveType.Byte:
            return ByteValue(0)

        case _:
            return ast.ValueSentinels.RuntimeValue


def _eval_binop_unit(
    binop: ast.BinopExpr, lhs: EvalResult, rhs: EvalResult
) -> ComptimeUnit:
    if (
        lhs.unit is ast.UnitSentinels.Incoherent
        or rhs.unit is ast.UnitSentinels.Incoherent
    ):
        return ast.UnitSentinels.Incoherent

    if lhs.unit is ast.UnitSentinels.NoUnit and rhs.unit is ast.UnitSentinels.NoUnit:
        return ast.UnitSentinels.NoUnit

    op = binop.op

    match op:
        case ast.BinaryOp.And | ast.BinaryOp.Or:
            # booleans are always not applicable to the unit checker
            # so if this is erroneous, the diagnostic would be emitted by the type checking
            return ast.UnitSentinels.NoUnit

        case (
            ast.BinaryOp.Equal
            | ast.BinaryOp.NotEqual
            | ast.BinaryOp.Less
            | ast.BinaryOp.Greater
            | ast.BinaryOp.LessEqual
            | ast.BinaryOp.GreaterEqual
            | ast.BinaryOp.Is
            | ast.BinaryOp.IsNot
        ):
            coerced_unit, binop.rhs.unit_conv_multiplier = _coerce_units(
                lhs.unit, rhs.unit
            )
            if coerced_unit is ast.UnitSentinels.Incoherent:
                diagnostics.error(
                    f"units ({lhs.unit}) and ({rhs.unit}) do not match"
                    + " and do not have any known conversions",
                    binop,
                )

            return ast.UnitSentinels.NoUnit  # booleans don't have units

        case (
            ast.BinaryOp.Add
            | ast.BinaryOp.Subtract
            | ast.BinaryOp.Remainder
            | ast.BinaryOp.Modulo
        ):
            coerced_unit, binop.rhs.unit_conv_multiplier = _coerce_units(
                lhs.unit, rhs.unit
            )
            if coerced_unit is ast.UnitSentinels.Incoherent:
                diagnostics.error(
                    f"units ({lhs.unit}) and ({rhs.unit}) do not match"
                    + " and do not have any known conversions",
                    binop,
                )
                return ast.UnitSentinels.Incoherent

            return coerced_unit

        case ast.BinaryOp.Multiply:
            l_has_unit = isinstance(lhs.unit, CanonicalUnit)
            r_has_unit = isinstance(rhs.unit, CanonicalUnit)
            if l_has_unit and r_has_unit:
                return CanonicalUnit.combine(lhs.unit, 1, rhs.unit, 1)  # pyright: ignore - it doesn't understand the substituted type refinement
            elif l_has_unit and rhs.unit is ast.UnitSentinels.Flexible:
                return lhs.unit
            elif r_has_unit and lhs.unit is ast.UnitSentinels.Flexible:
                return rhs.unit
            elif (
                lhs.unit is ast.UnitSentinels.Flexible
                and rhs.unit is ast.UnitSentinels.Flexible
            ):
                return ast.UnitSentinels.Flexible
            elif lhs.unit in (
                ast.UnitSentinels.NoUnit,
                ast.UnitSentinels.Flexible,
            ) and rhs.unit in (ast.UnitSentinels.NoUnit, ast.UnitSentinels.Flexible):
                return ast.UnitSentinels.NoUnit
            else:
                diagnostics.error(
                    "you cannot multiply a unitless value with a value with units"
                    + f" (|{lhs.unit}| {op.value} |{rhs.unit}|)",
                    binop,
                )
                return ast.UnitSentinels.Incoherent

        case ast.BinaryOp.TrueDivide | ast.BinaryOp.FloorDivide:
            l_has_unit = isinstance(lhs.unit, CanonicalUnit)
            r_has_unit = isinstance(rhs.unit, CanonicalUnit)
            if l_has_unit and r_has_unit:
                return CanonicalUnit.combine(lhs.unit, 1, rhs.unit, -1)  # pyright: ignore - it doesn't understand the substituted type refinement
            elif l_has_unit and rhs.unit is ast.UnitSentinels.Flexible:
                return lhs.unit
            elif r_has_unit and lhs.unit is ast.UnitSentinels.Flexible:
                return rhs.unit * -1  # pyright: ignore - it doesn't understand the substituted type refinement
            elif (
                lhs.unit is ast.UnitSentinels.Flexible
                and rhs.unit is ast.UnitSentinels.Flexible
            ):
                return ast.UnitSentinels.Flexible
            elif lhs.unit in (
                ast.UnitSentinels.NoUnit,
                ast.UnitSentinels.Flexible,
            ) and rhs.unit in (ast.UnitSentinels.NoUnit, ast.UnitSentinels.Flexible):
                return ast.UnitSentinels.NoUnit
            else:
                diagnostics.error(
                    "you cannot divide a unitless value by a value with units or vice-versa"
                    + f" (|{lhs.unit}| {op.value} |{rhs.unit}|)",
                    binop,
                )
                return ast.UnitSentinels.Incoherent

        case ast.BinaryOp.Power:
            if isinstance(lhs, CanonicalUnit):
                if isinstance(rhs.value, Fraction) and (
                    rhs.unit in (ast.UnitSentinels.NoUnit, ast.UnitSentinels.Flexible)
                    or (isinstance(rhs.unit, CanonicalUnit) and not rhs.unit)
                ):
                    if rhs.value.is_integer():
                        return lhs * rhs.value.numerator

                    else:
                        diagnostics.error(
                            "fractional exponents are not currently supported for values with units",
                            binop.rhs,
                        )
                        return ast.UnitSentinels.Incoherent
                else:
                    diagnostics.error(
                        "exponents of unit expressions must be statically known unitless integers",
                        binop.rhs,
                    )
                    return ast.UnitSentinels.Incoherent
            elif lhs.unit is ast.UnitSentinels.Flexible:
                return ast.UnitSentinels.Flexible
            else:
                return ast.UnitSentinels.NoUnit

        case Never():
            raise AssertionError(f"missing branch for {op.value}")


def _coerce_units(
    lhs: ComptimeUnit, rhs: ComptimeUnit
) -> tuple[ComptimeUnit, Fraction]:
    if lhs is ast.UnitSentinels.Flexible:
        return rhs, Fraction(1)
    elif rhs is ast.UnitSentinels.Flexible:
        return lhs, Fraction(1)

    if lhs == rhs:
        return lhs, Fraction(1)

    # TODO: implicit conversions and resulting fraction

    return ast.UnitSentinels.Incoherent, Fraction(1)


class ConversionSentinels(Enum):
    NoImplicitConversion = auto()


def _coerce(lhs: EvalResult, rhs: EvalResult) -> ComptimeType | ConversionSentinels:
    if (
        conv := _implicit_convert(lhs.type, rhs.type)
    ) is not ast.TypeSentinels.Impossible:
        return conv

    if (
        conv := _implicit_convert(rhs.type, lhs.type)
    ) is not ast.TypeSentinels.Impossible:
        return conv

    # TODO: handle fixed point decimals which cannot convert to one or the other but could both convert to a common size

    return ConversionSentinels.NoImplicitConversion


def _implicit_convert(dest: ComptimeType, src: ComptimeType) -> ComptimeType:
    if src == dest:
        return src

    match dest, src:
        # TODO: composite types

        case StaticArrayType(), StaticArrayType():
            if dest.shape == src.shape and not isinstance(
                (elem := _implicit_convert(dest.elem, src.elem)),
                (ast.TypeSentinels, FlexType),
            ):
                return StaticArrayType(
                    elem=elem,
                    shape=dest.shape,
                )

            return ast.TypeSentinels.Impossible

        case ((PointerType() | OptionalType()), FlexType(FlexAffinity.Nil)):
            return dest

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
                return ast.TypeSentinels.Impossible

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
            return ast.TypeSentinels.Impossible


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


@dataclass(kw_only=True)
class OperatorCompatCategory:
    name: str
    supported_binops: set[ast.BinaryOp]


IntegerOpCategory = OperatorCompatCategory(
    name="Integer",
    supported_binops={
        ast.BinaryOp.Add,
        ast.BinaryOp.Subtract,
        ast.BinaryOp.Multiply,
        ast.BinaryOp.FloorDivide,
        ast.BinaryOp.Power,
        ast.BinaryOp.Modulo,
        ast.BinaryOp.Remainder,
        ast.BinaryOp.Equal,
        ast.BinaryOp.NotEqual,
        ast.BinaryOp.Less,
        ast.BinaryOp.LessEqual,
        ast.BinaryOp.Greater,
        ast.BinaryOp.GreaterEqual,
    },
)


DecimalOpCategory = OperatorCompatCategory(
    name="Decimal",
    supported_binops={
        ast.BinaryOp.Add,
        ast.BinaryOp.Subtract,
        ast.BinaryOp.Multiply,
        ast.BinaryOp.TrueDivide,
        ast.BinaryOp.FloorDivide,
        ast.BinaryOp.Power,
        ast.BinaryOp.Modulo,
        ast.BinaryOp.Remainder,
        ast.BinaryOp.Equal,
        ast.BinaryOp.NotEqual,
        ast.BinaryOp.Less,
        ast.BinaryOp.LessEqual,
        ast.BinaryOp.Greater,
        ast.BinaryOp.GreaterEqual,
    },
)


BinFloatOpCategory = OperatorCompatCategory(
    name="Binary Float",
    supported_binops={
        ast.BinaryOp.Add,
        ast.BinaryOp.Subtract,
        ast.BinaryOp.Multiply,
        ast.BinaryOp.TrueDivide,
        ast.BinaryOp.FloorDivide,
        ast.BinaryOp.Power,
        ast.BinaryOp.Modulo,
        ast.BinaryOp.Remainder,
        ast.BinaryOp.Less,
        ast.BinaryOp.LessEqual,
        ast.BinaryOp.Greater,
        ast.BinaryOp.GreaterEqual,
    },
)


BooleanOpCategory = OperatorCompatCategory(
    name="Boolean",
    supported_binops={
        ast.BinaryOp.Equal,
        ast.BinaryOp.NotEqual,
        ast.BinaryOp.And,
        ast.BinaryOp.Or,
    },
)


OrderedCategory = OperatorCompatCategory(
    name="Ordered",
    supported_binops={
        ast.BinaryOp.Equal,
        ast.BinaryOp.NotEqual,
        ast.BinaryOp.Less,
        ast.BinaryOp.LessEqual,
        ast.BinaryOp.Greater,
        ast.BinaryOp.GreaterEqual,
    },
)


EnumOpCategory = OperatorCompatCategory(
    name="Enum",
    supported_binops={
        ast.BinaryOp.Is,
        ast.BinaryOp.IsNot,
        # CAVEAT: enums only support equality if the selected variant supports equality
        ast.BinaryOp.Equal,
        ast.BinaryOp.NotEqual,
    },
)


EqualityOnlyOpCategory = OperatorCompatCategory(
    name="Equality Only",
    supported_binops={
        ast.BinaryOp.Equal,
        ast.BinaryOp.NotEqual,
    },
)


EmptyOpCategory = OperatorCompatCategory(
    name="Operators Not Supported",
    supported_binops=set(),
)


def _op_category_of(typ: ComptimeType) -> OperatorCompatCategory:
    match typ:
        case DistinctType():
            assert typ.definition.underlying.canonical
            return _op_category_of(typ.definition.underlying.canonical)

        case EnumType():
            return EnumOpCategory

        case StructType():
            return EmptyOpCategory  # TODO: it's actually the intersection of all of its fields' categories

        case StaticArrayType():
            return _op_category_of(typ.elem)

        case FlexType(FlexAffinity.Nil):
            return BooleanOpCategory

        case FlexType(FlexAffinity.Boolean) | PrimitiveType.Boolean:
            return BooleanOpCategory

        case (
            FlexType(FlexAffinity.String | FlexAffinity.Rune)
            | PrimitiveType.String
            | PrimitiveType.Rune
        ):
            return OrderedCategory

        case (
            FlexType(FlexAffinity.Integer | FlexAffinity.UInt)
            | FixedDecimal(_, 0)
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
            return IntegerOpCategory

        case (
            FlexType(FlexAffinity.Decimal)
            | FixedDecimal()
            | PrimitiveType.Decimal
            | PrimitiveType.Dec64
            | PrimitiveType.Dec32
        ):
            return DecimalOpCategory

        case (
            FlexType(FlexAffinity.Float) | PrimitiveType.Float64 | PrimitiveType.Float32
        ):
            return BinFloatOpCategory

        case _:
            return EqualityOnlyOpCategory
