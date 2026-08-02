from __future__ import annotations

from collections import Counter
from dataclasses import dataclass, field
from fractions import Fraction
from pathlib import Path
from typing import Any, NewType

from frontend import diagnostics
from frontend import ast
from frontend import parser
from frontend.lexer import Identifier


SymbolID = NewType('SymbolID', int)
def _symbol_gen():
    sym_id = 1
    while True:
        yield SymbolID(sym_id)
        sym_id += 1

_NEXT_SYM = _symbol_gen()
SYMBOLS_BY_ID: dict[SymbolID, _Symbol] = {}

UNRESOLVED = object()


@dataclass(kw_only=True)
class _Symbol:
    id: SymbolID = field(default_factory=_NEXT_SYM.__next__)

    def __post_init__(self):
        SYMBOLS_BY_ID[self.id] = self


@dataclass(kw_only=True)
class Type(_Symbol):
    name: Identifier
    definition: ast.Node


@dataclass(kw_only=True)
class Function(_Symbol):
    name: Identifier
    definition: ast.Node


@dataclass(kw_only=True)
class Constant(_Symbol):
    name: Identifier
    type: Type | None = None
    value: Any = UNRESOLVED
    definition: ast.Node


@dataclass(kw_only=True)
class Variable(_Symbol):
    name: Identifier
    type: Type | None = None
    initial_value: Any = None
    definition: ast.Node


@dataclass(kw_only=True)
class UnitType(_Symbol):
    name: Identifier
    definition: ast.Node


@dataclass(kw_only=True)
class Unit(_Symbol):
    name: Identifier
    unit_type: UnitType | None = None
    definition: ast.Node
    conversions: dict[SymbolID, Fraction] = field(default_factory=dict)


@dataclass(kw_only=True)
class Capability(_Symbol):
    name: Identifier
    definition: ast.Node


@dataclass(kw_only=True)
class Module(_Symbol):
    file: ast.File
    name: Identifier
    imports: dict[Identifier, Module] = field(default_factory=dict)
    types: dict[Identifier, Type] = field(default_factory=dict)
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
        'Integer',
        'Int128',
        'Int64',
        'Int32',
        'Int16',
        'Int8',
        'UInt128',
        'UInt64',
        'UInt32',
        'UInt16',
        'UInt8',

        'Number',
        'Dec128',
        'Dec64',
        'Dec32',

        'Boolean',
        'String',

        # - ANNOTATIONS -
        'private',
        'deprecated',
        'forward',
    ]
}

WRITE_ONLY = Builtin(Identifier('_'))


@dataclass
class TemplateVar:
    name: Identifier


type Named = _Symbol | Builtin | TemplateVar

class CanonicalUnit(Counter[SymbolID]):
    def __str__(self):
        components = []
        for comp_id, exp in self.items():
            if exp == 0:
                continue

            unit = SYMBOLS_BY_ID[comp_id]
            unit_name = unit.name if isinstance(unit, (Unit, UnitType)) else '???'

            if exp == 1:
                components.append(str(unit_name))
            else:
                components.append(f"{unit_name}^{exp}")

        if components:
            return ' '.join(components)
        else:
            return '<ratio>'


