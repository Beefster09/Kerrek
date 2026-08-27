from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
from typing import TYPE_CHECKING

from frontend import ast, diagnostics, hir, parser
from frontend.hir import SymbolID
from frontend.lexer import Identifier
from frontend.types import PrimitiveType
from frontend.units import CanonicalUnit

if TYPE_CHECKING:
    from frontend.exprs import FlexibleValue


def _symbol_gen():
    sym_id = 10000  # 1-9999 reserved for builtins
    while True:
        yield SymbolID(sym_id)
        sym_id += 1


next_symbol_id = _symbol_gen().__next__


@dataclass(kw_only=True)
class PartialSymbol[T: ast.Node]:
    """A partially translated symbol with an id

    It references the AST node associated with the symbol id
    Its associated HIR isn't initially filled in
    """

    id: SymbolID = field(default_factory=next_symbol_id)
    name: Identifier
    ast: T  # generics used to shut up pyright on derived classes
    processed: bool = False


@dataclass(kw_only=True)
class Function(PartialSymbol):
    ast: ast.FuncDefinition
    hir: hir.FuncDefinition | None = None


@dataclass(kw_only=True)
class DistinctType(PartialSymbol):
    ast: ast.DistinctTypeDecl
    hir: hir.DistinctType | None = None


@dataclass(kw_only=True)
class StructType(PartialSymbol):
    ast: ast.StructDefinition
    hir: hir.StructType | None = None


@dataclass(kw_only=True)
class EnumType(PartialSymbol):
    ast: ast.EnumDefinition
    hir: hir.EnumType | None = None


type TypeDefinition = DistinctType | StructType | EnumType


@dataclass(kw_only=True)
class Constant(PartialSymbol):
    ast: ast.LocalConstant | ast.GlobalConstant
    value: FlexibleValue | None = None


@dataclass(kw_only=True)
class GlobalVariable(PartialSymbol):
    ast: ast.GlobalVariable
    hir: hir.GlobalVariable | None = None


@dataclass(kw_only=True)
class LocalVariable(PartialSymbol):
    ast: ast.LocalVariable
    hir: hir.GlobalVariable | None


@dataclass(kw_only=True)
class UnitType(PartialSymbol):
    ast: ast.UnitTypeDecl
    hir: hir.UnitType | None = None


@dataclass(kw_only=True)
class BaseUnit(PartialSymbol):
    ast: ast.UnitDecl
    hir: hir.BaseUnit | None = None


@dataclass(kw_only=True)
class UnitTypeAlias(PartialSymbol):
    ast: ast.UnitTypeAliasDecl
    canonical: CanonicalUnit | None = None


@dataclass(kw_only=True)
class UnitAlias(PartialSymbol):
    ast: ast.UnitAlias
    canonical: CanonicalUnit | None = None  # This is filled in later
    # NOTE: these *might* still exist in the HIR for reflection purposes
    # e.g. printing a kg m / s^2 as newtons


@dataclass(kw_only=True)
class Capability(PartialSymbol):
    ast: ast.CapabilityDecl
    hir: hir.Capability | None = None


@dataclass(kw_only=True)
class Annotation(PartialSymbol):
    ast: ast.AnnotationDef
    hir: hir.AnnotationDef | None = None


@dataclass(kw_only=True)
class FormalParameter(PartialSymbol):
    ast: ast.FormalParameter
    hir: hir.FormalParameter


@dataclass(kw_only=True)
class NamedReturn(PartialSymbol):
    ast: ast.FuncReturn
    hir: hir.FuncReturn


@dataclass
class Builtin:
    name: Identifier


BUILTINS = {
    Identifier(name): Builtin(Identifier(name))
    for name in [
        # - TYPES -
        *(prim.value for prim in PrimitiveType if not prim.value.startswith("Float")),
        # - ANNOTATIONS -
        "deprecated",
        "forward",
        "pure",
        "layout",
        "calling_convention",
        # - FUNCTIONS -
        "len",
        "cap",
        "append",
        "owned_shallow_clone",
        "owned_deep_clone",
        "shared_shallow_clone",
        "shared_deep_clone",
    ]
}


type Named = PartialSymbol | Module | Builtin


