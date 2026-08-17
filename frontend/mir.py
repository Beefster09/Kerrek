from __future__ import annotations

from dataclasses import dataclass, field
from decimal import Decimal
from enum import Enum, auto

from frontend.resolver import SymbolID


@dataclass(kw_only=True)
class TranslationUnit:
    types: list[Type] = field(default_factory=list)
    globals: list[Variable] = field(default_factory=list)
    functions: list[Function] = field(default_factory=list)


@dataclass(kw_only=True)
class Function:
    id: SymbolID
    params: list[Parameter]
    returns: list[Type]
    error: Type | None
    locals: list[Variable] = field(default_factory=list)
    blocks: list[Block] = field(default_factory=list)


@dataclass(kw_only=True)
class Block:
    id: int
    ops: list[Operation]
    end: Terminator


# === TYPES ===


class Type:
    pass


class PrimitiveType(Type, Enum):
    Integer = auto()
    I8 = auto()
    I16 = auto()
    I32 = auto()
    I64 = auto()
    I128 = auto()
    U8 = auto()
    U16 = auto()
    U32 = auto()
    U64 = auto()
    U128 = auto()

    # NOTE: fixed-point decimal lowers to integer

    D32 = auto()
    D64 = auto()
    D128 = auto()

    F32 = auto()
    F64 = auto()

    Boolean = auto()

    String = auto()

    Void = auto()


@dataclass
class EnumType(Type):
    variants: list[EnumVariant]


@dataclass
class EnumVariant:
    id: SymbolID
    slot: int
    type: Type


@dataclass
class StructType(Type):
    fields: list[StructField]


@dataclass
class StructField:
    name: str
    type: Type


@dataclass
class FixedArrayType(Type):
    elem: Type
    size: int


@dataclass
class SliceType(Type):
    elem: Type


@dataclass
class DynamicSliceType(Type):
    elem: Type


@dataclass
class Pointer(Type):
    elem: Type


@dataclass
class WeakPointer(Type):
    elem: Type


@dataclass
class Optional(Type):
    elem: Type


@dataclass
class Map(Type):
    key: Type
    value: Type


# === OPERATIONS ===


class Operation:
    pass


@dataclass
class Set(Operation):
    """set the variable to some value"""

    dest: Writable
    value: Operand


@dataclass
class Clear(Operation):
    """the zeroing-out operation"""

    dest: Writable


@dataclass
class Alloc(Operation):
    """allocate a new 'owned' block of memory"""

    ptr: Writable
    count: Operand


@dataclass
class Free(Operation):
    """free an 'owned' block of memory"""

    ptr: Writable


@dataclass
class NewRC(Operation):
    """allocate a new reference-counted memory block
    with a reference count initialized to zero
    """

    ptr: Writable
    size: Operand


@dataclass
class IncRC(Operation):
    """increment the reference count"""

    ptr: Writable


@dataclass
class DecRC(Operation):
    """decrement the reference count and free if zero"""

    ptr: Writable


@dataclass
class DeriveWeak(Operation):
    """get the weak pointer version of an owned/shared pointer"""

    dest: Writable
    ptr: Operand


@dataclass
class Add(Operation):
    """add two operands"""

    dest: Writable
    lhs: Operand
    rhs: Operand


@dataclass
class Sub(Operation):
    """subtract one operand from another"""

    dest: Writable
    lhs: Operand
    rhs: Operand


@dataclass
class Mul(Operation):
    """multiply two operands"""

    dest: Writable
    lhs: Operand
    rhs: Operand


@dataclass
class Div(Operation):
    """divide one operand from another"""

    dest: Writable
    lhs: Operand
    rhs: Operand


@dataclass
class Call(Operation):
    """call a function, returning its values and error into the given variables"""

    func: Function
    args: list[Operand]
    results: list[Writable]


# === TERMINATORS ===


class Terminator:
    """the last part of a block that tells it what block to go to next"""


@dataclass
class Jump(Terminator):
    """unconditional jump"""

    next: int = 0


@dataclass
class BranchZero(Terminator):
    """branch depending on whether the value is zero or not"""

    value: Operand
    z_branch: int = 0
    nz_branch: int = 0


@dataclass
class WeakPtrValid(Terminator):
    """branch depending on whether the value is zero or not"""

    value: Operand
    valid_branch: int = 0
    invalid_branch: int = 0


@dataclass
class Switch(Terminator):
    """branch to many possible places depending on a value"""

    value: Operand
    cases: list[tuple[Constant, int]]


@dataclass
class Compare(Terminator):
    """compare the lhs and rhs, branching depending on their relationship"""

    lhs: Operand
    rhs: Operand
    lt_branch: int = 0
    eq_branch: int = 0
    gt_branch: int = 0


@dataclass
class Return(Terminator):
    """return some operands and exit the function"""

    values: list[Operand]


@dataclass
class Fail(Terminator):
    """fail with an error value"""

    err: Operand | None


# === OPERANDS ===


class Operand:
    pass


type Writable = Operand


class Discard(Operand):
    pass


@dataclass
class Variable(Operand):
    id: int
    name: str
    type: Type


@dataclass
class Temporary(Operand):
    id: int
    type: PrimitiveType


@dataclass
class Parameter(Operand):
    index: int
    type: Type


@dataclass
class FieldOf(Operand):
    base: Operand
    field: str


@dataclass
class IndexOf(Operand):
    base: Operand
    elem: Operand


@dataclass
class Constant(Operand):
    value: int | float | Decimal | str | bool
