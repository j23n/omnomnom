from __future__ import annotations

import shutil
import tempfile
import unittest
from collections.abc import Mapping
from pathlib import Path

from fooddb import bls
from fooddb import build as b
from fooddb.errors import InputError, MappingError
from fooddb.table import Table, read_table

FIXTURES = Path(__file__).parent / "fixtures" / "bls"
DATA = FIXTURES / "bls_4.0_daten.tsv"


def table_from(text: str, name: str = "bls_daten.tsv") -> tuple[Path, Table]:
    directory = Path(tempfile.mkdtemp())
    path = directory / name
    path.write_text(text, encoding="utf-8")
    return path, read_table(path)


def header(*columns: str) -> str:
    return "\t".join(columns)


def number(values: Mapping[str, float | None], column: str) -> float:
    """One value that must be known, so a comparison has something to compare."""
    found = values[column]
    if found is None:
        raise AssertionError(f"{column} is unknown")
    return found


MINIMAL = header(
    "BLS Code", "Lebensmittelbezeichnung",
    "ENERCC Energie (Kilokalorien) [kcal/100g]", "PROT625 Protein (Nx6,25) [g/100g]",
    "FAT Fett [g/100g]", "CHO Kohlenhydrate, verfügbar [g/100g]",
)


class ColumnTests(unittest.TestCase):
    def test_the_published_layout(self) -> None:
        columns = bls.resolve_columns(read_table(DATA))
        self.assertEqual(columns.key, "BLS Code")
        self.assertEqual(columns.german_name, "Lebensmittelbezeichnung")
        self.assertEqual(columns.english_name, "Food name")
        self.assertIsNone(columns.category)
        self.assertEqual(
            columns.nutrients["sugar_100g"].header,
            "SUGAR Zucker (Mono- und Disaccharide), gesamt [g/100g]",
        )

    def test_a_components_provenance_column_is_not_its_value(self) -> None:
        # "NA Datenherkunft" carries the same code but states no unit.
        _, table = table_from(
            header(*MINIMAL.split("\t"), "NA Datenherkunft", "NA Natrium [mg/100g]")
            + "\nF1\tApfel\t54\t0,3\t0,4\t11,4\tAnalyse\t1\n"
        )
        columns = bls.resolve_columns(table)
        self.assertEqual(columns.nutrients["sodium_mg_100g"].header, "NA Natrium [mg/100g]")

    def test_missing_required_component_lists_what_is_there(self) -> None:
        _, table = table_from(
            header("BLS Code", "Lebensmittelbezeichnung",
                   "ENERCC Energie (Kilokalorien) [kcal/100g]", "FAT Fett [g/100g]")
            + "\nF1\tApfel\t54\t0,4\n"
        )
        with self.assertRaises(MappingError) as caught:
            bls.resolve_columns(table)
        message = str(caught.exception)
        self.assertIn("protein_100g", message)
        self.assertIn("ENERCC", message)

    def test_missing_name_column_says_so(self) -> None:
        _, table = table_from(
            header("BLS Code", "ENERCC Energie (Kilokalorien) [kcal/100g]",
                   "PROT625 Protein (Nx6,25) [g/100g]", "FAT Fett [g/100g]",
                   "CHO Kohlenhydrate, verfügbar [g/100g]")
            + "\nF1\t54\t0,3\t0,4\t11,4\n"
        )
        with self.assertRaises(InputError) as caught:
            bls.resolve_columns(table)
        self.assertIn("food name", str(caught.exception))

    def test_optional_components_may_be_absent(self) -> None:
        _, table = table_from(MINIMAL + "\nF1\tApfel\t54\t0,3\t0,4\t11,4\n")
        columns = bls.resolve_columns(table)
        self.assertNotIn("sodium_mg_100g", columns.nutrients)
        self.assertNotIn("fiber_100g", columns.nutrients)


class UnitTests(unittest.TestCase):
    def test_units_are_read_from_the_headers_not_guessed(self) -> None:
        columns = bls.resolve_columns(read_table(DATA))
        self.assertEqual(columns.nutrients["protein_100g"].published_unit, "g")
        self.assertEqual(columns.nutrients["protein_100g"].factor, 1.0)
        self.assertEqual(columns.nutrients["sodium_mg_100g"].factor, 1.0)

    def test_a_component_published_in_another_mass_is_converted(self) -> None:
        _, table = table_from(
            header(*MINIMAL.split("\t"), "NA Natrium [g/100g]")
            + "\nF1\tApfel\t54\t0,3\t0,4\t11,4\t0,011\n"
        )
        columns = bls.resolve_columns(table)
        self.assertEqual(columns.nutrients["sodium_mg_100g"].factor, 1000.0)
        rows, _, _ = bls.read(table.path)
        self.assertAlmostEqual(number(rows[0].values, "sodium_mg_100g"), 11.0)

    def test_milligrams_where_grams_are_wanted_are_converted(self) -> None:
        _, table = table_from(
            header("BLS Code", "Lebensmittelbezeichnung",
                   "ENERCC Energie (Kilokalorien) [kcal/100g]",
                   "PROT625 Protein (Nx6,25) [mg/100g]", "FAT Fett [g/100g]",
                   "CHO Kohlenhydrate, verfügbar [g/100g]")
            + "\nF1\tApfel\t54\t300\t0,4\t11,4\n"
        )
        rows, _, _ = bls.read(table.path)
        self.assertAlmostEqual(number(rows[0].values, "protein_100g"), 0.3)

    def test_kilojoules_where_kilocalories_are_wanted_are_refused(self) -> None:
        _, table = table_from(
            header("BLS Code", "Lebensmittelbezeichnung",
                   "ENERCC Energie (Kilojoule) [kJ/100g]", "PROT625 Protein (Nx6,25) [g/100g]",
                   "FAT Fett [g/100g]", "CHO Kohlenhydrate, verfügbar [g/100g]")
            + "\nF1\tApfel\t226\t0,3\t0,4\t11,4\n"
        )
        with self.assertRaises(MappingError) as caught:
            bls.resolve_columns(table)
        self.assertIn("kilocalories", str(caught.exception))

    def test_a_unit_we_cannot_convert_is_refused(self) -> None:
        _, table = table_from(
            header(*MINIMAL.split("\t"), "NA Natrium [IE/100g]")
            + "\nF1\tApfel\t54\t0,3\t0,4\t11,4\t1\n"
        )
        with self.assertRaises(MappingError) as caught:
            bls.resolve_columns(table)
        self.assertIn("sodium_mg_100g", str(caught.exception))

    def test_both_micro_signs_are_the_same_unit(self) -> None:
        self.assertEqual(bls.normalise_unit("µg"), bls.normalise_unit("μg"))


