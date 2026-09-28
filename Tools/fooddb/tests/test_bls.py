from __future__ import annotations

import shutil
import tempfile
import unittest
from pathlib import Path

from fooddb import bls
from fooddb import build as b
from fooddb.errors import InputError, MappingError
from fooddb.table import read_table

FIXTURES = Path(__file__).parent / "fixtures" / "bls"


def table_from(text: str, name: str = "bls.csv") -> tuple[Path, object]:
    directory = Path(tempfile.mkdtemp())
    path = directory / name
    path.write_text(text, encoding="utf-8")
    return path, read_table(path)


class ColumnTests(unittest.TestCase):
    def test_short_mnemonics(self) -> None:
        columns = bls.resolve_columns(read_table(FIXTURES / "bls_4.0_daten.csv"))
        self.assertEqual(columns.key, "SBLS")
        self.assertEqual(columns.german_name, "ST")
        self.assertEqual(columns.english_name, "STE")
        self.assertEqual(columns.category, "Hauptgruppe")
        self.assertEqual(columns.nutrients["sugar_100g"], "KMD")

    def test_spelled_out_names_in_any_case_or_spelling(self) -> None:
        _, table = table_from(
            "BLS-Schlüssel;Lebensmittelbezeichnung;Energie (kcal);EIWEISS;Fett;Kohlenhydrate\n"
            "F110100;Apfel;54;0,3;0,4;11,4\n"
        )
        columns = bls.resolve_columns(table)  # type: ignore[arg-type]
        self.assertEqual(columns.german_name, "Lebensmittelbezeichnung")
        self.assertEqual(columns.nutrients["protein_100g"], "EIWEISS")
        self.assertEqual(columns.nutrients["kcal_100g"], "Energie (kcal)")

    def test_missing_required_column_lists_what_is_there(self) -> None:
        _, table = table_from("SBLS;ST;GCAL;ZE;ZF\nF1;Apfel;54;0,3;0,4\n")
        with self.assertRaises(MappingError) as caught:
            bls.resolve_columns(table)  # type: ignore[arg-type]
        message = str(caught.exception)
        self.assertIn("carb_100g", message)
        self.assertIn("SBLS, ST, GCAL, ZE, ZF", message)

    def test_missing_name_column_says_so(self) -> None:
        _, table = table_from("SBLS;GCAL;ZE;ZF;ZK\nF1;54;0,3;0,4;11\n")
        with self.assertRaises(InputError) as caught:
            bls.resolve_columns(table)  # type: ignore[arg-type]
        self.assertIn("food name", str(caught.exception))

    def test_optional_columns_may_be_absent(self) -> None:
        _, table = table_from("SBLS;ST;GCAL;ZE;ZF;ZK\nF1;Apfel;54;0,3;0,4;11,4\n")
        columns = bls.resolve_columns(table)  # type: ignore[arg-type]
        self.assertNotIn("sodium_mg_100g", columns.nutrients)


