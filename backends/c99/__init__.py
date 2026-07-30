from pathlib import Path

from frontend import ast

class Backend:
    def generate(
        self,
        outfile: Path,
        files: list[ast.File],
        entry_point: ast.FuncDefinition,
    ):
        raise NotImplementedError()
