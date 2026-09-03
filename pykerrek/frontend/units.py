from __future__ import annotations

from collections import Counter
from collections.abc import Iterable, Mapping
from enum import Enum, auto
from typing import TYPE_CHECKING, ClassVar, overload

from frontend.common import SymbolID

if TYPE_CHECKING:
    from frontend.resolver import BaseUnit


class IndeterminateUnit(Enum):
    NoUnit = auto()  # explicit `nil` unit
    Flexible = auto()  # unit is `_`; unitless, but can participate in math with units
    Inferred = auto()  # inferred from usage


SUPERSCRIPT_DIGITS = "⁰¹²³⁴⁵⁶⁷⁸⁹"
SUPERSCRIPT_NEGATIVE = "⁻"


def superscript_number(n: int) -> str:
    digits = []

    x = int(abs(n))
    while x > 0:
        digits.append(SUPERSCRIPT_DIGITS[x % 10])
        x //= 10

    if n < 0:
        digits.append(SUPERSCRIPT_NEGATIVE)

    digits.reverse()
    return "".join(digits)


class CanonicalUnit(Counter[SymbolID]):
    _base_unit_names: ClassVar[dict[SymbolID, str]] = {}

    @classmethod
    def register_unit_name(cls, base_unit: BaseUnit):
        cls._base_unit_names[base_unit.id] = base_unit.ast.name

    @overload
    def __init__(
        self,
        initial: None = None,
        /,
        *,
        is_absolute=False,
    ): ...
    @overload
    def __init__(
        self,
        initial: Mapping[SymbolID, int],
        /,
        *,
        is_absolute=False,
    ): ...
    @overload
    def __init__(
        self,
        initial: Iterable[SymbolID],
        /,
        *,
        is_absolute=False,
    ): ...
    @overload
    def __init__(
        self,
        initial: Iterable[tuple[SymbolID, int]],
        /,
        *,
        is_absolute=False,
    ): ...

    def __init__(
        self,
        initial: Mapping[SymbolID, int]
        | Iterable[SymbolID]
        | Iterable[tuple[SymbolID, int]]
        | None = None,
        /,
        *,
        is_absolute=False,
    ):
        super().__init__()
        self.is_absolute = is_absolute

        if isinstance(initial, Mapping):
            for k, v in initial.items():
                assert not isinstance(k, tuple)
                self[k] = v

        elif isinstance(initial, Iterable):
            for item in initial:
                if isinstance(item, tuple):
                    self[item[0]] = item[1]
                else:
                    self[item] += 1

    def __str__(self):
        components = []
        for comp_id, exp in self.most_common():
            if exp == 0:
                continue

            unit_name = self._base_unit_names.get(comp_id, f"UNIT#{comp_id}")

            if exp == 1:
                components.append(str(unit_name))
            else:
                components.append(f"{unit_name}{superscript_number(exp)}")

        if components:
            return " ".join(components)
        else:
            return "1"

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
            return "unit(1)"

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
