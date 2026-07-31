from dataclasses import dataclass
from pathlib import Path
from typing import overload

from frontend import ast
from frontend.lexer import Location


@dataclass
class Diagnostic:
    message: str
    file: Path
    start: Location
    end: Location

    @overload
    def __init__(
        self,
        message: str,
        file: Path,
        start: Location,
        end: Location | None = None,
        /,
    ):
        ...

    @overload
    def __init__(
        self,
        message: str,
        node: ast.Node,
        /,
    ):
        ...

    def __init__(
        self,
        message: str,
        file_or_node: Path | ast.Node,
        start_maybe: Location | None = None,
        end_maybe: Location | None = None,
    ):
        self.message = message
        if isinstance(file_or_node, ast.Node):
            self.file = file_or_node.file
            self.start = file_or_node.start
            self.end = file_or_node.end
        elif start_maybe:
            self.file = file_or_node
            self.start = start_maybe
            self.end = end_maybe or start_maybe
        else:
            raise TypeError("start and end location required")


class Error(Diagnostic):
    pass


class Warning(Diagnostic):
    pass


class Info(Diagnostic):
    pass


def report(diags: list[Diagnostic]) -> bool:
    """prints all of the diagnostics are returns True if any were errors
    """
    any_errors = False
    for diag in diags:
        if isinstance(diag, Error):
            any_errors = True

        print(f"{type(diag).__name__.lower()}: {diag.message}")
        print(f"\tin {diag.file} at {diag.start}")

    return any_errors
