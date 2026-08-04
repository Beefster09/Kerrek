

from decimal import Decimal
from enum import Enum
from fractions import Fraction
import math
import operator
from dataclasses import dataclass
from typing import Any, Literal, NamedTuple

from frontend import ast, diagnostics
from frontend.resolver import CanonicalUnit, Constant, EvalState, Unit, Variable


type Num = int | float | Decimal | Fraction


@dataclass
class ScalarValue:
    value: Num
    unit: CanonicalUnit | None
    absolute: bool = False

    def __bool__(self) -> bool:
        return bool(self.value)

class PrimitiveType(Enum):
    Integer = 'Integer'
    Int64 = 'Int64'
    Int32 = 'Int32'
    Int16 = 'Int16'
    Int8 = 'Int8'
    UInt64 = 'UInt64'
    UInt32 = 'UInt32'
    UInt16 = 'UInt16'
    UInt8 = 'UInt8'
    Byte = 'Byte'

    Number = 'Number'
    Dec64 = 'Dec64'
    Dec32 = 'Dec32'

    Float64 = 'Float64'
    Float32 = 'Float32'

    Boolean = 'Boolean'
    String = 'String'
    Rune = 'Rune'

    Any = 'Any'


type ComptimeValue = ScalarValue | ast.RuneValue | str | bool | None | ast.ConstantFolding
type ComptimeType = PrimitiveType | ast.TypeState
type ExprResult = tuple[ComptimeValue, ComptimeType]

def calculate_constants(self):
    """calculates compile-time known values:

    - global constants
    - local constants
    - default values of struct fields
    - default values of function parameters (usually)
    - initial values of global variables (sometimes)
    """
    for module in self.modules.values():
        for const in module.constants.values():
            _ensure_const_evaluated(const)

        for func in module.funcs.values():
            for stmt in func.definition.body.walk_statements():
                if isinstance(stmt, ast.LocalConstant):
                    assert stmt.resolves_to, "this should have been defined by now"
                    _ensure_const_evaluated(stmt.resolves_to)

    diagnostics.report()


def _ensure_const_evaluated(const: Constant):
    if const.value is ast.ConstantFolding.NotEvaluated:
        try:
            const.value = fold_constants(const.definition.expr)
        except Exception as err:
            diagnostics.error(f"value for {const.name} cannot be computed at compile time: {err}", const.definition)
            const.value = ast.ConstantFolding.RuntimeValue

    return const.value


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

    node.folded_value = value
    node.result_type = typ
    return value, typ


def _evaluate(node: ast.Expression) -> ExprResult:
    match node:
        case ast.SimpleLiteralExpr():
            return node.value, ast.TypeState.Flexible
        case ast.ScalarLiteralExpr():
            return ScalarValue(node.value.value, node.unit.canonical if node.unit else None), ast.TypeState.Flexible

        case ast.BinopExpr():
            return _eval_binop(node)

        case ast.QualnameExpr():
            resolved = node.name.resolves_to
            if isinstance(resolved, Constant):
                val = _ensure_const_evaluated(resolved)
                return val, ast.TypeState.Flexible  # WRONG: flexible type might be wrong here
            elif isinstance(resolved, Variable):
                return ast.ConstantFolding.RuntimeValue, resolved.type  # TODO: ensure the variable's type is inferred (might be hard for globals)
            elif isinstance(resolved, Unit):
                if isinstance(resolved.definition, ast.UnitAlias):
                    return ScalarValue(1, resolved.definition.base.canonical), ast.TypeState.Flexible
                else:
                    return ScalarValue(1, CanonicalUnit([resolved.id])), ast.TypeState.Flexible

            return ast.ConstantFolding.RuntimeValue, ast.TypeState.Impossible # TODO: do something more sensible here

        case _:
            for child in node:
                if isinstance(child, ast.Expression):
                    return fold_constants(child)

            return ast.ConstantFolding.RuntimeValue, node.result_type  # TODO: ensure this has been resolved


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
    return _eval_binop_value(binop.op, lhs, rhs), _eval_binop_type(binop.op, lhs_type, rhs_type)

def _eval_binop_value(op: ast.Operator, lhs: ComptimeValue, rhs: ComptimeValue) -> ComptimeValue:
    match op, lhs, rhs:
        case (_, ast.ConstantFolding.RuntimeValue, _) | (_, _, ast.ConstantFolding.RuntimeValue):
            return ast.ConstantFolding.RuntimeValue

        case (_, ast.ConstantFolding.Failed, _) | (_, _, ast.ConstantFolding.Failed):
            return ast.ConstantFolding.Failed

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
                + f" on types {type(lhs).__name__} and {type(rhs).__name__}", )


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
