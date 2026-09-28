"""Reading the Bundeslebensmittelschlüssel (Max Rubner-Institut, Germany).

The BLS is published as one wide table: one row per food, three columns per
component — the value, where it came from, and its reference — keyed by the
seven-character BLS code. Every value column names its component code, its
German name and its unit, as in `NA Natrium [mg/100g]`, so the unit is read
rather than assumed: a component published in another unit is converted by a
stated factor, and one published in a unit this pipeline does not know stops the
build instead of being quietly wrong by a thousand.

Columns are matched on the component code alone, which is the part of a header
that does not move. That also keeps `NA Natrium [mg/100g]` apart from its
`NA Datenherkunft` and `NA Referenz` neighbours, since only a value column
carries the unit.

Version 4.0 carries an English name beside the German one, so a BLS row reads
in English and is still found by typing German.
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

NAME_LOCALE_DE = "de"
NAME_LOCALE_EN = "en"

# Headers are matched with case, spaces, underscores and punctuation ignored.
KEY_NAMES = ("BLS Code", "SBLS", "BLS-Schlüssel", "Schlüssel", "Code")
GERMAN_NAME_NAMES = ("Lebensmittelbezeichnung", "ST", "Bezeichnung", "Lebensmittel", "Name")
ENGLISH_NAME_NAMES = ("Food name", "STE", "Lebensmittelbezeichnung englisch", "English name")
CATEGORY_NAMES = ("Lebensmittelgruppe", "Hauptgruppe", "Obergruppe", "Gruppe", "Food group")

# "PROT625 Protein (Nx6,25) [g/100g]" -> code PROT625, unit g.
_VALUE_HEADER = re.compile(r"^(?P<code>\S+)\s.*\[\s*(?P<unit>[^\]/]+?)\s*/\s*100\s*g\s*\]$")

# What a mass unit is worth in grams. Both micro signs are folded to one.
MASS_UNITS: dict[str, float] = {"g": 1.0, "mg": 1e-3, "µg": 1e-6}
ENERGY_UNIT = "kcal"

# Text in a value column that means the component was not determined.
ABSENT = frozenset({"", "-", "–", ".", "nd", "n.d.", "nv", "n.v.", "na", "n.a.", "n/a"})

ENERGY_COLUMN = "kcal_100g"

# The BLS numbers its editions rather than dating them, and writes the number with
# a dot in prose and an underscore in file names: "BLS 4.0", "BLS_4_0_2025_DE".
_VERSION_RE = re.compile(r"(?<![\d.])\d+[._]\d+(?![\d.])")


@dataclass(frozen=True)
class ComponentSpec:
    """One output column, the BLS component codes that can fill it, and its unit.

    Codes are tried in order, so a renamed component can be added in front of the
    one it replaced without changing anything else.
    """

    column: str
    codes: tuple[str, ...]
    unit: str  # the unit the output column is in: kcal, g or mg
    required: bool = True


COMPONENT_SPECS: tuple[ComponentSpec, ...] = (
    ComponentSpec(ENERGY_COLUMN, ("ENERCC",), "kcal"),
    ComponentSpec("protein_100g", ("PROT625", "PROT"), "g"),
    ComponentSpec("carb_100g", ("CHO", "CHOAVL"), "g"),
    ComponentSpec("fat_100g", ("FAT",), "g"),
    ComponentSpec("satfat_100g", ("FASAT",), "g", required=False),
    ComponentSpec("fiber_100g", ("FIBT",), "g", required=False),
    ComponentSpec("sugar_100g", ("SUGAR",), "g", required=False),
    ComponentSpec("sodium_mg_100g", ("NA",), "mg", required=False),
)


@dataclass(frozen=True)
class ValueColumn:
    """A value column of the table and what to multiply it by to get the output unit."""

    header: str
    published_unit: str
    factor: float


@dataclass(frozen=True)
class BlsColumns:
    """Which header carries what, resolved once against the table that was read."""

    key: str
    german_name: str
    english_name: str | None
    category: str | None
    nutrients: dict[str, ValueColumn]


def normalise_header(text: str) -> str:
    """Fold a header to what identifies it: letters and digits, lowercased."""
    folded = text.strip().casefold()
    folded = folded.replace("ß", "ss").replace("ä", "ae").replace("ö", "oe").replace("ü", "ue")
    return "".join(character for character in folded if character.isalnum())


def normalise_unit(text: str) -> str:
    """Fold a unit as published: both micro signs are the same unit."""
    return text.strip().replace("μ", "µ").casefold().replace("μ", "µ")


def find_bundle(root: Path, sheet: str | None = None) -> Bundle:
    """The BLS data table under `root`, whatever the download is called.

    A bundle's root is the table file itself here, not a folder: the BLS is one
    file among several in its download, and which one was read belongs in the log.
    """
    root = Path(root)
    path = find_table(root, stem_hints=("daten", "data", "bls"))
    return Bundle(BLS, path, version_of(path, root.parent), sheet)


def version_of(path: Path, stop: Path) -> str:
    """The edition number in the file or folder name, else a date, else unknown."""
    for candidate in (path, *path.parents):
        if candidate == stop:
            break
        match = _VERSION_RE.search(candidate.stem if candidate == path else candidate.name)
        if match:
            return match.group(0).replace("_", ".")
    return version_from_path(path.parent, stop)


def value_columns(table: Table) -> dict[str, ValueColumn]:
    """Component code -> its value column, for every header that states a unit.

    A header without a `[unit/100g]` suffix is not a value: the BLS puts the
    provenance and the reference of each component in columns of their own, under
    the same code.
    """
    found: dict[str, ValueColumn] = {}
    for header in table.headers:
        match = _VALUE_HEADER.match(header.strip())
        if match is None:
            continue
        unit = normalise_unit(match.group("unit"))
        found.setdefault(
            match.group("code"), ValueColumn(header=header, published_unit=unit, factor=1.0)
        )
    return found


def conversion(published: str, wanted: str, column: str, where: str) -> float:
    """What to multiply a published value by to get `wanted`.

    Energy is never converted: a column of kilojoules is a different component,
    not a different unit of the same one, and the mapping table names the one to
    read.
    """
    if wanted == ENERGY_UNIT:
        if published != ENERGY_UNIT:
            raise MappingError(
                f"{where}: {column} is published in {published!r}, not kilocalories. "
                f"Check which component code was matched."
            )
        return 1.0
    if published not in MASS_UNITS or wanted not in MASS_UNITS:
        raise MappingError(
            f"{where}: {column} is published in {published!r}, which is not a mass "
            f"this pipeline converts ({', '.join(MASS_UNITS)})."
        )
    return MASS_UNITS[published] / MASS_UNITS[wanted]


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
        raise InputError(f"{table.where}: no column holds {wanted}. Columns present: {listing}")

    published = value_columns(table)
    codes = ", ".join(sorted(published)) or "(none)"
    nutrients: dict[str, ValueColumn] = {}
    for spec in COMPONENT_SPECS:
        column = next((published[code] for code in spec.codes if code in published), None)
        if column is None:
            if spec.required:
                raise MappingError(
                    f"{table.where}: no component holds {spec.column} "
                    f"(tried {', '.join(spec.codes)}). Components present: {codes}"
                )
            log.warning("%s: no component for %s; it will be null for every BLS food",
                        table.where, spec.column)
            continue
        factor = conversion(column.published_unit, spec.unit, spec.column, table.where)
        nutrients[spec.column] = ValueColumn(column.header, column.published_unit, factor)
        log.debug("%s: %s from %r (%s, x%g)", table.where, spec.column, column.header,
                  column.published_unit, factor)
    return BlsColumns(
        key=key, german_name=german, english_name=pick(ENGLISH_NAME_NAMES),
        category=pick(CATEGORY_NAMES), nutrients=nutrients,
    )


@dataclass(frozen=True)
class BlsRow:
    """One food as published, with every value already in the output unit."""

    key: str
    name_de: str
    name_en: str
    category: str | None
    values: dict[str, float | None]


def read_values(table: Table, columns: BlsColumns) -> tuple[list[BlsRow], int]:
    """Rows with the output units applied. Returns (rows, count dropped for no name)."""
    rows: list[BlsRow] = []
    blank = 0
    seen: set[str] = set()
    unreadable: dict[str, int] = {}
    key_at = table.index(columns.key)
    german_at = table.index(columns.german_name)
    english_at = table.index(columns.english_name) if columns.english_name else None
    category_at = table.index(columns.category) if columns.category else None
    value_at = {column: table.index(source.header) for column, source in columns.nutrients.items()}
    for line, row in enumerate(table.rows, start=2):
        key = table.cell(row, key_at).strip()
        name_de = " ".join(table.cell(row, german_at).split())
        if not key and not name_de:
            continue
        if not name_de:
            blank += 1
            log.warning("%s:%d: %s has no name, dropped", table.where, line, key or "a row")
            continue
        if key and key in seen:
            raise InputError(f"{table.where}:{line}: duplicate BLS code {key}")
        if key:
            seen.add(key)
        values: dict[str, float | None] = {}
        for column, source in columns.nutrients.items():
            values[column] = _value(
                table.cell(row, value_at[column]), source, column, table.where, line, unreadable
            )
        name_en = " ".join(table.cell(row, english_at).split()) if english_at is not None else ""
        category = None
        if category_at is not None:
            category = " ".join(table.cell(row, category_at).split()) or None
        rows.append(BlsRow(
            key=key or name_de, name_de=name_de, name_en=name_en,
            category=category, values=values,
        ))
    for column, count in unreadable.items():
        log.warning("%s: %d values of %s were not numbers and read as unknown",
                    table.where, count, column)
    if not rows:
        raise InputError(f"{table.where}: no usable rows")
    return rows, blank


def _value(
    text: str, source: ValueColumn, column: str, where: str, line: int,
    unreadable: dict[str, int],
) -> float | None:
    """One published value in the output unit, or None when it was not determined.

    A cell that is neither a number nor one of the markers the BLS uses for "not
    determined" is counted and read as unknown rather than stopping a build over
    one cell in half a million; the count is logged once per column.
    """
    raw = text.strip()
    if raw.casefold() in ABSENT:
        return None
    try:
        number = parse_number(raw)
    except ValueError:
        if not unreadable.get(column):
            log.warning("%s:%d: %s=%r is not a number", where, line, column, raw)
        unreadable[column] = unreadable.get(column, 0) + 1
        return None
    if number is None:
        return None
    if number < 0:
        log.warning("%s:%d: %s is negative (%s), read as unknown", where, line, column, raw)
        return None
    return number * source.factor


def read(path: Path, sheet: str | None = None) -> tuple[list[BlsRow], int, str]:
    """Read one BLS table into rows with output units applied."""
    table = read_table(path, sheet)
    rows, blank = read_values(table, resolve_columns(table))
    return rows, blank, table.where


def names_for(row: BlsRow) -> tuple[str, str, Sequence[str]]:
    """(display name, locale, other names to index for search).

    Version 4.0 names every food in English as well as German, so the English
    name is shown and the German one is indexed; an edition without it shows
    German.
    """
    if row.name_en:
        return row.name_en, NAME_LOCALE_EN, [row.name_de]
    return row.name_de, NAME_LOCALE_DE, []


def units_summary(columns: Mapping[str, ValueColumn]) -> str:
    """One line per mapped column, for the inspect report."""
    return "\n".join(
        f"    {column}: {source.header!r} in {source.published_unit!r} (x{source.factor:g})"
        for column, source in columns.items()
    )
