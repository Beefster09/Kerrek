from collections.abc import Iterable
from dataclasses import dataclass
from enum import Enum, auto
from pathlib import Path
from typing import NamedTuple, NewType, TypedDict

SymbolID = NewType("SymbolID", int)


class Location(NamedTuple):
    line: int
    col: int

    def __str__(self):
        return f"<line {self.line}, col {self.col}>"


class Where(TypedDict):
    file: Path
    start: Location
    end: Location


@dataclass
class RuneValue:
    codepoint: int

    @property
    def char(self):
        return chr(self.codepoint)


@dataclass
class ByteValue:
    value: int
    # TODO: validation


class PointerOwnership(Enum):
    Borrowed = auto()
    Owned = auto()
    Shared = auto()
    Weak = auto()
    Unsafe = auto()


class UnaryOp(Enum):
    Positive = "+"
    Negate = "-"

    Not = "not"


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


def get_first[K, V](dicts: Iterable[dict[K, V]], key: K) -> V | None:
    for d in dicts:
        if key in d:
            return d[key]

    return None
