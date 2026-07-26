from __future__ import annotations

from dataclasses import dataclass, field
from decimal import Decimal
from os import PathLike
from pathlib import Path

from frontend.lexer import Location, Identifier


@dataclass(kw_only=True)
class File:
    source: Path | None
    imports: list[_Import] = field(default_factory=list)
    declarations: list[Declaration] = field(default_factory=list)


@dataclass(kw_only=True)
class Node:
    file: Path
    start: Location
    end: Location


@dataclass(kw_only=True)
class QualifiedName(Node):
    path: list[Identifier]


@dataclass(kw_only=True)
class _Import(Node):
    collection: Identifier
    package: PathLike


@dataclass(kw_only=True)
class ScopedImport(_Import):
    import_name: Identifier


@dataclass(kw_only=True)
class NamedImport(_Import):
    names: list[Identifier]


@dataclass(kw_only=True)
class AllImport(_Import):
    pass


@dataclass(kw_only=True)
class Declaration(Node):
    pass

@dataclass(kw_only=True)
class TypeDecl(Declaration):
    pass


@dataclass(kw_only=True)
class UnitTypeDecl(Declaration):
    name: Identifier


@dataclass(kw_only=True)
class UnitDecl(Declaration):
    """
    e.g.
    unit meter: length
    """
    name: Identifier
    unit_type: QualifiedName | None = None


@dataclass(kw_only=True)
class UnitAlias(Declaration):
    """
    e.g.
    unit newton is kg m / s^2
    """
    alias: Identifier
    base: CompoundUnit


@dataclass(kw_only=True)
class UnitConversion(Declaration):
    """
    e.g.
    unit radians = 3.14159265358979 * degrees / 180
    """
    dest: Identifier
    mult: Decimal | None = None
    src: QualifiedName
    div: Decimal | None = None


@dataclass(kw_only=True)
class UnitComponent(Node):
    base: QualifiedName
    exponent: int


@dataclass(kw_only=True)
class CompoundUnit(Node):
    components: list[UnitComponent]
