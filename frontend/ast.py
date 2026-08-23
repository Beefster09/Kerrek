from __future__ import annotations

from dataclasses import dataclass, field, fields
from decimal import Decimal
from enum import Enum, auto
from pathlib import Path

from frontend.common import (
    BinaryOp,
    Location,
    PointerOwnership,
    RuneValue,
    UnaryOp,
    Where,
)
from frontend.lexer import Identifier, Numeric
from frontend.units import IndeterminateUnit

# === NODES ===


@dataclass(kw_only=True)
class File:
    source: Path | None = field(repr=False)
    imports: list[Import] = field(default_factory=list)
    declarations: list[TopLevelDeclaration] = field(default_factory=list)


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

    def where(self) -> Where:
        return {
            "file": self.file,
            "start": self.start,
            "end": self.end,
        }


@dataclass(kw_only=True)
class QualifiedName(Node):
    path: list[Identifier]

    def __str__(self):
        return ".".join(self.path)


@dataclass(kw_only=True)
class Annotation(Node):
    base: QualifiedName
    args: list[Argument]


@dataclass(kw_only=True)
class TopLevelItem(Node):
    annotations: list[Annotation] = field(default_factory=list)


@dataclass(kw_only=True)
class Import(TopLevelItem):
    collection: Identifier | None
    module_path: list[str]
    namespace: Identifier


@dataclass(kw_only=True)
class ImportUsingNames(Import):
    names: list[Identifier]


@dataclass(kw_only=True)
class TopLevelDeclaration(TopLevelItem):
    pass


@dataclass(kw_only=True)
class GlobalConstant(TopLevelDeclaration):
    name: Identifier
    type: TypeExpression | None
    unit: DeclaredUnit
    expr: Expression


@dataclass(kw_only=True)
class GlobalVariable(TopLevelDeclaration):
    name: Identifier
    type: TypeExpression | None
    unit: DeclaredUnit
    expr: Expression | None


@dataclass(kw_only=True)
class TypeAlias(TopLevelDeclaration):
    pass


@dataclass(kw_only=True)
class AnnotationDef(TopLevelDeclaration):
    base: QualifiedName
    args: list[Argument]


# === UNITS ===


@dataclass(kw_only=True)
class UnitTypeDecl(TopLevelDeclaration):
    """
    e.g.
    unit type length;
    """

    name: Identifier


@dataclass(kw_only=True)
class UnitTypeAliasDecl(TopLevelDeclaration):
    """
    e.g.
    unit type volume = length^3;
    """

    name: Identifier
    orig: CompoundUnit


@dataclass(kw_only=True)
class UnitDecl(TopLevelDeclaration):
    """
    e.g.
    unit meter: length;
    """

    name: Identifier
    unit_type: QualifiedName | None = None
    conversions: list[UnitConversionDef]


@dataclass(kw_only=True)
class UnitAlias(TopLevelDeclaration):
    """
    e.g.
    unit newton = kg m / s^2;
    """

    name: Identifier
    orig: CompoundUnit


class ConversionDirection(Enum):
    To = auto()
    From = auto()


@dataclass(kw_only=True)
class UnitConversionDef(Node):
    """
    e.g.
    unit radians: angle {
        from degrees: * math.PI / 180;
    }

    or

    unit feet: length {
        to meters: / 3.28084;
        to yards: / 3;
        to inches: * 12;
    }
    """

    direction: ConversionDirection
    other: QualifiedName
    multiplier: int | float | Decimal | QualifiedName = 1
    divisor: int | float | Decimal | QualifiedName = 1


@dataclass(kw_only=True)
class UnitComponent(Node):
    base: QualifiedName
    exponent: int


@dataclass(kw_only=True)
class CompoundUnit(Node):
    components: list[UnitComponent]
    is_absolute: bool


type DeclaredUnit = CompoundUnit | IndeterminateUnit


# === EXPRESSIONS ===


# - abstract base node -


@dataclass(kw_only=True)
class Expression(Node):
    pass


# - concrete nodes and supporting types -


@dataclass(kw_only=True)
class NameExpr(Expression):
    name: Identifier


@dataclass(kw_only=True)
class PlaceholderExpr(Expression):
    pass


@dataclass(kw_only=True)
class FieldAccessExpr(Expression):
    base: Expression
    field: Identifier


@dataclass(kw_only=True)
class ScalarLiteralExpr(Expression):
    value: Numeric
    unit: CompoundUnit | None


@dataclass(kw_only=True)
class SimpleLiteralExpr(Expression):
    value: RuneValue | str | bool | None


@dataclass
class ImplicitEnum(Expression):
    """
    e.g. .Foo("bar")
    """

    name: Identifier
    payload: Expression | None


@dataclass(kw_only=True)
class MoveExpr(Expression):
    expr: Expression


@dataclass(kw_only=True)
class BinopExpr(Expression):
    op: BinaryOp
    lhs: Expression
    rhs: Expression


@dataclass(kw_only=True)
class UnaryExpr(Expression):
    op: UnaryOp
    expr: Expression


@dataclass(kw_only=True)
class AddressOfExpr(Expression):
    expr: Expression


@dataclass(kw_only=True)
class DereferenceExpr(Expression):
    expr: Expression


@dataclass(kw_only=True)
class CastExpr(Expression):
    expr: Expression
    to: TypeExpression


