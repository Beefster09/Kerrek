from pathlib import Path
from typing import Protocol

import rich

from frontend import analysis, diagnostics, lowering, mir, resolver


class Backend(Protocol):
    def generate(
        self,
        outfile: Path,
        translation_unit: mir.TranslationUnit,
    ): ...


def build(entry_point: Path, backend: Backend) -> bool:
    r = resolver.Resolver()
    main = r.require(entry_point)
    r.finish_imports()
    rich.print(main.file)

    for module in r.modules.values():
        for decl in module.file.declarations:
            analysis.validate(decl)

    diagnostics.report()

    tu = lowering.translate_to_mir(r, main)

    rich.print(tu)

    return True
