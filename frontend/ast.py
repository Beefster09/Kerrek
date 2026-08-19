from __future__ import annotations

from dataclasses import dataclass, field, fields
from decimal import Decimal
from enum import Enum, auto
from pathlib import Path

from frontend.common import BinaryOp, Location, PointerOwnership, RuneValue, UnaryOp
from frontend.lexer import Identifier, Numeric

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

    def __iter__(self):
        for f in fields(self):
            value = getattr(self, f.name)
            if not value:
                continue
            elif isinstance(value, (list, tuple)) and isinstance(value[0], Node):
                yield from value
            elif isinstance(value, Node):
                yield value

    def walk(self):
        yield self
        for f in fields(self):
            value = getattr(self, f.name)
            if isinstance(value, (list, tuple)):
                for sub in value:
                    if isinstance(sub, Node):
                        yield from sub.walk()
            elif isinstance(value, Node):
                yield from value.walk()


@dataclass(kw_only=True)
class QualifiedName(Node):
    path: list[Identifier]


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
    unit type volume is length^3;
    """

    name: Identifier
    base: CompoundUnit


@dataclass(kw_only=True)
class UnitDecl(TopLevelDeclaration):
    """
    e.g.
    unit meter: length;
    """

    name: Identifier
    unit_type: QualifiedName | None = None


@dataclass(kw_only=True)
class UnitAlias(TopLevelDeclaration):
    """
    e.g.
    unit newton is kg m / s^2;
    """

    name: Identifier
    base: CompoundUnit


@dataclass(kw_only=True)
class UnitConversionDef(TopLevelDeclaration):
    """
    e.g.
    unit radians = 3.14159265358979 * degrees / 180;
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


class IndeterminateUnit(Enum):
    NoUnit = auto()  # explicit `nil` unit
    Flexible = auto()  # unit is `_`; unitless, but can participate in math with units
    Inferred = auto()  # inferred from usage


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

    # TODO: validation


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

    def walk_statements(self):
        for stmt in self.body:
            yield stmt
            for child in stmt:
                if isinstance(child, Block):
                    yield from child.walk_statements()


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
    # Ellipsis as the error type indicates the function can fail but the error type is void
    error_type: TypeExpression | None
    fallible: bool
    requires: CapabilityExpression | None
    body: Block


@dataclass(kw_only=True)
class Argument(Node):
    name: Identifier | None
    expr: Expression


@dataclass(kw_only=True)
class FuncOverload(TopLevelDeclaration):
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
