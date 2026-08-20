from pathlib import Path
from typing import Protocol

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

    r.resolve_names()
    r.canonicalize_units()
    r.canonicalize_types()
    r.build_unit_conversions()

    for module in r.modules.values():
        for decl in module.file.declarations:
            analysis.validate(decl)

    diagnostics.report()

    tu = lowering.translate_to_mir(r, main)

    import rich

    rich.print(tu)

    return True
