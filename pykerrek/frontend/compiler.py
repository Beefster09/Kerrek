from pathlib import Path
from typing import BinaryIO, Protocol

import rich

from frontend import analysis, lowering, mir, resolver


class Backend(Protocol):
    def generate(
        self,
        out: BinaryIO,
        translation_unit: mir.TranslationUnit,
    ): ...

    def auto_suffix(self, infile: Path) -> Path: ...


def build(
    entry_point: Path,
    backend: Backend,
    *,
    out: Path | None = None,
) -> bool:
    res = resolver.Resolver()
    main = res.require(entry_point)
    res.finish_imports()

    hb = analysis.HIRBuilder(res, main)
    hir = hb.build()

    analysis.validate_hir(hir)

    tu = lowering.hir_to_mir(hir)

    if out is None:
        out = backend.auto_suffix(entry_point)

    with open(out, "wb") as fp:
        backend.generate(fp, tu)

    return True
