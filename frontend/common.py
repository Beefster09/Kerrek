from dataclasses import dataclass
from enum import Enum, auto
from typing import NamedTuple


class Location(NamedTuple):
    line: int
    col: int

    def __str__(self):
        return f"<line {self.line}, col {self.col}>"


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
