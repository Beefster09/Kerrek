from __future__ import annotations

import math
import operator
from collections.abc import Callable
from dataclasses import dataclass, field
from enum import Enum, auto
from fractions import Fraction
from typing import Any, Literal, NamedTuple, Never

import rich

from frontend import ast, diagnostics, hir
from frontend.common import ByteValue
from frontend.lexer import NumberLiteralForm
from frontend.resolver import (
    BaseUnit,
    Builtin,
    Constant,
    FormalParameter,
    GlobalVariable,
    LocalVariable,
    Module,
    Named,
    UnitAlias,
)
from frontend.types import (
    FixedDecimal,
    FlexAffinity,
    FlexType,
    PrimitiveType,
    conversion_class,
    is_boolean,
    is_string,
    underlying,
)
from frontend.units import CanonicalUnit, IndeterminateUnit

# === SENTINEL VALUES ===


class FlexNil:
    pass


type ComptimeValue = hir.Value | FlexNil
type ComptimeType = hir.Type | FlexType
type ComptimeUnit = (
    CanonicalUnit | Literal[IndeterminateUnit.Flexible, IndeterminateUnit.NoUnit]
)


class FlexibleValue(NamedTuple):
    value: ComptimeValue
    type: ComptimeType
    unit: ComptimeUnit

    def materialize(
        self,
        diag_context: diagnostics.HasSourceLoc,
        get_symbol: GetSymbolFunc,
    ) -> hir.ConstExpr | None:
        real_type = infer_type(self.type, diag_context)

        if real_type is None:
            return None

        return hir.ConstExpr(
            **diag_context.where(),
            value=(
                hir.NilOf(real_type) if isinstance(self.value, FlexNil) else self.value
            ),
            type=real_type,
            unit=(
                materialize_unit(self.unit, get_symbol)
                if isinstance(self.unit, CanonicalUnit)
                else self.unit
            ),
        )


class UnitAnalysisResult(NamedTuple):
    unit: ComptimeUnit
    lhs: EvalResult
    rhs: EvalResult


type EvalResult = FlexibleValue | hir.Expression | None
type GetSymbolFunc = Callable[[ast.Node | hir.SymbolID], Named | None]


def evaluate(node: ast.Expression, get_symbol: GetSymbolFunc) -> EvalResult:
    try:
        result = _evaluate(node, get_symbol)
    except Exception as err:  # noqa: BLE001 - TEMP but intended
        import traceback

        traceback.print_exc()
        diagnostics.error(f"translation to hir failed: {err}", node)
        return None

    return result


def get_canonical_unit(
    unit: ast.CompoundUnit | None,
    get_symbol: GetSymbolFunc,
    *,
    _orig_definition: ast.CompoundUnit | None = None,
    _seen_aliases: tuple[UnitAlias, ...] = (),
    _seen_alias_refs: tuple[ast.QualifiedName, ...] = (),
) -> CanonicalUnit | None:
    if unit is None:
        return None

    canonical = CanonicalUnit()

    for component in unit.components:
        resolved = get_symbol(component.base)
        match resolved:
            case None:
                diagnostics.error(
                    "this component does not resolve to a unit", component
                )
                return None

            case BaseUnit():
                canonical[resolved.id] += component.exponent

            case UnitAlias():
                if resolved in _seen_aliases:
                    assert _orig_definition is not None
                    err = diagnostics.error(
                        "circular dependency of unit definitions detected ...",
                        _orig_definition,
                    )
                    for ref in _seen_alias_refs:
                        err.reference(f"... '{ref}' references an alias ...", ref)

                    err.reference(
                        "... and ultimately loops back to this definition",
                        _seen_aliases[-1].ast,
                    )

                    return None

                if resolved.canonical is None:
                    resolved.canonical = get_canonical_unit(
                        resolved.ast.orig,
                        get_symbol,
                        _orig_definition=_orig_definition or unit,
                        _seen_aliases=(*_seen_aliases, resolved),
                        _seen_alias_refs=(*_seen_alias_refs, component.base),
                    )
                    if resolved.canonical is None:
                        return None

                canonical.inplace_combine(
                    resolved.canonical,
                    component.exponent,
                )

            case _:
                diagnostics.error(
                    f"'{'.'.join(component.base.path)}' does not name a unit or unit type",
                    component.base,
                )

    return canonical