class UnitTests(unittest.TestCase):
    def test_milligram_table_is_converted(self) -> None:
        rows, _, _ = bls.read(FIXTURES / "bls_4.0_daten.csv")
        butter = next(row for row in rows if row["name"] == "Butter")
        values = butter["values"]
        assert isinstance(values, dict)
        self.assertAlmostEqual(values["fat_100g"], 82.5)
        self.assertAlmostEqual(values["satfat_100g"], 51.0)
        self.assertAlmostEqual(values["kcal_100g"], 741.0)
        self.assertAlmostEqual(values["sodium_mg_100g"], 11.0)

    def test_gram_table_is_left_alone_and_sodium_scaled_up(self) -> None:
        path, _ = table_from(
            "SBLS;ST;GCAL;ZE;ZF;ZK;MNA\n"
            "F1;Apfel;54;0,3;0,4;11,4;0,001\n"
            "M1;Butter;741;0,6;82,5;0,6;0,011\n"
        )
        rows, _, _ = bls.read(path)
        butter = next(row for row in rows if row["name"] == "Butter")
        values = butter["values"]
        assert isinstance(values, dict)
        self.assertAlmostEqual(values["fat_100g"], 82.5)
        self.assertAlmostEqual(values["sodium_mg_100g"], 11.0)

    def test_one_odd_row_does_not_flip_the_unit(self) -> None:
        rows = "\n".join(f"F{index};Apfel {index};54;0,3;0,4;11,4" for index in range(50))
        path, _ = table_from(f"SBLS;ST;GCAL;ZE;ZF;ZK\n{rows}\nX1;Ausreisser;54;0,3;0,4;9999\n")
        read, _, _ = bls.read(path)
        apple = read[0]["values"]
        assert isinstance(apple, dict)
        self.assertAlmostEqual(apple["carb_100g"], 11.4)

    def test_kilojoule_column_is_refused(self) -> None:
        path, _ = table_from(
            "SBLS;ST;Energie;ZE;ZF;ZK\nF1;Apfel;227;0,3;0,4;11,4\nM1;Butter;3100;0,6;82,5;0,6\n"
        )
        with self.assertRaises(MappingError) as caught:
            bls.read(path)
        self.assertIn("kilojoules", str(caught.exception))

    def test_a_column_that_is_grams_for_some_rows_only_is_refused(self) -> None:
        # Most of the table reads as grams, so nothing is converted, and then a
        # tenth of the rows hold more carbohydrate than a food can.
        plain = "\n".join(f"F{index};Apfel {index};54;0,3;0,4;10" for index in range(40))
        odd = "\n".join(f"X{index};Sonderfall {index};54;0,3;0,4;5000" for index in range(10))
        path, _ = table_from(f"SBLS;ST;GCAL;ZE;ZF;ZK\n{plain}\n{odd}\n")
        with self.assertRaises(MappingError) as caught:
            bls.read(path)
        self.assertIn("carb_100g", str(caught.exception))


class RowTests(unittest.TestCase):
    def test_duplicate_code_fails_with_the_line(self) -> None:
        path, _ = table_from(
            "SBLS;ST;GCAL;ZE;ZF;ZK\nF1;Apfel;54;0,3;0,4;11,4\nF1;Apfel zwei;54;0,3;0,4;11,4\n"
        )
        with self.assertRaises(InputError) as caught:
            bls.read(path)
        self.assertIn(":3", str(caught.exception))

    def test_text_where_a_number_belongs_fails(self) -> None:
        path, _ = table_from("SBLS;ST;GCAL;ZE;ZF;ZK\nF1;Apfel;keine;0,3;0,4;11,4\n")
        with self.assertRaises(InputError) as caught:
            bls.read(path)
        self.assertIn("GCAL", str(caught.exception))

    def test_version_from_the_file_name(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp) / "BLS 4.0"
            root.mkdir()
            shutil.copy(FIXTURES / "bls_4.0_daten.csv", root)
            self.assertEqual(bls.find_bundle(root).version, "4.0")


class LoadTests(unittest.TestCase):
    def rows(self) -> list[b.FoodRow]:
        return b.load_bls_bundle(bls.find_bundle(FIXTURES), b.BuildSummary())

    def test_german_name_shown_english_indexed(self) -> None:
        apple = next(row for row in self.rows() if row.source_ref == "F110100")
        self.assertEqual(apple.name, "Apfel roh")
        self.assertEqual(apple.name_locale, "de")
        self.assertEqual(apple.alt_names, ("Apple raw",))
        self.assertEqual(apple.category, "Obst")

    def test_an_english_name_equal_to_the_german_one_is_not_repeated(self) -> None:
        butter = next(row for row in self.rows() if row.source_ref == "M120100")
        self.assertEqual(butter.alt_names, ())

    def test_rows_without_energy_or_a_name_are_dropped(self) -> None:
        summary = b.BuildSummary()
        b.load_bls_bundle(bls.find_bundle(FIXTURES), summary)
        self.assertEqual(summary.dropped_no_energy["bls"], 1)
        self.assertEqual(summary.dropped_blank_name["bls"], 1)


if __name__ == "__main__":
    unittest.main()
