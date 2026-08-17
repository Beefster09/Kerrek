import itertools
from dataclasses import dataclass, field
from fractions import Fraction

from frontend import ast, mir, resolver
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
            tu.globals.append(_translate_var(var))

        for func in module.funcs.values():
            tu.functions.append(_translate_func(func))

    return tu


def _translate_type(typ: resolver.StoredType) -> mir.Type | None:
    pass


def _translate_var(var: resolver.Variable) -> mir.Variable:
    pass


def _translate_func(src: resolver.Function) -> mir.Function:
    builder = FuncBuilder(src)
    builder._ast_block(src.definition.body)
    return builder.finish()


@dataclass
class _WIPBlock:
    id: int
    ops: list[mir.Operation] = field(default_factory=list)
    done: bool = False


class FuncBuilder:
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
        self._vars: dict[int, mir.Variable] = {}

    def finish(self) -> mir.Function:
        self.func.blocks.sort(key=lambda b: b.id)
        return self.func

    def _newtmp(self, typ: mir.PrimitiveType) -> mir.Temporary:
        return mir.Temporary(next(self._tmp_num), typ)

    def _newvar(self, decl: ast.LocalVariable) -> mir.Variable:
        assert decl.shadow_id, (
            f"local variable {decl.name} at {decl.start} should have been resolved by now"
        )
        var = mir.Variable(
            next(self._var_num), decl.name, decl.realized_type
        )  # TODO: ensure the realized type is translated
        self.func.locals.append(var)
        self._vars[decl.shadow_id] = var
        return var

    def _newblock(self, ops: list[mir.Operation]) -> _WIPBlock:
        block = _WIPBlock(next(self._block_num), ops)
        return block

    def _endblock(self, block: _WIPBlock, end: mir.Terminator):
        assert not block.done, "ended block twice; this is a programming error"
        self.func.blocks.append(
            mir.Block(
                id=block.id,
                ops=block.ops,
                end=end,
            )
        )
        block.done = True

    def _ast_block(self, src: ast.Block):
        block_ops = []
        for stmt in src.body:
            match stmt:
                case ast.LocalConstant():
                    continue

                case ast.LocalVariable():
                    var = self._newvar(stmt)
                    if stmt.expr is None:
                        block_ops.append(mir.Clear(var))
                    elif isinstance(stmt.expr, ast.Expression):
                        self._assign_expr(block_ops, var, stmt.expr)

                case ast.AssignStatement():
                    pass

                case ast.AssignStatement():
                    raise NotImplementedError(
                        f"{type(stmt).__name__} nodes not yet supported"
                    )

    def _assign_expr(
        self,
        ops: list[mir.Operation],
        dest: mir.Operand,
        expr: ast.Expression,
    ):
        if not isinstance(expr.evaluated_value, ast.ValueSentinels):
            self._assign_const(ops, dest, expr.evaluated_value, expr.required_type)
            return

        match expr:
            case ast.BinopExpr():
                self._binop_expr(ops, dest, expr)

            case ast.ScalarLiteralExpr():
                import rich

                rich.print(expr)
                raise AssertionError(
                    "this should be hit by the evaluated_value check above"
                )

            case _:
                raise NotImplementedError(
                    f"{type(expr).__name__} nodes not yet supported"
                )

    def _assign_const(
        self,
        ops: list[mir.Operation],
        dest: mir.Operand,
        value: Fraction | ast.RuneValue | ByteValue | str | bool | NilOf,
        type: RealizedType,
    ):
        pass

    def _binop_expr(
        self,
        ops: list[mir.Operation],
        dest: mir.Operand,
        expr: ast.BinopExpr,
    ):
        match expr.op:
            case ast.BinaryOp.Add:
                pass
