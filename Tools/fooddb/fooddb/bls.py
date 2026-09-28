"""Reading the Bundeslebensmittelschlüssel (Max Rubner-Institut, Germany).

The BLS is published as one wide table, one row per food, one column per
nutrient, keyed by the seven-character BLS code. Columns are named by the short
mnemonics the BLS has always used (GCAL for energy, ZE for protein), and an
edition may spell them out instead, so each output column accepts a small set of
names and the build says which headers it saw when none of them matches.

The table does not say what unit a column is in. The BLS has historically
published nutrients in milligrams per 100 g while energy is in kilocalories, but
an edition may change that, and a silent factor of a thousand would be the worst
possible bug here. So the unit is measured rather than assumed: no food has more
than 100 g of a macronutrient in 100 g, so a column whose values run past that is
in milligrams. The conclusion is logged on every build and the result is checked
against the same ceiling afterwards.
"""

from __future__ import annotations

import logging
import re
from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from pathlib import Path

from .bundles import BLS, Bundle, version_from_path
from .errors import InputError, MappingError
from .table import Table, find_table, parse_number, read_table

log = logging.getLogger(__name__)

NAME_LOCALE = "de"

# Names are matched with case, spaces, underscores and punctuation ignored.
KEY_NAMES = ("SBLS", "BLS-Schlüssel", "BLS-Code", "Schlüssel", "Code")
GERMAN_NAME_NAMES = ("ST", "Lebensmittelbezeichnung", "Bezeichnung", "Lebensmittel", "Name")
ENGLISH_NAME_NAMES = (
    "STE", "Lebensmittelbezeichnung englisch", "Bezeichnung englisch",
    "Name englisch", "English name", "Food name",
)
CATEGORY_NAMES = ("Hauptgruppe", "Lebensmittelgruppe", "Obergruppe", "Gruppe", "Food group")

# Above this, a macronutrient column cannot be in grams per 100 g.
GRAM_CEILING = 100.0
# Above this, an energy column cannot be in kilocalories per 100 g.
KCAL_CEILING = 2000.0


@dataclass(frozen=True)
class ColumnSpec:
    """One output column, the headers that can carry it, and the unit it ends in."""

    column: str
    names: tuple[str, ...]
    unit: str  # the unit the output column is in: kcal, g or mg
    required: bool = True


COLUMN_SPECS: tuple[ColumnSpec, ...] = (
    ColumnSpec("kcal_100g", ("GCAL", "Energie (kcal)", "Energie kcal", "Energie"), "kcal"),
    ColumnSpec("protein_100g", ("ZE", "Eiweiß", "Protein"), "g"),
    ColumnSpec("carb_100g", ("ZK", "Kohlenhydrate"), "g"),
    ColumnSpec("fat_100g", ("ZF", "Fett"), "g"),
    ColumnSpec("satfat_100g", ("FS", "gesättigte Fettsäuren", "Gesaettigte Fettsaeuren"), "g",
               required=False),
    ColumnSpec("fiber_100g", ("ZB", "Ballaststoffe"), "g", required=False),
    ColumnSpec("sugar_100g", ("KMD", "Zucker", "Mono- und Disaccharide"), "g", required=False),
    ColumnSpec("sodium_mg_100g", ("MNA", "Natrium"), "mg", required=False),
)

ENERGY_COLUMN = "kcal_100g"


@dataclass(frozen=True)
class BlsColumns:
    """Which header carries what, resolved once against the table that was read."""

    key: str
    german_name: str
    english_name: str | None
    category: str | None
    nutrients: dict[str, str]  # output column -> header


def normalise_header(text: str) -> str:
    """Fold a header to what identifies it: letters and digits, lowercased."""
    folded = text.strip().casefold()
    folded = folded.replace("ß", "ss").replace("ä", "ae").replace("ö", "oe").replace("ü", "ue")
    return "".join(character for character in folded if character.isalnum())


