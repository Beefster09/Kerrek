

import math
import operator
from dataclasses import dataclass
from decimal import Decimal
from enum import Enum, auto
from fractions import Fraction
from typing import Any, Literal, NamedTuple

from frontend import ast, diagnostics
from frontend.lexer import NumberLiteralForm
from frontend.resolver import AnyType, CanonicalUnit, Constant, PrimitiveType, Unit, Variable

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


type ComptimeValue = ScalarValue | ast.RuneValue | str | bool | None | ast.ConstantFolding
type ComptimeType = AnyType | FlexType | Literal[ast.TypeState.Impossible, ast.TypeState.Failed]
type ExprResult = tuple[ComptimeValue, ComptimeType]


def _ensure_const_evaluated(const_sym: Constant) -> ExprResult:
    const_def = const_sym.definition
    if const_def.expr.folded_value is ast.ConstantFolding.NotEvaluated:
        val, typ = fold_constants(const_def.expr)
        typ = _check_type(const_def.type, typ)
        return val, typ

    return const_def.expr.folded_value, const_def.expr.result_type


def _ensure_type_inferred(var: Variable) -> ComptimeType:
    if var.type is None:
        if isinstance(var.definition, (ast.LocalVariable, ast.GlobalVariable)) \
                and isinstance(var.definition.expr, ast.Expression):
            _, typ = fold_constants(var.definition.expr)
            typ = _check_type(var.definition.type, typ)
            return typ

    return var.type or ast.TypeState.Failed


def fold_constants(node: ast.Expression) -> ExprResult:
    if node.folded_value is not ast.ConstantFolding.NotEvaluated:
        return node.folded_value

    try:
        value, typ = _evaluate(node)
    except Exception as err:
        import traceback; traceback.print_exc()
        diagnostics.error(f"compile time evaluation failed: {err}", node)
        value = ast.ConstantFolding.Failed
        typ = ast.TypeState.Failed
    else:
        if typ in (ast.TypeState.Failed, ast.TypeState.Impossible):
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
                case NumberLiteralForm.Hex | NumberLiteralForm.Octal | NumberLiteralForm.Binary:
                    typ = FlexType(FlexAffinity.UInt)

            return ScalarValue(node.value.value, node.unit.canonical if node.unit else None), typ

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
                    return ScalarValue(1, resolved.definition.base.canonical), FlexType(FlexAffinity.Integer)
                else:
                    return ScalarValue(1, CanonicalUnit([resolved.id])), FlexType(FlexAffinity.Integer)

            return ast.ConstantFolding.RuntimeValue, ast.TypeState.Impossible # TODO: do something more sensible here

        case _:
            raise NotImplementedError(f"no evaluation implemented for {type(node).__qualname__}")


def _check_type(
    dest_type: ast.TypeExpression | ast.TypeState,
    evaluated_type: ComptimeType,
    context: ast.Node,
) -> ComptimeType:
    if dest_type is ast.TypeState.NeedsInference:
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
                diagnostics.error(f"cannot infer type of nil", context)
                return ast.TypeState.Impossible
            case _:
                return evaluated_type

    if dest_type is ast.TypeState.Flexible:  # specifically for constants and nothing else
        return evaluated_type

    assert not (
        isinstance(dest_type, ast.TypeState)
        or isinstance(dest_type.canonical, ast.TypeState)), \
        f"the dest type {dest_type} should have been evaluated by now"

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
    ast.Operator.Add: operator.add,
    ast.Operator.Subtract: operator.sub,
    ast.Operator.Multiply: operator.mul,
    ast.Operator.Divide: operator.truediv,
    ast.Operator.FloorDivide: operator.floordiv,
    ast.Operator.Power: operator.pow,

    ast.Operator.Modulo: modulo,
    ast.Operator.Remainder: remainder,

    ast.Operator.Equal: operator.eq,
    ast.Operator.NotEqual: operator.ne,
    ast.Operator.Less: operator.lt,
    ast.Operator.LessEqual: operator.le,
    ast.Operator.Greater: operator.gt,
    ast.Operator.GreaterEqual: operator.ge,
}


def _eval_binop(binop: ast.BinopExpr) -> ExprResult:
    lhs, lhs_type = fold_constants(binop.lhs)
    rhs, rhs_type = fold_constants(binop.rhs)
    return _eval_binop_value(binop, lhs, rhs), _eval_binop_type(binop.op, lhs_type, rhs_type)

