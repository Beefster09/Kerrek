from __future__ import annotations

from collections import Counter
from dataclasses import dataclass, field
from enum import Enum, auto
from fractions import Fraction
from pathlib import Path
from typing import Any, Literal, NewType

from frontend import ast, diagnostics, parser
from frontend.lexer import Identifier

SymbolID = NewType("SymbolID", int)


def _symbol_gen():
    sym_id = 1
    while True:
        yield SymbolID(sym_id)
        sym_id += 1


_NEXT_SYM = _symbol_gen()
SYMBOLS_BY_ID: dict[SymbolID, _Symbol] = {}


class PrimitiveType(Enum):
    Integer = "Integer"
    Int64 = "Int64"
    Int32 = "Int32"
    Int16 = "Int16"
    Int8 = "Int8"
    UInt64 = "UInt64"
    UInt32 = "UInt32"
    UInt16 = "UInt16"
    UInt8 = "UInt8"

    Decimal = "Decimal"
    Dec64 = "Dec64"
    Dec32 = "Dec32"

    Float64 = "Float64"
    Float32 = "Float32"

    Boolean = "Boolean"
    String = "String"
    Rune = "Rune"
    Byte = "Byte"

    Opaque = "Opaque"
    Opaque8 = "Opaque8"
    Opaque16 = "Opaque16"
    Opaque32 = "Opaque32"
    Opaque64 = "Opaque64"


@dataclass
class FixedDecimal:
    digits: int
    precision: int


@dataclass(kw_only=True)
class _Symbol:
    id: SymbolID = field(default_factory=_NEXT_SYM.__next__)

    def __post_init__(self):
        SYMBOLS_BY_ID[self.id] = self


@dataclass(kw_only=True)
class StructType(_Symbol):
    name: Identifier
    definition: ast.StructDefinition


@dataclass(kw_only=True)
class EnumType(_Symbol):
    name: Identifier
    definition: ast.EnumDefinition


@dataclass(kw_only=True)
class InterfaceType(_Symbol):
    name: Identifier
    definition: ast.InterfaceDefinition


@dataclass(kw_only=True)
class DistinctType(_Symbol):
    name: Identifier
    definition: ast.DistinctTypeDecl


@dataclass(kw_only=True)
class TypeAlias(_Symbol):
    name: Identifier
    canonical: AnyType | ast.TypeSentinels = ast.TypeSentinels.NotDetermined
    definition: ast.TypeAliasDecl


BaseType = (
    PrimitiveType | FixedDecimal | EnumType | StructType | DistinctType | InterfaceType
)


@dataclass(kw_only=True)
class PointerType:
    to: AnyType
    ownership: ast.PointerOwnership


@dataclass(kw_only=True)
class OptionalType:
    of: AnyType


@dataclass(kw_only=True)
class FixedArrayType:
    elem: AnyType
    shape: tuple[int, ...]


@dataclass(kw_only=True)
class DynamicArrayType:
    elem: AnyType
    ownership: ast.PointerOwnership


@dataclass(kw_only=True)
class DimensionedArrayType:
    elem: AnyType
    dimensions: int = 1
    ownership: ast.PointerOwnership


@dataclass(kw_only=True)
class MapType:
    key: AnyType
    value: AnyType
    ownership: ast.PointerOwnership


type CompoundType = (
    PointerType
    | OptionalType
    | FixedArrayType
    | DynamicArrayType
    | DimensionedArrayType
    | MapType
)

type AnyType = CompoundType | BaseType | GenericType


@dataclass(kw_only=True)
class Function(_Symbol):
    name: Identifier
    definition: ast.FuncDefinition
    params: list[Variable] | None = None


@dataclass(kw_only=True)
class Constant(_Symbol):
    name: Identifier
    definition: ast.GlobalConstant | ast.LocalConstant


@dataclass(kw_only=True)
class Variable(_Symbol):
    name: Identifier
    definition: ast.GlobalVariable | ast.LocalVariable | ast.FormalParameter


@dataclass(kw_only=True)
class UnitType(_Symbol):
    name: Identifier
    definition: ast.Node