class RowTests(unittest.TestCase):
    def rows(self) -> list[bls.BlsRow]:
        rows, _, _ = bls.read(DATA)
        return rows

    def test_values_come_through_with_their_decimal_commas(self) -> None:
        oats = next(row for row in self.rows() if row.key == "C131000")
        self.assertAlmostEqual(number(oats.values, "kcal_100g"), 345.0)
        self.assertAlmostEqual(number(oats.values, "protein_100g"), 12.6)
        self.assertAlmostEqual(number(oats.values, "carb_100g"), 55.7)
        self.assertAlmostEqual(number(oats.values, "sodium_mg_100g"), 8.0)

    def test_not_determined_markers_read_as_unknown(self) -> None:
        marked = next(row for row in self.rows() if row.key == "D100000")
        self.assertIsNone(marked.values["protein_100g"])
        self.assertIsNone(marked.values["fat_100g"])
        self.assertIsNone(marked.values["fiber_100g"])
        self.assertAlmostEqual(number(marked.values, "carb_100g"), 20.0)

    def test_a_value_that_is_not_a_number_is_counted_not_fatal(self) -> None:
        odd = next(row for row in self.rows() if row.key == "N100000")
        self.assertIsNone(odd.values["sodium_mg_100g"])
        self.assertAlmostEqual(number(odd.values, "kcal_100g"), 70.0)

    def test_a_row_without_a_name_is_dropped(self) -> None:
        _, blank, _ = bls.read(DATA)
        self.assertEqual(blank, 1)
        self.assertNotIn("X999999", [row.key for row in self.rows()])

    def test_duplicate_code_fails_with_the_line(self) -> None:
        path, _ = table_from(
            MINIMAL + "\nF1\tApfel\t54\t0,3\t0,4\t11,4\nF1\tApfel zwei\t54\t0,3\t0,4\t11,4\n"
        )
        with self.assertRaises(InputError) as caught:
            bls.read(path)
        self.assertIn(":3", str(caught.exception))

    def test_version_from_the_file_name(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp) / "BLS_4_0_2025_DE"
            root.mkdir()
            shutil.copy(DATA, root / "BLS_4_0_Daten_2025_DE.tsv")
            self.assertEqual(bls.find_bundle(root).version, "4.0")

    def test_the_data_table_is_preferred_over_the_component_legend(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            shutil.copy(DATA, root / "BLS_4_0_Daten_2025_DE.tsv")
            (root / "BLS_4_0_Components_DE_EN.tsv").write_text("a\tb\n1\t2\n", encoding="utf-8")
            self.assertEqual(bls.find_bundle(root).root.name, "BLS_4_0_Daten_2025_DE.tsv")


class NameTests(unittest.TestCase):
    def test_english_shown_german_indexed(self) -> None:
        rows, _, _ = bls.read(DATA)
        oats = next(row for row in rows if row.key == "C131000")
        self.assertEqual(
            bls.names_for(oats),
            ("Oat whole grain, raw", "en", ["Hafer ganzes Korn, roh"]),
        )

    def test_german_alone_when_there_is_no_english_name(self) -> None:
        rows, _, _ = bls.read(DATA)
        marked = next(row for row in rows if row.key == "D100000")
        name, locale, others = bls.names_for(marked)
        self.assertEqual((name, locale), ("Sonderfall mit Markern", "de"))
        self.assertEqual(list(others), [])


class LoadTests(unittest.TestCase):
    def rows(self) -> list[b.FoodRow]:
        return b.load_bls_bundle(bls.find_bundle(FIXTURES), b.BuildSummary())

    def test_rows_carry_both_names_and_the_english_one_is_shown(self) -> None:
        oats = next(row for row in self.rows() if row.source_ref == "C131000")
        self.assertEqual(oats.name, "Oat whole grain, raw")
        self.assertEqual(oats.name_locale, "en")
        self.assertEqual(oats.alt_names, ("Hafer ganzes Korn, roh",))
        self.assertIsNone(oats.category)

    def test_rows_without_energy_or_a_name_are_dropped(self) -> None:
        summary = b.BuildSummary()
        b.load_bls_bundle(bls.find_bundle(FIXTURES), summary)
        self.assertEqual(summary.dropped_no_energy["bls"], 1)
        self.assertEqual(summary.dropped_blank_name["bls"], 1)


if __name__ == "__main__":
    unittest.main()
