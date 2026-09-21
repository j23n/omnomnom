"""Reading the FDC CSV bundles (Foundation Foods and SR Legacy).

Every reader refers to columns by name so extra columns in newer bundles are
harmless. Malformed input becomes InputError with file and line context.
"""

from __future__ import annotations

import csv
import logging
import math
import re
from collections.abc import Callable
from dataclasses import dataclass
from pathlib import Path
from typing import TypeVar

from .errors import InputError

log = logging.getLogger(__name__)

FOUNDATION = "fdc_foundation"
SR_LEGACY = "fdc_sr_legacy"

# Marker file -> source id. A folder is a bundle when it holds food.csv plus one marker.
MARKERS: dict[str, str] = {
    "foundation_food.csv": FOUNDATION,
    "sr_legacy_food.csv": SR_LEGACY,
}
DATA_TYPES: dict[str, str] = {FOUNDATION: "foundation_food", SR_LEGACY: "sr_legacy_food"}

REQUIRED_FILES: tuple[str, ...] = (
    "food.csv",
    "food_nutrient.csv",
    "nutrient.csv",
    "food_portion.csv",
    "measure_unit.csv",
    "food_category.csv",
)

_DATE_RE = re.compile(r"\d{4}-\d{2}(?:-\d{2})?")

Row = dict[str, str]
T = TypeVar("T")


@dataclass(frozen=True)
class Bundle:
    """One unzipped FDC dataset."""

    source: str
    root: Path
    version: str


@dataclass(frozen=True)
class FdcFood:
    fdc_id: int
    description: str
    data_type: str
    food_category_id: int | None


@dataclass(frozen=True)
class FdcPortion:
    fdc_id: int
    seq_num: int | None
    amount: float | None
    measure_unit_id: int | None
    portion_description: str
    modifier: str
    gram_weight: float | None


def version_from_path(path: Path, stop: Path) -> str:
    """Date in the folder name or its ancestors below `stop`; `stop` itself is never used."""
    for candidate in (path, *path.parents):
        if candidate == stop:
            break
        match = _DATE_RE.search(candidate.name)
        if match:
            return match.group(0)
    return "unknown"


def find_bundles(fdc_dir: Path) -> list[Bundle]:
    """Locate FDC bundles below `fdc_dir`.

    Accepts a directory that holds the CSVs directly, or one that holds a
    subdirectory per bundle at any depth (zips unpack to a variety of names).
    """
    fdc_dir = Path(fdc_dir)
    if not fdc_dir.is_dir():
        raise InputError(f"FDC directory not found: {fdc_dir}")
    bundles: dict[str, Bundle] = {}
    for food_csv in sorted(fdc_dir.rglob("food.csv")):
        root = food_csv.parent
        found = [source for marker, source in MARKERS.items() if (root / marker).is_file()]
        if not found:
            log.debug("skipping %s: no bundle marker file", root)
            continue
        if len(found) > 1:
            raise InputError(f"{root} contains markers for more than one bundle: {found}")
        source = found[0]
        missing = [name for name in REQUIRED_FILES if not (root / name).is_file()]
        if missing:
            raise InputError(f"{root} ({source}) is missing {', '.join(missing)}")
        if source in bundles:
            raise InputError(f"found two {source} bundles: {bundles[source].root} and {root}")
        bundles[source] = Bundle(source, root, version_from_path(root, fdc_dir))
        log.info("found %s bundle at %s (version %s)", source, root, bundles[source].version)
    if not bundles:
        raise InputError(f"no FDC bundle found under {fdc_dir}")
    return [bundles[s] for s in (FOUNDATION, SR_LEGACY) if s in bundles]


def _read(path: Path, required: tuple[str, ...], convert: Callable[[Row], T]) -> list[T]:
    """Read every row of a CSV through `convert`, turning any failure into InputError."""
    try:
        with path.open(newline="", encoding="utf-8-sig") as handle:
            reader = csv.DictReader(handle, restval="")
            fields = reader.fieldnames
            if fields is None:
                raise InputError(f"{path}: empty file, no header row")
            missing = [column for column in required if column not in fields]
            if missing:
                raise InputError(f"{path}: missing columns {', '.join(missing)}")
            result: list[T] = []
            for row in reader:
                try:
                    result.append(convert(row))
                except (ValueError, KeyError, TypeError) as error:
                    raise InputError(f"{path}:{reader.line_num}: {error}") from error
            return result
    except UnicodeDecodeError as error:
        raise InputError(f"{path}: not valid UTF-8 ({error})") from error
    except (OSError, csv.Error) as error:
        raise InputError(f"{path}: {error}") from error


