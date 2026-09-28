"""Reading a source published as a spreadsheet or a delimited text file.

Sources outside FDC ship one wide table rather than a set of normalised CSVs,
and they ship it in whatever their publisher chose: an Excel workbook, a
semicolon-separated export, a tab-separated one. This module turns any of those
into the same `Table` of header row plus string cells, so a reader deals with
column names and never with file format.

Excel is read from the file itself: an .xlsx is a zip of XML, which the standard
library opens, and no third-party dependency is allowed here. The old binary
.xls is not readable that way and is rejected with the one-line fix.
"""

from __future__ import annotations

import csv
import io
import logging
import zipfile
from collections.abc import Iterator, Sequence
from dataclasses import dataclass
from pathlib import Path
from xml.etree import ElementTree

from .errors import InputError

log = logging.getLogger(__name__)

SPREADSHEET_NS = "{http://schemas.openxmlformats.org/spreadsheetml/2006/main}"
RELATIONSHIP_NS = "{http://schemas.openxmlformats.org/package/2006/relationships}"
DOCUMENT_RELATIONSHIP_NS = "{http://schemas.openxmlformats.org/officeDocument/2006/relationships}"

SPREADSHEET_SUFFIXES = (".xlsx", ".xlsm")
DELIMITED_SUFFIXES = (".csv", ".tsv", ".txt")
TABLE_SUFFIXES = SPREADSHEET_SUFFIXES + DELIMITED_SUFFIXES

# Tried in order; the first that splits the header row into more than one column wins.
DELIMITERS = (";", "\t", ",", "|")
# German and French exports are routinely Windows-encoded rather than UTF-8.
ENCODINGS = ("utf-8-sig", "cp1252")

_MAX_HEADER_SCAN = 20


@dataclass(frozen=True)
class Table:
    """A header row and the rows below it, every cell a string."""

    path: Path
    sheet: str | None
    headers: tuple[str, ...]
    rows: tuple[tuple[str, ...], ...]

    @property
    def where(self) -> str:
        return f"{self.path}" if self.sheet is None else f"{self.path} [{self.sheet}]"

    def require(self, columns: Sequence[str]) -> None:
        missing = [column for column in columns if column not in self.headers]
        if missing:
            raise InputError(
                f"{self.where}: missing columns {', '.join(missing)}. "
                f"Columns present: {', '.join(self.headers) or '(none)'}"
            )

    def index(self, column: str) -> int:
        """Where a column sits, for reading a wide table without a dict per row.

        The BLS is 418 columns and 7,140 rows; naming every cell of it would be
        three million dictionary entries to reach eleven of them.
        """
        try:
            return self.headers.index(column)
        except ValueError:
            raise InputError(f"{self.where}: no column named {column!r}") from None

    @staticmethod
    def cell(row: Sequence[str], index: int) -> str:
        """One cell of a row, empty when the row stops short of it."""
        return row[index] if 0 <= index < len(row) else ""

    def dicts(self) -> Iterator[tuple[int, dict[str, str]]]:
        """(line number, row by column name). Short rows pad with empty strings."""
        width = len(self.headers)
        for number, row in enumerate(self.rows, start=2):
            cells = list(row[:width]) + [""] * max(0, width - len(row))
            yield number, dict(zip(self.headers, cells))


def parse_number(text: str) -> float | None:
    """A number written the English or the continental way, or None when it is blank.

    "1.5" and "1,5" are both one and a half. With both separators present the comma
    groups thousands, as in "1,234.5". Anything else raises ValueError, so a marker
    such as "traces" is the caller's to recognise before asking for a number.
    """
    value = text.strip().replace(" ", "").replace(" ", "")
    if not value:
        return None
    if "," in value and "." in value:
        value = value.replace(",", "")
    else:
        value = value.replace(",", ".")
    number = float(value)  # ValueError for the caller to contextualise
    if number != number or number in (float("inf"), float("-inf")):
        raise ValueError(f"{text!r} is not finite")
    return number