# The BLS numbers its editions rather than dating them: "BLS 4.0".
_VERSION_RE = re.compile(r"(?<![\d.])\d+\.\d+(?![\d.])")


def find_bundle(root: Path, sheet: str | None = None) -> Bundle:
    """The BLS table under `root`, whatever the download is called.

    A bundle's root is the table file itself here, not a folder: the BLS is one
    file, and which one was read belongs in the log.
    """
    root = Path(root)
    path = find_table(root, stem_hints=("bls", "bundeslebensmittel"))
    return Bundle(BLS, path, version_of(path, root.parent), sheet)


def version_of(path: Path, stop: Path) -> str:
    """The edition number in the file or folder name, else a date, else unknown."""
    for candidate in (path, *path.parents):
        if candidate == stop:
            break
        match = _VERSION_RE.search(candidate.stem if candidate == path else candidate.name)
        if match:
            return match.group(0)
    return version_from_path(path.parent, stop)


def resolve_columns(table: Table) -> BlsColumns:
    """Match the table's headers to what the build needs, or say what it found instead."""
    by_name = {normalise_header(header): header for header in table.headers if header.strip()}

    def pick(candidates: Sequence[str]) -> str | None:
        for candidate in candidates:
            header = by_name.get(normalise_header(candidate))
            if header is not None:
                return header
        return None

    key = pick(KEY_NAMES)
    german = pick(GERMAN_NAME_NAMES)
    listing = ", ".join(table.headers) or "(none)"
    if key is None or german is None:
        wanted = "a BLS code" if key is None else "a food name"
        raise InputError(
            f"{table.where}: no column holds {wanted}. Columns present: {listing}"
        )
    nutrients: dict[str, str] = {}
    for spec in COLUMN_SPECS:
        header = pick(spec.names)
        if header is not None:
            nutrients[spec.column] = header
        elif spec.required:
            raise MappingError(
                f"{table.where}: no column holds {spec.column} "
                f"(tried {', '.join(spec.names)}). Columns present: {listing}"
            )
        else:
            log.warning("%s: no column for %s; it will be null for every BLS food",
                        table.where, spec.column)
    return BlsColumns(
        key=key, german_name=german, english_name=pick(ENGLISH_NAME_NAMES),
        category=pick(CATEGORY_NAMES), nutrients=nutrients,
    )


def read_values(table: Table, columns: BlsColumns) -> tuple[list[dict[str, object]], int]:
    """Rows as published, before any unit is applied. Returns (rows, blank name count)."""
    rows: list[dict[str, object]] = []
    blank = 0
    seen: set[str] = set()
    for line, row in table.dicts():
        key = row[columns.key].strip()
        name = " ".join(row[columns.german_name].split())
        if not key and not name:
            continue
        if not name:
            blank += 1
            log.warning("%s:%d: %s has no name, dropped", table.where, line, key or "a row")
            continue
        if key and key in seen:
            raise InputError(f"{table.where}:{line}: duplicate BLS code {key}")
        if key:
            seen.add(key)
        values: dict[str, float | None] = {}
        for column, header in columns.nutrients.items():
            text = row[header]
            try:
                number = parse_number(text)
            except ValueError as error:
                raise InputError(f"{table.where}:{line}: {header}={text!r} ({error})") from error
            if number is not None and number < 0:
                log.warning("%s:%d: %s is negative (%s), read as unknown",
                            table.where, line, header, text)
                number = None
            values[column] = number
        english = ""
        if columns.english_name is not None:
            english = " ".join(row[columns.english_name].split())
        category = None
        if columns.category is not None:
            category = " ".join(row[columns.category].split()) or None
        rows.append({
            "key": key or name, "name": name, "english": english,
            "category": category, "values": values,
        })
    if not rows:
        raise InputError(f"{table.where}: no usable rows")
    return rows, blank


