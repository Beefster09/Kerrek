from pathlib import Path
from typing import Protocol

from frontend import ast, diagnostics, resolver, analysis

class Backend(Protocol):
    def generate(
        self,
        outfile: Path,
        modules: list[resolver.Module],
        entry_point: resolver.Function,
    ):
        ...

def build(entry_point: Path, backend: Backend) -> bool:
    r = resolver.Resolver()
    main = r.require(entry_point)

    r.resolve_names()
    diagnostics.report()

    r.canonicalize_units()
    diagnostics.report()

    r.calculate_constants()
    diagnostics.report()

    for module in r.modules.values():
        for decl in module.file.declarations:
            analysis.validate(decl)

    return True
