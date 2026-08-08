import functools
import sys
from dataclasses import dataclass
from enum import Enum
from pathlib import Path
from typing import TextIO, overload

from frontend import ast, lexer
from frontend.common import Location

ANSI_CLEAR = '\x1b[0m'

ANSI_BLACK = '\x1b[30m'
ANSI_RED = '\x1b[31m'
ANSI_GREEN = '\x1b[32m'
ANSI_YELLOW = '\x1b[33m'
ANSI_BLUE = '\x1b[34m'
ANSI_MAGENTA = '\x1b[35m'
ANSI_CYAN = '\x1b[36m'
ANSI_GRAY = '\x1b[37m'

ANSI_SILVER = '\x1b[90m'
ANSI_BR_RED = '\x1b[91m'
ANSI_BR_GREEN = '\x1b[92m'
ANSI_BR_YELLOW = '\x1b[93m'
ANSI_BR_BLUE = '\x1b[94m'
ANSI_BR_MAGENTA = '\x1b[95m'
ANSI_BR_CYAN = '\x1b[96m'
ANSI_WHITE = '\x1b[97m'


class DiagnosticLevel(Enum):
    Error = 2    # i.e. the program can't compile because of this error
    Warning = 1  # vet issues: valid and can compile but frowned upon (e.g. unused variables/imports)
    Notice = 0   # may be surprising but not explicitly discouraged (e.g. shadowing)

    def pretty(self, out: TextIO):
        if out.isatty():
            match self:
                case DiagnosticLevel.Error:
                    return f"{ANSI_BR_RED}error{ANSI_CLEAR}"
                case DiagnosticLevel.Warning:
                    return f"{ANSI_YELLOW}warning{ANSI_CLEAR}"
                case DiagnosticLevel.Notice:
                    return f"{ANSI_CYAN}notice{ANSI_CLEAR}"
        else:
            return self.name.lower()


@dataclass(kw_only=True)
class Diagnostic:
    level: DiagnosticLevel
    category: str
    code: str
    message: str
    file: Path | None
    start: Location | None
    end: Location | None


_diagnostics: list[Diagnostic] = []


@overload
def _emit_diagnostic(
    level: DiagnosticLevel,
    message: str,
    file: Path | None,
    start: Location | None,
    end: Location | None = None,
    /, *,
    code: str = 'XXX',
    category: str = 'general',
):
    ...


@overload
def _emit_diagnostic(
    level: DiagnosticLevel,
    message: str,
    node: ast.Node,
    /, *,
    code: str = 'XXX',
    category: str = 'general',
):
    ...


def _emit_diagnostic(
    level: DiagnosticLevel,
    message: str,
    file_or_node: Path | ast.Node | None,
    start_maybe: Location | None = None,
    end_maybe: Location | None = None,
    *,
    code: str = 'XXX',
    category: str = 'general',
):
    if isinstance(file_or_node, ast.Node):
        file = file_or_node.file
        start = file_or_node.start
        end = file_or_node.end
    elif start_maybe:
        file = file_or_node
        start = start_maybe
        end = end_maybe or start_maybe
    else:
        file = file_or_node
        start = start_maybe
        end = end_maybe

    _diagnostics.append(Diagnostic(
        level=level,
        message=message,
        file=file,
        start=start,
        end=end,
        code=code,
        category=category,
    ))


@overload
def error(
    message: str,
    file: Path | None,
    start: Location | None,
    end: Location | None = None,
    /, *,
    code: str = 'XXX',
    category: str = 'general',
):
    ...


@overload
def error(
    message: str,
    node: ast.Node,
    /, *,
    code: str = 'XXX',
    category: str = 'general',
):
    ...


def error(*args, **kwargs):
    _emit_diagnostic(DiagnosticLevel.Error, *args, **kwargs)


@overload
def warning(
    message: str,
    file: Path | None,
    start: Location | None,
    end: Location | None = None,
    /, *,
    code: str = 'XXX',
    category: str = 'general',
):
    ...


@overload
def warning(
    message: str,
    node: ast.Node,
    /, *,
    code: str = 'XXX',
    category: str = 'general',
):
    ...


def warning(*args, **kwargs):
    _emit_diagnostic(DiagnosticLevel.Warning, *args, **kwargs)


@overload
def notice(
    message: str,
    file: Path | None,
    start: Location | None,
    end: Location | None = None,
    /, *,
    code: str = 'XXX',
    category: str = 'general',
):
    ...


@overload
def notice(
    message: str,
    node: ast.Node,
    /, *,
    code: str = 'XXX',
    category: str = 'general',
):
    ...


def notice(*args, **kwargs):
    _emit_diagnostic(DiagnosticLevel.Notice, *args, **kwargs)


@functools.cache
def _get_lines(file: Path) -> list[str]:
    return [
        line.expandtabs(lexer.TAB_WIDTH)
        for line in file.read_text().splitlines()
    ]


def count_leading_spaces(s: str) -> int:
    count = 0
    for c in s:
        if c.isspace():
            count += 1
        else:
            break

    return count


def report(warnings_as_errors=False):
    """prints all of the diagnostics are returns True if any were errors
    """
    global _diagnostics

    def highlight_diagnostic(diag: Diagnostic):
        if diag.file is None or diag.start is None:
            return False

        start = diag.start
        end = diag.end or start

        lines = _get_lines(diag.file)[start.line-1:end.line]

        if len(lines) == 1:
            line = lines[0].lstrip(' ')
            sp = count_leading_spaces(lines[0])
            print(
                ANSI_BLUE,
                " -> ",
                ANSI_CLEAR,
                line,
                sep='', file=sys.stderr)
            print(
                " " * 4,
                " " * max(0, start.col - 1 - sp),
                ANSI_BR_YELLOW,
                '^' * max(1, end.col - start.col),
                ANSI_CLEAR,
                sep='', file=sys.stderr)
        elif len(lines) < 5:
            pass
        else:
            pass


    err_count = 0
    warn_count = 0
    for diag in _diagnostics:
        match diag.level:
            case DiagnosticLevel.Error:
                err_count += 1
            case DiagnosticLevel.Warning:
                warn_count += 1

        print(f"{diag.level.pretty(sys.stderr)}: {diag.message}", file=sys.stderr)
        print(
            f"  {ANSI_GRAY}(in {diag.file or '(stdin)'}",
            f" on line {diag.start.line if diag.start else '???'}){ANSI_CLEAR}",
            sep='', file=sys.stderr)
        highlight_diagnostic(diag)

    if err_count:
        print(f"encountered {err_count} errors. aborting.")
        sys.exit(1)

    if warnings_as_errors and warn_count:
        print(f"encountered {err_count} warnings. aborting.")
        sys.exit(1)

    _diagnostics = []
