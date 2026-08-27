from __future__ import annotations

from dataclasses import dataclass, field
from fractions import Fraction
from pathlib import Path
from typing import Literal

from frontend import ast
from frontend.common import (
    BinaryOp,
    ByteValue,
    Location,
    PointerOwnership,
    RuneValue,
    SymbolID,
    UnaryOp,
    Where,
)
from frontend.lexer import Identifier
from frontend.types import FixedDecimal, PrimitiveType
from frontend.units import IndeterminateUnit

# === NODES ===


@dataclass(kw_only=True)
class TranslationUnit:
    entry_point: FuncDefinition | None = None
    types: dict[SymbolID, Type] = field(default_factory=dict)
    funcs: dict[SymbolID, FuncDefinition] = field(default_factory=dict)
    variables: dict[SymbolID, GlobalVariable] = field(default_factory=dict)
    unit_types: dict[SymbolID, UnitType] = field(default_factory=dict)
    units: dict[SymbolID, BaseUnit] = field(default_factory=dict)
    capabilities: dict[SymbolID, Capability] = field(default_factory=dict)
    annotations: dict[SymbolID, AnnotationDef] = field(default_factory=dict)


@dataclass(kw_only=True)
class Node:
    file: Path = field(repr=False)
    start: Location = field(repr=False)
    end: Location = field(repr=False)

    @classmethod
    def from_node(cls, base: Node | ast.Node, **other):
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
class Symbol(Node):
    id: SymbolID


@dataclass(kw_only=True)
class AnnotationDef(Symbol):
    name: Identifier
    params: list[FormalParameter]


@dataclass(kw_only=True)
class Annotation(Node):
    of: AnnotationDef
    args: list[Argument]


@dataclass(kw_only=True)
class Annotatable(Symbol):
    annotations: list[Annotation]


@dataclass(kw_only=True)
class GlobalVariable(Annotatable):
    name: Identifier
    type: Type
    unit: RealizedUnit
    expr: Expression


@dataclass(kw_only=True)
class UnitType(Symbol):
    name: Identifier


@dataclass(kw_only=True)
class BaseUnit(Symbol):
    name: Identifier
    type: UnitType | None


@dataclass(kw_only=True)
class CompoundUnit:
    components: list[tuple[BaseUnit, int]]
    is_absolute: bool


type RealizedUnit = (
    CompoundUnit | Literal[IndeterminateUnit.Flexible, IndeterminateUnit.NoUnit]
)


# === EXPRESSIONS ===


@dataclass
class NilOf:
    type: Type


@dataclass
class ZeroOf:
    type: Type


# - abstract base node -


@dataclass(kw_only=True)
class Expression(Node):
    pass


@dataclass(kw_only=True)
class SingleValueExpression(Expression):
    type: Type
    unit: RealizedUnit


@dataclass(kw_only=True)
class MultiValueExpression(Expression):
    types: list[Type]
    units: list[RealizedUnit]


# - concrete nodes and supporting types -


type Value = Fraction | RuneValue | ByteValue | str | bool | NilOf | ZeroOf


@dataclass(kw_only=True)
class VarExpr(SingleValueExpression):
    references: Symbol


@dataclass(kw_only=True)
class ConstExpr(SingleValueExpression):
    value: Value


@dataclass(kw_only=True)
class FieldAccessExpr(SingleValueExpression):
    base: Expression
    field: Identifier


@dataclass
class EnumValue(SingleValueExpression):
    """
    e.g. .Foo("bar")
    """

    enum: EnumType
    variant: int
    payload: Expression | None


@dataclass(kw_only=True)
class MoveExpr(SingleValueExpression):
    expr: Expression


@dataclass(kw_only=True)
class ConditionExpr(SingleValueExpression):
    condition: Expression
    if_true: Expression
    if_false: Expression


@dataclass(kw_only=True)
class BinopExpr(SingleValueExpression):
    op: BinaryOp
    lhs: Expression
    rhs: Expression


@dataclass(kw_only=True)
class UnaryExpr(SingleValueExpression):
    op: UnaryOp
    expr: Expression


@dataclass(kw_only=True)
class AddressOfExpr(SingleValueExpression):
    expr: Expression


@dataclass(kw_only=True)
class DereferenceExpr(SingleValueExpression):
    expr: Expression


@dataclass(kw_only=True)
class CastExpr(SingleValueExpression):
    expr: Expression
    to: Type


