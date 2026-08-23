from __future__ import annotations

from dataclasses import dataclass
import traceback
from typing import Never

from frontend import ast, diagnostics, exprs, hir
from frontend.resolver import (
    Annotation,
    Builtin,
    Constant,
    Function,
    GlobalVariable,
    LocalVariable,
    Module,
    Named,
    PartialSymbol,
    Resolver,
    Scope,
    next_symbol_id,
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
        - overload selection
        """

        for module in self.resolver.modules.values():
            for symbol in module:
                try:
                    self._build_symbol(symbol, module)
                except NotImplementedError as err:
                    print(
                        f"in file '{module.file.source}',",
                        f"{type(symbol).__name__} '{symbol.name}':",
                        err,
                    )
                except Exception:  # noqa: BLE001
                    traceback.print_exc()

        if self.hir.entry_point is None:
            diagnostics.error(
                f"no entry point function was found in {self.main_module.file.source}",
                None,
                None,
            )

        diagnostics.report()
        return self.hir

    def _symbol_getter(self, module: Module, *scopes: Scope):
        def _get_symbol(node: ast.Node):
            symbol = self.resolver.resolve(node, module, *scopes)

            if symbol:
                self._build_symbol(symbol, module, *scopes)

            return symbol

        return _get_symbol

    def _build_symbol(
        self,
        symbol: Named,
        module: Module,
        *scopes: Scope,
    ) -> hir.Symbol | None:
        match symbol:
            case Function():
                if not symbol.hir:
                    self.hir.funcs[symbol.id] = symbol.hir = self._build_func(
                        symbol.ast,
                        module,
                        *scopes,
                        id=symbol.id,
                    )
                    if scopes:
                        scopes[0][symbol.name] = symbol

                return symbol.hir

            case Constant():
                if not symbol.value:
                    evaluated = exprs.evaluate(
                        symbol.ast.expr,
                        self._symbol_getter(module, *scopes),
                    )
                    if isinstance(evaluated, exprs.FlexibleValue):
                        symbol.value = evaluated
                    else:
                        diagnostics.error(
                            "this expression is not constant at compile-time",
                            symbol.ast.expr,
                        )

                return None

            case GlobalVariable():
                if not symbol.hir:
                    self.hir.variables[symbol.id] = symbol.hir = self._build_var(
                        symbol.ast,
                        module,
                        *scopes,
                        id=symbol.id,
                    )

                return symbol.hir

            case LocalVariable():
                # local vars should have already been fully resolved because they are built up by the block builder
                return symbol.hir

            case _:
                raise NotImplementedError(
                    f"cannot translate {type(symbol).__name__} symbols yet"
                )

    def _build_func(
        self,
        func: ast.FuncDefinition,
        module: Module,
        *scopes: Scope,
        id: hir.SymbolID | None = None,
    ) -> hir.FuncDefinition:
        annotations: list[hir.Annotation] = []

        for annotation in func.annotations:
            anno = self.resolver.resolve(annotation, module, *scopes)
            # TODO: process certain builtin annotations and attach the rest
            match anno:
                case Builtin():
                    # TODO: special logic for certain annotations
                    diagnostics.error(
                        f"builtin '{anno.name}' is not a valid function annotation",
                        annotation.base,
                    )

                case Annotation():
                    if anno.hir is None:
                        anno.hir = self._build_annotation_def(
                            anno.ast,
                            module,
                            *scopes,
                        )

                    anno_hir = hir.Annotation(
                        file=annotation.file,
                        start=annotation.start,
                        end=annotation.end,
                        of=anno.hir,
                        args=[],
                    )
                    annotations.append(anno_hir)

                case _:
                    diagnostics.error(
                        f"'{annotation.base}' is not an annotation",
                        annotation.base,
                    )

        params_scope: Scope = {}
        params: list[hir.FormalParameter] = []
        generics: Scope = {}

        for ast_param in func.params:
            if ast_param.name in params_scope:
                diagnostics.error(
                    f"duplicate parameter name '{ast_param.name}'", ast_param
                )

            ptype = self._build_type(ast_param.type, module, *scopes)

            if ast_param.unit:
                punit = self._build_unit(ast_param.unit, module, *scopes)
            else:
                punit = None

            if ast_param.default:
                pdefault = self._build_expr(ast_param.default, module, *scopes)
                if not isinstance(pdefault, hir.ConstExpr):
                    diagnostics.error(
                        f"default value for '{ast_param.name}' is not known at compile-time",
                        ast_param.default,
                    )
            else:
                pdefault = None

            hir_param = hir.FormalParameter(
                file=ast_param.file,
                start=ast_param.start,
                end=ast_param.end,
                id=next_symbol_id(),
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

        for ret in func.returns:
            rtype = self._build_type(ret.type, module, *scopes)

            if ret.unit:
                runit = self._build_unit(ret.unit, module, *scopes)
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

        if func.error_type is not None:
            err_type = self._build_type(
                func.error_type,
                module,
                generics,
                *scopes,
            )
        else:
            err_type = None

        requires = None
        if func.requires:
            pass  # TODO

        return hir.FuncDefinition(
            file=func.file,
            start=func.start,
            end=func.end,
            id=id or next_symbol_id(),
            name=func.name,
            params=params,
            returns=returns,
            error_type=err_type,
            fallible=func.fallible,
            requires=requires,
            body=self._build_block(
                func.body,
                module,
                params_scope,
                generics,
                *scopes,
            ),
            annotations=annotations,
        )

    def _build_var(
        self,
        var: ast.GlobalVariable | ast.LocalVariable,
        module: Module,
        *scopes: Scope,
        id: hir.SymbolID | None = None,
    ) -> hir.Variable:
        if var.type:
            var_type = self._build_type(var.type, module, *scopes)
        else:
            var_type = None

        match var.expr:
            case ast.UnboundVar():
                value = None
                if var_type is None:
                    diagnostics.error("unbound variables must have a type", var)

            case ast.Expression():
                value = self._build_expr(
                    var.expr,
                    module,
                    *scopes,
                )
                if value.is_single_value() and var_type is None:
                    var_type = exprs.infer_type(value.type, var)

            case None:
                if var_type is None:
                    diagnostics.error(
                        "variables must specify a type or an initial value"
                        + " that implies a type",
                        var,
                    )
                elif exprs.is_zeroable(var_type):
                    value = hir.ZeroOf(
                        file=var.file,
                        start=var.end,
                        end=var.end,
                        type=var_type,
                    )
                else:
                    diagnostics.error(
                        f"variable '{var.name}' has a non-zeroable type and"
                        + " therefore must be given an initial value or be"
                        + " explicitly unbound",
                        var,
                    )

            case Never():
                raise AssertionError("unreachable")

        return hir.Variable(
            file=var.file,
            start=var.start,
            end=var.end,
            id=id or next_symbol_id(),
            name=var.name,
            type=var_type,
            unit=unit,
            expr=value,
            annotations=[],  # TODO
        )

    def _build_type(
        self,
        type: ast.TypeExpression,
        module: Module,
        *scopes: Scope,
    ) -> hir.Type: ...

    def _build_unit(
        self,
        unit: ast.CompoundUnit,
        module: Module,
        *scopes: Scope,
    ) -> hir.CompoundUnit: ...

    def _build_expr(
        self,
        expr: ast.Expression,
        module: Module,
        *scopes: Scope,
    ) -> hir.Expression: ...

    def _build_block(
        self,
        block: ast.Block,
        module: Module,
        *scopes: Scope,
    ) -> hir.Block:
        return None
        if isinstance(node.type, ast.TypeExpression):
            self._resolve_names(module, node.type, *scopes)

        if node.expr:
            self._resolve_names(module, node.expr, *scopes)

        local_scope = scopes[0]
        if node.name in local_scope:
            diagnostics.error(f"local with name '{node.name}' is already defined", node)
            return
        elif any(node.name in scope for scope in scopes[1:]):
            diagnostics.notice(
                f"local '{node.name}' shadows previously defined local", node
            )
        elif node.name in module:
            diagnostics.notice(f"local '{node.name}' shadows module global", node)
        elif node.name in BUILTINS:
            diagnostics.warning(f"local '{node.name}' shadows builtin", node)

        if isinstance(node, ast.LocalConstant):
            local_scope[node.name] = Constant(name=node.name, definition=node)
        else:
            var = Variable(name=node.name, definition=node)
            local_scope[node.name] = var
            node.shadow_id = var.id

    def _build_annotation_def(
        self,
        anno_def: ast.AnnotationDef,
        module: Module,
        *scopes: Scope,
    ) -> hir.AnnotationDef: ...


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
