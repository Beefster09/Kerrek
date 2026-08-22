from __future__ import annotations

from dataclasses import dataclass

from frontend import ast, diagnostics, exprs, hir
from frontend.lexer import Identifier
from frontend.resolver import (
    Builtin,
    Constant,
    Function,
    Module,
    Named,
    PartialSymbol,
    Resolver,
    Scope,
    Variable,
    next_symbol,
)


@dataclass(kw_only=True)
class FormalParameter(PartialSymbol):
    ast: ast.FormalParameter
    hir: hir.FormalParameter


@dataclass(kw_only=True)
class NamedReturn(PartialSymbol):
    ast: ast.FuncReturn
    hir: hir.FuncReturn


class HIRBuilder:
    def __init__(self, res: Resolver, main: Module):
        self.resolver = res
        self.main_module = main
        self.hir = hir.TranslationUnit()

    def build(self) -> hir.TranslationUnit:
        """builds up a typed HIR from the ast+resolver
        - named references are replaced with links to other parts of the HIR
        - dependency cycles are detected
        - constant evaluation
        - type checking and inference
        - unit analysis
        """

        for module in self.resolver.modules.values():
            for symbol in module:
                self._process_symbol(module, symbol)

        if self.hir.entry_point is None:
            diagnostics.error(
                f"no entry point function was found in {self.main_module.file.source}",
                None,
                None,
            )

        diagnostics.report()
        return self.hir

    def _process_symbol(
        self,
        module: Module,
        symbol: Named,
        *scopes: Scope,
    ):
        match symbol:
            case Function(ast=node):
                annotations: list[hir.Annotation] = []

                for annotation in node.annotations:
                    anno = self.resolver.resolve(module, annotation, *scopes)
                    # TODO: process certain builtin annotations and attach the rest
                    match anno:
                        case Builtin():
                            pass  # TODO: check validity and do something with this
                        case Annotation():
                            anno_hir = hir.Annotation(
                                file=annotation.file,
                                start=annotation.start,
                                end=annotation.end,
                                of=symbol.hir,
                                args=[],
                            )
                            annotations.append(anno_hir)

                params_scope: Scope = {}
                params: list[hir.FormalParameter] = []
                generics: Scope = {}

                for ast_param in node.params:
                    if ast_param.name in params_scope:
                        diagnostics.error(
                            f"duplicate parameter name '{ast_param.name}'", ast_param
                        )

                    ptype = self._build_type(module, ast_param.type, *scopes)

                    if ast_param.unit:
                        punit = self._build_unit(module, ast_param.unit, *scopes)
                    else:
                        punit = None

                    if ast_param.default:
                        pdefault = self._build_value(module, ast_param.default, *scopes)
                    else:
                        pdefault = None

                    hir_param = hir.FormalParameter(
                        file=ast_param.file,
                        start=ast_param.start,
                        end=ast_param.end,
                        id=next_symbol(),
                        name=ast_param.name,
                        type=ptype,
                        unit=punit,
                        default=pdefault,
                    )
                    param = FormalParameter(
                        id=hir_param.id,
                        name=ast_param.name,
                        ast=ast_param,
                        hir=hir_param,
                    )

                    params_scope[ast_param.name] = param
                    params.append(param.hir)

                returns: list[hir.FuncReturn] = []
                named_returns: Scope = {}

                for ret in node.returns:
                    rtype = self._build_type(module, ret.type, *scopes)

                    if ret.unit:
                        runit = self._build_unit(module, ret.unit, *scopes)
                    else:
                        runit = None

                    hir_ret = hir.FuncReturn(
                        file=ret.file,
                        start=ret.start,
                        end=ret.end,
                        type=rtype,
                        unit=runit,
                    )
                    returns.append(hir_ret)

                    if ret.name is not None:
                        named_returns[ret.name] = NamedReturn(
                            name=ret.name,
                            ast=ret,
                            hir=hir_ret,
                        )

                if node.error_type is not None:
                    err_type = self._build_type(
                        module,
                        node.error_type,
                        generics,
                        *scopes,
                    )
                else:
                    err_type = None

                requires = None
                if node.requires:
                    pass  # TODO

                func = hir.FuncDefinition(
                    file=node.file,
                    start=node.start,
                    end=node.end,
                    id=symbol.id,
                    name=node.name,
                    params=params,
                    returns=returns,
                    error_type=err_type,
                    fallible=node.fallible,
                    requires=requires,
                    body=self._build_block(module, node.body, *scopes, params_scope),
                    annotations=annotations,
                )
                symbol.hir = func
                self.hir.funcs[symbol.id] = func

            case Variable(ast=node):
                if isinstance(node.type, ast.TypeExpression):
                    self._resolve_names(module, node.type, *scopes)

                if node.expr:
                    self._resolve_names(module, node.expr, *scopes)

                local_scope = scopes[0]
                if node.name in local_scope:
                    diagnostics.error(
                        f"local with name '{node.name}' is already defined", node
                    )
                    return
                elif any(node.name in scope for scope in scopes[1:]):
                    diagnostics.notice(
                        f"local '{node.name}' shadows previously defined local", node
                    )
                elif node.name in module:
                    diagnostics.notice(
                        f"local '{node.name}' shadows module global", node
                    )
                elif node.name in BUILTINS:
                    diagnostics.warning(f"local '{node.name}' shadows builtin", node)

                if isinstance(node, ast.LocalConstant):
                    local_scope[node.name] = Constant(name=node.name, definition=node)
                else:
                    var = Variable(name=node.name, definition=node)
                    local_scope[node.name] = var
                    node.shadow_id = var.id

            case _:
                raise NotImplementedError(
                    f"cannot translate {type(symbol).__name__} symbols yet"
                )

    def _build_type(
        self,
        module: Module,
        type: ast.TypeExpression,
        *scopes: Scope,
    ) -> hir.Type: ...

    def _build_unit(
        self,
        module: Module,
        type: ast.CompoundUnit,
        *scopes: Scope,
    ) -> hir.CompoundUnit: ...

    def _build_value(
        self,
        module: Module,
        type: ast.Expression,
        *scopes: Scope,
    ) -> hir.Value: ...

    def _build_block(
        self,
        module: Module,
        type: ast.Block,
        *scopes: Scope,
    ) -> hir.Block: ...


