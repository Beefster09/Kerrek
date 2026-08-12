from __future__ import annotations

import re
import unicodedata
from collections.abc import Iterator
from dataclasses import dataclass
from decimal import Decimal
from enum import Enum, auto
from pathlib import Path

from frontend.common import Location

TAB_WIDTH = 4


class Punctuation(Enum):
    LParen = "("
    RParen = ")"
    LSquare = "["
    RSquare = "]"
    LCurly = "{"
    RCurly = "}"
    Dot = "."
    DotDot = ".."
    Ellipsis_ = "..."
    RangeExcl = "..<"
    RangeIncl = "..="
    Comma = ","
    Colon = ":"
    Semicolon = ";"
    Assign = "="
    Move = "<-"
    EQ = "=="
    NE = "!="
    LT = "<"
    GT = ">"
    GE = ">="
    LE = "<="
    Arrow = "->"
    FatArrow = "=>"
    Plus = "+"
    Minus = "-"
    Star = "*"
    DStar = "**"
    Slash = "/"
    DSlash = "//"
    Percent = "%"
    Amp = "&"
    Caret = "^"
    At = "@"
    Hash = "#"
    Dollar = "$"
    Bang = "!"
    Question = "?"
    Bar = "|"
    Backslash = "\\"
    Tilde = "~"

    @staticmethod
    def match(fragment: str, start: int) -> Punctuation | None:
        best: Punctuation | None = None

        for sym in Punctuation:
            if fragment.startswith(sym.value, start) and (
                not best or len(sym.value) > len(best.value)
            ):
                best = sym

        return best


class Keyword(Enum):
    If = "if"
    Else = "else"
    For = "for"
    In = "in"

    Continue = "continue"
    Break = "break"
    Return = "return"
    Fail = "fail"
    Abort = "abort"

    Assume = "assume"
    Assert = "assert"
    StaticAssert = "static_assert"

    Defer = "defer"
    Where = "where"
    With = "with"
    Using = "using"
    Context = "context"

    Let = "let"
    Const = "const"

    Type = "type"
    Enum = "enum"
    Map = "map"
    Struct = "struct"
    Interface = "interface"
    Impl = "impl"
    Func = "func"

    TypeOf = "type_of"
    SizeOf = "size_of"

    Unit = "unit"
    Per = "per"

    Capability = "capability"
    Requires = "requires"

    Annotation = "annotation"

    Import = "import"

    Reinterpret = "reinterpret"
    As = "as"

    Is = "is"
    IsNot = "is_not"

    And = "and"
    Or = "or"
    Not = "not"
    Mod = "mod"

    Auto = "auto"

    Nil = "nil"
    True_ = "true"
    False_ = "false"

    Future = "future"

    Owned = "owned"
    Shared = "shared"
    Weak = "weak"
    UnsafePtr = "unsafe_ptr"

    Placeholder = "_"


@dataclass
class Garbage:
    raw: str


class Identifier(str):
    @staticmethod
    def match(line: str, start: int) -> Identifier | None:
        c = line[start]
        if c.isalpha() or c == "_":
            for i in range(start + 1, len(line)):
                c = line[i]
                if not (c.isalnum() or c == "_"):
                    return Identifier(line[start:i])

        return None


class NumberLiteralForm(Enum):
    DecimalInteger = auto()
    Hex = auto()
    Octal = auto()
    Binary = auto()
    Decimal = auto()
    Float = auto()
    HexFloat = auto()


INT_PATTERN = re.compile(r"[+-]?[0-9][0-9_]*\b")
HEX_PATTERN = re.compile(r"0x[0-9a-fA-F][0-9a-fA-F_]*\b")
OCTAL_PATTERN = re.compile(r"0o[0-7][0-7_]*\b")
BINARY_PATTERN = re.compile(r"0b[01][01_]*\b")
DECIMAL_PATTERN = re.compile(r"[+-]?[0-9][0-9_]*\.[0-9][0-9_]*(?:[Ee][+-]?\d+)?f?\b")
HEXFLOAT_PATTERN = re.compile(
    r"[+-]?0x[0-9a-fA-F][0-9a-fA-F_]*\.[0-9a-fA-F][0-9a-fA-F_]*(?:[Pp][+-]?[0-9a-fA-F]+)?\b"
)