def _text(row: Row, field: str) -> str:
    return (row.get(field) or "").strip()


def _int(row: Row, field: str) -> int | None:
    value = _text(row, field)
    if not value:
        return None
    try:
        return int(value)
    except ValueError:
        raise ValueError(f"{field}: {value!r} is not an integer") from None


def _required_int(row: Row, field: str) -> int:
    value = _int(row, field)
    if value is None:
        raise ValueError(f"{field}: empty")
    return value


def _float(row: Row, field: str) -> float | None:
    value = _text(row, field)
    if not value:
        return None
    try:
        number = float(value)
    except ValueError:
        raise ValueError(f"{field}: {value!r} is not a number") from None
    if not math.isfinite(number):
        raise ValueError(f"{field}: {value!r} is not finite")
    return number


def read_foods(root: Path, expected_data_type: str | None = None) -> list[FdcFood]:
    path = root / "food.csv"
    foods = _read(
        path,
        ("fdc_id", "description"),
        lambda row: FdcFood(
            fdc_id=_required_int(row, "fdc_id"),
            description=_text(row, "description"),
            data_type=_text(row, "data_type"),
            food_category_id=_int(row, "food_category_id"),
        ),
    )
    seen: set[int] = set()
    for food in foods:
        if food.fdc_id in seen:
            raise InputError(f"{path}: duplicate fdc_id {food.fdc_id}")
        seen.add(food.fdc_id)
    if expected_data_type is not None:
        odd = sum(1 for food in foods if food.data_type != expected_data_type)
        if odd:
            log.warning("%s: %d rows whose data_type is not %r", path, odd, expected_data_type)
    return foods


def read_nutrient_units(root: Path) -> dict[int, str]:
    """nutrient id -> unit_name as published (KCAL, G, MG, ...)."""
    pairs = _read(
        root / "nutrient.csv",
        ("id", "unit_name"),
        lambda row: (_required_int(row, "id"), _text(row, "unit_name")),
    )
    return dict(pairs)


def read_food_nutrients(root: Path) -> dict[int, dict[int, float]]:
    """fdc_id -> {nutrient_id: amount}. Empty amounts are omitted; duplicates keep the first.

    FDC publishes a few slightly negative amounts for values computed "by difference";
    those are clamped to zero and counted, since a negative nutrient has no meaning.
    """
    path = root / "food_nutrient.csv"
    triples = _read(
        path,
        ("fdc_id", "nutrient_id", "amount"),
        lambda row: (
            _required_int(row, "fdc_id"),
            _required_int(row, "nutrient_id"),
            _float(row, "amount"),
        ),
    )
    result: dict[int, dict[int, float]] = {}
    duplicates = 0
    negatives = 0
    for fdc_id, nutrient_id, amount in triples:
        if amount is None:
            continue
        if amount < 0:
            negatives += 1
            amount = 0.0
        amounts = result.setdefault(fdc_id, {})
        if nutrient_id in amounts:
            duplicates += 1
            continue
        amounts[nutrient_id] = amount
    if duplicates:
        log.warning("%s: %d duplicate (fdc_id, nutrient_id) rows, kept the first", path, duplicates)
    if negatives:
        log.warning("%s: %d negative amounts clamped to 0", path, negatives)
    return result


def read_measure_units(root: Path) -> dict[int, str]:
    pairs = _read(
        root / "measure_unit.csv",
        ("id", "name"),
        lambda row: (_required_int(row, "id"), _text(row, "name")),
    )
    return dict(pairs)


def read_categories(root: Path) -> dict[int, str]:
    pairs = _read(
        root / "food_category.csv",
        ("id", "description"),
        lambda row: (_required_int(row, "id"), _text(row, "description")),
    )
    return dict(pairs)


def read_portions(root: Path) -> dict[int, list[FdcPortion]]:
    """fdc_id -> portions in file order."""
    portions = _read(
        root / "food_portion.csv",
        ("fdc_id", "gram_weight"),
        lambda row: FdcPortion(
            fdc_id=_required_int(row, "fdc_id"),
            seq_num=_int(row, "seq_num"),
            amount=_float(row, "amount"),
            measure_unit_id=_int(row, "measure_unit_id"),
            portion_description=_text(row, "portion_description"),
            modifier=_text(row, "modifier"),
            gram_weight=_float(row, "gram_weight"),
        ),
    )
    result: dict[int, list[FdcPortion]] = {}
    for portion in portions:
        result.setdefault(portion.fdc_id, []).append(portion)
    return result
