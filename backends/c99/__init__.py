import io
from pathlib import Path
from typing import BinaryIO

from backends.c99.dump import emit_function, emit_function_proto
from frontend import mir


class Backend:
    def generate(
        self,
        out: BinaryIO,
        translation_unit: mir.TranslationUnit,
    ):
        text_out = io.TextIOWrapper(out, encoding="utf-8")

        print("#include <stdbool.h>", file=text_out)
        print("#include <stdint.h>", file=text_out)

        for func in translation_unit.functions:
            emit_function_proto(text_out, func)

        for func in translation_unit.functions:
            emit_function(text_out, func)

    def auto_suffix(self, infile: Path):
        return infile.with_suffix(".c")