@dataclass(kw_only=True)
class Module:
    file: ast.File
    name: Identifier
    imports: dict[Identifier, Module] = field(default_factory=dict)
    types: dict[Identifier, TypeDefinition] = field(default_factory=dict)
    funcs: dict[Identifier, Function] = field(default_factory=dict)
    constants: dict[Identifier, Constant] = field(default_factory=dict)
    variables: dict[Identifier, GlobalVariable] = field(default_factory=dict)
    unit_types: dict[Identifier, UnitType] = field(default_factory=dict)
    base_units: dict[Identifier, BaseUnit] = field(default_factory=dict)
    unit_aliases: dict[Identifier, UnitAlias] = field(default_factory=dict)
    unit_type_aliases: dict[Identifier, UnitTypeAlias] = field(default_factory=dict)
    capabilities: dict[Identifier, Capability] = field(default_factory=dict)

    def __contains__(self, name: Identifier) -> bool:
        return (
            name in self.imports
            or name in self.types
            or name in self.funcs
            or name in self.constants
            or name in self.variables
            or name in self.unit_types
            or name in self.base_units
            or name in self.unit_type_aliases
            or name in self.unit_aliases
            or name in self.capabilities
        )

    def lookup(self, name: Identifier) -> Named | None:
        if thing := self.imports.get(name):
            return thing

        if thing := self.types.get(name):
            return thing

        if thing := self.funcs.get(name):
            return thing

        if thing := self.constants.get(name):
            return thing

        if thing := self.variables.get(name):
            return thing

        if thing := self.unit_types.get(name):
            return thing

        if thing := self.base_units.get(name):
            return thing

        if thing := self.unit_type_aliases.get(name):
            return thing

        if thing := self.unit_aliases.get(name):
            return thing

        if thing := self.capabilities.get(name):
            return thing

        return None

    def lookup_using_imports(self, name: Identifier) -> Named | None:
        pass

    def __iter__(self):
        """iterate through all of the symbols *defined* by the module
        (does not include imports)
        """
        yield from self.types.values()
        yield from self.unit_types.values()
        yield from self.unit_type_aliases.values()
        yield from self.base_units.values()
        yield from self.unit_aliases.values()
        yield from self.constants.values()
        yield from self.variables.values()
        yield from self.capabilities.values()
        yield from self.funcs.values()


type Scope = dict[Identifier, PartialSymbol]


