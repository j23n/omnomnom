import unittest

from fooddb import mapping
from fooddb.errors import MappingError

GOOD_UNITS = {1008: "KCAL", 2047: "KCAL", 2048: "KCAL", 1003: "G", 1005: "G", 1004: "G",
              1258: "G", 1079: "G", 2033: "G", 2000: "G", 1063: "G", 1093: "MG"}


class MappingTests(unittest.TestCase):
    def test_primary_wins(self) -> None:
        values = mapping.map_nutrients({1008: 52.0, 2047: 50.0, 1003: 1.0})
        self.assertEqual(values["kcal_100g"], 52.0)
        self.assertEqual(values["protein_100g"], 1.0)

    def test_fallback_when_primary_absent(self) -> None:
        values = mapping.map_nutrients({2047: 89.0, 2033: 2.4, 1063: 3.0})
        self.assertEqual(values["kcal_100g"], 89.0)
        self.assertEqual(values["fiber_100g"], 2.4)
        self.assertEqual(values["sugar_100g"], 3.0)

    def test_third_fallback(self) -> None:
        self.assertEqual(mapping.map_nutrients({2048: 61.0})["kcal_100g"], 61.0)

    def test_missing_is_none_not_zero(self) -> None:
        values = mapping.map_nutrients({1008: 10.0})
        for column in mapping.NUTRIENT_COLUMNS:
            if column != "kcal_100g":
                self.assertIsNone(values[column], column)

    def test_validate_accepts_good_units_and_missing_fallbacks(self) -> None:
        units = dict(GOOD_UNITS)
        del units[2047], units[2048], units[2033], units[1063]
        mapping.validate_units(units)  # no raise

    def test_validate_accepts_lowercase_units(self) -> None:
        mapping.validate_units({k: v.lower() for k, v in GOOD_UNITS.items()})

    def test_unit_mismatch_raises(self) -> None:
        units = {**GOOD_UNITS, 1093: "G"}
        with self.assertRaisesRegex(MappingError, "1093"):
            mapping.validate_units(units)

    def test_fallback_unit_mismatch_raises(self) -> None:
        units = {**GOOD_UNITS, 2047: "KJ"}
        with self.assertRaisesRegex(MappingError, "2047"):
            mapping.validate_units(units, "fdc_foundation")

    def test_missing_primary_raises(self) -> None:
        units = dict(GOOD_UNITS)
        del units[1258]
        with self.assertRaisesRegex(MappingError, "1258"):
            mapping.validate_units(units)


if __name__ == "__main__":
    unittest.main()
