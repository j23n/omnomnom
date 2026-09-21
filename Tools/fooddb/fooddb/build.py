"""Assembling output rows from FDC bundles: mapping, dedup, popularity."""

from __future__ import annotations

import dataclasses
import logging
import re
from collections.abc import Iterable, Sequence
from dataclasses import dataclass, field
from pathlib import Path

from . import fdc, mapping
from .errors import InputError
from .fdc import Bundle
from .portions import PortionRow, build_portions

log = logging.getLogger(__name__)

DEFAULT_POPULAR = Path(__file__).parent / "curated" / "popular.txt"
NAME_LOCALE = "en"

# Soft plausibility ceilings per 100 g; a value above logs a warning, never fails.
PLAUSIBLE_MAX: dict[str, float] = {
    "kcal_100g": 900,
    **{column: 100 for column in mapping.NUTRIENT_COLUMNS if column.endswith("_100g")
       and column not in ("kcal_100g", "sodium_mg_100g")},
    "sodium_mg_100g": 100_000,
}


@dataclass(frozen=True)
class FoodRow:
    name: str
    key: str  # normalised name, used for dedup and popularity
    source: str
    source_ref: str
    category: str | None
    nutrients: dict[str, float | None]
    portions: tuple[PortionRow, ...]
    popularity: int = 0
    name_locale: str = NAME_LOCALE
    is_estimated: int = 0


@dataclass
class BuildSummary:
    kept: dict[str, int] = field(default_factory=dict)
    dropped_no_energy: dict[str, int] = field(default_factory=dict)
    dropped_blank_name: dict[str, int] = field(default_factory=dict)
    dropped_duplicates: int = 0
    portions: int = 0
    unmatched_popular: list[str] = field(default_factory=list)

    def format(self) -> str:
        lines = ["Build summary"]
        sources = dict.fromkeys([*self.kept, *self.dropped_no_energy, *self.dropped_blank_name])
        for source in sources:
            lines.append(
                f"  {source}: {self.kept.get(source, 0)} foods kept, "
                f"{self.dropped_no_energy.get(source, 0)} dropped (no energy), "
                f"{self.dropped_blank_name.get(source, 0)} dropped (blank name)"
            )
        lines.append(f"  SR Legacy duplicates of Foundation dropped: {self.dropped_duplicates}")
        lines.append(f"  portions: {self.portions}")
        lines.append(f"  unmatched popular entries: {len(self.unmatched_popular)}")
        return "\n".join(lines)


def collapse_whitespace(text: str) -> str:
    return " ".join(text.split())


def normalise_description(text: str) -> str:
    """Key for dedup: casefolded, whitespace-collapsed, no trailing period."""
    return collapse_whitespace(text).casefold().rstrip(".").strip()


_PARENTHETICAL = re.compile(r"\s*\([^)]*\)")


def popular_key(text: str) -> str:
    """Key for the popular list: the dedup key with parenthetical notes removed, so FDC's
    "(Includes foods for USDA's Food Distribution Program)" suffixes need not be spelled out."""
    return normalise_description(_PARENTHETICAL.sub("", text))


def read_popular(path: Path) -> list[str]:
    """Normalised entries of popular.txt in file order; blank lines, # comments, repeats skipped."""
    entries: list[str] = []
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError as error:
        raise InputError(f"cannot read popular list {path}: {error}") from error
    for number, line in enumerate(lines, start=1):
        text = line.split("#", 1)[0].strip()
        if not text:
            continue
        entry = popular_key(text)
        if entry in entries:
            log.warning("%s:%d: duplicate popular entry %r ignored", path, number, entry)
            continue
        entries.append(entry)
    return entries


def popularity_scores(entries: Sequence[str]) -> dict[str, int]:
    """Earlier entries score higher: 100 minus index, floored at 1."""
    return {entry: max(1, 100 - index) for index, entry in enumerate(entries)}