@dataclass(kw_only=True)
class Unit(_Symbol):
    name: Identifier
    unit_type: UnitType | None = None
    definition: ast.UnitDecl | ast.UnitAlias | ast.UnitConversionDef
    conversions: dict[SymbolID, Fraction] = field(default_factory=dict)


@dataclass(kw_only=True)
class Capability(_Symbol):
    name: Identifier
    definition: ast.Node


StoredType = EnumType | StructType | DistinctType | TypeAlias


@dataclass(kw_only=True)
class Module(_Symbol):
    file: ast.File
    name: Identifier
    imports: dict[Identifier, Module] = field(default_factory=dict)
    types: dict[Identifier, StoredType] = field(default_factory=dict)
    funcs: dict[Identifier, Function] = field(default_factory=dict)
    constants: dict[Identifier, Constant] = field(default_factory=dict)
    variables: dict[Identifier, Variable] = field(default_factory=dict)
    unit_types: dict[Identifier, UnitType] = field(default_factory=dict)
    units: dict[Identifier, Unit] = field(default_factory=dict)
    capabilities: dict[Identifier, Capability] = field(default_factory=dict)

    def __contains__(self, name: Identifier):
        return (
            name in self.imports
            or name in self.types
            or name in self.funcs
            or name in self.constants
            or name in self.variables
            or name in self.unit_types
            or name in self.units
            or name in self.capabilities
        )

    def lookup(self, name: Identifier):
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

        if thing := self.units.get(name):
            return thing

        if thing := self.capabilities.get(name):
            return thing

        return None

    def __iter__(self):
        yield from self.types.values()
        yield from self.funcs.values()
        yield from self.constants.values()
        yield from self.variables.values()
        yield from self.unit_types.values()
        yield from self.units.values()
        yield from self.capabilities.values()


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
        "owned_shallow_clone",
        "owned_deep_clone",
        "shared_shallow_clone",
        "shared_deep_clone",
    ]
}

WRITE_ONLY = Builtin(Identifier("_"))


@dataclass
class GenericType:
    name: Identifier
    bound: AnyType | None = None


Named = _Symbol | Builtin | GenericType | AnyType


class CanonicalUnit(Counter[SymbolID]):
    def __str__(self):
        components = []
        for comp_id, exp in self.most_common():
            if exp == 0:
                continue

            unit = SYMBOLS_BY_ID[comp_id]
            unit_name = unit.name if isinstance(unit, (Unit, UnitType)) else "???"

            if exp == 1:
                components.append(str(unit_name))
            else:
                components.append(f"{unit_name}^{exp}")

        if components:
            return " ".join(components)
        else:
            return "<ratio>"

    def __repr__(self):
        components = []
        for comp_id, exp in self.most_common():
            if exp == 0:
                continue

            unit = SYMBOLS_BY_ID[comp_id]
            unit_name = unit.name if isinstance(unit, (Unit, UnitType)) else "???"

            if exp == 1:
                components.append(str(unit_name))
            else:
                components.append(f"{unit_name}^{exp}")

        if components:
            return f"unit({' '.join(components)})"
        else:
            return "unit()"

    def __mul__(self, exponent: int):
        result = CanonicalUnit()

        for comp, exp in self.items():
            result[comp] += exp * exponent

        return result

    __rmul__ = __mul__

    def inplace_combine(self, other: CanonicalUnit, exponent: int):
        for comp, exp in other.items():
            self[comp] += exp * exponent

    @staticmethod
    def combine(
        a: CanonicalUnit,
        a_exp: int,
        b: CanonicalUnit,
        b_exp: int,
    ) -> CanonicalUnit:
        result = CanonicalUnit()

        for comp, exp in a.items():
            result[comp] += exp * a_exp

        for comp, exp in b.items():
            result[comp] += exp * b_exp

        return result


