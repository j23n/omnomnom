from __future__ import annotations

import tempfile
import unittest
import zipfile
from pathlib import Path

from fooddb.errors import InputError
from fooddb.table import find_table, parse_number, read_table

SHEET_XML = """<?xml version="1.0"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
 <sheetData>
  <row r="1"><c r="A1" t="s"><v>0</v></c><c r="C1" t="s"><v>1</v></c></row>
  <row r="2"><c r="A2" t="inlineStr"><is><t>Apfel</t></is></c><c r="C2"><v>54.3</v></c></row>
  <row r="3"><c r="A3" t="s"><v>2</v></c><c r="C3"><v>272</v></c></row>
 </sheetData>
</worksheet>
"""

STRINGS_XML = """<?xml version="1.0"?>
<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
 <si><t>ST</t></si><si><t>GCAL</t></si><si><t>Brot</t></si>
</sst>
"""

WORKBOOK_XML = """<?xml version="1.0"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"
 xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
 <sheets><sheet name="Daten" sheetId="1" r:id="rId1"/></sheets>
</workbook>
"""

RELS_XML = """<?xml version="1.0"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
 <Relationship Id="rId1" Target="worksheets/sheet1.xml"
  Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet"/>
</Relationships>
"""


def write_workbook(path: Path) -> None:
    with zipfile.ZipFile(path, "w") as archive:
        archive.writestr("xl/workbook.xml", WORKBOOK_XML)
        archive.writestr("xl/_rels/workbook.xml.rels", RELS_XML)
        archive.writestr("xl/sharedStrings.xml", STRINGS_XML)
        archive.writestr("xl/worksheets/sheet1.xml", SHEET_XML)


class ParseNumberTests(unittest.TestCase):
    def test_both_decimal_conventions(self) -> None:
        self.assertEqual(parse_number("1.5"), 1.5)
        self.assertEqual(parse_number("1,5"), 1.5)
        self.assertEqual(parse_number(" 1 234,5 "), 1234.5)
        self.assertEqual(parse_number("1,234.5"), 1234.5)

    def test_blank_is_none(self) -> None:
        self.assertIsNone(parse_number(""))
        self.assertIsNone(parse_number("   "))

    def test_words_and_infinities_raise(self) -> None:
        for text in ("traces", "n/a", "inf", "nan"):
            with self.assertRaises(ValueError):
                parse_number(text)


class TempDirTests(unittest.TestCase):
    def setUp(self) -> None:
        self.dir = Path(tempfile.mkdtemp())
        self.addCleanup(lambda: __import__("shutil").rmtree(self.dir, ignore_errors=True))


class SpreadsheetTests(TempDirTests):
    def test_reads_shared_inline_and_numeric_cells(self) -> None:
        path = self.dir / "bls.xlsx"
        write_workbook(path)
        table = read_table(path)
        self.assertEqual(table.sheet, "Daten")
        # The B column is empty in every row and keeps its place.
        self.assertEqual(table.headers, ("ST", "", "GCAL"))
        self.assertEqual([row for _, row in table.dicts()],
                         [{"ST": "Apfel", "": "", "GCAL": "54.3"},
                          {"ST": "Brot", "": "", "GCAL": "272"}])

    def test_unknown_sheet_names_the_ones_present(self) -> None:
        path = self.dir / "bls.xlsx"
        write_workbook(path)
        with self.assertRaises(InputError) as caught:
            read_table(path, sheet="Nope")
        self.assertIn("Daten", str(caught.exception))

    def test_old_binary_excel_says_what_to_do(self) -> None:
        path = self.dir / "bls.xls"
        path.write_bytes(b"\xd0\xcf\x11\xe0")
        with self.assertRaises(InputError) as caught:
            read_table(path)
        self.assertIn("save as .xlsx", str(caught.exception))


class DelimitedTests(TempDirTests):
    def test_semicolons_and_windows_encoding(self) -> None:
        path = self.dir / "bls.csv"
        path.write_bytes("ST;GCAL\r\nGemüse;25\r\n".encode("cp1252"))
        table = read_table(path)
        self.assertEqual(table.headers, ("ST", "GCAL"))
        self.assertEqual([row for _, row in table.dicts()], [{"ST": "Gemüse", "GCAL": "25"}])

    def test_tabs(self) -> None:
        path = self.dir / "bls.txt"
        path.write_text("ST\tGCAL\nApfel\t54\n", encoding="utf-8")
        self.assertEqual(read_table(path).headers, ("ST", "GCAL"))

    def test_short_rows_pad(self) -> None:
        path = self.dir / "bls.csv"
        path.write_text("a;b;c\n1;2\n", encoding="utf-8")
        self.assertEqual([row for _, row in read_table(path).dicts()],
                         [{"a": "1", "b": "2", "c": ""}])


class FindTableTests(TempDirTests):
    def test_nothing_to_read(self) -> None:
        with self.assertRaises(InputError) as caught:
            find_table(self.dir)
        self.assertIn("no .xlsx", str(caught.exception))

    def test_single_file_wins_wherever_it_sits(self) -> None:
        nested = self.dir / "BLS_4.0" / "daten"
        nested.mkdir(parents=True)
        (nested / "bls.csv").write_text("a;b\n1;2\n", encoding="utf-8")
        self.assertEqual(find_table(self.dir).name, "bls.csv")

    def test_several_need_a_hint(self) -> None:
        (self.dir / "readme.txt").write_text("a;b\n", encoding="utf-8")
        (self.dir / "other.csv").write_text("a;b\n", encoding="utf-8")
        with self.assertRaises(InputError) as caught:
            find_table(self.dir)
        self.assertIn("several tables", str(caught.exception))
        (self.dir / "bls_4.0.csv").write_text("a;b\n", encoding="utf-8")
        self.assertEqual(find_table(self.dir, ("bls",)).name, "bls_4.0.csv")


if __name__ == "__main__":
    unittest.main()
