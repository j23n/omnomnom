from __future__ import annotations

import shutil
import tempfile
import unittest
from pathlib import Path

from fooddb import build as b
from fooddb import ciqual
from fooddb.errors import InputError, MappingError

FIXTURES = Path(__file__).parent / "fixtures" / "ciqual"


class LocateTests(unittest.TestCase):
    def test_finds_every_role(self) -> None:
        files = ciqual.locate_files(FIXTURES)
        self.assertEqual(files["foods"].name, "alim.xml")
        self.assertEqual(files["groups"].name, "alim_grp.xml")
        self.assertEqual(files["compo"].name, "compo.xml")
        self.assertEqual(files["const"].name, "const.xml")

    def test_missing_file_says_which(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            shutil.copy(FIXTURES / "alim.xml", root)
            with self.assertRaises(InputError) as caught:
                ciqual.locate_files(root)
            message = str(caught.exception)
            self.assertIn("compo", message)
            self.assertIn("const", message)
            self.assertNotIn("foods (alim*.xml)", message)

    def test_version_comes_from_the_folder_name(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp) / "Table Ciqual 2025 XML"
            shutil.copytree(FIXTURES, root)
            self.assertEqual(ciqual.find_bundle(root).version, "2025")


class ValueTests(unittest.TestCase):
    def test_markers(self) -> None:
        self.assertEqual(ciqual.parse_value("12,5", "x"), ciqual.CiqualValue(12.5, False))
        self.assertEqual(ciqual.parse_value("traces", "x"), ciqual.CiqualValue(0.0, True))
        self.assertEqual(ciqual.parse_value("< 0,5", "x"), ciqual.CiqualValue(0.0, True))
        self.assertEqual(ciqual.parse_value("-", "x"), ciqual.CiqualValue(None, False))
        self.assertEqual(ciqual.parse_value("", "x"), ciqual.CiqualValue(None, False))

    def test_unknown_text_fails_with_context(self) -> None:
        with self.assertRaises(InputError) as caught:
            ciqual.parse_value("beaucoup", "compo.xml: food 1, constituent 328")
        self.assertIn("constituent 328", str(caught.exception))

    def test_negative_fails(self) -> None:
        with self.assertRaises(InputError):
            ciqual.parse_value("-3,2", "x")


class UnitTests(unittest.TestCase):
    def test_units_read_from_the_constituent_names(self) -> None:
        units = ciqual.read_constituent_units(FIXTURES / "const.xml")
        self.assertEqual(units[328], "kcal")
        self.assertEqual(units[10110], "mg")
        self.assertEqual(units[327], "kj")
        ciqual.validate_units(units)

    def test_changed_unit_fails(self) -> None:
        units = dict(ciqual.read_constituent_units(FIXTURES / "const.xml"))
        units[10110] = "g"
        with self.assertRaises(MappingError) as caught:
            ciqual.validate_units(units)
        self.assertIn("sodium_mg_100g", str(caught.exception))

    def test_missing_constituent_fails(self) -> None:
        units = dict(ciqual.read_constituent_units(FIXTURES / "const.xml"))
        del units[328]
        with self.assertRaises(MappingError):
            ciqual.validate_units(units)


class NameTests(unittest.TestCase):
    def food(self, **overrides: str) -> ciqual.CiqualFood:
        fields = {
            "code": "1", "name_fr": "Pomme, crue", "name_eng": "Apple, raw",
            "index_fr": "Pomme crue", "index_eng": "Apple raw",
            "group_code": "13", "subgroup_code": "1302",
        }
        fields.update(overrides)
        return ciqual.CiqualFood(**fields)

    def test_english_shown_french_indexed(self) -> None:
        name, locale, others = ciqual.names_for(self.food(), prefer_english=True)
        self.assertEqual((name, locale), ("Apple, raw", "en"))
        self.assertEqual(others, ["Pomme, crue", "Apple raw", "Pomme crue"])

    def test_falls_back_to_french(self) -> None:
        name, locale, others = ciqual.names_for(self.food(name_eng=""), prefer_english=True)
        self.assertEqual((name, locale), ("Pomme, crue", "fr"))
        self.assertNotIn("", others)


class LoadTests(unittest.TestCase):
    def rows(self) -> list[b.FoodRow]:
        bundle = ciqual.find_bundle(FIXTURES)
        return b.load_ciqual_bundle(bundle, b.BuildSummary())

    def test_reads_values_names_and_category(self) -> None:
        rows = {row.source_ref: row for row in self.rows()}
        self.assertEqual(sorted(rows), ["13001", "20001"])
        apple = rows["13001"]
        self.assertEqual(apple.name, "Apple, pulp and skin, raw")
        self.assertEqual(apple.name_locale, "en")
        self.assertEqual(apple.category, "fruits")
        self.assertEqual(apple.nutrients["kcal_100g"], 54.3)
        self.assertEqual(apple.nutrients["sodium_mg_100g"], 1.2)
        # The French name is read and then dropped: the app is English-only, so
        # "pomme" finds nothing. See `build.NAME_LOCALE_SHIPPED`.
        self.assertEqual(apple.alt_names, ())

    def test_trace_marks_the_food_estimated_and_stores_zero(self) -> None:
        apple = next(row for row in self.rows() if row.source_ref == "13001")
        self.assertEqual(apple.nutrients["satfat_100g"], 0.0)
        self.assertEqual(apple.is_estimated, 1)

    def test_unmeasured_stays_null(self) -> None:
        bread = next(row for row in self.rows() if row.source_ref == "20001")
        self.assertIsNone(bread.nutrients["fiber_100g"])
        self.assertIsNone(bread.nutrients["satfat_100g"])
        self.assertEqual(bread.nutrients["sugar_100g"], 0.0)

    def test_food_without_energy_and_without_a_name_are_dropped(self) -> None:
        summary = b.BuildSummary()
        b.load_ciqual_bundle(ciqual.find_bundle(FIXTURES), summary)
        self.assertEqual(summary.dropped_no_energy["ciqual"], 1)
        self.assertEqual(summary.dropped_blank_name["ciqual"], 1)

    def test_constituents_we_do_not_map_are_ignored(self) -> None:
        composition = ciqual.read_composition(FIXTURES / "compo.xml")
        self.assertNotIn(327, composition["13001"])


if __name__ == "__main__":
    unittest.main()
