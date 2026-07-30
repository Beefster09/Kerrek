from dataclasses import dataclass
from pathlib import Path

from frontend.lexer import Location


@dataclass
class Diagnostic:
    message: str
    file: Path
    start: Location
    end: Location


@dataclass
class Error(Diagnostic):
    pass


@dataclass
class Warning(Diagnostic):
    pass


@dataclass
class Info(Diagnostic):
    pass
