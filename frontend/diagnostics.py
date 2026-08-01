import sys
from dataclasses import dataclass
from enum import Enum
from pathlib import Path
from typing import TextIO, overload

from frontend import ast
from frontend.lexer import Location


class DiagnosticLevel(Enum):
    Error = 2    # i.e. the program can't compile because of this error
    Warning = 1  # vet issues: valid and can compile but frowned upon
    Info = 0     # may be surprising but not explicitly discouraged (e.g. shadowing)

    def pretty(self, out: TextIO):
        if out.isatty():
            match self:
                case DiagnosticLevel.Error:
                    return "\x1b[91merror\x1b[0m"
                case DiagnosticLevel.Warning:
                    return "\x1b[32mwarning\x1b[0m"
                case DiagnosticLevel.Info:
                    return "\x1b[36minfo\x1b[0m"
        else:
            return self.name.lower()


@dataclass(kw_only=True)
class Diagnostic:
    level: DiagnosticLevel
    category: str
    code: str
    message: str
    file: Path
    start: Location
    end: Location


_diagnostics: list[Diagnostic] = []


@overload
def _emit_diagnostic(
    level: DiagnosticLevel,
    message: str,
    file: Path,
    start: Location,
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
    file_or_node: Path | ast.Node,
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
        raise TypeError("start and end location required")

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
    file: Path,
    start: Location,
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
    file: Path,
    start: Location,
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
def info(
    message: str,
    file: Path,
    start: Location,
    end: Location | None = None,
    /, *,
    code: str = 'XXX',
    category: str = 'general',
):
    ...


@overload
def info(
    message: str,
    node: ast.Node,
    /, *,
    code: str = 'XXX',
    category: str = 'general',
):
    ...


def info(*args, **kwargs):
    _emit_diagnostic(DiagnosticLevel.Info, *args, **kwargs)


def report(warnings_as_errors=False):
    """prints all of the diagnostics are returns True if any were errors
    """
    global _diagnostics

    err_count = 0
    for diag in _diagnostics:
        if diag.level is DiagnosticLevel.Error:
            err_count += 1

        print(f"{diag.level.pretty(sys.stdout)}: {diag.message}", file=sys.stdout)
        print(f"\tin {diag.file} at {diag.start}", file=sys.stdout)

    if err_count:
        print(f"encountered {err_count} errors. aborting.")
        sys.exit(1)

    _diagnostics = []
