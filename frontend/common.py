from typing import NamedTuple


class Location(NamedTuple):
    line: int
    col: int

    def __str__(self):
        return f"<line {self.line}, col {self.col}>"
