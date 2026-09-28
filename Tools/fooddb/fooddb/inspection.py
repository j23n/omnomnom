"""Describing a downloaded source without building anything.

A publisher renames columns and files between editions, and the build can only
say that something it expected is missing. This says what is actually there, so
the mapping tables in `ciqual.py` and `bls.py` can be corrected in one edit.
"""

from __future__ import annotations

from collections.abc import Sequence
from pathlib import Path

from . import bls, ciqual
from .errors import FooddbError
from .table import TABLE_SUFFIXES, Table, find_table, read_table

_SAMPLE_ROWS = 3
_SAMPLE_VALUES = 60


def describe(path: Path, sheet: str | None = None) -> str:
    """A report on whatever is at `path`: a Ciqual export, or a table of any source."""
    path = Path(path)
    if not path.exists():
        raise FooddbError(f"not found: {path}")
    lines: list[str] = [f"{path}"]
    if path.is_dir() and _looks_like_ciqual(path):
        lines.extend(_describe_ciqual(path))
        return "\n".join(lines)
    table_path = find_table(path, stem_hints=("bls", "bundeslebensmittel"))
    lines.extend(_describe_table(table_path, sheet))
    return "\n".join(lines)


def _looks_like_ciqual(root: Path) -> bool:
    names = [candidate.name.lower() for candidate in root.rglob("*.xml")]
    return any(name.startswith("alim") for name in names)


def _describe_ciqual(root: Path) -> list[str]:
    lines = ["  looks like a Ciqual XML export"]
    files = ciqual.locate_files(root)
    for role, file_path in files.items():
        lines.append(f"  {role}: {file_path.name}")
    units = ciqual.read_constituent_units(files["const"])
    lines.append(f"  constituents carrying a unit: {len(units)}")
    for spec in ciqual.CONST_SPECS:
        found = [code for code in spec.codes if code in units]
        if found:
            code = found[0]
            lines.append(f"    {spec.column}: {code} in {units[code]!r} (expected {spec.unit!r})")
        else:
            lines.append(f"    {spec.column}: NONE of {spec.codes} present")
    foods = ciqual.read_foods(files["foods"])
    english = sum(1 for food in foods if food.name_eng.strip())
    lines.append(f"  foods: {len(foods)}, of which {english} have an English name")
    for food in foods[:_SAMPLE_ROWS]:
        lines.append(f"    {food.code}: {food.name_fr!r} / {food.name_eng!r}")
    return lines


def _describe_table(path: Path, sheet: str | None) -> list[str]:
    table = read_table(path, sheet)
    lines = [f"  table: {table.where}", f"  columns: {len(table.headers)}, rows: {len(table.rows)}"]
    lines.extend(_column_lines(table.headers))
    lines.append("  first rows:")
    for _, row in list(table.dicts())[:_SAMPLE_ROWS]:
        shown = ", ".join(f"{name}={value!r}" for name, value in row.items() if value.strip())
        lines.append(f"    {shown[:_SAMPLE_VALUES * 4]}")
    lines.extend(_bls_lines(table))
    return lines


def _column_lines(headers: Sequence[str]) -> list[str]:
    lines = ["  column names:"]
    for index, header in enumerate(headers):
        lines.append(f"    [{index}] {header!r}")
    return lines


def _bls_lines(table: Table) -> list[str]:
    lines = ["  read as a BLS table:"]
    try:
        columns = bls.resolve_columns(table)
    except FooddbError as error:
        lines.append(f"    would fail: {error}")
        return lines
    lines.append(f"    code: {columns.key!r}, name: {columns.german_name!r}")
    lines.append(f"    English name: {columns.english_name!r}, category: {columns.category!r}")
    for spec in bls.COLUMN_SPECS:
        header = columns.nutrients.get(spec.column)
        lines.append(f"    {spec.column}: {header!r}" if header
                     else f"    {spec.column}: not found")
    try:
        rows, blank, _ = bls.read(table.path, table.sheet)
    except FooddbError as error:
        lines.append(f"    values would fail: {error}")
        return lines
    lines.append(f"    {len(rows)} rows readable, {blank} without a name")
    return lines


def suffixes() -> str:
    return ", ".join(TABLE_SUFFIXES)