def read_table(path: Path, sheet: str | None = None) -> Table:
    """Read `path` as a table, choosing the reader by suffix."""
    path = Path(path)
    suffix = path.suffix.lower()
    if suffix == ".xls":
        raise InputError(
            f"{path}: the old binary .xls format cannot be read without a third-party "
            f"library. Open it and save as .xlsx, or download the .xlsx edition."
        )
    if suffix in SPREADSHEET_SUFFIXES:
        return _read_spreadsheet(path, sheet)
    if suffix in DELIMITED_SUFFIXES:
        return _read_delimited(path)
    raise InputError(f"{path}: not a table this pipeline reads ({', '.join(TABLE_SUFFIXES)})")


def find_table(root: Path, stem_hints: Sequence[str] = ()) -> Path:
    """The one table file under `root`, preferring a name containing a hint.

    Publishers name their download whatever they like and change it between
    versions, so the folder is the argument and the file is discovered. When the
    folder holds several candidates a hint disambiguates; without one, it is an
    error rather than a guess.
    """
    root = Path(root)
    if root.is_file():
        return root
    if not root.is_dir():
        raise InputError(f"directory not found: {root}")
    candidates = sorted(
        path
        for path in root.rglob("*")
        if path.is_file()
        and path.suffix.lower() in TABLE_SUFFIXES
        and not path.name.startswith(".")
    )
    if not candidates:
        raise InputError(
            f"{root}: no {' or '.join(TABLE_SUFFIXES)} file found. Unzip the download into this "
            f"folder, or point at the file itself."
        )
    if len(candidates) == 1:
        return candidates[0]
    for hint in stem_hints:
        hinted = [path for path in candidates if hint.lower() in path.name.lower()]
        if len(hinted) == 1:
            return hinted[0]
    listing = ", ".join(path.name for path in candidates)
    raise InputError(f"{root}: several tables here ({listing}); point at the one to read")


def _read_delimited(path: Path) -> Table:
    text = _decode(path)
    lines = text.splitlines()
    if not lines:
        raise InputError(f"{path}: empty file, no header row")
    delimiter = _delimiter(lines[0])
    try:
        rows = list(csv.reader(io.StringIO(text), delimiter=delimiter))
    except csv.Error as error:
        raise InputError(f"{path}: {error}") from error
    rows = [row for row in rows if any(cell.strip() for cell in row)]
    if not rows:
        raise InputError(f"{path}: no rows")
    headers = tuple(cell.strip() for cell in rows[0])
    return Table(path=path, sheet=None, headers=headers, rows=tuple(tuple(r) for r in rows[1:]))


def _decode(path: Path) -> str:
    try:
        raw = path.read_bytes()
    except OSError as error:
        raise InputError(f"cannot read {path}: {error}") from error
    for encoding in ENCODINGS:
        try:
            return raw.decode(encoding)
        except UnicodeDecodeError:
            continue
    raise InputError(f"{path}: not readable as {' or '.join(ENCODINGS)}")


def _delimiter(header_line: str) -> str:
    best = max(DELIMITERS, key=header_line.count)
    return best if header_line.count(best) else ","


def _read_spreadsheet(path: Path, sheet: str | None) -> Table:
    try:
        with zipfile.ZipFile(path) as archive:
            names = _sheet_targets(archive, path)
            target, title = _pick_sheet(names, sheet, path)
            strings = _shared_strings(archive)
            rows = _sheet_rows(archive, target, strings, path)
    except zipfile.BadZipFile as error:
        raise InputError(f"{path}: not a readable .xlsx ({error})") from error
    except OSError as error:
        raise InputError(f"cannot read {path}: {error}") from error
    header_index = _header_index(rows)
    if header_index is None:
        raise InputError(
            f"{path} [{title}]: no header row in the first {_MAX_HEADER_SCAN} rows"
        )
    headers = tuple(cell.strip() for cell in rows[header_index])
    body = tuple(tuple(row) for row in rows[header_index + 1:] if any(cell.strip() for cell in row))
    return Table(path=path, sheet=title, headers=headers, rows=body)


