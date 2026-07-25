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
class DimensionDecl(Declaration):
    name: Identifier


@dataclass(kw_only=True)
class UnitDecl(Declaration):
    """
    e.g.
    unit meter: length
    """
    name: Identifier
    dimension: Identifier | None = None


@dataclass(kw_only=True)
class UnitAlias(Declaration):
    """
    e.g.
    unit newton is kg m / s^2
    """
    alias: Identifier
    bases: dict[Identifier, int]


@dataclass(kw_only=True)
class UnitConversion(Declaration):
    """
    e.g.
    unit fahrenheit = 9 * celsius / 5 + 32
    """
    dest: Identifier
    mult: Decimal | None = None
    src: Identifier
    div: Decimal | None = None
    offset: Decimal | None = None
