from __future__ import annotations

from dataclasses import dataclass
from enum import Enum, auto
from typing import TYPE_CHECKING, overload

from frontend import hir

if TYPE_CHECKING:
    from frontend.exprs import ComptimeType


class PrimitiveType(Enum):
    Integer = "Integer"
    Int64 = "Int64"
    Int32 = "Int32"
    Int16 = "Int16"
    Int8 = "Int8"
    UInt64 = "UInt64"
    UInt32 = "UInt32"
    UInt16 = "UInt16"
    UInt8 = "UInt8"

    Decimal = "Decimal"
    Dec64 = "Dec64"
    Dec32 = "Dec32"

    Float64 = "Float64"
    Float32 = "Float32"

    Boolean = "Boolean"
    String = "String"
    Rune = "Rune"
    Byte = "Byte"

    Opaque = "Opaque"
    Opaque8 = "Opaque8"
    Opaque16 = "Opaque16"
    Opaque32 = "Opaque32"
    Opaque64 = "Opaque64"


@dataclass
class FixedDecimal:
    digits: int
    precision: int


class FlexAffinity(Enum):
    Nil = auto()
    UInt = auto()
    Integer = auto()
    Float = auto()
    Decimal = auto()
    Boolean = auto()
    String = auto()
    Rune = auto()


@dataclass
class FlexType:
    affinity: FlexAffinity


class TypeKind(Enum):
    """defines the group of mutual convertability of types"""

    Numeric = (
        auto()
    )  # Numeric types + Rune and Byte and all distinct types backed by them
    String = auto()
    Boolean = auto()


@dataclass
class FixedArrayKind:
    shape: tuple[int, ...]
    inner_kind: ConversionClass


class _Unconv:
    def __eq__(self, other):
        return False


Unconvertable = _Unconv()

type ConversionClass = TypeKind | FixedArrayKind | _Unconv


def conversion_class(typ: ComptimeType) -> ConversionClass:
    match typ:
        case hir.SimpleType(hir.DistinctType(underlying=underlying)):
            return conversion_class(underlying)

        case hir.FixedArrayType():
            return FixedArrayKind(typ.shape, conversion_class(typ.elem))

        case FlexType(FlexAffinity.Boolean) | hir.SimpleType(PrimitiveType.Boolean):
            return TypeKind.Boolean

        case FlexType(FlexAffinity.String) | hir.SimpleType(PrimitiveType.String):
            return TypeKind.String

        case (
            FlexType(
                FlexAffinity.Integer
                | FlexAffinity.UInt
                | FlexAffinity.Decimal
                | FlexAffinity.Float
            )
            | FixedDecimal()
            | hir.SimpleType(
                PrimitiveType.Integer
                | PrimitiveType.Int64
                | PrimitiveType.Int32
                | PrimitiveType.Int16
                | PrimitiveType.Int8
                | PrimitiveType.UInt64
                | PrimitiveType.UInt32
                | PrimitiveType.UInt16
                | PrimitiveType.UInt8
                | PrimitiveType.Decimal
                | PrimitiveType.Dec64
                | PrimitiveType.Dec32
                | PrimitiveType.Float64
                | PrimitiveType.Float32
                | PrimitiveType.Rune
                | PrimitiveType.Byte
            )
        ):
            return TypeKind.Numeric

        case _:
            return Unconvertable


def is_integer(typ: ComptimeType) -> bool:
    match typ:
        case hir.SimpleType(hir.DistinctType(underlying=underlying)):
            return is_integer(underlying)

        case (
            FlexType(FlexAffinity.Integer | FlexAffinity.UInt)
            | FixedDecimal(_, 0)
            | hir.SimpleType(
                PrimitiveType.Integer
                | PrimitiveType.Int64
                | PrimitiveType.Int32
                | PrimitiveType.Int16
                | PrimitiveType.Int8
                | PrimitiveType.UInt64
                | PrimitiveType.UInt32
                | PrimitiveType.UInt16
                | PrimitiveType.UInt8
            )
        ):
            return True

        case _:
            return False


def is_decimal(typ: ComptimeType) -> bool:
    match typ:
        case hir.SimpleType(hir.DistinctType(underlying=underlying)):
            return is_decimal(underlying)

        case (
            FlexType(FlexAffinity.Decimal)
            | FixedDecimal()
            | hir.SimpleType(
                PrimitiveType.Decimal | PrimitiveType.Dec64 | PrimitiveType.Dec32
            )
        ):
            return True

        case _:
            return False


def is_binfloat(typ: ComptimeType) -> bool:
    match typ:
        case hir.SimpleType(hir.DistinctType(underlying=underlying)):
            return is_binfloat(underlying)

        case FlexType(FlexAffinity.Float) | hir.SimpleType(
            PrimitiveType.Float64 | PrimitiveType.Float32
        ):
            return True

        case _:
            return False


def is_boolean(typ: ComptimeType) -> bool:
    match typ:
        case hir.SimpleType(hir.DistinctType(underlying=underlying)):
            return is_boolean(underlying)

        case FlexType(FlexAffinity.Boolean) | PrimitiveType.Boolean:
            return True

        case _:
            return False


def is_string(typ: ComptimeType) -> bool:
    match typ:
        case hir.SimpleType(hir.DistinctType(underlying=underlying)):
            return is_string(underlying)

        case FlexType(FlexAffinity.String) | PrimitiveType.String:
            return True

        case _:
            return False


def is_rune(typ: ComptimeType) -> bool:
    match typ:
        case hir.SimpleType(hir.DistinctType(underlying=underlying)):
            return is_rune(underlying)

        case FlexType(FlexAffinity.Rune) | PrimitiveType.Rune:
            return True

        case _:
            return False


def is_pointer(typ: ComptimeType) -> bool:
    return isinstance(underlying(typ), hir.PointerType)


@overload
def underlying(typ: hir.Type) -> hir.Type: ...
@overload
def underlying(typ: ComptimeType) -> ComptimeType: ...


def underlying(typ: ComptimeType) -> ComptimeType:
    while True:
        match typ:
            case hir.SimpleType(hir.DistinctType(underlying=underlying)):
                typ = underlying
            case hir.TypeWithTags():
                typ = typ.base
            case _:
                return typ
