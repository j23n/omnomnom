"""Assembling output rows from every source: mapping, dedup, popularity.

Each source has its own reader module; this one turns what they yield into the
rows the database is written from, drops what cannot be logged (a food with no
energy value), and settles overlap between sources by name."""

from __future__ import annotations

import dataclasses
import logging
import re
from collections.abc import Iterable, Sequence
from dataclasses import dataclass, field
from pathlib import Path

from . import bls, ciqual, fdc, ingredient, mapping
from .bundles import BLS, CIQUAL, FOUNDATION, SR_LEGACY, Bundle
from .errors import InputError
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
    # 1 when the row is an ingredient or a dry form rather than a portion; set in
    # one pass over every source by `apply_ingredient_flags`.
    is_ingredient: int = 0
    # The same food's names in the other languages the source publishes, indexed
    # for search but never displayed: a French speaker finds "Pomme, pulpe, crue"
    # and reads "Apple, pulp, raw".
    alt_names: tuple[str, ...] = ()


@dataclass
class BuildSummary:
    kept: dict[str, int] = field(default_factory=dict)
    dropped_no_energy: dict[str, int] = field(default_factory=dict)
    dropped_blank_name: dict[str, int] = field(default_factory=dict)
    dropped_duplicates: int = 0
    ingredients: int = 0
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
        lines.append(f"  duplicate names dropped: {self.dropped_duplicates}")
        lines.append(f"  ingredient forms flagged: {self.ingredients}")
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


def load_fdc_bundle(bundle: Bundle, summary: BuildSummary) -> list[FoodRow]:
    """Read one FDC bundle into FoodRows, dropping foods without energy or a name."""
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
    return _finish(rows, summary, source, root, no_energy, blank)


def load_ciqual_bundle(bundle: Bundle, summary: BuildSummary) -> list[FoodRow]:
    """Read the Ciqual export into FoodRows.

    Ciqual publishes English names beside the French ones; when this edition has
    them the English name is what the app shows and the French one is indexed for
    search, so the same build serves both languages.
    """
    source = bundle.source
    files = ciqual.locate_files(bundle.root)
    ciqual.validate_units(ciqual.read_constituent_units(files["const"]))
    foods = ciqual.read_foods(files["foods"])
    composition = ciqual.read_composition(files["compo"])
    prefer_english = any(food.name_eng.strip() for food in foods)
    if not prefer_english:
        log.warning("%s: this export has no English names; French names will be shown", source)
    groups = ciqual.read_groups(files["groups"], prefer_english)
    rows: list[FoodRow] = []
    no_energy = blank = 0
    for food in foods:
        name, locale, others = ciqual.names_for(food, prefer_english)
        if not name:
            blank += 1
            log.warning("%s %s: no name in either language, dropped", source, food.code)
            continue
        values, estimated = ciqual.map_nutrients(composition.get(food.code, {}))
        if values[mapping.ENERGY_COLUMN] is None:
            no_energy += 1
            log.debug("dropping %s %s: no energy", source, name)
            continue
        check_plausible(values, source, food.code)
        category = groups.get(food.subgroup_code) or groups.get(food.group_code)
        rows.append(
            FoodRow(
                name=name,
                key=normalise_description(name),
                source=source,
                source_ref=food.code,
                category=category,
                nutrients=values,
                portions=(),
                name_locale=locale,
                is_estimated=1 if estimated else 0,
                alt_names=tuple(others),
            )
        )
    return _finish(rows, summary, source, bundle.root, no_energy, blank)


