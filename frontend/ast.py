from __future__ import annotations

from dataclasses import dataclass
from decimal import Decimal
from os import PathLike
from pathlib import Path

from frontend.lexer import Location, Identifier

struct = dataclass(kw_only=True)


@struct
class File:
    source: Path
    imports: list[_Import]
    declarations: dict[str, Declaration]


@struct
class Node:
    file: Path
    start: Location
    end: Location


@struct
class _Import(Node):
    collection: Identifier
    package: PathLike


@struct
class ScopedImport(_Import):
    import_name: Identifier


@struct
class NamedImport(_Import):
    names: list[Identifier]


@struct
class AllImport(_Import):
    pass


@struct
class Declaration(Node):
    pass

@struct
class TypeDecl(Declaration):
    pass


@struct
class DimensionDecl(Declaration):
    name: Identifier


@struct
class UnitDecl(Declaration):
    """
    e.g.
    unit meter: length
    """
    name: Identifier
    dimension: Identifier | None = None


@struct
class UnitAlias(Declaration):
    """
    e.g.
    unit newton is kg m / s^2
    """
    alias: Identifier
    bases: dict[Identifier, int]


@struct
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
