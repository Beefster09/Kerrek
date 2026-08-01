from pathlib import Path
from typing import Protocol

from frontend import ast, diagnostics, lexer, parser, resolver

class Backend(Protocol):
    def generate(
        self,
        outfile: Path,
        files: list[ast.File],
        entry_point: ast.FuncDefinition,
    ):
        ...

def build(entry_point: Path, backend: Backend) -> bool:
    r = resolver.Resolver()
    main = r.require(entry_point)

    r.resolve_names()
    diagnostics.report()

    r.canonicalize_units()
    diagnostics.report()

    for module in r.modules:
        pass

    return True
