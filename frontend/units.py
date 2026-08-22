from __future__ import annotations

from collections import Counter
from typing import TYPE_CHECKING, ClassVar

from frontend.hir import SymbolID

if TYPE_CHECKING:
    from resolver import BaseUnit

SUPERSCRIPT_DIGITS = "⁰¹²³⁴⁵⁶⁷⁸⁹"
SUPERSCRIPT_NEGATIVE = "⁻"


def superscript_number(n: int) -> str:
    digits = []

    if n < 0:
        digits.append(SUPERSCRIPT_NEGATIVE)

    x = int(abs(n))
    while x > 0:
        digits.append(SUPERSCRIPT_DIGITS[x % 10])
        x //= 10

    return "".join(digits)


class CanonicalUnit(Counter[SymbolID]):
    _base_unit_names: ClassVar[dict[SymbolID, str]] = {}

    @classmethod
    def register_unit_name(cls, base_unit: BaseUnit):
        cls._base_unit_names[base_unit.id] = base_unit.ast.name

    def __str__(self):
        components = []
        for comp_id, exp in self.most_common():
            if exp == 0:
                continue

            unit_name = self._base_unit_names.get(comp_id, f"unit{comp_id}")

            if exp == 1:
                components.append(str(unit_name))
            else:
                components.append(f"{unit_name}{superscript_number(exp)}")

        if components:
            return " ".join(components)
        else:
            return "<ratio>"

    def __repr__(self):
        components = []
        for comp_id, exp in self.most_common():
            if exp == 0:
                continue

            unit_name = self._base_unit_names.get(comp_id, "<MISSING>")

            if exp == 1:
                components.append(str(unit_name))
            else:
                components.append(f"{unit_name}^{exp}")

        if components:
            return f"unit({' '.join(components)})"
        else:
            return "unit()"

    def __mul__(self, exponent: int):
        result = CanonicalUnit()

        for comp, exp in self.items():
            result[comp] += exp * exponent

        return result

    __rmul__ = __mul__

    def inplace_combine(self, other: CanonicalUnit, exponent: int):
        for comp, exp in other.items():
            self[comp] += exp * exponent

    @staticmethod
    def combine(
        a: CanonicalUnit,
        a_exp: int,
        b: CanonicalUnit,
        b_exp: int,
    ) -> CanonicalUnit:
        result = CanonicalUnit()

        for comp, exp in a.items():
            result[comp] += exp * a_exp

        for comp, exp in b.items():
            result[comp] += exp * b_exp

        return result