@dataclass(kw_only=True)
class Numeric:
    raw: str
    value: int | float | Decimal
    form: NumberLiteralForm

    @staticmethod
    def match(line: str, start: int) -> Numeric | None:
        if m := DECIMAL_PATTERN.match(line, start):
            raw = m[0]
            if raw.endswith("f"):
                return Numeric(
                    raw=raw,
                    value=float(raw.rstrip("f")),
                    form=NumberLiteralForm.Float,
                )
            else:
                return Numeric(
                    raw=raw,
                    value=Decimal(raw),
                    form=NumberLiteralForm.Decimal,
                )

        elif m := HEXFLOAT_PATTERN.match(line, start):
            raw = m[0]
            return Numeric(
                raw=raw,
                value=float.fromhex(raw),
                form=NumberLiteralForm.HexFloat,
            )

        elif m := INT_PATTERN.match(line, start):
            raw = m[0]
            return Numeric(
                raw=raw,
                value=int(raw),
                form=NumberLiteralForm.DecimalInteger,
            )

        elif m := HEX_PATTERN.match(line, start):
            raw = m[0]
            return Numeric(
                raw=raw,
                value=int(raw),
                form=NumberLiteralForm.Hex,
            )

        elif m := OCTAL_PATTERN.match(line, start):
            raw = m[0]
            return Numeric(
                raw=raw,
                value=int(raw),
                form=NumberLiteralForm.Octal,
            )

        elif m := BINARY_PATTERN.match(line, start):
            raw = m[0]
            return Numeric(
                raw=raw,
                value=int(raw),
                form=NumberLiteralForm.Binary,
            )

        return None


@dataclass
class String:
    raw: str
    value: str
    is_raw: bool = False
    is_multiline: bool = False

    def __init__(self, raw: str, is_multiline=False):
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
                        return String(line[start : i + 1])
                    case "\\":
                        saw_backslash = True

            return Garbage(line[start:])

        return None


@dataclass
class Rune:
    raw: str
    codepoint: int

    @staticmethod
    def match(line: str, start: int) -> Rune | Garbage | None:
        if line[start] != "'":
            return None

        match c := line[start + 1]:
            case "\\":
                try:
                    char, length = interpret_escape(line, start + 1)
                except ValueError:
                    return Garbage(line[start : start + 2])
                end_optional = True

            case " " | "'":
                char = c
                length = 1
                end_optional = False

            case _:
                char = c
                length = 1
                end_optional = True

        if line[start + length + 1] == "'":
            length += 2
        elif end_optional:
            length += 1
        else:
            return Garbage(line[start : start + length + 1])

        r = Rune(line[start : start + length], ord(char))
        return r


def interpret_escape(line: str, start: int) -> tuple[str, int]:
    assert line[start] == "\\"
    match c := line[start + 1]:
        case "0":
            return "\0", 2
        case "n":
            return "\n", 2
        case "t":
            return "\t", 2
        case "r":
            return "\r", 2
        case "e":
            return "\x1b", 2
        case "a":
            return "\a", 2
        case "b":
            return "\b", 2
        case "x":
            return chr(int(line[start + 2 : start + 4], 16)), 4
        case "u":
            return chr(int(line[start + 2 : start + 6], 16)), 6
        case "U":
            return chr(int(line[start + 2 : start + 8], 16)), 8

        case '"' | "'" | "\\":
            return c, 2

        case _:
            raise ValueError(f"invalid escape sequence: {line[start : start + 2]}")


type TokenData = Punctuation | Keyword | Identifier | Numeric | String | Garbage | Rune


