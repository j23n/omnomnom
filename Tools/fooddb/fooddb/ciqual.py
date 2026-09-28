"""Reading the Ciqual XML export (ANSES, France).

Ciqual publishes one file per table: the foods, their groups, the constituents
and the composition values that join the two. The export carries French and
English names for every food and every constituent, so the same download serves
a French and an English speaking user.

Values are published as text rather than numbers because a food can be measured
at "traces" or below a detection limit. Both are stored as zero with the row
marked estimated, so a sum never silently omits them and the UI can say the
value is approximate. A constituent that was never measured stays null.
"""

from __future__ import annotations

import logging
import re
from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from pathlib import Path
from xml.etree import ElementTree

from .bundles import CIQUAL, Bundle, version_from_path
from .errors import InputError, MappingError
from .table import parse_number

log = logging.getLogger(__name__)

NAME_LOCALE_EN = "en"
NAME_LOCALE_FR = "fr"

# Text that means "not measured" rather than a number.
ABSENT = frozenset({"", "-", "nd", "n.d.", "null", "na", "n/a"})
# Text that means "present but below what the method resolves"; stored as zero.
TRACE = frozenset({"traces", "trace"})

# The unit written into a constituent's name, as "(g/100 g)".
_UNIT_RE = re.compile(r"\(([^()/]+)/100\s*g\)")


@dataclass(frozen=True)
class ConstSpec:
    """One output column and the Ciqual constituent codes that can fill it."""

    column: str
    codes: tuple[int, ...]
    unit: str

    @property
    def primary_code(self) -> int:
        return self.codes[0]


# Verified against the constituent names in the export on every build: the unit in
# the name has to match, so a renumbering or a unit change fails loudly.
CONST_SPECS: tuple[ConstSpec, ...] = (
    ConstSpec("kcal_100g", (328,), "kcal"),
    ConstSpec("protein_100g", (25000, 25001), "g"),
    ConstSpec("carb_100g", (31000,), "g"),
    ConstSpec("fat_100g", (40000,), "g"),
    ConstSpec("satfat_100g", (40302,), "g"),
    ConstSpec("fiber_100g", (34100,), "g"),
    ConstSpec("sugar_100g", (32000,), "g"),
    ConstSpec("sodium_mg_100g", (10110,), "mg"),
)

# file role -> the name prefix the export uses. Editions append the date, so the
# match is on the prefix and the longest prefix wins.
FILE_PREFIXES: tuple[tuple[str, str], ...] = (
    ("groups", "alim_grp"),
    ("compo", "compo"),
    ("const", "const"),
    ("foods", "alim"),
)


@dataclass(frozen=True)
class CiqualFood:
    code: str
    name_fr: str
    name_eng: str
    index_fr: str
    index_eng: str
    group_code: str
    subgroup_code: str


@dataclass(frozen=True)
class CiqualValue:
    value: float | None
    is_estimated: bool


def find_bundle(root: Path) -> Bundle:
    """The Ciqual export under `root`, wherever inside it the XML files sit."""
    root = Path(root)
    if not root.is_dir():
        raise InputError(f"Ciqual directory not found: {root}")
    files = locate_files(root)
    folder = files["foods"].parent
    return Bundle(CIQUAL, folder, version_from_path(folder, root.parent))


def locate_files(root: Path) -> dict[str, Path]:
    """Map each role to its XML file, or say exactly which role is missing."""
    found: dict[str, Path] = {}
    for path in sorted(root.rglob("*.xml")):
        name = path.name.lower()
        for role, prefix in FILE_PREFIXES:
            if name.startswith(prefix) and role not in found:
                found[role] = path
                break
    missing = [role for role, _ in FILE_PREFIXES if role not in found]
    if missing:
        listing = ", ".join(f"{role} ({prefix}*.xml)" for role, prefix in FILE_PREFIXES
                            if role in missing)
        raise InputError(
            f"{root}: the Ciqual XML export is incomplete, missing {listing}. "
            f"Download 'Données XML' from ciqual.anses.fr and unzip it into this folder."
        )
    return found


def _elements(path: Path, tag: str) -> list[dict[str, str]]:
    """Every `<tag>` in the file as {child tag: text}, wherever it sits in the tree."""
    try:
        root = ElementTree.parse(path).getroot()
    except ElementTree.ParseError as error:
        raise InputError(f"{path}: not valid XML ({error})") from error
    except OSError as error:
        raise InputError(f"cannot read {path}: {error}") from error
    rows: list[dict[str, str]] = []
    for element in root.iter():
        if element.tag.rpartition("}")[2].upper() != tag:
            continue
        rows.append({
            child.tag.rpartition("}")[2].lower(): (child.text or "").strip()
            for child in element
        })
    if not rows:
        raise InputError(f"{path}: no <{tag}> elements")
    return rows


def read_constituent_units(path: Path) -> dict[int, str]:
    """Constituent code -> the unit written into its name, lowercased."""
    units: dict[int, str] = {}
    for row in _elements(path, "CONST"):
        code = row.get("const_code", "")
        if not code.strip().isdigit():
            continue
        name = row.get("const_nom_eng") or row.get("const_nom_fr") or ""
        match = _UNIT_RE.search(name)
        if match:
            units[int(code)] = match.group(1).strip().lower()
    if not units:
        raise InputError(f"{path}: no constituent carries a unit in its name")
    return units