def _header_index(rows: Sequence[Sequence[str]]) -> int | None:
    """The first row that names at least two columns.

    Publishers put a title line, or a blank one, above the header. Nothing below
    a real header is ever blank in both of its first columns, so the first row
    with two non-empty cells is the header.
    """
    for index, row in enumerate(rows[:_MAX_HEADER_SCAN]):
        if sum(1 for cell in row if cell.strip()) >= 2:
            return index
    return None


def _sheet_targets(archive: zipfile.ZipFile, path: Path) -> list[tuple[str, str]]:
    """[(zip member path, sheet title)] in workbook order."""
    workbook = _xml(archive, "xl/workbook.xml", path)
    rels = _xml(archive, "xl/_rels/workbook.xml.rels", path)
    by_id = {
        element.get("Id", ""): element.get("Target", "")
        for element in rels.iter(f"{RELATIONSHIP_NS}Relationship")
    }
    targets: list[tuple[str, str]] = []
    for element in workbook.iter(f"{SPREADSHEET_NS}sheet"):
        target = by_id.get(element.get(f"{DOCUMENT_RELATIONSHIP_NS}id", ""), "")
        if not target:
            continue
        member = target[1:] if target.startswith("/") else f"xl/{target.lstrip('/')}"
        targets.append((member.replace("xl/xl/", "xl/"), element.get("name", "")))
    if not targets:
        raise InputError(f"{path}: the workbook holds no sheets")
    return targets


def _pick_sheet(
    targets: Sequence[tuple[str, str]], wanted: str | None, path: Path
) -> tuple[str, str]:
    if wanted is None:
        return targets[0]
    for member, title in targets:
        if title == wanted:
            return member, title
    listing = ", ".join(title for _, title in targets)
    raise InputError(f"{path}: no sheet named {wanted!r}; the workbook has {listing}")


def _shared_strings(archive: zipfile.ZipFile) -> list[str]:
    if "xl/sharedStrings.xml" not in archive.namelist():
        return []
    root = ElementTree.fromstring(archive.read("xl/sharedStrings.xml"))
    return ["".join(node.text or "" for node in item.iter(f"{SPREADSHEET_NS}t")) for item in root]


def _sheet_rows(
    archive: zipfile.ZipFile, member: str, strings: Sequence[str], path: Path
) -> list[list[str]]:
    if member not in archive.namelist():
        raise InputError(f"{path}: the workbook is missing {member}")
    root = ElementTree.fromstring(archive.read(member))
    rows: list[list[str]] = []
    for row in root.iter(f"{SPREADSHEET_NS}row"):
        cells: list[str] = []
        for cell in row.iter(f"{SPREADSHEET_NS}c"):
            index = _column_index(cell.get("r", ""))
            if index is None:
                index = len(cells)
            while len(cells) <= index:
                cells.append("")
            cells[index] = _cell_text(cell, strings)
        rows.append(cells)
    return rows


def _cell_text(cell: ElementTree.Element, strings: Sequence[str]) -> str:
    kind = cell.get("t", "n")
    if kind == "s":
        node = cell.find(f"{SPREADSHEET_NS}v")
        index = (node.text or "").strip() if node is not None else ""
        if not index:
            return ""
        try:
            return strings[int(index)]
        except (ValueError, IndexError):
            return ""
    if kind == "inlineStr":
        inline = cell.find(f"{SPREADSHEET_NS}is")
        if inline is None:
            return ""
        return "".join(node.text or "" for node in inline.iter(f"{SPREADSHEET_NS}t"))
    node = cell.find(f"{SPREADSHEET_NS}v")
    return (node.text or "") if node is not None else ""


def _column_index(reference: str) -> int | None:
    """"C7" -> 2. None when the cell carries no reference."""
    letters = "".join(character for character in reference if character.isalpha())
    if not letters:
        return None
    index = 0
    for character in letters.upper():
        index = index * 26 + (ord(character) - ord("A") + 1)
    return index - 1


def _xml(archive: zipfile.ZipFile, member: str, path: Path) -> ElementTree.Element:
    if member not in archive.namelist():
        raise InputError(f"{path}: not a readable .xlsx, {member} is missing")
    try:
        return ElementTree.fromstring(archive.read(member))
    except ElementTree.ParseError as error:
        raise InputError(f"{path}: {member} is not valid XML ({error})") from error
