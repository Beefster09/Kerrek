from __future__ import annotations

from dataclasses import dataclass, field
from decimal import Decimal
from os import PathLike
from pathlib import Path
from types import EllipsisType

from frontend.lexer import Location, Identifier, Numeric


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
class TypeAlias(Declaration):
    pass

@dataclass(kw_only=True)
class DistinctTypeDecl(Declaration):
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


@dataclass(kw_only=True)
class Expression(Node):
    pass


@dataclass(kw_only=True)
class ScalarExpr(Expression):
    value: Numeric
    unit: CompoundUnit | None


@dataclass(kw_only=True)
class SimpleLiteralExpr(Expression):
    value: str | bool | None


@dataclass(kw_only=True)
class TypeExpression(Node):
    pass


@dataclass(kw_only=True)
class SimpleType(TypeExpression):
    type_name: QualifiedName
    unit: CompoundUnit | None = None


@dataclass(kw_only=True)
class CapabilityExpression(Node):
    pass


@dataclass(kw_only=True)
class Statement(Node):
    pass


@dataclass(kw_only=True)
class ReturnStatement(Statement):
    value: Expression | None


@dataclass(kw_only=True)
class Block(Statement):
    body: list[Statement]


@dataclass(kw_only=True)
class FormalParameter(Node):
    name: Identifier
    type_: TypeExpression
    default: Expression | None = None


@dataclass(kw_only=True)
class FuncDefinition(Declaration):
    name: Identifier
    params: list[FormalParameter]
    return_types: list[TypeExpression]
    error_type: TypeExpression | EllipsisType | None = None  # Ellipsis as the error type indicates the function can fail but the error type is void
    capabilities_required: CapabilityExpression | None = None
    body: Block
