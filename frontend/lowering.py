import itertools
from dataclasses import dataclass, field
from decimal import ROUND_HALF_UP, Decimal
from decimal import Context as DecCtx
from fractions import Fraction

from frontend import ast, mir, resolver, types
from frontend.exprs import ByteValue, NilOf, RealizedType


def translate_to_mir(
    res: resolver.Resolver,
    main_module: resolver.Module,
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
    builder._ast_block(src.definition.body)
    return builder.finish()


class FuncBuilder:
    @dataclass
    class WIPBlock:
        id: int
        ops: list[mir.Operation] = field(default_factory=list)
        done: bool = False

    def __init__(self, src: resolver.Function):
        self.func = mir.Function(
            id=src.id,
            params=[],
            returns=[],
            error=None,
        )
        self._tmp_num = itertools.count(1)
        self._var_num = itertools.count(1)
        self._block_num = itertools.count(1)
        self._vars: dict[int, mir.LocalVar] = {}
        self._current_block: FuncBuilder.WIPBlock | None = None

    def finish(self) -> mir.Function:
        self.func.blocks.sort(key=lambda b: b.id)
        return self.func

    def _newtmp(self, typ: mir.PrimitiveType) -> mir.Temporary:
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
        self._current_block = block

    def _endblock(self, block: WIPBlock, end: mir.Terminator):
        assert not block.done, "ended block twice; this is a programming error"
        self.func.blocks.append(
            mir.Block(
                id=block.id,
                ops=block.ops,
                end=end,
            )
        )
        block.done = True

    def _emit(self, op: mir.Operation):
        assert self._current_block, "NO CURRENT BLOCK"
        self._current_block.ops.append(op)

    def _ast_block(self, src: ast.Block):
        out = self._newblock()
        for stmt in src.body:
            match stmt:
                case ast.LocalConstant():
                    continue

                case ast.LocalVariable():
                    var = self._newvar(stmt)
                    if stmt.expr is None:
                        out.ops.append(mir.Clear(var))
                    elif isinstance(stmt.expr, ast.Expression):
                        self._assign_expr(out, var, stmt.expr)

                case ast.ReturnStatement():
                    pass

                case _:
                    raise NotImplementedError(
                        f"{type(stmt).__name__} nodes not yet supported"
                    )

    def _lower_expr(
        self,
        expr: ast.Expression,
    ) -> mir.Operand:
        if not isinstance(expr.evaluated_value, ast.ValueSentinels):
            return self._constant(expr.evaluated_value, expr.required_type)

        match expr:
            case ast.BinopExpr():
                self._binop_expr(expr)

            case ast.ScalarLiteralExpr() | ast.SimpleLiteralExpr():
                import rich

                rich.print(expr)
                raise AssertionError(
                    "this should be hit by the evaluated_value check above"
                )

            case _:
                raise NotImplementedError(
                    f"{type(expr).__name__} nodes not yet supported"
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
                return mir.Constant(
                    Decimal(value.numerator) / Decimal(value.denominator)
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
                return mir.Constant(0)

            case _:
                raise NotImplementedError(f"cannot create constant operand for {type}")

    def _binop_expr(
        self,
        expr: ast.BinopExpr,
    ) -> mir.Operand:
        match expr.op:
            case ast.BinaryOp.Add:
                pass