@dataclass(kw_only=True)
class VarState:
    declaration: ast.LocalVariable
    possibly_unbound: bool = False  # likely needs to be a more complicated type but i'm just sketching it out


@dataclass(kw_only=True)
class ParamVar:
    declaration: ast.FormalParameter


def validate_hir(node: hir.TranslationUnit):
    """does all of the core validation of the code:
    - value label provenance checking
    - capability tracking
    - unused variables (just a warning)
    """

    diagnostics.report()


def validate(node: hir.Node):
    match node:
        case hir.Variable():
            if node.expr and not isinstance(node.expr, ast.UnboundVar):
                exprs.evaluate(node.expr)

        case hir.FuncDefinition():
            params_scope: Scope = {}
            for param in node.params:
                if param.default:
                    result = exprs.evaluate(param.default)
                    exprs.check_type(param.type, result.type, param)
                    params_scope[param.name] = ParamVar(declaration=param)

            _validate_block(node, node.body, params_scope)


def _validate_block(func: ast.FuncDefinition, block: ast.Block, *scopes: Scope):
    local_scope: Scope = {}
    for stmt in block.body:
        match stmt:
            case ast.Block():
                _validate_block(func, stmt, local_scope, *scopes)

            case ast.LocalConstant():
                result = exprs.evaluate(stmt.expr)
                if stmt.type:
                    exprs.check_type(stmt.type, result.type, stmt)

            case ast.LocalVariable():
                if isinstance(stmt.expr, ast.UnboundVar):
                    local_scope[stmt.name] = VarState(
                        declaration=stmt,
                        possibly_unbound=True,
                    )
                elif stmt.expr:
                    result = exprs.evaluate(stmt.expr)

                    if stmt.type is None:
                        typ = exprs.infer_type(result.type, stmt)
                        stmt.realized_type = typ
                    else:
                        typ = exprs.check_type(stmt.type, result.type, stmt)
                        assert not isinstance(typ, exprs.FlexType)
                        stmt.realized_type = typ

                    local_scope[stmt.name] = VarState(declaration=stmt)

            case ast.AssignStatement():
                lresults = [exprs.evaluate(dest) for dest in stmt.dests]
                rresults = [exprs.evaluate(expr) for expr in stmt.exprs]

            case ast.ReturnStatement():
                if len(stmt.values) < len(func.returns):
                    diagnostics.error(
                        "return statement has too few values"
                        + f" (expected {len(func.returns)}, got {len(stmt.values)})",
                        stmt,
                    )
                    continue

                if len(stmt.values) > len(func.returns):
                    diagnostics.error(
                        "return statement has too many values"
                        + f" (expected {len(func.returns)}, got {len(stmt.values)})",
                        stmt,
                    )
                    continue

                for ret, value in zip(func.returns, stmt.values, strict=True):
                    result = exprs.evaluate(value)
                    typ = exprs.check_type(ret.type, result.type, value)
                    assert not isinstance(typ, exprs.FlexType)
                    value.required_type = typ

            case _:
                diagnostics.error(
                    f"cannot analyze {type(stmt).__name__} statements",
                    stmt,
                )
