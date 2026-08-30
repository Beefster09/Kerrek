from __future__ import annotations

from dataclasses import dataclass, field
from decimal import Decimal

from frontend import hir
from frontend.resolver import SymbolID


@dataclass(kw_only=True)
class TranslationUnit:
    types: list[hir.Type] = field(default_factory=list)
    globals: list[GlobalVar] = field(default_factory=list)
    functions: list[Function] = field(default_factory=list)


@dataclass(kw_only=True)
class Function:
    id: SymbolID
    name: str
    no_mangle: bool = False  # never mangle the name if this is true
    params: list[Parameter]
    returns: list[hir.Type]
    error: hir.Type | None
    locals: list[LocalVar] = field(default_factory=list)
    blocks: list[Block] = field(default_factory=list)


@dataclass(kw_only=True)
class Block:
    id: int
    ops: list[Operation]
    end: Terminator


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
class Convert(Operation):
    """convert a value to the given type"""

    dest: Writable
    value: Operand
    type: MachineType


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
class GetAddr(Operation):
    """get the weak pointer version of an owned/shared pointer"""

    dest: Writable
    addressible: Addressable


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
class Rem(Operation):
    """get the remainder of dividing one operand by another"""

    dest: Writable
    lhs: Operand
    rhs: Operand


@dataclass
class Truncate(Operation):
    """truncate the result of division"""

    dest: Writable
    value: Operand


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

    next: int


@dataclass
class BranchZero(Terminator):
    """branch depending on whether the value is zero or not"""

    value: Operand
    z_branch: int
    nz_branch: int


@dataclass
class WeakPtrValid(Terminator):
    """branch depending on whether the value is zero or not"""

    value: Operand
    valid_branch: int
    invalid_branch: int


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
    lt_branch: int
    eq_branch: int
    gt_branch: int


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
type Addressable = Operand


class Discard(Operand):
    pass


@dataclass
class GlobalVar(Operand):
    id: int
    name: str
    type: hir.Type


@dataclass
class LocalVar(Operand):
    id: int
    name: str
    type: hir.Type


@dataclass
class Temporary(Operand):
    id: int
    type: MachineType


@dataclass
class Parameter(Operand):
    index: int
    type: hir.Type


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
    value: int | float | Decimal | str | bool | None


@dataclass
class Dereferenced(Operand):
    base: Operand
    indirection: int


def is_writable(opd: Operand) -> bool:
    match opd:
        case GlobalVar() | LocalVar() | Dereferenced() | Discard():
            return True
        case Constant() | Parameter() | Temporary():
            return False
        case FieldOf() | IndexOf():
            return is_writable(opd.base)
        case _:
            raise NotImplementedError(f"cannot determine if {opd} is writable")