class Resolver:
    def __init__(self, project_root: Path = Path.cwd()):
        self.project_root = project_root
        self.modules: dict[Path, Module] = {}
        self._deferred_unit_convs: list[ast.UnitConversionDef] = []

    def require(self, path: Path) -> Module:
        """Resolves imported modules and parses them if missing"""
        path = path.absolute()

        if path in self.modules:
            return self.modules[path]

        module = Module(
            file=parser.load(path),
            name=Identifier(path.stem),
        )
        self.modules[path] = module

        for imp in module.file.imports:
            if shadowed := module.imports.get(imp.namespace):
                diagnostics.error(
                    f"import of {'/'.join(imp.module_path)}"
                    + f" conflicts with existing import of {shadowed.file.source}",
                    imp,
                )

            module.imports[imp.namespace] = self.require(
                imp.get_filepath(self.project_root, path)
            )

        return module

    def resolve_names(self):
        """Resolves qualified names to point to their definitions"""

        for module in self.modules.values():
            for decl in module.file.declarations:
                self._add_symbol(module, decl)

        for module in self.modules.values():
            for decl in module.file.declarations:
                self._resolve_names(module, decl)

        diagnostics.report()

    def _resolve_names(
        self,
        module: Module,
        node: ast.Node,
        *scopes: dict[Identifier, Named],
    ):
        """Resolves qualified names to point to their definitions"""
        match node:
            case ast.QualifiedName():
                self._resolve_qualname(module, node, *scopes)

            case ast.NameExpr():
                resolved = self._lookup_scoped(module, node.name, *scopes)

                if resolved:
                    node.resolves_to = resolved
                else:
                    diagnostics.error(f"cannot resolve name '{node.name}'", node)

            case ast.FieldAccessExpr():
                self._resolve_names(module, node.base, *scopes)

                match node.base:  # TODO
                    case ast.NameExpr():
                        pass
                    case ast.FieldAccessExpr() if node.static_resolves_to is not None:
                        pass

            case ast.FuncDefinition():
                for annotation in node.annotations:
                    self._resolve_names(module, annotation, *scopes)

                params: dict[Identifier, Named] = {}
                templates: dict[Identifier, Named] = {}

                for param in node.params:
                    if param.name == "_":
                        diagnostics.error(
                            "placeholder ('_') is not a valid parameter name", node
                        )
                        return

                    if param.name in params:
                        diagnostics.error(
                            f"duplicate parameter name '{param.name}'", param
                        )

                    params[param.name] = Variable(name=param.name, definition=param)

                    for sub in param.type.walk():
                        if isinstance(sub, ast.GenericType):
                            templates[sub.name] = GenericType(sub.name)

                    self._resolve_names(module, param.type, templates, *scopes)
                    if param.unit:
                        self._resolve_names(module, param.unit, templates, *scopes)

                for ret in node.returns:
                    self._resolve_names(module, ret, templates, *scopes)

                if node.error_type is not ... and node.error_type is not None:
                    self._resolve_names(module, node.error_type, templates, *scopes)

                if node.requires:
                    self._resolve_names(module, node.requires, *scopes)

                self._resolve_names(module, node.body, params, templates, *scopes)

            case ast.Block():
                local_scope = {}
                for stmt in node.body:
                    self._resolve_names(module, stmt, local_scope, *scopes)

            case ast.LocalVariable() | ast.LocalConstant():
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
                for sub in node:
                    self._resolve_names(module, sub, *scopes)

    def _lookup_scoped(
        self,
        module: Module,
        base_name: Identifier,
        *scopes: dict[Identifier, Named],
    ) -> Named | None:
        for scope in scopes:
            if base_name in scope:
                return scope[base_name]

        return module.lookup(base_name) or BUILTINS.get(base_name)

    def _resolve_qualname(
        self,
        module: Module,
        qualname: ast.QualifiedName,
        *scopes: dict[Identifier, Named],
    ):
        base_name, *rest = qualname.path

        base = self._lookup_scoped(module, base_name, *scopes)

        if not base:
            diagnostics.error(f"cannot resolve '{'.'.join(qualname.path)}'", qualname)
            return

        resolved = base

        if rest:
            raise NotImplementedError("qualified name traversal not yet supported")

        qualname.resolves_to = resolved

    def _add_symbol(self, module: Module, decl: ast.TopLevelDeclaration):
        def check_shadowing(node: ast.Node, kind: type, name: Identifier):
            if shadowed := module.lookup(name):
                diagnostics.warning(
                    f"{kind.__name__.lower()} '{name}' shadows {type(shadowed).__name__} '{shadowed.name}'",
                    node,
                )
            elif shadowed := BUILTINS.get(name):
                diagnostics.notice(
                    f"{kind.__name__.lower()} '{name}' shadows a builtin", node
                )

        match decl:
            case ast.FuncDefinition():
                check_shadowing(decl, Function, decl.name)

                module.funcs[decl.name] = Function(name=decl.name, definition=decl)

            case ast.UnitTypeDecl() | ast.UnitTypeAliasDecl():
                check_shadowing(decl, UnitType, decl.name)

                module.unit_types[decl.name] = UnitType(name=decl.name, definition=decl)

            case ast.UnitDecl() | ast.UnitAlias():
                check_shadowing(decl, Unit, decl.name)

                module.units[decl.name] = Unit(name=decl.name, definition=decl)

            case ast.UnitConversionDef():
                self._deferred_unit_convs.append(decl)

                if decl.dest in module.units:
                    return  # you can duplicate unit names for conversions

                check_shadowing(decl, Unit, decl.dest)

                module.units[decl.dest] = Unit(name=decl.dest, definition=decl)

    def canonicalize_types(self):
        for module in self.modules.values():
            for typ in module.types.values():
                self._eval_type_decl(typ.definition)

            for named in module.variables.values():
                for node in named.definition.walk():
                    if isinstance(node, ast.TypeExpression):
                        self._ensure_type_built(node)

            for named in module.constants.values():
                for node in named.definition.walk():
                    if isinstance(node, ast.TypeExpression):
                        self._ensure_type_built(node)

            for named in module.funcs.values():
                for node in named.definition.walk():
                    if isinstance(node, ast.TypeExpression):
                        self._ensure_type_built(node)

        diagnostics.report()

    def _eval_type_decl(self, decl: ast.TypeDeclaration) -> AnyType | ast.TypeSentinels:
        match decl:
            case ast.TypeAliasDecl():
                return self._ensure_type_built(decl.orig_type)

            case ast.DistinctTypeDecl():
                return self._ensure_type_built(decl.underlying)

            case ast.StructDefinition():
                diagnostics.error("unable to evaluate struct declaration", decl)
                raise NotImplementedError("TODO")

            case ast.EnumDefinition():
                diagnostics.error("unable to evaluate enum declaration", decl)
                raise NotImplementedError("TODO")

            case _:
                diagnostics.error("unable to evaluate type declaration", decl)
                raise NotImplementedError("TODO")

    def _ensure_type_built(
        self, type_expr: ast.TypeExpression
    ) -> AnyType | ast.TypeSentinels:
        if type_expr.canonical is None:
            type_expr.canonical = self._build_type(type_expr)

        return type_expr.canonical

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

    def canonicalize_units(self):
        for module in self.modules.values():
            for decl in module.file.declarations:
                for node in decl.walk():
                    if isinstance(node, ast.CompoundUnit):
                        self._ensure_canonical_unit(node)

        diagnostics.report()

    def _ensure_canonical_unit(self, unit: ast.CompoundUnit):
        if unit.canonical is not None:
            return

        unit.canonical = CanonicalUnit()

        for component in unit.components:
            resolved = component.base.resolves_to
            assert resolved is not None, "this should have been resolved by now"
            if isinstance(resolved, (Unit, UnitType)):
                if isinstance(resolved.definition, ast.UnitAlias):
                    self._ensure_canonical_unit(resolved.definition.base)
                    assert resolved.definition.base.canonical is not None
                    unit.canonical.inplace_combine(
                        resolved.definition.base.canonical,
                        component.exponent,
                    )
                else:
                    unit.canonical[resolved.id] += component.exponent
            else:
                diagnostics.error(
                    f"'{'.'.join(component.base.path)}' does not name a unit or unit type",
                    component.base,
                )

    def build_unit_conversions(self):
        for conv in self._deferred_unit_convs:
            pass  # TODO

        diagnostics.report()