class Resolver:
    def __init__(self, project_root: Path = Path.cwd()):
        self.project_root = project_root
        self.modules: dict[Path, Module] = {}

    def require(self, path: Path) -> Module:
        """Resolves imported modules and parses them if missing
        """
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
                    imp)

            module.imports[imp.namespace] = self.require(
                imp.get_filepath(self.project_root, path))

        return module

    def resolve_names(self):
        """Resolves qualified names to point to their definitions
        """

        for module in self.modules.values():
            for decl in module.file.declarations:
                self._add_symbol(module, decl)

        for module in self.modules.values():
            for decl in module.file.declarations:
                self._resolve_names(module, decl)


    def _resolve_names(
        self,
        module: Module,
        node: ast.Node,
        *scopes: dict[Identifier, Named],
    ):
        """Resolves qualified names to point to their definitions
        """
        match node:
            case ast.QualifiedName():
                self._resolve_name(module, node, *scopes)

            case ast.FuncDefinition():
                for annotation in node.annotations:
                    self._resolve_names(module, annotation, *scopes)

                params: dict[Identifier, Named] = {}
                templates: dict[Identifier, Named] = {}

                for param in node.params:
                    if param.name == '_':
                        diagnostics.error("placeholder ('_') is not a valid parameter name", node)
                        return

                    if param.name in params:
                        diagnostics.error(f"duplicate parameter name '{param.name}'", param)

                    params[param.name] = Variable(name=param.name, definition=param)

                    for sub in param.type_.walk():
                        if isinstance(sub, ast.SimpleTemplateType):
                            templates[sub.name] = TemplateVar(sub.name)

                    self._resolve_names(module, param.type_, templates, *scopes)

                for ret in node.return_types:
                    self._resolve_names(module, ret, templates, *scopes)

                if node.error_type is not ... and node.error_type is not None:
                    self._resolve_names(module, node.error_type, templates, *scopes)

                if node.capabilities_required:
                    self._resolve_names(module, node.capabilities_required, *scopes)

                self._resolve_names(module, node.body, params, templates, *scopes)

            case ast.Block():
                local_scope = {}
                for stmt in node.body:
                    self._resolve_names(module, stmt, local_scope, *scopes)

            case ast.LocalDeclaration():
                if node.name == '_':
                    diagnostics.error("placeholder ('_') is not a valid variable name", node)
                    return

                if node.type_:
                    self._resolve_names(module, node.type_, *scopes)
                if node.expr:
                    self._resolve_names(module, node.expr, *scopes)

                local_scope = scopes[0]
                if node.name in local_scope:
                    diagnostics.error(f"local with name '{node.name}' is already defined", node)
                    return
                elif any(node.name in scope for scope in scopes[1:]):
                    diagnostics.info(f"local '{node.name}' shadows previously defined local", node)
                elif node.name in module:
                    diagnostics.info(f"local '{node.name}' shadows module global", node)
                elif node.name in BUILTINS:
                    diagnostics.info(f"local '{node.name}' shadows builtin", node)

                if node.is_const:
                    if node.expr is None:
                        diagnostics.error(f"value of constant {node.name} not defined", node)
                        return

                    local_scope[node.name] = Constant(name=node.name, definition=node)
                else:
                    local_scope[node.name] = Variable(name=node.name, initial_value=node.expr, definition=node)

            case _:
                for sub in node.children():
                    self._resolve_names(module, sub, *scopes)

    def _resolve_name(
        self,
        module: Module,
        qualname: ast.QualifiedName,
        *scopes: dict[Identifier, Named],
    ):
        base_name, *rest = qualname.path

        if base_name == '_':
            if rest:
                diagnostics.error("placeholder ('_') does not support field access", qualname)
                return

            qualname.resolves_to = WRITE_ONLY
            return

        elif '_' in qualname.path:
            diagnostics.error("placeholder ('_') is not a valid accessible field", qualname)
            return

        for scope in scopes:
            if base_name in scope:
                base = scope[base_name]
                break
        else:
            base = module.lookup(base_name) or BUILTINS.get(base_name)

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
                diagnostics.info(f"{kind.__name__.lower()} '{name}' shadows a builtin", node)

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
                if decl.dest in module.units:
                    return  # you can duplicate unit names for conversions

                check_shadowing(decl, Unit, decl.dest)

                module.units[decl.dest] = Unit(name=decl.dest, definition=decl)

                # the actual conversion has to be resolved later

    def canonicalize_units(self):
        for module in self.modules.values():
            for decl in module.file.declarations:
                for node in decl.walk():
                    if isinstance(node, ast.CompoundUnit):
                        self._ensure_canonical_unit(node)

    def _ensure_canonical_unit(self, unit: ast.CompoundUnit):
        if unit.canonical is not None:
            return

        unit.canonical = CanonicalUnit()

        for component in unit.components:
            resolved = component.base.resolves_to
            if isinstance(resolved, (Unit, UnitType)):
                if isinstance(resolved.definition, ast.UnitAlias):
                    self._ensure_canonical_unit(resolved.definition.base)
                    assert resolved.definition.base.canonical is not None
                    unit.canonical += resolved.definition.base.canonical
                else:
                    unit.canonical[resolved.id] += component.exponent
            else:
                diagnostics.error(f"{component.base} is not a unit or unit type", component.base)
