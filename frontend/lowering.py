from __future__ import annotations

import itertools
from dataclasses import dataclass, field
from decimal import ROUND_HALF_UP, Decimal
from decimal import Context as DecCtx
from fractions import Fraction
from typing import Never, overload

from frontend import ast, hir, mir, resolver, types
from frontend.exprs import ByteValue, ComptimeType


def hir_to_mir(
    hir: hir.TranslationUnit,
) -> mir.TranslationUnit:
    tu = mir.TranslationUnit()

    for module in res.modules.values():
        for typ in module.types.values():
            if mir_type := _translate_type(typ):
                tu.types.append(mir_type)

        for var in module.variables.values():
            tu.globals.append(_translate_globalvar(var))

        for func in module.funcs.values():
            tu.functions.append(_translate_func(func))

    return tu


def _translate_type(typ: resolver.StoredType) -> mir.Type | None:
    pass


def _translate_globalvar(var: resolver.Variable) -> mir.GlobalVar:
    pass


def _translate_func(src: resolver.Function) -> mir.Function:
    builder = FuncBuilder(src)
    builder.lower_block(src.definition.body)
    return builder.finish()


class FuncBuilder:
    @dataclass
    class WIPBlock:
        id: int
        ops: list[mir.Operation] = field(default_factory=list)
        done: bool = False

    def __init__(self, src: resolver.Function):
        self._tmp_num = itertools.count(1)
        self._var_num = itertools.count(1)
        self._block_num = itertools.count(1)
        self._vars: dict[int, mir.LocalVar] = {}
        self._params: dict[int, mir.Parameter] = {
            param.id: mir.Parameter(i, param.definition.type)
            for i, param in enumerate(src.params)
        }
        self._current_block: FuncBuilder.WIPBlock | None = None

        self.func = mir.Function(
            id=src.id,
            name=src.name,
            params=[*self._params.values()],
            returns=[],
            error=None,
        )

    def finish(self) -> mir.Function:
        self.func.blocks.sort(key=lambda b: b.id)
        return self.func

    def _newtmp(self, typ: ComptimeType) -> mir.Temporary:
        # TODO: translate the type
        return mir.Temporary(next(self._tmp_num), typ)

    def _newvar(self, decl: ast.LocalVariable) -> mir.LocalVar:
        assert decl.shadow_id, (
            f"local variable {decl.name} at {decl.start} should have been resolved by now"
        )
        var = mir.LocalVar(
            next(self._var_num), decl.name, decl.realized_type
        )  # TODO: ensure the realized type is translated
        self.func.locals.append(var)
        self._vars[decl.shadow_id] = var
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

    def lower_block(self, src: ast.Block):
        import rich

        start = self._newblock()
        defers = []

        for stmt in src.body:
            rich.print(stmt)
            match stmt:
                case ast.LocalConstant():
                    continue

                case ast.LocalVariable():
                    var = self._newvar(stmt)
                    if stmt.expr is None:
                        self._emit(mir.Clear(var))
                    elif isinstance(stmt.expr, ast.Expression):
                        self._emit(mir.Set(var, self._lower_expr(stmt.expr)))

                case ast.AssignStatement():
                    lvalue = self._lower_expr(stmt.dest)
                    assert isinstance(
                        lvalue, (mir.LocalVar, mir.GlobalVar, mir.Dereferenced)
                    )

                case ast.ReturnStatement():
                    retvals = [self._lower_expr(val_expr) for val_expr in stmt.values]
                    self._endblock(mir.Return(retvals))

                case _:
                    raise NotImplementedError(
                        f"{type(stmt).__name__} nodes not yet supported"
                    )

    def _lower_expr(
        self,
        expr: ast.Expression,
    ) -> mir.Operand:
        if not isinstance(expr.evaluated_value, ast.ValueSentinels):
            assert not isinstance(
                expr.required_type, (ast.TypeSentinels, types.FlexType)
            ), f"required type of {expr} should have been materialized by now"
            return self._constant(expr.evaluated_value, expr.required_type)

        match expr:
            case ast.NameExpr():
                resolved = expr.resolves_to
                match resolved:
                    case resolver.Variable():
                        if local := self._vars.get(resolved.id):
                            return local
                        if param := self._params.get(resolved.id):
                            return param

                raise NotImplementedError(
                    f"cannot find operand for name expression resolving to {resolved}"
                )

            case ast.BinopExpr():
                return self._binop_expr(expr)

            case ast.ScalarLiteralExpr() | ast.SimpleLiteralExpr():
                raise AssertionError(
                    "this should be hit by the evaluated_value check above"
                )

            case ast.UnitReinterpretExpr():
                # this is quite intentionally a no-op
                return self._lower_expr(expr.expr)

            case _:
                raise NotImplementedError(
                    f"{type(expr).__name__} expression nodes not yet supported"
                )

    def _constant(
        self,
        value: Fraction | ast.RuneValue | ByteValue | str | bool | NilOf,
        t: RealizedType,
    ) -> mir.Constant:
        type = types.underlying(t)
        match value, type:
            case Fraction(), _ if types.is_integer(type):
                return mir.Constant(value.numerator // value.denominator)
            case Fraction(), resolver.FixedDecimal(digits, prec):
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

            case NilOf(), _ if types.is_pointer(type):
                return mir.Constant(None)

            case _:
                print(value, type)
                raise NotImplementedError(f"cannot create constant operand for {t}")

    def _binop_expr(
        self,
        expr: ast.BinopExpr,
    ) -> mir.Operand:

        match expr.op:
            case ast.BinaryOp.Add:
                lhs = self._lower_expr(expr.lhs)
                rhs = self._lower_expr(expr.rhs)
                result = self._newtmp(expr.required_type)
                self._emit(mir.Add(result, lhs, rhs))
                return result

            case ast.BinaryOp.Subtract:
                lhs = self._lower_expr(expr.lhs)
                rhs = self._lower_expr(expr.rhs)
                result = self._newtmp(expr.required_type)
                self._emit(mir.Sub(result, lhs, rhs))
                return result

            case ast.BinaryOp.Multiply:
                lhs = self._lower_expr(expr.lhs)
                rhs = self._lower_expr(expr.rhs)
                result = self._newtmp(expr.required_type)
                self._emit(mir.Mul(result, lhs, rhs))
                return result

            case ast.BinaryOp.TrueDivide:
                lhs = self._lower_expr(expr.lhs)
                rhs = self._lower_expr(expr.rhs)
                result = self._newtmp(expr.required_type)
                self._emit(mir.Div(result, lhs, rhs))
                return result

            case ast.BinaryOp.FloorDivide:
                lhs = self._lower_expr(expr.lhs)
                rhs = self._lower_expr(expr.rhs)
                result = self._newtmp(expr.required_type)
                self._emit(mir.Div(result, lhs, rhs))

                if types.is_integer(expr.lhs.evaluated_type) and types.is_integer(
                    expr.lhs.evaluated_type
                ):
                    self._emit(mir.Truncate(result, result))

                return result

            case ast.BinaryOp.Remainder:
                lhs = self._lower_expr(expr.lhs)
                rhs = self._lower_expr(expr.rhs)
                result = self._newtmp(expr.required_type)
                self._emit(mir.Rem(result, lhs, rhs))
                return result

            case ast.BinaryOp.Modulo:
                lhs = self._lower_expr(expr.lhs)
                rhs = self._lower_expr(expr.rhs)
                result = self._newtmp(expr.required_type)
                self._emit(mir.Rem(result, lhs, rhs))

                before = self._current_block
                assert before

                negative = self._newblock()
                self._emit(mir.Add(result, result, rhs))

                after = self._newblock()

                self._endblock(
                    before,
                    mir.Compare(
                        result,
                        mir.Constant(0),
                        lt_branch=negative.id,
                        eq_branch=after.id,
                        gt_branch=after.id,
                    ),
                )
                self._endblock(negative, mir.Jump(after.id))

                self._setblock(after)

                return result

            case ast.BinaryOp.Is:
                pass
            case ast.BinaryOp.IsNot:
                pass

            case ast.BinaryOp.Equal:
                pass
            case ast.BinaryOp.NotEqual:
                pass
            case ast.BinaryOp.Less:
                pass
            case ast.BinaryOp.LessEqual:
                pass
            case ast.BinaryOp.Greater:
                pass
            case ast.BinaryOp.GreaterEqual:
                pass

            case ast.BinaryOp.And:
                pass
            case ast.BinaryOp.Or:
                pass

            case Never():
                raise AssertionError("unreachable")

        raise NotImplementedError(f"unable to handle binary operator {expr.op.value}")
