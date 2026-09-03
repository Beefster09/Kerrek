import functools
import sys
from dataclasses import dataclass, field
from enum import Enum
from pathlib import Path
from typing import Protocol, Self, TextIO, overload, runtime_checkable

from frontend import lexer
from frontend.common import Location, Where

ANSI_CLEAR = "\x1b[0m"

ANSI_BLACK = "\x1b[30m"
ANSI_RED = "\x1b[31m"
ANSI_GREEN = "\x1b[32m"
ANSI_YELLOW = "\x1b[33m"
ANSI_BLUE = "\x1b[34m"
ANSI_MAGENTA = "\x1b[35m"
ANSI_CYAN = "\x1b[36m"
ANSI_GRAY = "\x1b[37m"

ANSI_SILVER = "\x1b[90m"
ANSI_BR_RED = "\x1b[91m"
ANSI_BR_GREEN = "\x1b[92m"
ANSI_BR_YELLOW = "\x1b[93m"
ANSI_BR_BLUE = "\x1b[94m"
ANSI_BR_MAGENTA = "\x1b[95m"
ANSI_BR_CYAN = "\x1b[96m"
ANSI_WHITE = "\x1b[97m"


@runtime_checkable
class HasSourceLoc(Protocol):
    file: Path
    start: Location
    end: Location

    def where(self) -> Where: ...


class DiagnosticLevel(Enum):
    Error = 2  # i.e. the program can't compile because of this error
    Warning = 1  # vet issues: valid and can compile but frowned upon (e.g. unused variables/imports)
    Notice = 0  # may be surprising but not explicitly discouraged (e.g. shadowing)

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
class DiagnosticReference:
    message: str
    file: Path | None
    start: Location | None
    end: Location | None


@dataclass(kw_only=True)
class Diagnostic:
    level: DiagnosticLevel
    category: str
    code: str
    message: str
    file: Path | None
    start: Location | None
    end: Location | None

    suggestions: list[str] = field(default_factory=list)
    references: list[DiagnosticReference] = field(default_factory=list)

    def suggest(self, message: str) -> Self:
        self.suggestions.append(message)
        return self

    @overload
    def reference(
        self,
        message: str,
        file: Path | None,
        start: Location | None,
        end: Location | None = None,
        /,
    ) -> Self: ...

    @overload
    def reference(
        self,
        message: str,
        node: HasSourceLoc,
        /,
    ) -> Self: ...

    def reference(
        self,
        message: str,
        file_or_node: Path | HasSourceLoc | None,
        start_maybe: Location | None = None,
        end_maybe: Location | None = None,
    ) -> Self:
        if isinstance(file_or_node, HasSourceLoc):
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

        self.references.append(
            DiagnosticReference(
                message=message,
                file=file,
                start=start,
                end=end,
            )
        )

        return self


_diagnostics: list[Diagnostic] = []


@overload
def _emit_diagnostic(
    level: DiagnosticLevel,
    message: str,
    file: Path | None,
    start: Location | None,
    end: Location | None = None,
    /,
    *,
    code: str = "XXX",
    category: str = "general",
) -> Diagnostic: ...


@overload
def _emit_diagnostic(
    level: DiagnosticLevel,
    message: str,
    node: HasSourceLoc,
    /,
    *,
    code: str = "XXX",
    category: str = "general",
) -> Diagnostic: ...


def _emit_diagnostic(
    level: DiagnosticLevel,
    message: str,
    file_or_node: Path | HasSourceLoc | None,
    start_maybe: Location | None = None,
    end_maybe: Location | None = None,
    *,
    code: str = "XXX",
    category: str = "general",
) -> Diagnostic:
    if isinstance(file_or_node, HasSourceLoc):
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

    diag = Diagnostic(
        level=level,
        message=message,
        file=file,
        start=start,
        end=end,
        code=code,
        category=category,
    )
    _diagnostics.append(diag)

    return diag


@overload
def error(
    message: str,
    file: Path | None,
    start: Location | None,
    end: Location | None = None,
    /,
    *,
    code: str = "XXX",
    category: str = "general",
) -> Diagnostic: ...


@overload
def error(
    message: str,
    node: HasSourceLoc,
    /,
    *,
    code: str = "XXX",
    category: str = "general",
) -> Diagnostic: ...


def error(*args, **kwargs) -> Diagnostic:
    return _emit_diagnostic(DiagnosticLevel.Error, *args, **kwargs)


@overload
def warning(
    message: str,
    file: Path | None,
    start: Location | None,
    end: Location | None = None,
    /,
    *,
    code: str = "XXX",
    category: str = "general",
) -> Diagnostic: ...


@overload
def warning(
    message: str,
    node: HasSourceLoc,
    /,
    *,
    code: str = "XXX",
    category: str = "general",
) -> Diagnostic: ...


