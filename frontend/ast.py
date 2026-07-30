from __future__ import annotations

from dataclasses import dataclass, field
from decimal import Decimal
from enum import Enum, auto
from os import PathLike
from pathlib import Path
from types import EllipsisType
from typing import Any

from frontend.lexer import Location, Identifier, Numeric


@dataclass(kw_only=True)
class File:
    source: Path | None = field(repr=False)
    imports: list[_Import] = field(default_factory=list)
    declarations: list[Declaration] = field(default_factory=list)


@dataclass(kw_only=True)
class Node:
    file: Path = field(repr=False)
    start: Location = field(repr=False)
    end: Location = field(repr=False)

    @classmethod
    def from_node(cls, base: Node, **other):
        return cls(
            file=base.file,
            start=base.start,
            end=base.end,
            **other,
        )


@dataclass(kw_only=True)
class QualifiedName(Node):
    path: list[Identifier]

    resolves_to: Any = field(default=None, repr=False)


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
class UnitTypeAliasDecl(Declaration):
    name: Identifier
    base: CompoundUnit


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
    src: QualifiedName
    mult: Decimal = Decimal(1)
    div: Decimal = Decimal(1)


@dataclass(kw_only=True)
class UnitComponent(Node):
    base: QualifiedName
    exponent: int


@dataclass(kw_only=True)
class CompoundUnit(Node):
    components: list[UnitComponent]
    is_absolute: bool


@dataclass(kw_only=True)
class Expression(Node):
    pass


@dataclass(kw_only=True)
class UndefinedValue(Expression):
    pass


@dataclass(kw_only=True)
class QualnameExpr(Expression):
    name: QualifiedName


@dataclass(kw_only=True)
class ScalarExpr(Expression):
    value: Numeric
    unit: CompoundUnit | None


@dataclass(kw_only=True)
class SimpleLiteralExpr(Expression):
    value: str | bool | None


class Operator(Enum):
    Add = auto()
    Subtract = auto()
    Multiply = auto()
    Divide = auto()
    FloorDivide = auto()
    Modulo = auto()
    Exponent = auto()

    Equal = auto()
    NotEqual = auto()
    Less = auto()
    LessEqual = auto()
    Greater = auto()
    GreaterEqual = auto()

    And = auto()
    Or = auto()


@dataclass(kw_only=True)
class BinopExpr(Expression):
    lhs: Expression
    rhs: Expression
    op: Operator


@dataclass(kw_only=True)
class CastExpr(Expression):
    expr: Expression
    to: TypeExpression


@dataclass(kw_only=True)
class TypeExpression(Node):
    pass


@dataclass(kw_only=True)
class SimpleType(TypeExpression):
    type_name: QualifiedName


@dataclass(kw_only=True)
class OptionalType(TypeExpression):
    base: TypeExpression


class PointerOwnership(Enum):
    Borrowed = auto()
    Owned = auto()
    Shared = auto()
    Weak = auto()
    Unsafe = auto()


@dataclass(kw_only=True)
class PointerType(TypeExpression):
    to: TypeExpression
    ownership: PointerOwnership
    nullable: bool


@dataclass(kw_only=True)
class TypeWithUnit(TypeExpression):
    base: TypeExpression | None  # None means the base type is implicit
    unit: CompoundUnit | None  # None means the unit is explicitly cleared from the type via <nil>


@dataclass(kw_only=True)
class TypeWithTag(TypeExpression):
    base: TypeExpression | None  # None means the base type is implicit
    tag: QualifiedName


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
class ExprStatement(Statement):
    expr: Expression


@dataclass(kw_only=True)
class AssignStatement(Statement):
    dest: Expression
    expr: Expression
    is_move: bool


@dataclass(kw_only=True)
class LocalDeclaration(Statement):
    name: Identifier
    type_: TypeExpression | None
    expr: Expression | None
    is_const: bool


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
