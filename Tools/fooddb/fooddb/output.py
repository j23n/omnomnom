"""Writing foods.sqlite and sources.json atomically."""

from __future__ import annotations

import datetime as dt
import json
import logging
import os
import re
import sqlite3
from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from pathlib import Path

from .build import FoodRow
from .bundles import BLS, CIQUAL, FOUNDATION, SR_LEGACY
from .errors import InputError
from .fsutil import publish, temp_beside
from .mapping import NUTRIENT_COLUMNS

log = logging.getLogger(__name__)

SCHEMA_VERSION = "3"
SCHEMA_PATH = Path(__file__).parent / "schema.sql"

_FOOD_COLUMNS = (
    "name", "name_locale", "alt_names", "source", "source_ref", "category",
    *NUTRIENT_COLUMNS, "is_estimated", "is_ingredient", "popularity",
)
_INSERT_FOOD = (
    f"INSERT INTO foods({', '.join(_FOOD_COLUMNS)}) VALUES ({', '.join('?' * len(_FOOD_COLUMNS))})"
)
_INSERT_PORTION = "INSERT INTO portions(food_id, label, grams, seq) VALUES (?, ?, ?, ?)"
_INSERT_META = "INSERT INTO meta(key, value) VALUES (?, ?)"
_YEAR_RE = re.compile(r"^\d{4}")


def build_time() -> dt.datetime:
    """Now in UTC, or SOURCE_DATE_EPOCH when set (reproducible builds)."""
    epoch = os.environ.get("SOURCE_DATE_EPOCH")
    if epoch is None:
        return dt.datetime.now(dt.timezone.utc)
    try:
        return dt.datetime.fromtimestamp(int(epoch), dt.timezone.utc)
    except (ValueError, OverflowError, OSError) as error:
        raise InputError(f"SOURCE_DATE_EPOCH={epoch!r} is not a valid epoch: {error}") from error


def citation_year(versions: Mapping[str, str]) -> int:
    """Year of the newest dataset version; the build year when no version carries one."""
    years = [int(m.group(0)) for v in versions.values() if (m := _YEAR_RE.match(v))]
    return max(years) if years else build_time().year


def _food_params(row: FoodRow) -> tuple[object, ...]:
    return (
        row.name,
        row.name_locale,
        "\n".join(row.alt_names) or None,
        row.source,
        row.source_ref,
        row.category,
        *(row.nutrients[column] for column in NUTRIENT_COLUMNS),
        row.is_estimated,
        row.is_ingredient,
        row.popularity,
    )


def _populate(conn: sqlite3.Connection, rows: Sequence[FoodRow], meta: Mapping[str, str]) -> None:
    conn.executescript(SCHEMA_PATH.read_text(encoding="utf-8"))
    portion_count = 0
    for row in rows:
        food_id = conn.execute(_INSERT_FOOD, _food_params(row)).lastrowid
        for portion in row.portions:
            conn.execute(_INSERT_PORTION, (food_id, portion.label, portion.grams, portion.seq))
            portion_count += 1
    conn.execute("INSERT INTO foods_fts(foods_fts) VALUES('rebuild')")
    full_meta = {
        "schema_version": SCHEMA_VERSION,
        "built_at": build_time().isoformat(timespec="seconds"),
        "food_count": str(len(rows)),
        "portion_count": str(portion_count),
        **meta,
    }
    conn.executemany(_INSERT_META, sorted(full_meta.items()))
    conn.commit()


def write_sqlite(target: Path, rows: Sequence[FoodRow], meta: Mapping[str, str]) -> None:
    """Build the database in a temp file and rename it over `target`."""
    target = Path(target)
    try:
        temp = temp_beside(target)
    except OSError as error:
        raise InputError(f"cannot write {target}: {error}") from error
    try:
        conn = sqlite3.connect(temp)
        try:
            conn.execute("PRAGMA journal_mode=DELETE")
            _populate(conn, rows, meta)
            conn.execute("VACUUM")
        finally:
            conn.close()
        publish(temp, target)
    except (OSError, sqlite3.Error) as error:
        temp.unlink(missing_ok=True)
        raise InputError(f"cannot write {target}: {error}") from error
    except BaseException:
        temp.unlink(missing_ok=True)
        raise
    log.info("wrote %s (%d foods)", target, len(rows))