class Resolver:
    def __init__(self, project_root: Path | None = None):
        self.project_root = project_root or Path.cwd()
        self.modules: dict[Path, Module] = {}

    def require(self, path: Path) -> Module:
        """loads the file found at the given path and all of its imports, recursively"""
        path = path.absolute()

        if path in self.modules:
            return self.modules[path]

        module = Module(
            file=parser.load(path),
            name=Identifier(path.stem),
        )
        self.modules[path] = module

        for decl in module.file.declarations:
            self._add_symbol(module, decl)

        for imp in module.file.imports:
            if shadowed := module.imports.get(imp.namespace):
                diagnostics.error(
                    f"import of {imp.collection or '<relative>'}:{'/'.join(imp.module_path)}"
                    + f" conflicts with existing import of {shadowed.file.source}",
                    imp,
                )

            module.imports[imp.namespace] = self.require(
                imp.get_filepath(self.project_root, path)
            )

            # TODO: usings on imports

        return module

    def finish_imports(self):
        diagnostics.report()

    def partial_resolve(
        self,
        node: ast.Node,
        module: Module,
        *scopes: Scope,
    ) -> tuple[Named | None, tuple[Identifier, ...]]:
        """Resolves qualified names to point to their definitions"""
        match node:
            case ast.QualifiedName():
                return self._resolve_qualname(node, module, *scopes), ()

            case ast.NameExpr():
                return self.lookup(node.name, module, *scopes), ()

            case ast.FieldAccessExpr():
                base, rest = self.partial_resolve(node.base, module, *scopes)

                if base and (more := self._static_resolve_field(base, node.field)):
                    return more, ()
                else:
                    return base, (node.field, *rest)

            case _:
                return None, ()

    def resolve(
        self,
        node: ast.Node,
        module: Module,
        *scopes: Scope,
    ) -> Named | None:
        named, unresolved = self.partial_resolve(node, module, *scopes)

        if named and unresolved:
            diagnostics.error("cannot fully resolve this", node)
            return None

        return named

    def lookup(
        self,
        base_name: Identifier,
        module: Module,
        *scopes: Scope,
    ) -> Named | None:
        for scope in scopes:
            if base_name in scope:
                return scope[base_name]

        return module.lookup(base_name) or BUILTINS.get(base_name)

    def _add_symbol(self, module: Module, decl: ast.TopLevelDeclaration):
        def check_shadowing(node: ast.Node, name: Identifier):
            if shadowed := BUILTINS.get(name):
                diagnostics.notice(f"'{name}' shadows a builtin name", node)
            elif shadowed := module.lookup(name):
                err = diagnostics.error(
                    f"'{name}' conflicts with previously defined name in the module",
                    node,
                )
                if not isinstance(shadowed, (Module, Builtin)):
                    err.reference(f"'{name}' was previously defined here", shadowed.ast)

        match decl:
            case ast.FuncDefinition():
                check_shadowing(decl, decl.name)
                module.funcs[decl.name] = Function(name=decl.name, ast=decl)

            case ast.GlobalConstant():
                check_shadowing(decl, decl.name)
                module.constants[decl.name] = Constant(name=decl.name, ast=decl)

            case ast.GlobalVariable():
                check_shadowing(decl, decl.name)
                module.variables[decl.name] = GlobalVariable(name=decl.name, ast=decl)

            case ast.UnitTypeDecl():
                check_shadowing(decl, decl.name)

                module.unit_types[decl.name] = UnitType(name=decl.name, ast=decl)

            case ast.UnitTypeAliasDecl():
                check_shadowing(decl, decl.name)
                module.unit_type_aliases[decl.name] = UnitTypeAlias(
                    name=decl.name, ast=decl
                )

            case ast.UnitDecl():
                check_shadowing(decl, decl.name)
                base_unit = BaseUnit(name=decl.name, ast=decl)
                module.base_units[decl.name] = base_unit
                CanonicalUnit.register_unit_name(base_unit)

            case ast.UnitAlias():
                check_shadowing(decl, decl.name)
                module.unit_aliases[decl.name] = UnitAlias(name=decl.name, ast=decl)

            case _:
                raise NotImplementedError(f"cannot handle {type(decl).__name__} nodes")

    def _static_resolve_field(
        self,
        base: Named,
        field: Identifier,
    ):
        match base:
            case Module():
                return base.lookup(field)

            case BaseUnit() | UnitType() | Function() | Capability():
                # NOTE: this might be a redundant error
                diagnostics.error(
                    f"cannot get field '{field}' of '{base.name}'"
                    + f" because it is a {type(base).__name__},"
                    + " which never has a namespace",
                    base.ast,
                )

            case _:
                return None

    def _resolve_qualname(
        self,
        qualname: ast.QualifiedName,
        module: Module,
        *scopes: Scope,
    ) -> Named | None:
        base_name, *rest = qualname.path

        base = self.lookup(base_name, module, *scopes)

        if not base:
            diagnostics.error(f"cannot resolve '{base_name}'", qualname)
            return None

        resolved = base

        for i, field in enumerate(rest, 1):  # noqa: F402
            resolved = self._static_resolve_field(resolved, field)
            if not resolved:
                diagnostics.error(
                    f"cannot resolve '{'.'.join(qualname.path[:i])}'", qualname
                )
                return None

        return resolved

    def _build_type(self, type_expr: ast.TypeExpression) -> AnyType | ast.TypeSentinels:
        match type_expr:
            case ast.SimpleType():
                resolved = type_expr.type_name.resolves_to
                assert resolved is not None, "this should have been resolved by now"

                if isinstance(resolved, Builtin):
                    try:
                        return PrimitiveType[resolved.name]
                    except KeyError:
                        pass

                elif isinstance(resolved, TypeAlias):
                    if resolved.canonical is ast.TypeSentinels.NotDetermined:
                        resolved.canonical = self._eval_type_decl(resolved.definition)
                    return resolved.canonical

                elif isinstance(
                    resolved, (EnumType, StructType, DistinctType, GenericType)
                ):
                    return resolved

                diagnostics.error(
                    f"'{'.'.join(type_expr.type_name.path)}' does not name a type",
                    type_expr,
                )
                return ast.TypeSentinels.Impossible

            case ast.GenericType():
                return GenericType(type_expr.name)

            case _:
                raise NotImplementedError(
                    f"no support for {type(type_expr).__qualname__}"
                )