@dataclass(kw_only=True)
class Token[T: TokenData]:
    file: Path
    start: Location
    end: Location
    what: T
    first_on_line: bool
    comment_before: str | None

    def __str__(self):
        prefix = "<EOL>\n" if self.first_on_line else ""
        return f"{prefix}{self.what!r} (in '{self.file}': {self.start} to {self.end})"


def tokenize(file: Path) -> Iterator[Token]:
    with file.open("rt", encoding="utf-8") as fp:
        lines_iter = iter(enumerate(fp, 1))
        last_comment = None

        for line_no, line in lines_iter:
            first_token_on_line = True

            i = 0
            col = 1

            def advance(chars: int):
                nonlocal i, col, line

                for j in range(i, i + chars):
                    c = line[j]
                    if c == "\t":
                        tab_stop_width = TAB_WIDTH - (col - 1) % TAB_WIDTH
                        col += tab_stop_width
                    elif unicodedata.east_asian_width(c) in "FW":
                        col += 2
                    else:
                        col += 1

                i += chars

            line_len = len(line)
            while i < line_len:
                if line[i].isspace():
                    advance(1)
                    continue  # next col

                elif line.startswith(r"\\", i):
                    last_comment = line[i:]
                    break  # next line

                elif line.startswith('"""', i):
                    raise NotImplementedError("multiline strings don't work yet")

                elif string := String.single_line_match(line, i):
                    yield Token(
                        file=file,
                        start=Location(line_no, col),
                        end=Location(line_no, col + len(string.raw)),
                        what=string,
                        first_on_line=first_token_on_line,
                        comment_before=last_comment,
                    )
                    last_comment = None
                    advance(len(string.raw))

                elif rune := Rune.match(line, i):
                    yield Token(
                        file=file,
                        start=Location(line_no, col),
                        end=Location(line_no, col + len(rune.raw)),
                        what=rune,
                        first_on_line=first_token_on_line,
                        comment_before=last_comment,
                    )
                    last_comment = None
                    advance(len(rune.raw))

                elif num := Numeric.match(line, i):
                    yield Token(
                        file=file,
                        start=Location(line_no, col),
                        end=Location(line_no, col + len(num.raw)),
                        what=num,
                        first_on_line=first_token_on_line,
                        comment_before=last_comment,
                    )
                    last_comment = None
                    advance(len(num.raw))

                elif line[i] == "`" and (ident := Identifier.match(line, i + 1)):
                    if line[i + 1 + len(ident)] == "`":
                        yield Token(
                            file=file,
                            start=Location(line_no, col),
                            end=Location(line_no, col + len(ident) + 2),
                            what=ident,
                            first_on_line=first_token_on_line,
                            comment_before=last_comment,
                        )
                        last_comment = None
                        advance(len(ident) + 2)
                        break

                elif ident := Identifier.match(line, i):
                    for kw in Keyword:
                        if kw.value == ident:
                            yield Token(
                                file=file,
                                start=Location(line_no, col),
                                end=Location(line_no, col + len(kw.value)),
                                what=kw,
                                first_on_line=first_token_on_line,
                                comment_before=last_comment,
                            )
                            last_comment = None
                            advance(len(kw.value))
                            break
                    else:
                        yield Token(
                            file=file,
                            start=Location(line_no, col),
                            end=Location(line_no, col + len(ident)),
                            what=ident,
                            first_on_line=first_token_on_line,
                            comment_before=last_comment,
                        )
                        last_comment = None
                        advance(len(ident))

                elif sym := Punctuation.match(line, i):
                    yield Token(
                        file=file,
                        start=Location(line_no, col),
                        end=Location(line_no, col + len(sym.value)),
                        what=sym,
                        first_on_line=first_token_on_line,
                        comment_before=last_comment,
                    )
                    last_comment = None
                    advance(len(sym.value))

                else:
                    yield Token(
                        file=file,
                        start=Location(line_no, col),
                        end=Location(line_no, col + 1),
                        what=Garbage(line[i]),
                        first_on_line=first_token_on_line,
                        comment_before=last_comment,
                    )
                    last_comment = None
                    advance(1)

                first_token_on_line = False