def detect_scales(
    rows: Sequence[Mapping[str, object]], where: str
) -> dict[str, float]:
    """Factor per column that turns the published value into the output unit.

    No food holds more than 100 g of a macronutrient in 100 g, so a table whose
    macronutrients run well past that is written in milligrams. The decision is
    taken once for all of them, from the ninetieth percentile of every value in
    the group, so one corrupt row cannot move it either way, and a publisher who
    changed units for only some columns fails the check afterwards instead.
    Sodium is decided on its own, because its output unit is the milligram.
    Energy is only checked: a column of kilojoules is a mismatched header, not a
    unit to correct here.
    """
    factors: dict[str, float] = {}
    gram_columns = [spec.column for spec in COLUMN_SPECS if spec.unit == "g"]
    macros = [
        value for row in rows for column in gram_columns
        if (value := _value_of(row, column)) is not None
    ]
    in_milligrams = percentile(macros, 0.9) > GRAM_CEILING
    log.info("%s: macronutrients read as %s", where, "mg/100 g" if in_milligrams else "g/100 g")
    for spec in COLUMN_SPECS:
        values = [
            value for row in rows
            if (value := _value_of(row, spec.column)) is not None
        ]
        if not values:
            continue
        if spec.unit == "kcal":
            highest = max(values)
            if highest > KCAL_CEILING:
                raise MappingError(
                    f"{where}: the energy column peaks at {highest:g}, too high for "
                    f"kilocalories per 100 g. It is probably kilojoules; check which "
                    f"column was matched."
                )
            factors[spec.column] = 1.0
        elif spec.unit == "g":
            factors[spec.column] = 0.001 if in_milligrams else 1.0
        else:  # mg
            grams = percentile(values, 0.9) <= GRAM_CEILING and not in_milligrams
            factors[spec.column] = 1000.0 if grams else 1.0
            log.info("%s: %s read as %s", where, spec.column,
                     "g/100 g" if grams else "mg/100 g")
    return factors


def percentile(values: Sequence[float], fraction: float) -> float:
    """The value `fraction` of the way up the sorted list; 0 when there is nothing."""
    if not values:
        return 0.0
    ordered = sorted(values)
    index = int(round(fraction * (len(ordered) - 1)))
    return ordered[index]


def _value_of(row: Mapping[str, object], column: str) -> float | None:
    values = row.get("values")
    if not isinstance(values, dict):
        return None
    value = values.get(column)
    return value if isinstance(value, float) else None


def apply_scales(
    rows: Sequence[Mapping[str, object]], factors: Mapping[str, float], where: str
) -> None:
    """Convert in place, then check the result against the same ceiling.

    A handful of rows above it are a publisher's data errors and are logged one by
    one; a large share of them means the unit was read wrong, which is worth
    stopping for.
    """
    for row in rows:
        values = row["values"]
        assert isinstance(values, dict)
        for column, factor in factors.items():
            value = values.get(column)
            if value is not None and factor != 1.0:
                values[column] = value * factor
    tolerated = max(5, len(rows) // 100)
    for spec in COLUMN_SPECS:
        if spec.unit != "g":
            continue
        over = [value for row in rows
                if (value := _value_of(row, spec.column)) is not None and value > GRAM_CEILING]
        if not over:
            continue
        if len(over) > tolerated:
            raise MappingError(
                f"{where}: {len(over)} rows hold more than {GRAM_CEILING:g} g of "
                f"{spec.column} in 100 g, peaking at {max(over):g}. The column was read "
                f"in the wrong unit; check which header it was matched to."
            )
        log.warning("%s: %d rows exceed %g g of %s per 100 g, highest %g",
                    where, len(over), GRAM_CEILING, spec.column, max(over))


def read(path: Path, sheet: str | None = None) -> tuple[list[dict[str, object]], int, str]:
    """Read one BLS table into rows with output units applied."""
    table = read_table(path, sheet)
    columns = resolve_columns(table)
    rows, blank = read_values(table, columns)
    apply_scales(rows, detect_scales(rows, table.where), table.where)
    return rows, blank, table.where