def materialize_unit(
    unit: ComptimeUnit,
    get_symbol: GetSymbolFunc,
) -> hir.RealizedUnit:
    if isinstance(unit, IndeterminateUnit):
        return unit

    components: list[tuple[hir.BaseUnit, int]] = []
    for comp_id, exp in unit.most_common():
        if exp == 0:
            continue

        unit_symbol = get_symbol(comp_id)
        if isinstance(unit_symbol, BaseUnit) and unit_symbol.hir is not None:
            components.append((unit_symbol.hir, exp))
        else:
            unit_name = CanonicalUnit._base_unit_names.get(comp_id, f"UNIT#{comp_id}")
            diagnostics.error(f"missing component for {unit_name}", None, None)

    return hir.CompoundUnit(
        components=components,
        is_absolute=unit.is_absolute,
    )


def dematerialize_unit(unit: hir.RealizedUnit) -> ComptimeUnit:
    if isinstance(unit, IndeterminateUnit):
        return unit

    return CanonicalUnit(
        ((symbol.id, exp) for symbol, exp in unit.components),
        is_absolute=unit.is_absolute,
    )


def singular_type_and_unit(
    res: EvalResult,
) -> tuple[ComptimeType, ComptimeUnit] | tuple[None, None]:
    if isinstance(res, FlexibleValue):
        return res.type, res.unit
    elif isinstance(res, hir.MultiValueExpression):
        if len(res.types) == 1 and len(res.units) == 1:
            return res.types[0], dematerialize_unit(res.units[0])
        else:
            rich.print(res)
            return None, None
    elif isinstance(res, (hir.SingleValueExpression, FlexibleValue)):
        return res.type, dematerialize_unit(res.unit)
    else:
        raise NotImplementedError(
            f"unable to determine singular type and unit of {type(res).__name__}"
        )


def singular_realized_type_and_unit(
    res: EvalResult,
    diag_context: diagnostics.HasSourceLoc,
    get_symbol: GetSymbolFunc,
) -> tuple[hir.Type, hir.RealizedUnit] | tuple[None, None]:
    if isinstance(res, FlexibleValue):
        mat = res.materialize(diag_context, get_symbol)
        if mat is None:
            return None, None
        else:
            return mat.type, mat.unit
    elif isinstance(res, hir.MultiValueExpression):
        if len(res.types) == 1 and len(res.units) == 1:
            return res.types[0], res.units[0]
        else:
            return None, None
    elif isinstance(res, (hir.SingleValueExpression, FlexibleValue)):
        return res.type, res.unit
    else:
        raise NotImplementedError(
            f"unable to determine singular type and unit of {type(res).__name__}"
        )


