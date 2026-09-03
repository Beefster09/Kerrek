from __future__ import annotations

import builtins
import itertools
from dataclasses import dataclass, field
from decimal import ROUND_HALF_UP, Decimal
from decimal import Context as DecCtx
from fractions import Fraction
from typing import Never, overload

import rich

from frontend import ast, hir, mir, types
from frontend.common import BinaryOp, RuneValue
from frontend.exprs import ByteValue


def hir_to_mir(
    hir: hir.TranslationUnit,
) -> mir.TranslationUnit:
    tu = mir.TranslationUnit()

    for typ in hir.types.values():
        tu.types.append(typ)

    for var in hir.variables.values():
        tu.globals.append(_translate_globalvar(var))

    for func in hir.funcs.values():
        mir_func = _translate_func(func)
        tu.functions.append(mir_func)
        if func is hir.entry_point:
            mir_func.no_mangle = True
            mir_func.name = "main"

    return tu


def _translate_globalvar(var: hir.GlobalVariable) -> mir.GlobalVar:
    return mir.GlobalVar(id=var.id, name=var.name, type=var.type)


def _translate_func(src: hir.FuncDefinition) -> mir.Function:
    builder = FuncBuilder(src)
    builder.lower_block(src.body)
    return builder.finish()


class FuncBuilder:
    @dataclass
    class WIPBlock:
        id: int
        ops: list[mir.Operation] = field(default_factory=list)
        done: bool = False

    def __init__(self, src: hir.FuncDefinition):
        self._tmp_num = itertools.count(1)
        self._var_num = itertools.count(1)
        self._block_num = itertools.count(1)
        self._vars: dict[int, mir.LocalVar] = {}
        self._params: dict[int, mir.Parameter] = {
            param.id: mir.Parameter(i, param.name, param.type)
            for i, param in enumerate(src.params)
        }
        self._current_block: FuncBuilder.WIPBlock | None = None

        self.func = mir.Function(
            id=src.id,
            name=src.name,
            params=[*self._params.values()],
            returns=[ret.type for ret in src.returns],
            error=None,
            fallible=src.fallible,
        )

    def finish(self) -> mir.Function:
        if self._current_block:
            self._endblock(mir.Return([]))
        self.func.blocks.sort(key=lambda b: b.id)
        return self.func

    def _new_tmp(self, typ: hir.Type) -> mir.Temporary:
        # TODO: translate the type
        return mir.Temporary(next(self._tmp_num), typ)

    def _new_mut_tmp(self, typ: hir.Type) -> mir.LocalVar:
        tmp_id = next(self._var_num)
        var = mir.LocalVar(tmp_id, "tmp", typ)
        self.func.locals.append(var)
        return var

    def _new_var(self, decl: hir.LocalVariable) -> mir.LocalVar:
        var = mir.LocalVar(next(self._var_num), decl.name, decl.type)
        self.func.locals.append(var)
        self._vars[decl.id] = var
        return var

    def _newblock(self) -> WIPBlock:
        block = self.WIPBlock(next(self._block_num), [])
        self._current_block = block
        return block

    def _setblock(self, block: WIPBlock):
        assert not block.done, "set finished block as the current block"
        self._current_block = block

    @overload
    def _endblock(self, end: mir.Terminator, /): ...

    @overload
    def _endblock(self, block: WIPBlock, end: mir.Terminator, /): ...

    def _endblock(
        self,
        block_or_end: WIPBlock | mir.Terminator,
        end_maybe: mir.Terminator | None = None,
    ):
        if end_maybe:
            assert isinstance(block_or_end, FuncBuilder.WIPBlock)
            block = block_or_end
            end = end_maybe
        else:
            assert isinstance(block_or_end, mir.Terminator)
            block = self._current_block
            end = block_or_end

        assert block, "no current block"
        assert not block.done, "ended block twice; this is a programming error"
        self.func.blocks.append(
            mir.Block(
                id=block.id,
                ops=block.ops,
                end=end,
            )
        )
        block.done = True
        if end_maybe is None:
            self._current_block = None

    def _emit(self, op: mir.Operation):
        assert self._current_block, "no current block"
        assert not self._current_block.done, "current block already ended"
        self._current_block.ops.append(op)

    def lower_block(self, src: hir.Block):

        start = self._newblock()
        defers = []

        for stmt in src.body:
            match stmt:
                case hir.LocalVariable():
                    var = self._new_var(stmt)
                    if stmt.expr is None:
                        self._emit(mir.Clear(var))
                    elif isinstance(stmt.expr, hir.Expression):
                        self._emit(mir.Set(var, self._lower_expr(stmt.expr)))

                case hir.AssignStatement():
                    lvalues = [self._lower_expr(dest) for dest in stmt.dests]
                    rvalues = [self._lower_expr(expr) for expr in stmt.exprs]
                    # TODO

                case hir.ReturnStatement():
                    retvals = [self._lower_expr(val_expr) for val_expr in stmt.values]
                    self._endblock(mir.Return(retvals))

                case _:
                    raise NotImplementedError(
                        f"{type(stmt).__name__} nodes not yet supported"
                    )

    def _lower_expr(
        self,
        expr: hir.Expression,
    ) -> mir.Operand:

        match expr:
            case hir.ConstExpr(value=value, type=type):
                match value, type:
                    case Fraction(), _ if types.is_integer(type):
                        return mir.Constant(value.numerator)
                    case Fraction(), _ if types.is_decimal(type):
                        return mir.Constant(
                            Decimal(value.numerator) / Decimal(value.denominator)
                        )
                    case Fraction(), _ if types.is_binfloat(type):
                        return mir.Constant(value.numerator / value.denominator)
                    case hir.ZeroOf(ta), tb if types.is_integer(
                        ta
                    ) and types.is_integer(tb):
                        return mir.Constant(0)
                    case hir.ZeroOf(ta), tb if types.is_decimal(
                        ta
                    ) and types.is_decimal(tb):
                        return mir.Constant(Decimal(0))
                    case hir.ZeroOf(ta), tb if types.is_binfloat(
                        ta
                    ) and types.is_binfloat(tb):
                        return mir.Constant(0.0)
                    case RuneValue(codepoint), _:
                        return mir.Constant(codepoint)
                    case ByteValue(byteval), _:
                        return mir.Constant(byteval)
                    case hir.NilOf(ta), tb if types.is_pointer(ta) and types.is_pointer(
                        tb
                    ):
                        return mir.Constant(None)
                    case str() | bool(), _:
                        return mir.Constant(value)
                    case _:
                        raise NotImplementedError(
                            f"cannot convert ({type})({value}) to constant"
                        )

            case hir.VarExpr():
                match expr.references:
                    case hir.LocalVariable():
                        return self._vars[expr.references.id]
                    case hir.FormalParameter():
                        return self._params[expr.references.id]

                raise NotImplementedError(
                    f"cannot find operand for name expression resolving to {expr.references}"
                )

            case hir.BinopExpr():
                return self._binop_expr(expr)

            case hir.UnitReinterpretExpr(expr=sub):
                # this is quite intentionally a no-op
                return self._lower_expr(sub)

            case hir.CastExpr(to=to, expr=sub):
                if types.is_pointer(to):
                    # pointers are interchangeable at the CPU level (and in C), so no actual cast is necessary
                    return self._lower_expr(sub)
                else:
                    tmp = self._new_tmp(to)
                    self._emit(mir.Convert(tmp, self._lower_expr(sub), to))
                    return tmp

            case _:
                raise NotImplementedError(
                    f"{builtins.type(expr).__name__} expression nodes not yet supported"
                )

    def _constant(
        self,
        value: Fraction | ast.RuneValue | ByteValue | str | bool | hir.NilOf,
        t: hir.Type,
    ) -> mir.Constant:
        type = types.underlying(t)
        match value, type:
            case Fraction(), _ if types.is_integer(type):
                return mir.Constant(value.numerator // value.denominator)
            case Fraction(), hir.SimpleType(types.FixedDecimal(digits, prec)):
                ctx = DecCtx(digits, rounding=ROUND_HALF_UP, Emin=-prec, Emax=-prec)
                return mir.Constant(
                    Decimal(value.numerator, ctx) / Decimal(value.denominator, ctx)
                )
            case Fraction(), _ if types.is_decimal(type):
                ctx = DecCtx(rounding=ROUND_HALF_UP)
                return mir.Constant(
                    Decimal(value.numerator, ctx) / Decimal(value.denominator, ctx)
                )
            case Fraction(), _ if types.is_binfloat(type):
                return mir.Constant(value.numerator / value.denominator)

            case ast.RuneValue(codepoint), _:
                return mir.Constant(codepoint)

            case ByteValue(bval), _:
                return mir.Constant(bval)

            case ((str() | bool()), _):
                return mir.Constant(value)

            case hir.NilOf(), _ if types.is_pointer(type):
                return mir.Constant(None)

            case _:
                print(value, type)
                raise NotImplementedError(f"cannot create constant operand for {t}")

    def _binop_expr(
        self,
        expr: hir.BinopExpr,
    ) -> mir.Operand:

        match expr.op:
            case BinaryOp.Add:
                lhs = self._lower_expr(expr.lhs)
                rhs = self._lower_expr(expr.rhs)
                result = self._new_tmp(expr.type)
                self._emit(mir.Add(result, lhs, rhs))
                return result

            case BinaryOp.Subtract:
                lhs = self._lower_expr(expr.lhs)
                rhs = self._lower_expr(expr.rhs)
                result = self._new_tmp(expr.type)
                self._emit(mir.Sub(result, lhs, rhs))
                return result

            case BinaryOp.Multiply:
                lhs = self._lower_expr(expr.lhs)
                rhs = self._lower_expr(expr.rhs)
                result = self._new_tmp(expr.type)
                self._emit(mir.Mul(result, lhs, rhs))
                return result

            case BinaryOp.TrueDivide:
                lhs = self._lower_expr(expr.lhs)
                rhs = self._lower_expr(expr.rhs)
                result = self._new_tmp(expr.type)
                self._emit(mir.Div(result, lhs, rhs))
                return result

            case BinaryOp.FloorDivide:
                lhs = self._lower_expr(expr.lhs)
                rhs = self._lower_expr(expr.rhs)
                result = self._new_mut_tmp(expr.type)
                self._emit(mir.Div(result, lhs, rhs))

                if not (
                    types.is_integer(expr.lhs.singular_type)
                    and types.is_integer(expr.rhs.singular_type)
                ):
                    self._emit(mir.Truncate(result, result))

                return result

            case BinaryOp.Remainder:
                lhs = self._lower_expr(expr.lhs)
                rhs = self._lower_expr(expr.rhs)
                result = self._new_tmp(expr.type)
                self._emit(mir.Rem(result, lhs, rhs))
                return result

            case BinaryOp.Modulo:
                lhs = self._lower_expr(expr.lhs)
                rhs = self._lower_expr(expr.rhs)
                result = self._new_mut_tmp(expr.type)
                self._emit(mir.Rem(result, lhs, rhs))

                before = self._current_block
                assert before

                negative = self._newblock()
                self._emit(mir.Add(result, result, rhs))

                after = self._newblock()

                self._endblock(
                    before,
                    mir.BranchLess(
                        result,
                        mir.Constant(0),
                        lt_branch=negative.id,
                        ge_branch=after.id,
                    ),
                )
                self._endblock(negative, mir.Jump(after.id))

                self._setblock(after)

                return result

            case BinaryOp.Is:
                raise NotImplementedError()
            case BinaryOp.IsNot:
                raise NotImplementedError()

            case BinaryOp.Equal:
                raise NotImplementedError()
            case BinaryOp.NotEqual:
                raise NotImplementedError()
            case BinaryOp.Less:
                raise NotImplementedError()
            case BinaryOp.LessEqual:
                raise NotImplementedError()
            case BinaryOp.Greater:
                raise NotImplementedError()
            case BinaryOp.GreaterEqual:
                raise NotImplementedError()

            case BinaryOp.And:
                raise NotImplementedError()
            case BinaryOp.Or:
                raise NotImplementedError()

            case Never():
                raise AssertionError("unreachable")

        raise NotImplementedError(f"unable to handle binary operator {expr.op.value}")