def _eval_binop_value(binop: ast.BinopExpr, lhs: ComptimeValue, rhs: ComptimeValue) -> ComptimeValue:
    if lhs is ast.ConstantFolding.Failed or rhs is ast.ConstantFolding.Failed:
        return ast.ConstantFolding.Failed

    if lhs is ast.ConstantFolding.RuntimeValue or rhs is ast.ConstantFolding.RuntimeValue:
        return ast.ConstantFolding.RuntimeValue  # might still be invalid depending on typechecking result

    op = binop.op

    match op, lhs, rhs:
        case (ast.Operator.Equal, None, _) | (ast.Operator.Equal, _, None):
            return lhs is None and rhs is None

        case (ast.Operator.NotEqual, None, _) | (ast.Operator.NotEqual, _, None):
            return not (lhs is None and rhs is None)

        case (_, None, _) | (_, _, None):
            return None

        case ast.Operator.Multiply, bool(), _:
            return rhs if lhs else _zero(rhs)

        case ast.Operator.Multiply, _, bool():
            return lhs if rhs else _zero(lhs)

        case ast.Operator.Add, str(), str():
            return lhs + rhs

        case ast.Operator.And, _, _:
            return _truthy(lhs) and _truthy(rhs)

        case ast.Operator.Or, _, _:
            return _truthy(lhs) or _truthy(rhs)

        case (
            (
                ast.Operator.Add | ast.Operator.Subtract
                | ast.Operator.Remainder | ast.Operator.Modulo
                | ast.Operator.Equal | ast.Operator.NotEqual
                | ast.Operator.Less | ast.Operator.Greater
                | ast.Operator.LessEqual | ast.Operator.GreaterEqual
            ),
            ScalarValue(), ScalarValue(),
        ):
            if lhs.unit == rhs.unit:
                opfunc = BINOP_FUNCS[op]
                return ScalarValue(opfunc(*_coerce(lhs.value, rhs.value)), lhs.unit)
            else:
                raise ValueError(f"incompatible units: ({lhs.unit}) and ({rhs.unit})")

        case ast.Operator.Multiply, ScalarValue(), ScalarValue():
            return ScalarValue(
                operator.mul(*_coerce(lhs.value, rhs.value)),
                CanonicalUnit.combine(lhs.unit, 1, rhs.unit, 1),
            )

        case ast.Operator.Divide, ScalarValue(), ScalarValue():
            return ScalarValue(
                Fraction(lhs.value) / Fraction(rhs.value),
                CanonicalUnit.combine(lhs.unit, 1, rhs.unit, -1),
            )

        case ast.Operator.FloorDivide, ScalarValue(), ScalarValue():
            return ScalarValue(
                operator.floordiv(*_coerce(lhs.value, rhs.value)),
                CanonicalUnit.combine(lhs.unit, 1, rhs.unit, -1),
            )

        case ast.Operator.Power, ScalarValue(), ScalarValue():
            if rhs.unit:
                raise ValueError("exponents must be unitless")

            if lhs.unit:
                frac_exp = Fraction(rhs.value)
                if frac_exp.is_integer():
                    new_unit = lhs.unit * frac_exp.numerator

                else:
                    raise ValueError("fractional exponents not yet supported for values with units")
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


def _coerce(a: Num, b: Num) -> tuple[int, int] | tuple[float, float] | tuple[Decimal, Decimal] | tuple[Fraction, Fraction]:
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


def _eval_binop_type(op: ast.Operator, lhs: ComptimeType, rhs: ComptimeType) -> ComptimeType:
    match op, lhs, rhs:
        case (
            (ast.Operator.Equal | ast.Operator.NotEqual),
            (PrimitiveType.Float32 | PrimitiveType.Float64),
            (PrimitiveType.Float32 | PrimitiveType.Float64),
        ):
            # quick and dirty: should probably handled by the case below, once compatibility checks are added in
            return ast.TypeState.Impossible

        case (
            (
                ast.Operator.Equal | ast.Operator.NotEqual
                | ast.Operator.Less | ast.Operator.Greater
                | ast.Operator.LessEqual | ast.Operator.GreaterEqual
            ),
            _, _,
        ):
            # TODO: actually check type compatibility of the comparison operator
            return PrimitiveType.Boolean

        case ast.Operator.Multiply, PrimitiveType.Boolean, _:
            return rhs

        case ast.Operator.Multiply, _, PrimitiveType.Boolean:
            return lhs

        case ast.Operator.Add, PrimitiveType.String, PrimitiveType.String:
            return PrimitiveType.String

        case (
            (ast.Operator.And | ast.Operator.Or),
            PrimitiveType.Boolean, PrimitiveType.Boolean,
        ):
            return PrimitiveType.Boolean

        case (
            (
                ast.Operator.Add | ast.Operator.Subtract
                | ast.Operator.Remainder | ast.Operator.Modulo
                | ast.Operator.Multiply | ast.Operator.Power
                | ast.Operator.Divide | ast.Operator.FloorDivide
            ),
            _, _,
        ):
            if lhs == rhs:
                # TODO: this isn't quite right but it's good enough for a first pass
                # this is overly strict for numeric types and doesn't allow implicit conversions
                # it doesn't factor in units at all
                # other types which do not actually support these operators are let through
                return lhs
            else:
                return ast.TypeState.Impossible

        case _:
            return ast.TypeState.Impossible
