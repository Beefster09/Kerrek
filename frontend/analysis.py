from __future__ import annotations

import builtins
import traceback
from dataclasses import dataclass
from typing import Never, overload

import rich

from frontend import ast, diagnostics, exprs, hir
from frontend.common import get_first
from frontend.resolver import (
    BUILTINS,
    Annotation,
    BaseUnit,
    Builtin,
    Constant,
    FormalParameter,
    Function,
    GlobalVariable,
    LocalVariable,
    Module,
    Named,
    NamedReturn,
    PartialSymbol,
    Resolver,
    Scope,
    UnitAlias,
    UnitType,
    UnitTypeAlias,
    next_symbol_id,
)
from frontend.types import PrimitiveType
from frontend.units import CanonicalUnit, IndeterminateUnit


class HIRBuilder:
    def __init__(self, res: Resolver, main: Module):
        self.resolver = res
        self.main_module = main
        self.hir = hir.TranslationUnit()
        self.symbols_by_id: dict[hir.SymbolID, PartialSymbol] = {}

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
                    self._ensure_symbol_processed(symbol, module)

                    # if hasattr(symbol, "hir"):
                    #     rich.print(symbol.hir)
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
        def _get_symbol(ref: ast.Node | hir.SymbolID):
            if isinstance(ref, ast.Node):
                return self._resolve_and_process(ref, module, *scopes)
            else:
                return self.symbols_by_id.get(ref)

        return _get_symbol

    def _resolve_and_process(self, node: ast.Node, module: Module, *scopes: Scope):
        symbol = self.resolver.resolve(node, module, *scopes)

        if symbol:
            self._ensure_symbol_processed(symbol, module, *scopes)

        return symbol

    def _ensure_symbol_processed(
        self,
        symbol: Named,
        module: Module,
        *scopes: Scope,
    ) -> None:
        if isinstance(symbol, (Module, Builtin)):
            return
        elif isinstance(symbol, PartialSymbol):
            if symbol.processed:
                return
            else:
                symbol.processed = True
                self.symbols_by_id[symbol.id] = symbol

        match symbol:
            case Function():
                symbol.hir = self._build_func(
                    symbol.ast,
                    module,
                    *scopes,
                    id=symbol.id,
                )
                if symbol.hir:
                    self.hir.funcs[symbol.id] = symbol.hir

                if scopes:
                    scopes[0][symbol.name] = symbol

            case UnitType():
                symbol.hir = hir.UnitType(
                    **symbol.ast.where(),
                    id=symbol.id,
                    name=symbol.name,
                )
                self.hir.unit_types[symbol.id] = symbol.hir

                if scopes:
                    scopes[0][symbol.name] = symbol

            case UnitTypeAlias() | UnitAlias():
                if scopes:
                    scopes[0][symbol.name] = symbol

            case BaseUnit():
                if symbol.ast.unit_type:
                    utype = self._resolve_and_process(
                        symbol.ast.unit_type, module, *scopes
                    )
                    if not isinstance(utype, UnitType):
                        diagnostics.error(
                            f"base unit declaration cannot be based on a {type(utype).__name__}",
                            symbol.ast.unit_type,
                        )
                        return
                    else:
                        utype = utype.hir
                else:
                    utype = None

                symbol.hir = hir.BaseUnit(
                    **symbol.ast.where(),
                    id=symbol.id,
                    name=symbol.name,
                    type=utype,
                )
                self.hir.units[symbol.id] = symbol.hir

                if scopes:
                    scopes[0][symbol.name] = symbol

            case Constant():
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

            case GlobalVariable():
                symbol.hir = self._build_var(
                    symbol.ast,
                    module,
                    *scopes,
                    id=symbol.id,
                )
                if symbol.hir:
                    self.hir.variables[symbol.id] = symbol.hir

            case LocalVariable() | FormalParameter():
                # local vars and params should have already been fully resolved
                # because they are built up by the block/func builder
                pass

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
    ) -> hir.FuncDefinition | None:
        annotations: list[hir.Annotation] = []
        should_assert_func_is_pure = False

        for annotation in func.annotations:
            anno = self.resolver.resolve(annotation.base, module, *scopes)
            # TODO: process certain builtin annotations and attach the rest
            match anno:
                case Builtin():
                    # TODO: special logic for certain annotations
                    match anno.name:
                        case "pure":
                            should_assert_func_is_pure = True
                            diagnostics.notice(
                                "note: pure function verification is not yet implemented",
                                annotation,
                            )
                        case _:
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
                continue

            ptype = self._build_type(ast_param.type, module, *scopes)
            if ptype is None:
                continue

            if ast_param.unit:
                punit = self._build_unit(ast_param.unit, module, *scopes)
                if punit is None:
                    continue
            else:
                continue

            if ast_param.default:
                pdefault = self._build_expr(ast_param.default, module, *scopes)
                if not isinstance(pdefault, hir.ConstExpr):
                    diagnostics.error(
                        f"default value for '{ast_param.name}' is not known at compile-time",
                        ast_param.default,
                    )
                    continue
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
                processed=True,
            )

            params_scope[ast_param.name] = param
            params.append(param.hir)

        returns: list[hir.FuncReturn] = []
        named_returns: Scope = {}

        for ret in func.returns:
            rtype = self._build_type(ret.type, module, *scopes)
            runit = self._build_unit(ret.unit, module, *scopes)

            if rtype is None:
                continue

            if runit is None:
                diagnostics.error("unit missing on func return", ret)
                continue

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

        result = hir.FuncDefinition(
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
            body=...,  # pyright: ignore[reportArgumentType] - treat as unbound
            annotations=annotations,
        )
        result.body = self._build_block(
            func.body,
            result,
            module,
            params_scope,
            generics,
            *scopes,
        )

        if func.name == "main" and module is self.main_module and not scopes:
            self._set_entry_point(result)

        if should_assert_func_is_pure:
            pass  # TODO

        return result

    @overload
    def _build_var(
        self,
        var: ast.GlobalVariable,
        module: Module,
        *scopes: Scope,
        id: hir.SymbolID | None = None,
    ) -> hir.GlobalVariable | None: ...

    @overload
    def _build_var(
        self,
        var: ast.LocalVariable,
        module: Module,
        *scopes: Scope,
        id: hir.SymbolID | None = None,
    ) -> hir.LocalVariable | None: ...

    def _build_var(
        self,
        var: ast.GlobalVariable | ast.LocalVariable,
        module: Module,
        *scopes: Scope,
        id: hir.SymbolID | None = None,
    ) -> hir.GlobalVariable | hir.LocalVariable | None:
        if var.type:
            var_type = self._build_type(var.type, module, *scopes)
        else:
            var_type = None

        if isinstance(var.unit, ast.CompoundUnit):
            unit = self._build_unit(var.unit, module, *scopes)
            if unit is None:
                return None
        else:
            unit = var.unit

        match var.expr:
            case ast.UnboundVar():
                value = None

                if var_type is None:
                    diagnostics.error("unbound variables must have a type", var)
                    return None

                if unit is IndeterminateUnit.Inferred:
                    unit = IndeterminateUnit.NoUnit

            case ast.Expression():
                match value := self._build_expr(
                    var.expr,
                    module,
                    *scopes,
                ):
                    case hir.SingleValueExpression():
                        var_type = exprs.infer_type(value.type, var)

                        if unit is IndeterminateUnit.Inferred:
                            unit = value.unit
                    case hir.MultiValueExpression():
                        match value_count := len(value.types):
                            case 0:
                                diagnostics.error(
                                    "this expression results in no values and"
                                    + f" therefore cannot be assigned to '{var.name}'",
                                    var.expr,
                                )
                                return None
                            case 1:
                                var_type = exprs.infer_type(value.types[0], var)

                                if unit is IndeterminateUnit.Inferred:
                                    unit = value.units[0]
                            case _:
                                diagnostics.error(
                                    f"this expression results in {value_count} values and"
                                    + f" therefore cannot be assigned to '{var.name}'",
                                    var.expr,
                                )
                                return None
                    case _:
                        raise NotImplementedError(
                            f"cannot assign {type(value).__name__} to variables"
                        )

                if var_type is None:
                    # type inference or prior evaluation should have reported an error by now
                    return None

            case None:
                if var_type is None:
                    diagnostics.error(
                        "variables must specify a type or an initial value"
                        + " that implies a type",
                        var,
                    )
                    return None
                elif exprs.is_zeroable(var_type):
                    if unit is IndeterminateUnit.Inferred:
                        unit = IndeterminateUnit.Flexible

                    value = hir.ConstExpr(
                        file=var.file,
                        start=var.end,
                        end=var.end,
                        value=hir.ZeroOf(var_type),
                        type=var_type,
                        unit=unit,
                    )
                else:
                    diagnostics.error(
                        f"variable '{var.name}' has a non-zeroable type and"
                        + " therefore must be given an initial value or be"
                        + " explicitly unbound",
                        var,
                    )
                    return None

            case Never():
                raise AssertionError("unreachable")

        assert unit is not IndeterminateUnit.Inferred and unit is not None, (
            "unit should have been inferred by now"
        )

        if isinstance(var, ast.GlobalVariable):
            if value is None:
                diagnostics.error("global variables may not be unbound", var)
                return None

            return hir.GlobalVariable(
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
        else:
            return hir.LocalVariable(
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
    ) -> hir.Type | None:
        match type:
            case ast.SimpleType():
                resolved = self._resolve_and_process(type.type_name, module, *scopes)

                match resolved:
                    case Builtin():
                        try:
                            return hir.SimpleType(PrimitiveType[resolved.name])
                        except KeyError:
                            diagnostics.error(
                                f"'{type.type_name}' names a builtin that is not a primitive type",
                                type.type_name,
                            )
                            return None
                    case _:
                        diagnostics.error(
                            f"'{type.type_name}' does not name a valid type",
                            type.type_name,
                        )
                        return None

            case _:
                raise NotImplementedError(
                    f"cannot build type from {builtins.type(type).__name__} yet"
                )

    def _build_unit(
        self,
        unit: ast.DeclaredUnit,
        module: Module,
        *scopes: Scope,
    ) -> hir.RealizedUnit | None:
        if unit is IndeterminateUnit.Inferred:
            return IndeterminateUnit.Flexible  # TODO: this logic is context-dependent
        elif isinstance(unit, IndeterminateUnit):
            return unit

        get_symbol = self._symbol_getter(module, *scopes)
        canonical = exprs.get_canonical_unit(unit, get_symbol)
        if canonical is not None:
            return exprs.materialize_unit(canonical, get_symbol)
        else:
            return None

    def _build_expr(
        self,
        expr: ast.Expression,
        module: Module,
        *scopes: Scope,
    ) -> hir.Expression | None:
        get_symbol = self._symbol_getter(module, *scopes)
        match result := exprs.evaluate(expr, get_symbol):
            case exprs.FlexibleValue():
                return result.materialize(expr, get_symbol)
            case hir.Expression() | None:
                return result

            case Never():
                raise AssertionError("unreachable")

    def _build_block(
        self,
        block: ast.Block,
        func: hir.FuncDefinition,
        module: Module,
        *scopes: Scope,
    ) -> hir.Block:
        local_scope: Scope = {}
        body: list[hir.Statement] = []
        get_symbol = self._symbol_getter(module, local_scope, *scopes)

        def _new_local(symbol: PartialSymbol):
            nonlocal local_scope

            if symbol.name in local_scope:
                diagnostics.error(
                    f"local with name '{symbol.name}' is already defined", symbol.ast
                ).reference(
                    f"'{symbol.name}' was previously defined here",
                    local_scope[symbol.name].ast,
                )
                return
            elif shadowed := get_first(scopes, symbol.name):
                diagnostics.notice(
                    f"local '{symbol.name}' shadows previously defined local",
                    symbol.ast,
                ).reference(
                    f"'{symbol.name}' was previously defined here",
                    shadowed.ast,
                )
            elif symbol.name in module:
                notice = diagnostics.notice(
                    f"local '{symbol.name}' shadows module global", symbol.ast
                )
                match referenced := module.lookup(symbol.name):
                    case PartialSymbol():
                        notice.reference(
                            f"'{symbol.name}' was previously defined here",
                            referenced.ast,
                        )
            elif symbol.name in BUILTINS:
                diagnostics.warning(
                    f"local '{symbol.name}' shadows builtin", symbol.ast
                )

            local_scope[symbol.name] = symbol

        for stmt in block.body:
            match stmt:
                case ast.Block():
                    body.append(
                        self._build_block(stmt, func, module, local_scope, *scopes)
                    )

                case ast.LocalConstant():
                    evaluated = exprs.evaluate(stmt.expr, get_symbol)

                    if isinstance(evaluated, exprs.FlexibleValue):
                        _new_local(
                            Constant(
                                name=stmt.name,
                                ast=stmt,
                                value=evaluated,
                                processed=True,
                            )
                        )
                    else:
                        diagnostics.error(
                            "this expression is not constant at compile-time",
                            stmt.expr,
                        )

                case ast.LocalVariable():
                    var = self._build_var(stmt, module, local_scope, *scopes)
                    if var:
                        body.append(var)
                        _new_local(
                            LocalVariable(
                                name=stmt.name,
                                ast=stmt,
                                hir=var,
                                processed=True,
                            )
                        )

                case ast.AssignStatement():
                    lresults = [exprs.evaluate(dest, get_symbol) for dest in stmt.dests]
                    rresults = [exprs.evaluate(expr, get_symbol) for expr in stmt.exprs]

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
                        result = exprs.evaluate(value, get_symbol)

                case _:
                    raise NotImplementedError(
                        f"block builder doesn't handle {type(stmt).__name__} yet"
                    )

        return hir.Block(**block.where(), body=body)

    def _build_annotation_def(
        self,
        anno_def: ast.AnnotationDef,
        module: Module,
        *scopes: Scope,
    ) -> hir.AnnotationDef: ...

    def _set_entry_point(self, func: hir.FuncDefinition):
        if self.hir.entry_point:
            diagnostics.error(
                "an entry point has already been defined", func
            ).reference("entry point was previously defined here", self.hir.entry_point)
            # this probably can't be triggered normally, but it's a good check
            return

        # TODO: check that the func signature is valid as an entry point

        self.hir.entry_point = func


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
        case hir.GlobalVariable():
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


def _validate_block(func: hir.FuncDefinition, block: ast.Block, *scopes: Scope):
    for stmt in block.body:
        match stmt:
            case _:
                pass
