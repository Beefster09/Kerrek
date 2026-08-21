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
    res = resolver.Resolver()
    main = res.require(entry_point)
    res.finish_imports()

    hb = analysis.HIRBuilder(res, main)
    hir = hb.build()

    analysis.validate_hir(hir)

    tu = lowering.hir_to_mir(hir)

    rich.print(tu)

    return True