def _evaluate(node: ast.Expression, get_symbol: GetSymbolFunc) -> EvalResult:
    match node:
        case ast.SimpleLiteralExpr():
            match node.value:
                case str():
                    return FlexibleValue(
                        node.value,
                        FlexType(FlexAffinity.String),
                        IndeterminateUnit.NoUnit,
                    )
                case ast.RuneValue():
                    return FlexibleValue(
                        node.value,
                        FlexType(FlexAffinity.Rune),
                        IndeterminateUnit.NoUnit,
                    )
                case bool():
                    return FlexibleValue(
                        node.value,
                        FlexType(FlexAffinity.Boolean),
                        IndeterminateUnit.NoUnit,
                    )
                case None:
                    return FlexibleValue(
                        FlexNil(),
                        FlexType(FlexAffinity.Nil),
                        IndeterminateUnit.NoUnit,
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

            return FlexibleValue(
                Fraction(node.value.value),
                FlexType(affinity),
                get_canonical_unit(node.unit, get_symbol) or IndeterminateUnit.Flexible,
            )

        case ast.BinopExpr():
            return _eval_binop(node, get_symbol)

        case ast.NameExpr():
            match resolved := get_symbol(node):
                case Constant():
                    return resolved.value
                case LocalVariable() | GlobalVariable() | FormalParameter():
                    assert resolved.hir is not None
                    return hir.VarExpr(
                        **node.where(),
                        references=resolved.hir,
                        type=resolved.hir.type,
                        unit=resolved.hir.unit,
                    )
                case BaseUnit():
                    return FlexibleValue(
                        Fraction(1),
                        FlexType(FlexAffinity.Integer),
                        CanonicalUnit([resolved.id]),
                    )
                case UnitAlias():
                    unit = get_canonical_unit(resolved.ast.orig, get_symbol)
                    if unit:
                        return FlexibleValue(
                            Fraction(1),
                            FlexType(FlexAffinity.Integer),
                            unit,
                        )
                    else:
                        return None  # should already have produced a diagnostic

                case None:
                    return None

                case Module() | Builtin():
                    diagnostics.error(
                        f"'{node.name}' references a {type(resolved).__name__}", node
                    )
                    return None

                case _:
                    diagnostics.error(
                        f"'{node.name}' references a {type(resolved).__name__}", node
                    ).reference("defined here", resolved.ast)
                    return None

        case ast.UnitReinterpretExpr():
            if node.new_unit is IndeterminateUnit.NoUnit:
                new_unit = IndeterminateUnit.NoUnit
            else:
                new_unit = get_canonical_unit(node.new_unit, get_symbol)

            if new_unit is None:
                return None

            match result := evaluate(node.expr, get_symbol):
                case FlexibleValue():
                    return FlexibleValue(
                        result.value,
                        result.type,
                        new_unit,
                    )
                case None:
                    return None
                case hir.SingleValueExpression():
                    return hir.UnitReinterpretExpr(
                        **node.where(),
                        type=result.type,
                        unit=materialize_unit(new_unit, get_symbol),
                        expr=result,
                    )

        case _:
            raise NotImplementedError(
                f"no evaluation implemented for {type(node).__name__} nodes"
            )


def infer_type(
    evaluated_type: ComptimeType,
    diagnostic_context: diagnostics.HasSourceLoc,
) -> hir.Type | None:
    match evaluated_type:
        case FlexType(FlexAffinity.Integer):
            return hir.SimpleType(type=PrimitiveType.Integer)

        case FlexType(FlexAffinity.UInt):
            return hir.SimpleType(type=PrimitiveType.UInt64)

        case FlexType(FlexAffinity.Decimal):
            return hir.SimpleType(type=PrimitiveType.Decimal)

        case FlexType(FlexAffinity.Float):
            return hir.SimpleType(type=PrimitiveType.Float64)

        case FlexType(FlexAffinity.Boolean):
            return hir.SimpleType(type=PrimitiveType.Boolean)

        case FlexType(FlexAffinity.String):
            return hir.SimpleType(type=PrimitiveType.String)

        case FlexType(FlexAffinity.Rune):
            return hir.SimpleType(type=PrimitiveType.Rune)

        case FlexType(FlexAffinity.Nil):
            diagnostics.error("cannot infer type of nil", diagnostic_context)
            return None

        case FlexType(affinity):
            raise NotImplementedError(f"missing a case for {affinity}")

        case _:
            return evaluated_type


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


def _eval_binop(binop: ast.BinopExpr, get_symbol: GetSymbolFunc) -> EvalResult:
    lhs = evaluate(binop.lhs, get_symbol)
    rhs = evaluate(binop.rhs, get_symbol)
    if lhs is None or rhs is None:
        return None

    ltype, lunit = singular_type_and_unit(lhs)
    rtype, runit = singular_type_and_unit(rhs)

    if ltype is None or lunit is None:
        diagnostics.error(
            "this expression does not return exactly one value", binop.lhs
        )
        return None

    if rtype is None or runit is None:
        diagnostics.error(
            "this expression does not return exactly one value", binop.rhs
        )
        return None

    # Well-defined non-coercing special cases
    match binop.op, ltype, rtype:
        case (
            ast.BinaryOp.Multiply,
            _,
            _,
        ) if is_boolean(ltype):
            return _eval_boolean_multiply(
                boolval=lhs,
                nonbool=rhs,
                nonbool_type=rtype,
                nonbool_ast=binop.rhs,
                binop=binop,
                get_symbol=get_symbol,
            )

        case (
            ast.BinaryOp.Multiply,
            _,
            _,
        ) if is_boolean(rtype):
            return _eval_boolean_multiply(
                boolval=rhs,
                nonbool=lhs,
                nonbool_type=ltype,
                nonbool_ast=binop.lhs,
                binop=binop,
                get_symbol=get_symbol,
            )

        case (ast.BinaryOp.Add, _, _) if (
            is_string(ltype)
            and is_string(rtype)
            and isinstance(lhs, FlexibleValue)
            and isinstance(rhs, FlexibleValue)
            and isinstance(lhs.value, str)
            and isinstance(rhs.value, str)
        ):
            typ = _coerce(ltype, rtype)
            assert not isinstance(typ, ConversionSentinels), (
                "there is a bug in type coercion logic, probably"
            )
            return FlexibleValue(
                lhs.value + rhs.value,
                typ,
                IndeterminateUnit.NoUnit,
            )

    coerced_type = _coerce(ltype, rtype)

    if coerced_type is ConversionSentinels.NoImplicitConversion:
        diagnostics.error(
            f"operator {binop.op.value} is not supported for types {ltype} and {rtype}"
            + " and no implicit conversion between them exists",
            binop,
        )
        return None

    op_compat = _op_category_of(coerced_type)

    if binop.op not in op_compat.supported_binops:
        err = diagnostics.error(
            f"operator {binop.op.value} is not supported for type {coerced_type}",
            binop,
        )
        if binop.op in op_compat.suggestions:
            err.suggest(op_compat.suggestions[binop.op])
        return None

    res = _eval_binop_unit(
        binop=binop,
        lhs=lhs,
        lunit=lunit,
        rhs=rhs,
        runit=runit,
        get_symbol=get_symbol,
    )

    if res is None:
        return None

    elif isinstance(res.lhs, FlexibleValue) and isinstance(res.rhs, FlexibleValue):
        return FlexibleValue(
            BINOP_FUNCS[binop.op](res.lhs.value, res.rhs.value),
            coerced_type,
            res.unit,
        )
    else:
        if isinstance(res.lhs, FlexibleValue):
            l = res.lhs.materialize(binop.lhs, get_symbol)
        else:
            l = res.lhs

        if isinstance(res.rhs, FlexibleValue):
            r = res.rhs.materialize(binop.rhs, get_symbol)
        else:
            r = res.rhs

        if l is None or r is None:
            return None

        inferred_type = infer_type(coerced_type, binop)

        if inferred_type is None:
            return None

        mat_unit = materialize_unit(res.unit, get_symbol)

        if not isinstance(ltype, FlexType) and ltype != coerced_type:
            l = hir.CastExpr(
                **l.where(),
                type=inferred_type,
                to=inferred_type,
                unit=l.singular_unit,
                expr=l,
            )

        if not isinstance(rtype, FlexType) and rtype != coerced_type:
            r = hir.CastExpr(
                **r.where(),
                type=inferred_type,
                to=inferred_type,
                unit=r.singular_unit,
                expr=r,
            )

        return hir.BinopExpr(
            **binop.where(),
            op=binop.op,
            lhs=l,
            rhs=r,
            type=inferred_type,
            unit=mat_unit,
        )


def _eval_boolean_multiply(
    *,
    boolval: EvalResult,
    nonbool: EvalResult,
    nonbool_type: ComptimeType,
    binop: ast.BinopExpr,
    nonbool_ast: ast.Expression,
    get_symbol: GetSymbolFunc,
) -> EvalResult:
    if not is_zeroable(nonbool_type):
        diagnostics.error(
            f"cannot multiply Boolean and {nonbool_type} because {nonbool_type}"
            + " does not have a well-defined zero value",
            binop,
        )
        return None

    if isinstance(boolval, FlexibleValue):
        if boolval.value is True:
            return nonbool

        elif boolval.value is False:
            if isinstance(nonbool, FlexibleValue):
                unit = nonbool.unit
            elif isinstance(nonbool, hir.SingleValueExpression):
                unit = dematerialize_unit(nonbool.unit)
            elif isinstance(nonbool, hir.MultiValueExpression):
                if len(nonbool.units) == 1:
                    unit = dematerialize_unit(nonbool.units[0])
                else:
                    raise AssertionError(
                        f"unreachable: {len(nonbool.units)} values returned by part of expression"
                    )
            else:
                raise AssertionError("unreachable")

            return FlexibleValue(
                zero_of(nonbool_type),
                nonbool_type,
                unit,
            )

        else:
            raise AssertionError(f"unreachable: {boolval.value} is not a boolean")

    elif isinstance(boolval, hir.Expression):
        if isinstance(nonbool, FlexibleValue):
            if_true = nonbool.materialize(nonbool_ast, get_symbol)

            if if_true is None:
                return None

            return hir.ConditionExpr(
                **binop.where(),
                condition=boolval,
                if_true=if_true,
                if_false=hir.ConstExpr(
                    **nonbool_ast.where(),
                    value=hir.ZeroOf(if_true.type),
                    type=if_true.type,
                    unit=if_true.unit,
                ),
                type=if_true.type,
                unit=if_true.unit,
            )

        if isinstance(nonbool, hir.SingleValueExpression):
            type = nonbool.type
            unit = nonbool.unit
        elif isinstance(nonbool, hir.MultiValueExpression):
            if len(nonbool.units) == 1:
                type = infer_type(nonbool.types[0], nonbool_ast)
                unit = nonbool.units[0]

                if type is None:
                    return None
            else:
                raise AssertionError(
                    f"unreachable: {len(nonbool.units)} values returned by part of expression"
                )
        else:
            raise AssertionError("unreachable")  # noqa: TRY004

        return hir.ConditionExpr(
            **binop.where(),
            condition=boolval,
            if_true=nonbool,
            if_false=hir.ConstExpr(
                **nonbool_ast.where(),
                value=hir.ZeroOf(type),
                type=type,
                unit=unit,
            ),
            type=type,
            unit=unit,
        )

    else:
        raise TypeError(
            f"{boolval} is not a compile-time known boolean or runtime value"
        )


def is_zeroable(typ: ComptimeType) -> bool:
    match typ:
        case hir.SimpleType(hir.Interface()):
            return False

        case hir.SimpleType(hir.EnumType() | hir.StructType()):
            # return typ.is_zeroable()
            return False

        case hir.FixedArrayType():
            return is_zeroable(typ.elem)

        case hir.PointerType():
            return typ.nullable

        case hir.SimpleType(hir.DistinctType(underyling=underlying)):
            return is_zeroable(underlying)

        case hir.TypeWithTags(base=base):
            return is_zeroable(base)

        case _:
            return True


def zero_of(typ: ComptimeType) -> ComptimeValue:
    match t := underlying(typ):
        case hir.PointerType() | hir.OptionalType():
            return hir.NilOf(t)

        case (
            FlexType(
                FlexAffinity.Integer
                | FlexAffinity.UInt
                | FlexAffinity.Decimal
                | FlexAffinity.Float
            )
            | FixedDecimal()
            | hir.SimpleType(
                PrimitiveType.Integer
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
            )
        ):
            return Fraction(0)

        case hir.SimpleType(PrimitiveType.Rune):
            return ast.RuneValue(0)

        case hir.SimpleType(PrimitiveType.Byte):
            return ByteValue(0)

        case _:
            raise TypeError("zero_of(...) should only be called with zeroable types")


def _eval_binop_unit(
    *,
    binop: ast.BinopExpr,
    lhs: EvalResult,
    lunit: ComptimeUnit,
    rhs: EvalResult,
    runit: ComptimeUnit,
    get_symbol: GetSymbolFunc,
) -> UnitAnalysisResult | None:

    if lhs is None or rhs is None:
        return None

    if lunit is IndeterminateUnit.NoUnit and runit is IndeterminateUnit.NoUnit:
        return UnitAnalysisResult(IndeterminateUnit.NoUnit, lhs, rhs)

    op = binop.op

    def _maybe_convert_rhs(rhs: EvalResult, rmult: Fraction):
        if rmult == Fraction(1) or rhs is None:
            return rhs

        if isinstance(rhs, FlexibleValue):
            rhs = rhs.materialize(binop.rhs, get_symbol)
            if rhs is None:
                return None

        t, u = singular_realized_type_and_unit(rhs, binop.rhs, get_symbol)

        if t is None or u is None:
            return None

        return hir.UnitConversionExpr(
            **binop.rhs.where(),
            expr=rhs,
            type=t,
            unit=u,
            factor=rmult,
        )

    match op:
        case ast.BinaryOp.And | ast.BinaryOp.Or:
            # booleans are never applicable to the unit checker
            # so if this is erroneous, the diagnostic would be emitted by the type checking
            return UnitAnalysisResult(IndeterminateUnit.NoUnit, lhs, rhs)

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
            coerced_unit, rmult = _coerce_units(lunit, runit)
            if coerced_unit is None:
                diagnostics.error(
                    f"units ({lunit}) and ({runit}) do not match"
                    + " and do not have any known conversions",
                    binop,
                )

            return UnitAnalysisResult(
                IndeterminateUnit.NoUnit,  # booleans don't have units
                lhs,
                _maybe_convert_rhs(rhs, rmult),
            )

        case (
            ast.BinaryOp.Add
            | ast.BinaryOp.Subtract
            | ast.BinaryOp.Remainder
            | ast.BinaryOp.Modulo
        ):
            coerced_unit, rmult = _coerce_units(lunit, runit)
            if coerced_unit is None:
                diagnostics.error(
                    f"units ({lunit}) and ({runit}) do not match"
                    + " and do not have any known conversions",
                    binop,
                )
                return None

            return UnitAnalysisResult(
                coerced_unit,
                lhs,
                _maybe_convert_rhs(rhs, rmult),
            )

        case ast.BinaryOp.Multiply:
            l_has_unit = isinstance(lunit, CanonicalUnit)
            r_has_unit = isinstance(runit, CanonicalUnit)
            if l_has_unit and r_has_unit:
                return UnitAnalysisResult(
                    CanonicalUnit.combine(lunit, 1, runit, 1),  # pyright: ignore - it doesn't understand the substituted type refinement
                    lhs,
                    rhs,
                )
            elif l_has_unit and runit is IndeterminateUnit.Flexible:
                return UnitAnalysisResult(lunit, lhs, rhs)
            elif r_has_unit and lunit is IndeterminateUnit.Flexible:
                return UnitAnalysisResult(runit, lhs, rhs)
            elif (
                lunit is IndeterminateUnit.Flexible
                and runit is IndeterminateUnit.Flexible
            ):
                return UnitAnalysisResult(IndeterminateUnit.Flexible, lhs, rhs)
            elif lunit in (
                IndeterminateUnit.NoUnit,
                IndeterminateUnit.Flexible,
            ) and runit in (IndeterminateUnit.NoUnit, IndeterminateUnit.Flexible):
                return UnitAnalysisResult(IndeterminateUnit.NoUnit, lhs, rhs)
            else:
                diagnostics.error(
                    "you cannot multiply a unitless value with a value with units"
                    + f" (|{lunit}| {op.value} |{runit}|)",
                    binop,
                )
                return None

        case ast.BinaryOp.TrueDivide | ast.BinaryOp.FloorDivide:
            l_has_unit = isinstance(lunit, CanonicalUnit)
            r_has_unit = isinstance(runit, CanonicalUnit)
            if l_has_unit and r_has_unit:
                return UnitAnalysisResult(
                    CanonicalUnit.combine(lunit, 1, runit, -1),  # pyright: ignore - it doesn't understand the substituted type refinement
                    lhs,
                    rhs,
                )
            elif l_has_unit and runit is IndeterminateUnit.Flexible:
                return UnitAnalysisResult(lunit, lhs, rhs)
            elif r_has_unit and lunit is IndeterminateUnit.Flexible:
                return UnitAnalysisResult(
                    runit * -1,  # pyright: ignore - it doesn't understand the substituted type refinement
                    lhs,
                    rhs,
                )
            elif (
                lunit is IndeterminateUnit.Flexible
                and runit is IndeterminateUnit.Flexible
            ):
                return UnitAnalysisResult(IndeterminateUnit.Flexible, lhs, rhs)
            elif lunit in (
                IndeterminateUnit.NoUnit,
                IndeterminateUnit.Flexible,
            ) and runit in (IndeterminateUnit.NoUnit, IndeterminateUnit.Flexible):
                return UnitAnalysisResult(IndeterminateUnit.NoUnit, lhs, rhs)
            else:
                diagnostics.error(
                    "you cannot divide a unitless value by a value with units or vice-versa"
                    + f" (|{lunit}| {op.value} |{runit}|)",
                    binop,
                )
                return None

        case ast.BinaryOp.Power:
            if isinstance(lunit, CanonicalUnit) and lunit:
                if (
                    isinstance(rhs, FlexibleValue)
                    and isinstance(rhs.value, Fraction)
                    and (
                        runit in (IndeterminateUnit.NoUnit, IndeterminateUnit.Flexible)
                        or (isinstance(runit, CanonicalUnit) and not runit)
                    )
                ):
                    if rhs.value.is_integer():
                        return UnitAnalysisResult(lunit * rhs.value.numerator, lhs, rhs)

                    else:
                        diagnostics.error(
                            "fractional exponents are not currently supported for values with units",
                            binop.rhs,
                        )
                        return None
                else:
                    diagnostics.error(
                        "exponents of unit expressions must be statically known unitless integers",
                        binop.rhs,
                    )
                    return None

            else:
                if isinstance(runit, CanonicalUnit) and runit:
                    diagnostics.error("exponents must be unitless or ratios", binop.rhs)
                    return None

                return UnitAnalysisResult(lunit, lhs, rhs)

        case Never():
            raise AssertionError(f"missing branch for {op.value}")


def _coerce_units(
    lhs: ComptimeUnit,
    rhs: ComptimeUnit,
) -> tuple[ComptimeUnit | None, Fraction]:
    if lhs is IndeterminateUnit.Flexible:
        return rhs, Fraction(1)
    elif rhs is IndeterminateUnit.Flexible:
        return lhs, Fraction(1)

    if lhs == rhs:
        return lhs, Fraction(1)

    # TODO: implicit conversions and resulting fraction

    return None, Fraction(1)


class ConversionSentinels(Enum):
    NoImplicitConversion = auto()


def _coerce(
    ltype: ComptimeType,
    rtype: ComptimeType,
) -> ComptimeType | ConversionSentinels:
    if conv := _implicit_convert(ltype, rtype):
        return conv

    if conv := _implicit_convert(rtype, ltype):
        return conv

    # TODO: handle fixed point decimals which cannot convert to one or the other but could both convert to a common size

    return ConversionSentinels.NoImplicitConversion


def _implicit_convert(dest: ComptimeType, src: ComptimeType) -> ComptimeType | None:
    if src == dest:
        return src

    match dest, src:
        case hir.FixedArrayType(), hir.FixedArrayType():
            if dest.shape == src.shape and isinstance(
                (elem := _implicit_convert(dest.elem, src.elem)),
                hir.Type,
            ):
                return hir.FixedArrayType(
                    elem=elem,
                    shape=dest.shape,
                )

            return None

        case ((hir.PointerType() | hir.OptionalType()), FlexType(FlexAffinity.Nil)):
            return dest

        case FlexType(FlexAffinity.Integer), FlexType(FlexAffinity.UInt):
            return dest

        case (
            FlexType(FlexAffinity.Float),
            FlexType(FlexAffinity.Integer | FlexAffinity.UInt),
        ):
            return dest

        case (
            FlexType(FlexAffinity.Decimal),
            FlexType(FlexAffinity.Integer | FlexAffinity.UInt),
        ):
            return dest

        case (
            (hir.SimpleType(PrimitiveType.Integer) | FlexType(FlexAffinity.Integer)),
            (
                FlexType(FlexAffinity.Integer | FlexAffinity.UInt)
                | hir.SimpleType(
                    FixedDecimal(_, 0)
                    | PrimitiveType.Int64
                    | PrimitiveType.Int32
                    | PrimitiveType.Int16
                    | PrimitiveType.Int8
                    | PrimitiveType.UInt64
                    | PrimitiveType.UInt32
                    | PrimitiveType.UInt16
                    | PrimitiveType.UInt8
                )
            ),
        ):
            return hir.SimpleType(PrimitiveType.Integer)

        case (
            hir.SimpleType(PrimitiveType.Int64),
            (
                FlexType(FlexAffinity.Integer | FlexAffinity.UInt)
                | hir.SimpleType(
                    PrimitiveType.Int32
                    | PrimitiveType.Int16
                    | PrimitiveType.Int8
                    | PrimitiveType.UInt32
                    | PrimitiveType.UInt16
                    | PrimitiveType.UInt8
                )
            ),
        ):
            return dest

        case (
            hir.SimpleType(PrimitiveType.Int32),
            (
                FlexType(FlexAffinity.Integer | FlexAffinity.UInt)
                | hir.SimpleType(
                    PrimitiveType.Int16
                    | PrimitiveType.Int8
                    | PrimitiveType.UInt16
                    | PrimitiveType.UInt8
                )
            ),
        ):
            return dest

        case (
            hir.SimpleType(PrimitiveType.Int16),
            (
                FlexType(FlexAffinity.Integer | FlexAffinity.UInt)
                | hir.SimpleType(PrimitiveType.Int8 | PrimitiveType.UInt8)
            ),
        ):
            return dest

        case (
            hir.SimpleType(PrimitiveType.Int8),
            (FlexType(FlexAffinity.Integer | FlexAffinity.UInt)),
        ):
            return dest

        case (
            hir.SimpleType(PrimitiveType.UInt64),
            (
                FlexType(FlexAffinity.Integer | FlexAffinity.UInt)
                | hir.SimpleType(
                    PrimitiveType.UInt32 | PrimitiveType.UInt16 | PrimitiveType.UInt8
                )
            ),
        ):
            return dest

        case (
            hir.SimpleType(PrimitiveType.UInt32),
            (
                FlexType(FlexAffinity.Integer | FlexAffinity.UInt)
                | hir.SimpleType(PrimitiveType.UInt16 | PrimitiveType.UInt8)
            ),
        ):
            return dest

        case (
            hir.SimpleType(PrimitiveType.UInt16),
            (
                FlexType(FlexAffinity.Integer | FlexAffinity.UInt)
                | hir.SimpleType(PrimitiveType.UInt8)
            ),
        ):
            return dest

        case (
            hir.SimpleType(PrimitiveType.UInt8),
            (FlexType(FlexAffinity.Integer | FlexAffinity.UInt)),
        ):
            return dest

        case (
            (hir.SimpleType(PrimitiveType.Decimal) | FlexType(FlexAffinity.Decimal)),
            (
                FlexType(
                    FlexAffinity.Integer | FlexAffinity.UInt | FlexAffinity.Decimal
                )
                | FixedDecimal()
                | hir.SimpleType(
                    PrimitiveType.Integer
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
                )
            ),
        ):
            return hir.SimpleType(PrimitiveType.Decimal)

        case (
            hir.SimpleType(PrimitiveType.Dec64),
            (
                FlexType(
                    FlexAffinity.Integer | FlexAffinity.UInt | FlexAffinity.Decimal
                )
                | hir.SimpleType(
                    PrimitiveType.Int32
                    | PrimitiveType.Int16
                    | PrimitiveType.Int8
                    | PrimitiveType.UInt32
                    | PrimitiveType.UInt16
                    | PrimitiveType.UInt8
                    | PrimitiveType.Dec32
                )
            ),
        ):
            return dest

        case (
            hir.SimpleType(PrimitiveType.Dec32),
            (
                FlexType(
                    FlexAffinity.Integer | FlexAffinity.UInt | FlexAffinity.Decimal
                )
                | hir.SimpleType(
                    PrimitiveType.Int16
                    | PrimitiveType.Int8
                    | PrimitiveType.UInt16
                    | PrimitiveType.UInt8
                )
            ),
        ):
            return dest

        case (
            hir.SimpleType(FixedDecimal(dig_dest, prec_dest)),
            hir.SimpleType(FixedDecimal(dig_src, prec_src)),
        ):
            if prec_dest >= prec_src and dig_dest - prec_dest >= dig_src - prec_src:
                return dest
            else:
                return None

        case (
            FixedDecimal(),
            (
                FlexType(
                    FlexAffinity.Integer | FlexAffinity.UInt | FlexAffinity.Decimal
                )
                # TODO: conversion from primitive types (it needs to factor in digits to the left of the decimal point)
            ),
        ):
            return dest

        case (
            hir.SimpleType(PrimitiveType.Float64),
            (
                FlexType(FlexAffinity.Integer | FlexAffinity.UInt | FlexAffinity.Float)
                | hir.SimpleType(
                    PrimitiveType.Integer
                    | PrimitiveType.Int32
                    | PrimitiveType.Int16
                    | PrimitiveType.Int8
                    | PrimitiveType.UInt32
                    | PrimitiveType.UInt16
                    | PrimitiveType.UInt8
                    | PrimitiveType.Float32
                )
            ),
        ):
            return dest

        case (
            hir.SimpleType(PrimitiveType.Float32),
            (
                FlexType(FlexAffinity.Integer | FlexAffinity.UInt | FlexAffinity.Float)
                | hir.SimpleType(
                    PrimitiveType.Integer
                    | PrimitiveType.Int16
                    | PrimitiveType.Int8
                    | PrimitiveType.UInt16
                    | PrimitiveType.UInt8
                )
            ),
        ):
            return dest

        case _:
            return None


def _cast_allowed(dest: ComptimeType, src: ComptimeType) -> bool:
    if src == dest:
        return True

    dest_kind = conversion_class(dest)
    src_kind = conversion_class(src)

    return dest_kind == src_kind


@dataclass(kw_only=True)
class OperatorCompatCategory:
    name: str
    supported_binops: set[ast.BinaryOp]
    suggestions: dict[ast.BinaryOp, str] = field(default_factory=dict)


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
    suggestions={
        ast.BinaryOp.TrueDivide: "did you mean to use // ? (the floor division operator)"
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
    suggestions={
        ast.BinaryOp.Equal: "consider using a comparison operator or approximate equality function from intrinsics:float",
        ast.BinaryOp.NotEqual: "consider using a comparison operator or approximate equality function from intrinsics:float",
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


OpaqueOpCategory = OperatorCompatCategory(
    name="Opaque",
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
        case hir.SimpleType(hir.DistinctType(underlying=underlying)):
            return _op_category_of(underlying)

        case hir.SimpleType(hir.EnumType()):
            return EnumOpCategory

        case hir.SimpleType(hir.StructType()):
            return EmptyOpCategory  # TODO: it's actually the intersection of all of its fields' categories

        case hir.FixedArrayType():
            return _op_category_of(typ.elem)

        case FlexType(FlexAffinity.Nil):
            return BooleanOpCategory

        case FlexType(FlexAffinity.Boolean) | hir.SimpleType(PrimitiveType.Boolean):
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
            | hir.SimpleType(
                PrimitiveType.Integer
                | PrimitiveType.Int64
                | PrimitiveType.Int32
                | PrimitiveType.Int16
                | PrimitiveType.Int8
                | PrimitiveType.UInt64
                | PrimitiveType.UInt32
                | PrimitiveType.UInt16
                | PrimitiveType.UInt8
            )
        ):
            return IntegerOpCategory

        case (
            FlexType(FlexAffinity.Decimal)
            | FixedDecimal()
            | hir.SimpleType(
                PrimitiveType.Decimal | PrimitiveType.Dec64 | PrimitiveType.Dec32
            )
        ):
            return DecimalOpCategory

        case FlexType(FlexAffinity.Float) | hir.SimpleType(
            PrimitiveType.Float64 | PrimitiveType.Float32
        ):
            return BinFloatOpCategory

        case _:
            return OpaqueOpCategory
