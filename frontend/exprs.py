from __future__ import annotations

import math
import operator
from collections.abc import Callable
from dataclasses import dataclass
from decimal import Decimal
from enum import Enum, auto
from fractions import Fraction
from typing import Any

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
    return var.definition.realized_type or ast.TypeSentinels.Impossible


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
                        ast.UnitSentinels.NotApplicable,
                    )
                case ast.RuneValue():
                    return EvalResult(
                        node.value,
                        FlexType(FlexAffinity.Rune),
                        ast.UnitSentinels.NotApplicable,
                    )
                case bool():
                    return EvalResult(
                        node.value,
                        FlexType(FlexAffinity.Boolean),
                        ast.UnitSentinels.NotApplicable,
                    )
                case None:
                    return EvalResult(
                        NilOf(FlexType(FlexAffinity.Nil)),
                        FlexType(FlexAffinity.Nil),
                        ast.UnitSentinels.NotApplicable,
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
                    # _ensure_unit_known(resolved),
                    ast.UnitSentinels.NoUnit,
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


BINOP_FUNCS: dict[ast.BinaryOp, Callable[[Any, Any], Any]] = {
    ast.BinaryOp.Add: operator.add,
    ast.BinaryOp.Subtract: operator.sub,
    ast.BinaryOp.Multiply: operator.mul,
    ast.BinaryOp.TrueDivide: operator.truediv,
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
                ast.UnitSentinels.NotApplicable,
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
        lhs.unit,  # TODO: needs to actually check the unit coherence
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


def _eval_binop_value(
    binop: ast.BinopExpr, lhs: ComptimeValue, rhs: ComptimeValue
) -> ComptimeValue:
    if (
        lhs is ast.ValueSentinels.CannotEvaluate
        or rhs is ast.ValueSentinels.CannotEvaluate
    ):
        return ast.ValueSentinels.CannotEvaluate

    if lhs is ast.ValueSentinels.RuntimeValue or rhs is ast.ValueSentinels.RuntimeValue:
        return (
            ast.ValueSentinels.RuntimeValue
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

        case ast.BinaryOp.TrueDivide, ScalarValue(), ScalarValue():
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

            return ast.ValueSentinels.CannotEvaluate


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
            return ast.TypeSentinels.Impossible

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
            ast.BinaryOp.TrueDivide,
            FlexType(FlexAffinity.Integer | FlexAffinity.UInt),
            FlexType(FlexAffinity.Integer | FlexAffinity.UInt),
        ):
            # This is supported for comptime integers, but not runtime integers
            return FlexType(FlexAffinity.Decimal)

        case ast.BinaryOp.TrueDivide, _, _ if _is_integer_type(
            lhs
        ) and _is_integer_type(rhs):
            diagnostics.error(
                "true division is not supported for integer types."
                + " use // if you meant to do floor division",
                binop,
            )
            return ast.TypeSentinels.Impossible

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
                | ast.BinaryOp.TrueDivide
                | ast.BinaryOp.FloorDivide
            ),
            _,
            _,
        ) if _is_numeric_type(lhs) and _is_numeric_type(rhs):
            if (
                coerced_left := _implicit_convert(lhs, rhs)
            ) is not ast.TypeSentinels.Impossible:
                return coerced_left
            if (
                coerced_right := _implicit_convert(rhs, lhs)
            ) is not ast.TypeSentinels.Impossible:
                return coerced_right
            else:
                diagnostics.error(f"cannot implicitly coalesce {lhs} and {rhs}", binop)
                return ast.TypeSentinels.Impossible

        case _:
            diagnostics.error(
                f"operator {op.value} is not defined for types {lhs} and {rhs}", binop
            )
            return ast.TypeSentinels.Impossible


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
