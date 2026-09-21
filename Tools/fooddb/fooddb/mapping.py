"""Mapping from FDC nutrient ids to output columns.

Each output column lists the FDC nutrient ids to try in order; the first id
that has an amount for a food wins. Units are validated against nutrient.csv
before any food is read, so a silently changed unit fails the build.
"""

from __future__ import annotations

from collections.abc import Mapping
from dataclasses import dataclass

from .errors import MappingError


@dataclass(frozen=True)
class NutrientSpec:
    """One output column and the FDC nutrient ids that can populate it."""

    column: str
    ids: tuple[int, ...]
    unit: str

    @property
    def primary_id(self) -> int:
        return self.ids[0]


NUTRIENT_SPECS: tuple[NutrientSpec, ...] = (
    NutrientSpec("kcal_100g", (1008, 2047, 2048), "KCAL"),
    NutrientSpec("protein_100g", (1003,), "G"),
    NutrientSpec("carb_100g", (1005,), "G"),
    NutrientSpec("fat_100g", (1004,), "G"),
    NutrientSpec("satfat_100g", (1258,), "G"),
    NutrientSpec("fiber_100g", (1079, 2033), "G"),
    NutrientSpec("sugar_100g", (2000, 1063), "G"),
    NutrientSpec("sodium_mg_100g", (1093,), "MG"),
)

ENERGY_COLUMN = "kcal_100g"

NUTRIENT_COLUMNS: tuple[str, ...] = tuple(spec.column for spec in NUTRIENT_SPECS)


def validate_units(units_by_id: Mapping[int, str], bundle: str = "") -> None:
    """Check nutrient.csv against the mapping table.

    Raises MappingError when a primary id is absent or when any id that we
    would read reports a unit other than the one we expect. Fallback ids may
    be absent (SR Legacy has no Atwater energy rows, for instance).
    """
    where = f" in {bundle}" if bundle else ""
    for spec in NUTRIENT_SPECS:
        if spec.primary_id not in units_by_id:
            raise MappingError(
                f"nutrient id {spec.primary_id} ({spec.column}) is missing "
                f"from nutrient.csv{where}"
            )
        for nutrient_id in spec.ids:
            unit = units_by_id.get(nutrient_id)
            if unit is None:
                continue
            if unit.strip().upper() != spec.unit:
                raise MappingError(
                    f"nutrient id {nutrient_id} ({spec.column}) has unit {unit!r}{where}, "
                    f"expected {spec.unit}"
                )


def resolve(spec: NutrientSpec, amounts: Mapping[int, float]) -> float | None:
    """Return the first available amount for the spec's ids, or None."""
    for nutrient_id in spec.ids:
        value = amounts.get(nutrient_id)
        if value is not None:
            return value
    return None


def map_nutrients(amounts: Mapping[int, float]) -> dict[str, float | None]:
    """Map a food's {nutrient_id: amount} to {column: value or None}."""
    return {spec.column: resolve(spec, amounts) for spec in NUTRIENT_SPECS}