def validate_units(units_by_code: Mapping[int, str]) -> None:
    """Fail when a constituent we read is gone or now published in another unit."""
    for spec in CONST_SPECS:
        if spec.primary_code not in units_by_code:
            raise MappingError(
                f"Ciqual constituent {spec.primary_code} ({spec.column}) is not in this export"
            )
        for code in spec.codes:
            unit = units_by_code.get(code)
            if unit is None:
                continue
            if unit != spec.unit:
                raise MappingError(
                    f"Ciqual constituent {code} ({spec.column}) is published in {unit!r}, "
                    f"expected {spec.unit!r}"
                )


def read_foods(path: Path) -> list[CiqualFood]:
    foods: list[CiqualFood] = []
    seen: set[str] = set()
    for row in _elements(path, "ALIM"):
        code = row.get("alim_code", "").strip()
        if not code:
            raise InputError(f"{path}: a food has no alim_code")
        if code in seen:
            raise InputError(f"{path}: duplicate alim_code {code}")
        seen.add(code)
        foods.append(CiqualFood(
            code=code,
            name_fr=row.get("alim_nom_fr", ""),
            name_eng=row.get("alim_nom_eng", ""),
            index_fr=row.get("alim_nom_index_fr", ""),
            index_eng=row.get("alim_nom_index_eng", ""),
            group_code=row.get("alim_grp_code", "").strip(),
            subgroup_code=row.get("alim_ssgrp_code", "").strip(),
        ))
    return foods


def read_groups(path: Path, prefer_english: bool) -> dict[str, str]:
    """Sub-group code -> its name, falling back to the group when there is no sub-group."""
    names: dict[str, str] = {}
    for row in _elements(path, "ALIM_GRP"):
        for code_field, name_fields in (
            ("alim_ssgrp_code", ("alim_ssgrp_nom_eng", "alim_ssgrp_nom_fr")),
            ("alim_grp_code", ("alim_grp_nom_eng", "alim_grp_nom_fr")),
        ):
            code = row.get(code_field, "").strip()
            if not code:
                continue
            ordered = name_fields if prefer_english else tuple(reversed(name_fields))
            name = next((row.get(field, "").strip() for field in ordered
                         if row.get(field, "").strip()), "")
            if name:
                names.setdefault(code, name)
    return names


def parse_value(text: str, where: str) -> CiqualValue:
    """One published composition value.

    Blank, "-" and the not-determined markers mean the constituent was never
    measured. "traces" and a "< x" detection limit mean present but negligible,
    which is stored as zero and marks the food estimated.
    """
    raw = text.strip()
    lowered = raw.casefold()
    if lowered in ABSENT:
        return CiqualValue(None, False)
    if lowered in TRACE:
        return CiqualValue(0.0, True)
    if raw.startswith("<"):
        return CiqualValue(0.0, True)
    try:
        number = parse_number(raw)
    except ValueError as error:
        raise InputError(f"{where}: {raw!r} is not a value Ciqual publishes ({error})") from error
    if number is None:
        return CiqualValue(None, False)
    if number < 0:
        raise InputError(f"{where}: negative value {raw!r}")
    return CiqualValue(number, False)


def read_composition(path: Path) -> dict[str, dict[int, CiqualValue]]:
    """Food code -> {constituent code: value}, keeping only what we map."""
    wanted = {code for spec in CONST_SPECS for code in spec.codes}
    composition: dict[str, dict[int, CiqualValue]] = {}
    for row in _elements(path, "COMPO"):
        code = row.get("const_code", "").strip()
        if not code.isdigit() or int(code) not in wanted:
            continue
        food = row.get("alim_code", "").strip()
        if not food:
            continue
        where = f"{path}: food {food}, constituent {code}"
        composition.setdefault(food, {})[int(code)] = parse_value(row.get("teneur", ""), where)
    if not composition:
        raise InputError(f"{path}: none of the constituents this pipeline reads are present")
    return composition


def map_nutrients(
    values: Mapping[int, CiqualValue]
) -> tuple[dict[str, float | None], bool]:
    """{column: value or None} plus whether any value came from a marker."""
    mapped: dict[str, float | None] = {}
    estimated = False
    for spec in CONST_SPECS:
        found = next((values[code] for code in spec.codes if code in values), None)
        mapped[spec.column] = None if found is None else found.value
        if found is not None and found.value is not None and found.is_estimated:
            estimated = True
    return mapped, estimated


def names_for(food: CiqualFood, prefer_english: bool) -> tuple[str, str, Sequence[str]]:
    """(display name, locale, other names to index for search)."""
    english = " ".join(food.name_eng.split())
    french = " ".join(food.name_fr.split())
    if prefer_english and english:
        primary, locale, others = english, NAME_LOCALE_EN, [french]
    else:
        primary, locale, others = french, NAME_LOCALE_FR, [english]
    others = [*others, " ".join(food.index_eng.split()), " ".join(food.index_fr.split())]
    unique: list[str] = []
    for name in others:
        if name and name != primary and name not in unique:
            unique.append(name)
    return primary, locale, unique