@dataclass(kw_only=True)
class UnitConversionExpr(SingleValueExpression):
    expr: Expression
    factor: Fraction


@dataclass(kw_only=True)
class UnitReinterpretExpr(SingleValueExpression):
    expr: Expression
    # unit is defined by SingleValueExpression


@dataclass(kw_only=True)
class IndexExpr(SingleValueExpression):
    collection: Expression
    args: list[Expression]


@dataclass(kw_only=True)
class FuncCallExpr(MultiValueExpression):
    callee: Expression
    args: list[Argument]


@dataclass(kw_only=True)
class Argument(Node):
    name: Identifier | None
    expr: Expression


# === TYPE EXPRESSIONS ===


@dataclass
class Type:
    pass


@dataclass
class SimpleType(Type):
    type: (
        PrimitiveType | FixedDecimal | StructType | EnumType | DistinctType | Interface
    )


@dataclass(kw_only=True)
class GenericType(Type):
    name: Identifier
    bound: Type | None = None


@dataclass(kw_only=True)
class FixedArrayType(Type):
    elem: Type
    shape: tuple[int, ...]


@dataclass
class DynamicArrayType(Type):
    elem: Type


@dataclass(kw_only=True)
class DimensionedArrayType(Type):
    elem: Type
    dimensions: int = 1


@dataclass
class MapType(Type):
    key: Type
    value: Type


@dataclass
class OptionalType(Type):
    base: Type


@dataclass(kw_only=True)
class PointerType(Type):
    to: Type
    ownership: PointerOwnership
    nullable: bool


@dataclass(kw_only=True)
class TypeWithTags(Type):
    base: Type
    tags: list[SymbolID]


# === CAPABILITIES ===


@dataclass(kw_only=True)
class Capability(Symbol):
    name: Identifier


@dataclass(kw_only=True)
class CapabilityExpression(Node):
    pass


# === STATEMENTS ===


@dataclass(kw_only=True)
class Statement(Node):
    pass


@dataclass(kw_only=True)
class LocalVariable(Annotatable, Statement):
    name: Identifier
    type: Type
    unit: RealizedUnit
    # expr = None means unbound. Default zero is made explicit when building the HIR
    expr: Expression | None


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
class Block(Statement):
    body: list[Statement]


# === FUNCTIONS ===


@dataclass(kw_only=True)
class FormalParameter(Symbol):
    name: Identifier
    type: Type
    unit: CompoundUnit | None
    default: ConstExpr | None


@dataclass(kw_only=True)
class FuncReturn(Node):
    type: Type
    unit: CompoundUnit | None


@dataclass(kw_only=True)
class FuncDefinition(Annotatable):
    name: Identifier
    params: list[FormalParameter]
    returns: list[FuncReturn]
    error_type: Type | None
    fallible: bool
    requires: CapabilityExpression | None = None
    body: Block


@dataclass(kw_only=True)
class FuncOverloadGroup(Symbol):
    name: Identifier
    overloads: list[FuncDefinition]


# === TYPE DEFINITIONS ===


@dataclass(kw_only=True)
class StructField(Node):
    name: Identifier
    type: Type
    requires: CapabilityExpression | None = None
    annotations: list[Annotation]


@dataclass(kw_only=True)
class StructType(Annotatable):
    name: Identifier
    fields: list[StructField]
    params: list[FormalParameter]
    capabilities: list[Capability]
    construct_requires: CapabilityExpression | None


@dataclass(kw_only=True)
class InterfaceMethod(Node):
    name: Identifier
    params: list[FormalParameter]
    return_types: list[Type]
    error_type: Type | None
    fallible: bool
    requires: CapabilityExpression | None = None
    is_optional: bool = False


@dataclass(kw_only=True)
class SubInterface(Node):
    interface: Interface
    is_optional: bool


@dataclass(kw_only=True)
class Interface(Annotatable):
    name: Identifier
    methods: list[InterfaceMethod | SubInterface]


@dataclass(kw_only=True)
class InterfaceImpl(Annotatable):
    name: Identifier
    impls: list[FuncDefinition]


@dataclass(kw_only=True)
class EnumVariant(Node):
    name: Identifier | None
    payload: Type | None
    slot: int


@dataclass(kw_only=True)
class EnumType(Annotatable):
    name: Identifier
    variants: list[EnumVariant]


@dataclass(kw_only=True)
class DistinctType(Annotatable):
    name: Identifier
    underlying: Type