def warning(*args, **kwargs) -> Diagnostic:
    return _emit_diagnostic(DiagnosticLevel.Warning, *args, **kwargs)


@overload
def notice(
    message: str,
    file: Path | None,
    start: Location | None,
    end: Location | None = None,
    /,
    *,
    code: str = "XXX",
    category: str = "general",
) -> Diagnostic: ...


@overload
def notice(
    message: str,
    node: HasSourceLoc,
    /,
    *,
    code: str = "XXX",
    category: str = "general",
) -> Diagnostic: ...


def notice(*args, **kwargs) -> Diagnostic:
    return _emit_diagnostic(DiagnosticLevel.Notice, *args, **kwargs)


@functools.cache
def _get_lines(file: Path) -> list[str]:
    return [line.expandtabs(lexer.TAB_WIDTH) for line in file.read_text().splitlines()]


def count_leading_spaces(s: str) -> int:
    count = 0
    for c in s:
        if c.isspace():
            count += 1
        else:
            break

    return count


def _show_diagnostic_source(
    diag: Diagnostic | DiagnosticReference,
    *,
    context_lines=3,
):
    if diag.file is None or diag.start is None:
        return False

    print(
        f"    {ANSI_GRAY}(in {diag.file or '<stdin>'}",
        f" on line {diag.start.line if diag.start else '???'}){ANSI_CLEAR}",
        sep="",
        file=sys.stderr,
    )

    start = diag.start
    end = diag.end or start

    lines = _get_lines(diag.file)[start.line - 1 : end.line]

    if len(lines) == 1:
        line = lines[0].lstrip(" ")
        indent = count_leading_spaces(lines[0])
        print(
            ANSI_BLUE,
            f"{start.line: 5} | ",
            ANSI_CLEAR,
            line,
            sep="",
            file=sys.stderr,
        )
        print(
            " " * (8 + max(0, start.col - 1 - indent)),
            ANSI_BR_YELLOW,
            "^" * max(1, end.col - start.col),
            ANSI_CLEAR,
            sep="",
            file=sys.stderr,
        )
    else:
        indent = min(count_leading_spaces(line) for line in lines if not line.isspace())
        print(
            " " * (8 + max(0, start.col - 1 - indent)),
            ANSI_BR_YELLOW,
            "|<---",
            ANSI_CLEAR,
            sep="",
            file=sys.stderr,
        )

        should_snip = len(lines) > 3 + context_lines * 2
        snip_start = start.line + context_lines + 1
        snip_end = end.line - context_lines - 1

        for line_no, line in enumerate(lines, start.line):
            if should_snip:
                if line_no == snip_start:
                    print(
                        ANSI_BLUE,
                        "  ... | ",
                        ANSI_GRAY,
                        f"\\\\ ... {len(lines) - 8} lines omitted ...",
                        ANSI_CLEAR,
                        sep="",
                        file=sys.stderr,
                    )
                    continue
                elif snip_start <= line_no <= snip_end:
                    continue

            print(
                ANSI_BLUE,
                f"{line_no: 5} | ",
                ANSI_CLEAR,
                line[indent:],
                sep="",
                file=sys.stderr,
            )

        print(
            " " * (4 + max(0, end.col - 1 - indent)),
            ANSI_BR_YELLOW,
            "--->|",
            ANSI_CLEAR,
            sep="",
            file=sys.stderr,
        )


def report(warnings_as_errors=False):
    """prints all of the diagnostics are returns True if any were errors"""
    global _diagnostics

    err_count = 0
    warn_count = 0
    for diag in _diagnostics:
        match diag.level:
            case DiagnosticLevel.Error:
                err_count += 1
            case DiagnosticLevel.Warning:
                warn_count += 1

        print(f"{diag.level.pretty(sys.stderr)}: {diag.message}", file=sys.stderr)
        _show_diagnostic_source(diag)

        for ref in diag.references:
            print(f"    {ANSI_BR_BLUE}context{ANSI_CLEAR}: {ref.message}")
            _show_diagnostic_source(ref)

        for message in diag.suggestions:
            print(
                f"    {ANSI_BR_GREEN}suggestion{ANSI_CLEAR}: {message}", file=sys.stderr
            )

    if err_count:
        print(
            ANSI_BR_MAGENTA,
            f"encountered {err_count} error{'s' * (err_count != 1)}",
            ANSI_CLEAR,
            sep="",
            file=sys.stderr,
        )
        sys.exit(1)

    if warnings_as_errors and warn_count:
        print(
            ANSI_BR_MAGENTA,
            f"encountered {warn_count} warning{'s' * (warn_count != 1)}",
            ANSI_CLEAR,
            sep="",
            file=sys.stderr,
        )
        sys.exit(1)

    _diagnostics = []
