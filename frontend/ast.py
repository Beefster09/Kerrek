from __future__ import annotations

from dataclasses import dataclass, field, fields
from decimal import Decimal
from enum import Enum, auto
from fractions import Fraction
from pathlib import Path
from types import EllipsisType
from typing import TYPE_CHECKING, Literal

from frontend.common import Location
from frontend.lexer import Identifier, Numeric

if TYPE_CHECKING:
    from frontend.exprs import ComptimeType, ComptimeUnit, ComptimeValue, RealizedType
    from frontend.resolver import AnyType, CanonicalUnit, Named


# === SENTINEL VALUES ===


class ValueSentinels(Enum):
    NotEvaluated = auto()  # value has yet to be determined from semantic analysis
    RuntimeValue = auto()  # value is not known at compile time
    CannotEvaluate = auto()  # it is not possible to evaluate the expression


class TypeSentinels(Enum):
    NotDetermined = (
        auto()
    )  # type has yet to be determined from semantic analysis (or needs to be inferred)
    Impossible = (
        auto()
    )  # the type cannot be inferred because the expression cannot be evaluated


class UnitSentinels(Enum):
    NotDetermined = (
        auto()
    )  # unit has yet to be determined from semantic analysis (or needs to be inferred)
    Flexible = (
        auto()
    )  # originates from a numeric literal or constant without explicit unit information
    NoUnit = auto()  # originates from a runtime value which did not declare a unit or a type which cannot have a unit
    Incoherent = auto()  # dimensional analysis failed to produce a coherent result unit or a unit was applied to a value which cannot have units


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

    # populated by resolver
    resolves_to: Named | None = field(default=None, repr=False)
    remaining_fields: list[Identifier] | None = field(default=None, repr=False)


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

    def get_filepath(self, build_root: Path, from_file: Path) -> Path: ...


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
    unit: CompoundUnit | UnitSentinels
    expr: Expression

    realized_type: RealizedType | None = field(default=None, repr=False)
    realized_unit: ComptimeUnit = field(default=UnitSentinels.NotDetermined, repr=False)


@dataclass(kw_only=True)
class GlobalVariable(TopLevelDeclaration):
    name: Identifier
    type: TypeExpression | None
    unit: CompoundUnit | UnitSentinels
    expr: Expression | None

    realized_type: RealizedType | None = field(default=None, repr=False)
    realized_unit: ComptimeUnit = field(default=UnitSentinels.NotDetermined, repr=False)


@dataclass(kw_only=True)
class TypeAlias(TopLevelDeclaration):
    pass


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

    canonical: CanonicalUnit | None = field(default=None)


# === EXPRESSIONS ===


# - abstract base node -


@dataclass(kw_only=True)
class Expression(Node):
    evaluated_value: ComptimeValue | Literal[ValueSentinels.NotEvaluated] = field(
        default=ValueSentinels.NotEvaluated, repr=False
    )
    evaluated_type: ComptimeType | Literal[TypeSentinels.NotDetermined] = field(
        default=TypeSentinels.NotDetermined, repr=False
    )
    evaluated_unit: CanonicalUnit | UnitSentinels = field(
        default=UnitSentinels.NotDetermined, repr=False
    )

    required_type: RealizedType | Literal[TypeSentinels.NotDetermined] = field(
        default=TypeSentinels.NotDetermined, repr=False
    )
    required_unit: CanonicalUnit | UnitSentinels = field(
        default=UnitSentinels.NotDetermined, repr=False
    )

    unit_conv_multiplier: Fraction = field(default=Fraction(1), repr=False)


# - concrete nodes and supporting types -


@dataclass(kw_only=True)
class QualnameExpr(Expression):
    name: QualifiedName


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


@dataclass
class RuneValue:
    codepoint: int

    @property
    def char(self):
        return chr(self.codepoint)

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


class BinaryOp(Enum):
    Add = "+"
    Subtract = "-"
    Multiply = "*"
    TrueDivide = "/"
    FloorDivide = "//"
    Remainder = "%"
    Modulo = "mod"
    Power = "**"

    Equal = "=="
    NotEqual = "!="
    Less = "<"
    LessEqual = "<="
    Greater = ">"
    GreaterEqual = ">="

    Is = "is"
    IsNot = "is_not"

    And = "and"
    Or = "or"


@dataclass(kw_only=True)
class BinopExpr(Expression):
    op: BinaryOp
    lhs: Expression
    rhs: Expression


class UnaryOp(Enum):
    Positive = "+"
    Negate = "-"

    Not = "not"


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


# === TYPE EXPRESSIONS ===


@dataclass(kw_only=True)
class TypeExpression(Node):
    canonical: RealizedType | None = field(default=None, repr=False)


@dataclass(kw_only=True)
class SimpleType(TypeExpression):
    type_name: QualifiedName


@dataclass(kw_only=True)
class GenericType(TypeExpression):
    name: Identifier
    bound: TypeExpression | None


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
class TypeWithTag(TypeExpression):
    base: TypeExpression | None  # None means the base type is implicit
    tag: QualifiedName


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
    dest: Expression
    expr: Expression
    is_move: bool


@dataclass(kw_only=True)
class UnboundVar(Node):
    pass


@dataclass(kw_only=True)
class LocalVariable(Statement):
    name: Identifier
    type: TypeExpression | None
    unit: CompoundUnit | UnitSentinels
    expr: Expression | UnboundVar | None

    realized_type: RealizedType | None = field(default=None, repr=False)
    realized_unit: ComptimeUnit = field(default=UnitSentinels.NotDetermined, repr=False)


@dataclass(kw_only=True)
class LocalConstant(Statement):
    name: Identifier
    type: TypeExpression | None
    unit: CompoundUnit | UnitSentinels
    expr: Expression

    realized_type: AnyType | None = field(default=None, repr=False)
    realized_unit: ComptimeUnit = field(default=UnitSentinels.NotDetermined, repr=False)


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
    error_type: TypeExpression | EllipsisType | None = (
        None  # Ellipsis as the error type indicates the function can fail but the error type is void
    )
    requires: CapabilityExpression | None = None
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
    error_type: TypeExpression | EllipsisType | None = (
        None  # Ellipsis as the error type indicates the function can fail but the error type is void
    )
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