def load_bls_bundle(bundle: Bundle, summary: BuildSummary) -> list[FoodRow]:
    """Read the BLS table into FoodRows.

    Version 4.0 names every food in English as well as German, so a row reads in
    English and is found by typing either, the same bargain Ciqual offers.
    """
    source = bundle.source
    published, blank, where = bls.read(bundle.root, bundle.sheet)
    rows: list[FoodRow] = []
    no_energy = 0
    for entry in published:
        values: dict[str, float | None] = {
            column: entry.values.get(column) for column in mapping.NUTRIENT_COLUMNS
        }
        name, locale, others = bls.names_for(entry)
        if values[mapping.ENERGY_COLUMN] is None:
            no_energy += 1
            log.debug("dropping %s %s: no energy", source, name)
            continue
        check_plausible(values, source, entry.key)
        rows.append(
            FoodRow(
                name=name,
                key=normalise_description(name),
                source=source,
                source_ref=entry.key,
                category=entry.category,
                nutrients=values,
                portions=(),
                name_locale=locale,
                alt_names=tuple(other for other in others if other and other != name),
            )
        )
    return _finish(rows, summary, source, Path(where), no_energy, blank)


def _finish(
    rows: list[FoodRow], summary: BuildSummary, source: str, where: Path,
    no_energy: int, blank: int,
) -> list[FoodRow]:
    """Record what one source dropped and refuse a source that yielded nothing."""
    summary.dropped_no_energy[source] = no_energy
    summary.dropped_blank_name[source] = blank
    log.info("%s: %d foods read, %d dropped for missing energy, %d for blank name",
             source, len(rows) + no_energy + blank, no_energy, blank)
    if not rows:
        raise InputError(f"{where} ({source}) yielded no usable foods")
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
    """Score each row by the curated list, matching its display name or any of its
    other names, so one list can rank foods across sources and languages."""
    scores = popularity_scores(entries)
    matched: set[str] = set()
    result: list[FoodRow] = []
    for row in rows:
        keys = [popular_key(name) for name in (row.name, *row.alt_names)]
        score = max((scores.get(key, 0) for key in keys), default=0)
        if score:
            matched.update(key for key in keys if key in scores)
        result.append(dataclasses.replace(row, popularity=score))
    summary.unmatched_popular = [entry for entry in entries if entry not in matched]
    if summary.unmatched_popular:
        log.warning(
            "%d of %d curated popular entries match no food in these sources; "
            "run with -v to list them", len(summary.unmatched_popular), len(entries)
        )
        for entry in summary.unmatched_popular:
            log.debug("popular entry not found: %r", entry)
    return result


def apply_ingredient_flags(
    rows: Sequence[FoodRow], summary: BuildSummary
) -> list[FoodRow]:
    """Flag every row that is an ingredient or a dry form rather than a portion.

    One pass over all sources rather than a line in each reader, so the rules are
    applied identically to a Ciqual row and a BLS one and there is a single place
    to audit when a flag looks wrong. Matching reads the display name together
    with the source's other names, which is what lets the English rules reach a
    German row.
    """
    result: list[FoodRow] = []
    flagged = 0
    for row in rows:
        why = ingredient.reasons(row.name, row.alt_names)
        if why:
            flagged += 1
            log.debug("ingredient form %r: %s", row.name, ", ".join(sorted(why)))
        result.append(dataclasses.replace(row, is_ingredient=1 if why else 0))
    summary.ingredients = flagged
    log.info("flagged %d of %d rows as ingredient forms", flagged, len(rows))
    return result


LOADERS = {
    FOUNDATION: load_fdc_bundle,
    SR_LEGACY: load_fdc_bundle,
    CIQUAL: load_ciqual_bundle,
    BLS: load_bls_bundle,
}


def assemble(
    bundles: Sequence[Bundle], popular_path: Path = DEFAULT_POPULAR
) -> tuple[list[FoodRow], BuildSummary]:
    """Full in-memory pipeline: read every bundle, dedup, score popularity."""
    summary = BuildSummary()
    rows: list[FoodRow] = []
    for bundle in bundles:
        loader = LOADERS.get(bundle.source)
        if loader is None:
            raise InputError(f"no reader for source {bundle.source!r}")
        rows.extend(loader(bundle, summary))
    rows = dedup(rows, summary)
    rows = apply_popularity(rows, read_popular(popular_path), summary)
    rows = apply_ingredient_flags(rows, summary)
    for row in rows:
        summary.kept[row.source] = summary.kept.get(row.source, 0) + 1
        summary.portions += len(row.portions)
    for bundle in bundles:
        summary.kept.setdefault(bundle.source, 0)
    return rows, summary