@dataclass(kw_only=True)
class UnitConversionExpr(Expression):
    expr: Expression
    to: CompoundUnit


@dataclass(kw_only=True)
class UnitReinterpretExpr(Expression):
    expr: Expression
    new_unit: CompoundUnit


@dataclass(kw_only=True)
class IndexExpr(Expression):
    collection: Expression
    args: list[Argument]


@dataclass(kw_only=True)
class CallishExpr(Expression):
    callee: Expression
    args: list[Argument]


@dataclass(kw_only=True)
class TypeExprExpr(Expression):
    type: TypeExpression


@dataclass(kw_only=True)
class UnitExpr(Expression):
    unit: CompoundUnit


# === TYPE EXPRESSIONS ===


@dataclass(kw_only=True)
class TypeExpression(Node):
    pass


@dataclass(kw_only=True)
class SimpleType(TypeExpression):
    type_name: QualifiedName


@dataclass(kw_only=True)
class TypeWithArgs(TypeExpression):
    base: QualifiedName
    args: list[Argument]


@dataclass(kw_only=True)
class GenericType(TypeExpression):
    name: Identifier
    bound: TypeExpression | None


@dataclass(kw_only=True)
class OptionalType(TypeExpression):
    base: TypeExpression


@dataclass(kw_only=True)
class PointerType(TypeExpression):
    to: TypeExpression
    ownership: PointerOwnership


@dataclass(kw_only=True)
class TypeWithTags(TypeExpression):
    base: TypeExpression
    tags: list[QualifiedName]


# === CAPABILITIES ===


@dataclass(kw_only=True)
class CapabilityDecl(TopLevelDeclaration):
    name: Identifier


@dataclass(kw_only=True)
class CapabilityExpression(Node):
    pass


# === STATEMENTS ===


@dataclass(kw_only=True)
class Statement(Node):
    pass


@dataclass(kw_only=True)
class ReturnStatement(Statement):
    values: list[Expression]


@dataclass(kw_only=True)
class ExprStatement(Statement):
    expr: Expression


@dataclass(kw_only=True)
class AssignStatement(Statement):
    dests: list[Expression]
    exprs: list[Expression]


@dataclass(kw_only=True)
class UnboundVar(Node):
    pass


@dataclass(kw_only=True)
class LocalVariable(Statement):
    name: Identifier
    type: TypeExpression | None
    unit: DeclaredUnit
    expr: Expression | UnboundVar | None


@dataclass(kw_only=True)
class LocalConstant(Statement):
    name: Identifier
    type: TypeExpression | None
    unit: DeclaredUnit
    expr: Expression


@dataclass(kw_only=True)
class Block(Statement):
    body: list[Statement]


# === FUNCTIONS ===


@dataclass(kw_only=True)
class FormalParameter(Node):
    name: Identifier
    type: TypeExpression
    unit: CompoundUnit | None
    default: Expression | None


@dataclass(kw_only=True)
class FuncReturn(Node):
    name: Identifier | None
    type: TypeExpression
    unit: CompoundUnit | None


@dataclass(kw_only=True)
class FuncDefinition(TopLevelDeclaration, Statement):
    name: Identifier
    params: list[FormalParameter]
    returns: list[FuncReturn]
    error_type: TypeExpression | None
    fallible: bool
    requires: CapabilityExpression | None
    body: Block


@dataclass(kw_only=True)
class Argument(Node):
    name: Identifier | None
    expr: Expression


@dataclass(kw_only=True)
class FuncOverloadGroup(TopLevelDeclaration):
    name: Identifier
    overloads: list[QualifiedName]


# === TYPE DEFINITIONS ===


class TypeDeclaration(TopLevelDeclaration, Statement):
    pass


@dataclass(kw_only=True)
class StructField(Node):
    name: Identifier
    type: TypeExpression
    requires: CapabilityExpression | None = None
    is_using: bool = False


@dataclass(kw_only=True)
class StructDefinition(TypeDeclaration):
    name: Identifier
    fields: list[StructField]
    params: list[FormalParameter]
    capabilities: list[CapabilityDecl]
    construct_requires: CapabilityExpression | None


@dataclass(kw_only=True)
class InterfaceMethod(Node):
    name: Identifier
    params: list[FormalParameter]
    return_types: list[TypeExpression]
    # Ellipsis as the error type indicates the function can fail but the error type is void
    error_type: TypeExpression | None = None
    fallible: bool
    requires: CapabilityExpression | None = None
    is_optional: bool = False


@dataclass(kw_only=True)
class SubInterface(Node):
    interface: QualifiedName
    is_optional: bool


@dataclass(kw_only=True)
class InterfaceDefinition(TypeDeclaration):
    name: Identifier
    methods: list[InterfaceMethod | SubInterface]


@dataclass(kw_only=True)
class EnumVariant(Node):
    name: Identifier | None
    payload: TypeExpression | None
    slot: int | None


@dataclass(kw_only=True)
class EnumDefinition(TypeDeclaration):
    name: Identifier
    variants: list[EnumVariant]


@dataclass(kw_only=True)
class TypeAliasDecl(TypeDeclaration):
    name: Identifier
    orig_type: TypeExpression


@dataclass(kw_only=True)
class DistinctTypeDecl(TypeDeclaration):
    name: Identifier
    underlying: TypeExpression
