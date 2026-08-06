from __future__ import annotations

from dataclasses import dataclass, field, fields
from decimal import Decimal
from enum import Enum, auto
from pathlib import Path
from types import EllipsisType
from typing import TYPE_CHECKING, Any, Literal

from frontend.lexer import Identifier, Numeric
from frontend.common import Location

if TYPE_CHECKING:
    from frontend.resolver import CanonicalUnit, Named, AnyType


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
                for sub in value:
                    yield sub
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

    resolves_to: Named | None = field(default=None, repr=False)


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

    def get_filepath(self, build_root: Path, from_file: Path) -> Path:
        ...


@dataclass(kw_only=True)
class ImportWithNames(Import):
    names: list[Identifier]


@dataclass(kw_only=True)
class TopLevelDeclaration(TopLevelItem):
    pass


@dataclass(kw_only=True)
class GlobalConstant(TopLevelDeclaration):
    name: Identifier
    type: TypeExpression | Literal[TypeState.Flexible]
    expr: Expression


@dataclass(kw_only=True)
class GlobalVariable(TopLevelDeclaration):
    name: Identifier
    type: TypeExpression | Literal[TypeState.NotDetermined]
    expr: Expression | None


@dataclass(kw_only=True)
class TypeAlias(TopLevelDeclaration):
    pass


@dataclass(kw_only=True)
class UnitTypeDecl(TopLevelDeclaration):
    name: Identifier


@dataclass(kw_only=True)
class UnitTypeAliasDecl(TopLevelDeclaration):
    name: Identifier
    base: CompoundUnit


@dataclass(kw_only=True)
class UnitDecl(TopLevelDeclaration):
    """
    e.g.
    unit meter: length
    """
    name: Identifier
    unit_type: QualifiedName | None = None


@dataclass(kw_only=True)
class UnitAlias(TopLevelDeclaration):
    """
    e.g.
    unit newton is kg m / s^2
    """
    name: Identifier
    base: CompoundUnit


@dataclass(kw_only=True)
class UnitConversionDef(TopLevelDeclaration):
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

    canonical: CanonicalUnit | None = field(default=None)


# === EXPRESSIONS ===


class ConstantFolding(Enum):
    NotEvaluated = auto()
    RuntimeValue = auto()
    Failed = auto()


class TypeState(Enum):
    NotDetermined = auto()
    Flexible = auto()  # i.e. the value assumes whatever compatible type it might need to be
    Impossible = auto()  # i.e. the expression cannot possibly be evaluated
    Failed = auto()  # i.e. an error occured while trying to evaluate the type


@dataclass(kw_only=True)
class Expression(Node):
    folded_value: Any = field(default=ConstantFolding.NotEvaluated, repr=False)
    result_type: Any = field(default=TypeState.NotDetermined, repr=False)


@dataclass(kw_only=True)
class QualnameExpr(Expression):
    name: QualifiedName


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


@dataclass(kw_only=True)
class SimpleLiteralExpr(Expression):
    value: RuneValue | str | bool | None

    def __post_init__(self):
        self.folded_value = self.value

@dataclass
class ImplicitEnum(Expression):
    name: Identifier


class Operator(Enum):
    Add = '+'
    Subtract = '-'
    Multiply = '*'
    Divide = '/'
    FloorDivide = '//'
    Remainder = '%'
    Modulo = 'mod'
    Power = '**'

    Equal = '=='
    NotEqual = '!='
    Less = '<'
    LessEqual = '<='
    Greater = '>'
    GreaterEqual = '>='

    Is = "is"

    And = "and"
    Or = "or"


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
class ExplicitUnitConversion(Expression):
    expr: Expression
    to: CompoundUnit


@dataclass(kw_only=True)
class IndexExpr(Expression):
    collection: Expression
    args: list[Argument]


@dataclass(kw_only=True)
class CallExpr(Expression):
    callee: Expression
    args: list[Argument]


# === TYPE EXPRESSIONS ===


@dataclass(kw_only=True)
class TypeExpression(Node):
    canonical: AnyType | TypeState = field(default=TypeState.NotDetermined, repr=False)


@dataclass(kw_only=True)
class SimpleType(TypeExpression):
    type_name: QualifiedName


@dataclass(kw_only=True)
class SimpleTemplateType(TypeExpression):
    name: Identifier


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
class UnboundVar(Node):
    pass


@dataclass(kw_only=True)
class LocalVariable(Statement):
    name: Identifier
    type: TypeExpression | Literal[TypeState.NotDetermined]
    expr: Expression | UnboundVar | None


@dataclass(kw_only=True)
class LocalConstant(Statement):
    name: Identifier
    type: TypeExpression | Literal[TypeState.Flexible]
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
    default: Expression | None = None


@dataclass(kw_only=True)
class FuncDefinition(TopLevelDeclaration, Statement):
    name: Identifier
    params: list[FormalParameter]
    return_types: list[TypeExpression]
    error_type: TypeExpression | EllipsisType | None = None  # Ellipsis as the error type indicates the function can fail but the error type is void
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
    error_type: TypeExpression | EllipsisType | None = None  # Ellipsis as the error type indicates the function can fail but the error type is void
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
