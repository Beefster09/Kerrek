from __future__ import annotations

from enum import Enum, auto
from dataclasses import dataclass
from decimal import Decimal
from fractions import Fraction
from pathlib import Path
from typing import Iterator, NamedTuple
import re


class Location(NamedTuple):
    line: int
    col: int

    def __str__(self):
        return f"<line {self.line}, col {self.col}>"


class Punctuation(Enum):
    LParen = '('
    RParen = ')'
    LSquare = '['
    RSquare = ']'
    LCurly = '{'
    RCurly = '}'
    Dot = '.'
    Comma = ','
    Colon = ':'
    Semicolon = ';'
    Ellipsis_ = '...'
    Assign = '='
    Move = '<-'
    EQ = '=='
    NE = '!='
    LT = '<'
    GT = '>'
    GE = '>='
    LE = '<='
    Arrow = '->'
    FatArrow = '=>'
    Plus = '+'
    Minus = '-'
    Mul = '*'
    Exp = '**'
    Div = '/'
    FloorDiv = '//'
    Percent = '%'
    Amp = '&'
    Caret = '^'
    At = '@'
    Hash = '#'
    Dollar = '$'
    Bang = '!'
    Question = '?'
    Bar = '|'
    Backslash = '\\'
    Tilde = '~'
    Tick = '`'
    Apostrophe = "'"

    EOL = '<EOL>'

    @staticmethod
    def match(fragment: str, start: int) -> Punctuation | None:
        best: Punctuation | None = None

        for sym in Punctuation:
            if sym is Punctuation.EOL:
                continue

            if (
                fragment.startswith(sym.value, start)
                and (not best or len(sym.value) > len(best.value))
            ):
                best = sym

        return best


class Keyword(Enum):
    If = 'if'
    Else = 'else'
    Loop = 'loop'
    In = 'in'

    Continue = 'continue'
    Break = 'break'
    Return = 'return'
    Abort = 'abort'
    Fail = 'fail'

    Where = 'where'
    With = 'with'
    Using = 'using'
    Requires = 'requires'

    Context = 'context'
    Temp = 'temp'

    Map = 'map'

    Type = 'type'
    Struct = 'struct'
    Interface = 'interface'
    Func = 'func'

    Unit = 'unit'
    Dimension = 'dimension'

    Capability = 'capability'
    Grant = 'grant'
    Revoke = 'revoke'

    Import = 'import'
    From = 'from'

    As = 'as'
    Is = 'is'
    And = 'and'
    Or = 'or'
    Not = 'not'

    Auto = 'auto'

    Nil = 'nil'
    True_ = 'true'
    False_ = 'false'

    Owned = 'owned'
    Shared = 'shared'
    Weak = 'weak'
    UnsafePtr = 'unsafe_ptr'


@dataclass
class Identifier:
    name: str

    @staticmethod
    def match(line: str, start: int) -> Identifier | None:
        c = line[start]
        if c.isalpha() or c == '_':
            for i in range(start + 1, len(line)):
                c = line[i]
                if not (c.isalnum() or c == '_'):
                    return Identifier(line[start:i])

        return None


class NumberLiteralKind(Enum):
    Integer = auto()
    Decimal = auto()
    BinFloat = auto()
    Rational = auto()


INT_PATTERN = re.compile(r'[+-]?[0-9][0-9_]*')
HEX_PATTERN = re.compile(r'0x[0-9a-fA-F][0-9a-fA-F_]*')
OCTAL_PATTERN = re.compile(r'0o[0-7][0-7_]*')
BINARY_PATTERN = re.compile(r'0b[01][01_]*')
DECIMAL_PATTERN = re.compile(r'[+-]?[0-9][0-9_]*.[0-9][0-9_]*(?:[Ee][+-]?\d+)?f?')
HEXFLOAT_PATTERN = re.compile(r'[+-]?0x[0-9a-fA-F][0-9a-fA-F_]*.[0-9a-fA-F][0-9a-fA-F_]*(?:[Pp][+-]?[0-9a-fA-F]+)?')
RATIONAL_PATTERN = re.compile(r'([+-]?[0-9][0-9_]*)/([0-9][0-9_]*)')