@dataclass(frozen=True)
class Source:
    """One publisher's entry in the attribution manifest.

    `datasets` are the build's own source ids paired with the names a reader would
    recognise; a source whose datasets are all absent from this build is left out
    of the manifest entirely, so the Sources screen names only what shipped.
    """

    id: str
    name: str
    publisher: str
    datasets: tuple[tuple[str, str], ...]
    licence: str
    licence_url: str
    url: str
    citation: str  # {year} is the newest dataset year, {version} the first version


SOURCES: tuple[Source, ...] = (
    Source(
        id="ciqual",
        name="Ciqual",
        publisher="ANSES, Agence nationale de sécurité sanitaire de l'alimentation, "
                  "de l'environnement et du travail",
        datasets=((CIQUAL, "Ciqual food composition table"),),
        licence="Licence Ouverte / Open Licence (Etalab)",
        licence_url="https://www.etalab.gouv.fr/licence-ouverte-open-licence/",
        url="https://ciqual.anses.fr/",
        citation="ANSES. Ciqual French food composition table, {year}. ciqual.anses.fr.",
    ),
    Source(
        id="bls",
        name="Bundeslebensmittelschlüssel",
        publisher="Max Rubner-Institut, Bundesforschungsinstitut für Ernährung und Lebensmittel",
        datasets=((BLS, "Bundeslebensmittelschlüssel (BLS)"),),
        licence="CC BY 4.0",
        licence_url="https://creativecommons.org/licenses/by/4.0/",
        url="https://www.blsdb.de/",
        citation="Max Rubner-Institut. Bundeslebensmittelschlüssel (BLS), "
                 "Version {version}. blsdb.de.",
    ),
    Source(
        id="fdc",
        name="USDA FoodData Central",
        publisher="U.S. Department of Agriculture, Agricultural Research Service",
        datasets=((FOUNDATION, "Foundation Foods"), (SR_LEGACY, "SR Legacy")),
        licence="CC0 1.0",
        licence_url="https://creativecommons.org/publicdomain/zero/1.0/",
        url="https://fdc.nal.usda.gov/",
        citation="U.S. Department of Agriculture, Agricultural Research Service. "
                 "FoodData Central, {year}. fdc.nal.usda.gov.",
    ),
)


def sources_manifest(versions: Mapping[str, str]) -> list[dict[str, object]]:
    """The manifest for what this build actually read, in source order."""
    manifest: list[dict[str, object]] = []
    for source in SOURCES:
        datasets = [
            {"id": dataset_id, "name": name, "version": versions[dataset_id]}
            for dataset_id, name in source.datasets
            if dataset_id in versions
        ]
        if not datasets:
            continue
        own = {str(entry["id"]): str(entry["version"]) for entry in datasets}
        manifest.append({
            "id": source.id,
            "name": source.name,
            "publisher": source.publisher,
            "datasets": datasets,
            "licence": source.licence,
            "licence_url": source.licence_url,
            "url": source.url,
            "citation": source.citation.format(
                year=citation_year(own), version=next(iter(own.values()))
            ),
        })
    if not manifest:
        raise InputError("no source in this build has an attribution entry")
    return manifest


def write_sources_json(target: Path, versions: Mapping[str, str]) -> None:
    target = Path(target)
    try:
        temp = temp_beside(target)
    except OSError as error:
        raise InputError(f"cannot write {target}: {error}") from error
    try:
        temp.write_text(json.dumps(sources_manifest(versions), indent=2) + "\n", encoding="utf-8")
        publish(temp, target)
    except OSError as error:
        temp.unlink(missing_ok=True)
        raise InputError(f"cannot write {target}: {error}") from error
    except BaseException:
        temp.unlink(missing_ok=True)
        raise
    log.info("wrote %s", target)
