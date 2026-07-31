from __future__ import annotations

from dataclasses import dataclass, field
from fractions import Fraction
import itertools
from pathlib import Path
from typing import NewType

from frontend.diagnostics import Diagnostic, Error, Warning, Info
from frontend.lexer import Identifier
from frontend import ast
from frontend import parser


SymbolID = NewType('SymbolID', int)
_symbol_gen = itertools.count(0)


@dataclass(kw_only=True)
class Type:
    id: SymbolID = field(default_factory=lambda: SymbolID(next(_symbol_gen)))
    name: Identifier
    definition: ast.Node


@dataclass(kw_only=True)
class Function:
    id: SymbolID = field(default_factory=lambda: SymbolID(next(_symbol_gen)))
    name: Identifier
    definition: ast.Node


@dataclass(kw_only=True)
class Constant:
    id: SymbolID = field(default_factory=lambda: SymbolID(next(_symbol_gen)))
    name: Identifier
    definition: ast.Node


@dataclass(kw_only=True)
class Variable:
    id: SymbolID = field(default_factory=lambda: SymbolID(next(_symbol_gen)))
    name: Identifier
    type: Type | None = None
    initial_value: ast.Node | None = None


@dataclass(kw_only=True)
class UnitType:
    id: SymbolID = field(default_factory=lambda: SymbolID(next(_symbol_gen)))
    name: Identifier
    definition: ast.Node


@dataclass(kw_only=True)
class Unit:
    id: SymbolID = field(default_factory=lambda: SymbolID(next(_symbol_gen)))
    name: Identifier
    unit_type: UnitType | None = None
    definition: ast.Node
    conversions: dict[SymbolID, Fraction] = field(default_factory=dict)


@dataclass(kw_only=True)
class Capability:
    id: SymbolID = field(default_factory=lambda: SymbolID(next(_symbol_gen)))
    name: Identifier
    definition: ast.Node


@dataclass
class Module:
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

type Named = (
    Module
    | Type
    | Function
    | Constant
    | Variable
    | UnitType
    | Unit
    | Capability
)


class Resolver:
    def __init__(self, project_root: Path = Path.cwd()):
        self.project_root = project_root
        self.modules: dict[Path, Module] = {}
        self.diagnostics: list[Diagnostic] = []

    def require(self, path: Path) -> Module:
        """Resolves imported modules and parses them if missing
        """
        path = path.absolute()

        if path in self.modules:
            return self.modules[path]

        module = Module(parser.load(path), Identifier(path.stem))
        self.modules[path] = module

        for imp in module.file.imports:
            if shadowed := module.imports.get(imp.namespace):
                message = f"import of {imp.package} shadows existing import of {shadowed.file.source}"
                self.diagnostics.append(Error(message, imp))

            module.imports[imp.namespace] = self.require(imp.get_filepath())

        return module

    def resolve_names(self) -> list[Diagnostic]:
        """Resolves qualified names to point to their definitions
        """

        diagnostics: list[Diagnostic] = []

        for module in self.modules.values():
            for decl in module.file.declarations:
                self._add_symbol(module, decl)

        for module in self.modules.values():
            for decl in module.file.declarations:
                self._resolve_names(module, decl)

        return diagnostics


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
                params: dict[Identifier, Named] = {}

                for param in node.params:
                    if param.name in params:
                        self.diagnostics.append(Error(f"duplicate parameter name '{param.name}'", param))
                    params[param.name] = Variable(name=param.name)

                    self._resolve_names(module, param.type_, *scopes)

                for ret in node.return_types:
                    self._resolve_names(module, ret, *scopes)

                if node.error_type is not ... and node.error_type is not None:
                    self._resolve_names(module, node.error_type, *scopes)

                if node.capabilities_required:
                    self._resolve_names(module, node.capabilities_required, *scopes)

                self._resolve_names(module, node.body, params, *scopes)

            case ast.Block():
                local_scope = {}
                for stmt in node.body:
                    self._resolve_names(module, stmt, local_scope, *scopes)

            case ast.LocalDeclaration():
                if node.type_:
                    self._resolve_names(module, node.type_, *scopes)
                if node.expr:
                    self._resolve_names(module, node.expr, *scopes)

                local_scope = scopes[0]
                if node.name in local_scope:
                    self.diagnostics.append(Error(f"local with name {node.name} is already defined", node))
                    return

                if node.is_const:
                    if node.expr is None:
                        self.diagnostics.append(Error(f"constant {node.name} not defined", node))
                        return

                    local_scope[node.name] = Constant(name=node.name, definition=node.expr)
                else:
                    local_scope[node.name] = Variable(name=node.name, initial_value=node.expr)

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

        for scope in scopes:
            if base_name in scope:
                base = scope[base_name]
                break
        else:
            base = module.lookup(base_name)

        if not base:
            self.diagnostics.append(Error(f"cannot resolve '{'.'.join(qualname.path)}'", qualname))
            return

        resolved = base

        if rest:
            raise NotImplementedError("qualified name traversal not yet supported")

        qualname.resolves_to = resolved

    def _add_symbol(self, module: Module, decl: ast.Declaration):
        def check_shadowing(node: ast.Node, kind: type, name: Identifier) -> Diagnostic | None:
            if shadowed := module.lookup(name):
                self.diagnostics.append(
                    Error(f"{kind.__name__} '{name}' shadows {type(shadowed).__name__} '{shadowed.name}'", node)
                )

        match decl:
            case ast.FuncDefinition():
                if diag := check_shadowing(decl, Function, decl.name):
                    return diag

                module.funcs[decl.name] = Function(name=decl.name, definition=decl)

            case ast.UnitTypeDecl() | ast.UnitTypeAliasDecl():
                if diag := check_shadowing(decl, UnitType, decl.name):
                    return diag

                module.unit_types[decl.name] = UnitType(name=decl.name, definition=decl)

            case ast.UnitDecl() | ast.UnitAlias():
                if diag := check_shadowing(decl, Unit, decl.name):
                    return diag

                module.units[decl.name] = Unit(name=decl.name, definition=decl)

            case ast.UnitConversion():
                if decl.dest in module.units:
                    return

                if diag := check_shadowing(decl, Unit, decl.dest):
                    return diag

                module.units[decl.dest] = Unit(name=decl.dest, definition=decl)

                # the actual conversion has to be resolved later

    def canonicalize_units(self):
        """Give unique ids to all base units and simplify compound units
        """