@dataclass(kw_only=True)
class Numeric:
    raw: str
    value: int | float | Decimal | Fraction
    kind: NumberLiteralKind

    @staticmethod
    def match(line: str, start: int) -> Numeric | None:
        if m := RATIONAL_PATTERN.match(line, start):
            return Numeric(
                raw=m[0],
                value=Fraction(int(m[1]), int(m[2])),
                kind=NumberLiteralKind.Rational,
            )

        elif m := DECIMAL_PATTERN.match(line, start):
            raw = m[0]
            if raw.endswith('f'):
                return Numeric(
                    raw=raw,
                    value=float(raw),
                    kind=NumberLiteralKind.BinFloat,
                )
            else:
                return Numeric(
                    raw=raw,
                    value=Decimal(raw),
                    kind=NumberLiteralKind.Decimal,
                )

        elif m := HEXFLOAT_PATTERN.match(line, start):
            raw = m[0]
            return Numeric(
                raw=raw,
                value=float.fromhex(raw),
                kind=NumberLiteralKind.BinFloat,
            )

        elif m := (
                INT_PATTERN.match(line, start)
                or HEX_PATTERN.match(line, start)
                or OCTAL_PATTERN.match(line, start)
                or BINARY_PATTERN.match(line, start)
            ):
            raw = m[0]
            return Numeric(
                raw=raw,
                value=int(raw),
                kind=NumberLiteralKind.Integer,
            )

        return None


@dataclass
class String:
    raw: str
    value: str
    is_raw: bool = False
    is_multiline: bool = False

    def __init__(self, raw: str, is_multiline = False) -> None:
        self.raw = raw
        self.value = "<TODO>"
        self.is_multiline = is_multiline

    @staticmethod
    def single_line_match(line: str, start: int) -> String | Garbage | None:
        if line[start] == '"':
            saw_backslash = False
            for i in range(start + 1, len(line)):
                if saw_backslash:
                    saw_backslash = False
                    continue

                match line[i]:
                    case '"':
                        return String(line[start:i+1])
                    case '\\':
                        saw_backslash = True

            return Garbage(line[start:])

        return None


@dataclass
class Garbage:
    raw: str


@dataclass
class Comment:
    content: str


@dataclass(kw_only=True)
class Token:
    file: Path
    start: Location
    end: Location
    what: Punctuation | Keyword | Identifier | Numeric | String | Comment | Garbage

    def __str__(self):
        return f"{self.what!r} (in '{self.file}': {self.start} to {self.end})"


def tokenize(file: Path, include_comments=False) -> Iterator[Token]:
    with file.open('rt', encoding='utf-8') as fp:
        multiline_string_start: Location | None = None
        multiline_string_parts: list[str] = []

        for line_no, line in enumerate(fp, 1):

            i = 0
            line_len = len(line)
            while i < line_len:
                if multiline_string_start:
                    if line.startswith('"""', i):
                        multiline_string_parts.append('')  # TODO
                        yield Token(
                            file=file,
                            start=multiline_string_start,
                            end=Location(line_no, i + 4),
                            what=String('\n'.join(multiline_string_parts))
                        )
                        multiline_string_start = None

                elif line[i].isspace():
                    i += 1
                    continue  # next col

                elif line.startswith(r'\\', i):
                    if include_comments:
                        yield Token(
                            file=file,
                            start=Location(line_no, i+1),
                            end=Location(line_no, len(line)),
                            what=Comment(line[i:])
                        )
                    break  # next line

                elif line.startswith('"""', i):
                    multiline_string_start = Location(line_no, i+1)
                    multiline_string_parts = []
                    i += 3

                elif string := String.single_line_match(line, i):
                    yield Token(
                        file=file,
                        start=Location(line_no, i + 1),
                        end=Location(line_no, i + 1 + len(string.raw)),
                        what=string,
                    )
                    i += len(string.raw)

                elif num := Numeric.match(line, i):
                    yield Token(
                        file=file,
                        start=Location(line_no, i + 1),
                        end=Location(line_no, i + 1 + len(num.raw)),
                        what=num,
                    )
                    i += len(num.raw)

                elif ident := Identifier.match(line, i):
                    for kw in Keyword:
                        if kw.value == ident.name:
                            yield Token(
                                file=file,
                                start=Location(line_no, i + 1),
                                end=Location(line_no, i + 1 + len(kw.value)),
                                what=kw,
                            )
                            i += len(kw.value)
                            break
                    else:
                        yield Token(
                            file=file,
                            start=Location(line_no, i + 1),
                            end=Location(line_no, i + 1 + len(ident.name)),
                            what=ident,
                        )
                        i += len(ident.name)

                elif sym := Punctuation.match(line, i):
                    yield Token(
                        file=file,
                        start=Location(line_no, i + 1),
                        end=Location(line_no, i + 1 + len(sym.value)),
                        what=sym,
                    )
                    i += len(sym.value)

                else:
                    yield Token(
                        file=file,
                        start=Location(line_no, i + 1),
                        end=Location(line_no, i + 2),
                        what=Garbage(line[i]),
                    )
                    i += 1

            line_end = Location(line_no, len(line) + 1)
            yield Token(
                file=file,
                start=line_end,
                end=line_end,
                what=Punctuation.EOL,
            )
