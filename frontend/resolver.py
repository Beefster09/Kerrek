from __future__ import annotations

from collections import Counter
from dataclasses import dataclass, field
from pathlib import Path
from typing import ClassVar

from frontend import ast, diagnostics, hir, parser
from frontend.hir import SymbolID
from frontend.lexer import Identifier
from frontend.types import FixedDecimal, PrimitiveType


def _symbol_gen():
    sym_id = 10000  # 1-9999 reserved for builtins
    while True:
        yield SymbolID(sym_id)
        sym_id += 1


next_symbol = _symbol_gen().__next__


@dataclass(kw_only=True)
class PartialSymbol[T: ast.Node]:
    """A partially translated symbol with an id

    It references the AST node associated with the symbol id
    Its associated HIR isn't initially filled in
    """

    id: SymbolID = field(default_factory=next_symbol)
    name: Identifier
    ast: T  # generics used to shut up pyright on derived classes


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
class Constant:
    """A compile-time evaluated constant

    constants get evaluated down to typed constants in the HIR,
    therefore this is NOT a partial symbol
    """

    name: Identifier
    ast: ast.LocalConstant | ast.GlobalConstant


@dataclass(kw_only=True)
class Variable(PartialSymbol):
    ast: ast.LocalVariable | ast.GlobalVariable
    hir: hir.Variable | None = None


@dataclass(kw_only=True)
class UnitType(PartialSymbol):
    ast: ast.UnitTypeDecl
    hir: hir.UnitType | None = None


@dataclass(kw_only=True)
class BaseUnit(PartialSymbol):
    ast: ast.UnitDecl | ast.UnitConversionDef
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

SUPERSCRIPT_DIGITS = "⁰¹²³⁴⁵⁶⁷⁸⁹"
SUPERSCRIPT_NEGATIVE = "⁻"


def superscript_number(n: int) -> str:
    digits = []

    if n < 0:
        digits.append(SUPERSCRIPT_NEGATIVE)

    x = int(abs(n))
    while x > 0:
        digits.append(SUPERSCRIPT_DIGITS[x % 10])
        x //= 10

    return "".join(digits)


class CanonicalUnit(Counter[SymbolID]):
    _base_unit_names: ClassVar[dict[SymbolID, str]] = {}

    @classmethod
    def register_unit_name(cls, base_unit: BaseUnit):
        cls._base_unit_names[base_unit.id] = base_unit.ast.name

    def __str__(self):
        components = []
        for comp_id, exp in self.most_common():
            if exp == 0:
                continue

            unit_name = self._base_unit_names.get(comp_id, f"unit{comp_id}")

            if exp == 1:
                components.append(str(unit_name))
            else:
                components.append(f"{unit_name}{superscript_number(exp)}")

        if components:
            return " ".join(components)
        else:
            return "<ratio>"

    def __repr__(self):
        components = []
        for comp_id, exp in self.most_common():
            if exp == 0:
                continue

            unit_name = self._base_unit_names.get(comp_id, "<MISSING>")

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


type Named = PartialSymbol | Constant | Module | Builtin


@dataclass(kw_only=True)
class Module:
    file: ast.File
    name: Identifier
    imports: dict[Identifier, Module] = field(default_factory=dict)
    types: dict[Identifier, TypeDefinition] = field(default_factory=dict)
    funcs: dict[Identifier, Function] = field(default_factory=dict)
    constants: dict[Identifier, Constant] = field(default_factory=dict)
    variables: dict[Identifier, Variable] = field(default_factory=dict)
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
        yield from self.funcs.values()
        yield from self.constants.values()
        yield from self.variables.values()
        yield from self.unit_types.values()
        yield from self.unit_type_aliases.values()
        yield from self.base_units.values()
        yield from self.unit_aliases.values()
        yield from self.capabilities.values()


type Scope = dict[Identifier, Named]


class Resolver:
    def __init__(self, project_root: Path | None = None):
        self.project_root = project_root or Path.cwd()
        self.modules: dict[Path, Module] = {}
        self._deferred_unit_convs: list[ast.UnitConversionDef] = []

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
        for conv in self._deferred_unit_convs:
            pass  # TODO

        diagnostics.report()

    def partial_resolve(
        self,
        module: Module,
        node: ast.Node,
        *scopes: Scope,
    ) -> tuple[Named | None, tuple[Identifier, ...]]:
        """Resolves qualified names to point to their definitions"""
        match node:
            case ast.QualifiedName():
                return self._resolve_qualname(module, node, *scopes), ()

            case ast.NameExpr():
                return self.lookup(module, node.name, *scopes), ()

            case ast.FieldAccessExpr():
                base, rest = self.partial_resolve(module, node.base, *scopes)

                if base and (more := self._static_resolve_field(base, node.field)):
                    return more, ()
                else:
                    return base, (node.field, *rest)

            case _:
                return None, ()

    def resolve(
        self,
        module: Module,
        node: ast.Node,
        *scopes: Scope,
    ) -> Named | None:
        named, unresolved = self.partial_resolve(module, node, *scopes)

        if named and unresolved:
            diagnostics.error("cannot fully resolve this", node)
            return None

        return named

    def lookup(
        self,
        module: Module,
        base_name: Identifier,
        *scopes: Scope,
    ) -> Named | None:
        for scope in scopes:
            if base_name in scope:
                return scope[base_name]

        return module.lookup(base_name) or BUILTINS.get(base_name)

    def get_canonical_unit(
        self,
        module: Module,
        unit: ast.CompoundUnit,
        *,
        _orig_definition: ast.CompoundUnit | None = None,
        _seen_aliases: tuple[UnitAlias, ...] = (),
        _seen_alias_refs: tuple[ast.QualifiedName, ...] = (),
    ) -> CanonicalUnit | None:
        canonical = CanonicalUnit()

        for component in unit.components:
            resolved, _ = self.resolve(module, component)
            match resolved:
                case None:
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
                        resolved.canonical = self.get_canonical_unit(
                            module,
                            resolved.ast.orig,
                            _orig_definition=_orig_definition or unit,
                            _seen_aliases=(*_seen_aliases, resolved),
                            _seen_alias_refs=(*_seen_alias_refs, component.base),
                        )

                    assert resolved.canonical
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
                module.variables[decl.name] = Variable(name=decl.name, ast=decl)

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
                module.base_units[decl.name] = BaseUnit(name=decl.name, ast=decl)

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
        module: Module,
        qualname: ast.QualifiedName,
        *scopes: Scope,
    ) -> Named | None:
        base_name, *rest = qualname.path

        base = self.lookup(module, base_name, *scopes)

        if not base:
            diagnostics.error(f"cannot resolve '{base_name}'", qualname)
            return None

        resolved = base

        for i, field in enumerate(rest, 1):
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