def check_plausible(values: dict[str, float | None], source: str, ref: str) -> None:
    for column, ceiling in PLAUSIBLE_MAX.items():
        value = values.get(column)
        if value is not None and value > ceiling:
            log.warning(
                "%s %s: implausible %s=%s (> %s per 100 g)", source, ref, column, value, ceiling
            )


def load_bundle(bundle: Bundle, summary: BuildSummary) -> list[FoodRow]:
    """Read one bundle into FoodRows, dropping foods without energy or a name."""
    root, source = bundle.root, bundle.source
    mapping.validate_units(fdc.read_nutrient_units(root), source)
    nutrients = fdc.read_food_nutrients(root)
    categories = fdc.read_categories(root)
    unit_names = fdc.read_measure_units(root)
    portions = fdc.read_portions(root)
    rows: list[FoodRow] = []
    no_energy = blank = 0
    for food in fdc.read_foods(root, fdc.DATA_TYPES.get(source)):
        name = collapse_whitespace(food.description)
        if not name:
            blank += 1
            log.warning("%s %s: blank description, dropped", source, food.fdc_id)
            continue
        values = mapping.map_nutrients(nutrients.get(food.fdc_id, {}))
        if values[mapping.ENERGY_COLUMN] is None:
            no_energy += 1
            log.debug("dropping %s %s: no energy", food.fdc_id, name)
            continue
        check_plausible(values, source, str(food.fdc_id))
        category = None
        if food.food_category_id is not None:
            category = categories.get(food.food_category_id)
        rows.append(
            FoodRow(
                name=name,
                key=normalise_description(name),
                source=source,
                source_ref=str(food.fdc_id),
                category=category,
                nutrients=values,
                portions=tuple(build_portions(portions.get(food.fdc_id, []), unit_names)),
            )
        )
    summary.dropped_no_energy[source] = no_energy
    summary.dropped_blank_name[source] = blank
    log.info("%s: %d foods read, %d dropped for missing energy, %d for blank name",
             source, len(rows) + no_energy + blank, no_energy, blank)
    if not rows:
        raise InputError(f"{root} ({source}) yielded no usable foods")
    return rows


def dedup(rows: Iterable[FoodRow], summary: BuildSummary) -> list[FoodRow]:
    """Keep one row per normalised name across sources; the first source seen wins.

    Rows must arrive Foundation first (find_bundles guarantees the order).
    """
    kept: list[FoodRow] = []
    seen: dict[str, str] = {}
    for row in rows:
        previous = seen.get(row.key)
        if previous is not None and previous != row.source:
            summary.dropped_duplicates += 1
            log.debug("dropping %s %s: duplicates %s", row.source, row.source_ref, previous)
            continue
        seen.setdefault(row.key, row.source)
        kept.append(row)
    return kept


def apply_popularity(
    rows: Sequence[FoodRow], entries: Sequence[str], summary: BuildSummary
) -> list[FoodRow]:
    scores = popularity_scores(entries)
    matched: set[str] = set()
    result: list[FoodRow] = []
    for row in rows:
        score = scores.get(popular_key(row.name), 0)
        if score:
            matched.add(popular_key(row.name))
        result.append(dataclasses.replace(row, popularity=score))
    summary.unmatched_popular = [entry for entry in entries if entry not in matched]
    for entry in summary.unmatched_popular:
        log.warning("popular entry not found in any bundle: %r", entry)
    return result


def assemble(
    bundles: Sequence[Bundle], popular_path: Path = DEFAULT_POPULAR
) -> tuple[list[FoodRow], BuildSummary]:
    """Full in-memory pipeline: read every bundle, dedup, score popularity."""
    summary = BuildSummary()
    rows: list[FoodRow] = []
    for bundle in bundles:
        rows.extend(load_bundle(bundle, summary))
    rows = dedup(rows, summary)
    rows = apply_popularity(rows, read_popular(popular_path), summary)
    for row in rows:
        summary.kept[row.source] = summary.kept.get(row.source, 0) + 1
        summary.portions += len(row.portions)
    for bundle in bundles:
        summary.kept.setdefault(bundle.source, 0)
    return rows, summary
