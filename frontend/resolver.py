from __future__ import annotations

from dataclasses import dataclass, field
from fractions import Fraction
import itertools
from pathlib import Path
from typing import NewType

from frontend.diagnostics import Diagnostic, Error
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
    definition: ast.Node


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

    def add_symbol(self, decl: ast.Declaration) -> Diagnostic | None:
        match decl:
            case ast.UnitTypeDecl() | ast.UnitTypeAliasDecl():
                if decl.name in self.unit_types:
                    return Error(f"unit type {decl.name} is already defined")
                if decl.name in self:
                    return Warning()


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

        module = Module(parser.load(path))
        self.modules[path] = module

        for imp in module.imports:
            self.require(imp.get_filepath())  # TODO

        return module

    def resolve_names(self) -> list[Diagnostic]:
        """Resolves qualified names to point to their definitions
        """

        diagnostics: list[Diagnostic] = []

        for module in self.modules.values():
            for decl in module.file.declarations:
                diag = module.add_symbol(decl)
                if diag:
                    diagnostics.append(diag)

        return diagnostics


    def _resolve_names(self, module: Module, node: ast.Node):
        """Resolves qualified names to point to their definitions
        """

    def canonicalize_units(self):
        """Give unique ids to all base units and simplify compound units
        """
