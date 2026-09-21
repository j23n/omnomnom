import shutil
import tempfile
import unittest
from pathlib import Path

from fooddb import fdc
from fooddb.errors import InputError

FIXTURES = Path(__file__).parent / "fixtures" / "fdc"


def rewrite(path: Path, old: str, new: str) -> None:
    text = path.read_text()
    assert old in text, old
    path.write_text(text.replace(old, new))


class FixtureCopyTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp)
        self.fdc = self.tmp / "fdc"
        shutil.copytree(FIXTURES, self.fdc)
        self.foundation = self.fdc / "foundation"
        self.sr_legacy = self.fdc / "sr_legacy"

    def set_rice_energy(self, value: str, previous: str = "130") -> None:
        """Rewrite the SR Legacy rice (fdc_id 2002) energy amount, file line 4."""
        rewrite(
            self.sr_legacy / "food_nutrient.csv",
            f'"3","2002","1008","{previous}"', f'"3","2002","1008","{value}"',
        )


class DiscoveryTests(FixtureCopyTests):
    def test_finds_both_bundles_in_order(self) -> None:
        bundles = fdc.find_bundles(FIXTURES)
        self.assertEqual([x.source for x in bundles], [fdc.FOUNDATION, fdc.SR_LEGACY])
        self.assertEqual([x.version for x in bundles], ["unknown", "unknown"])

    def test_nested_bundle_dir_and_version(self) -> None:
        root = self.tmp / "nested" / "FoodData_Central_sr_legacy_food_csv_2018-04" / "inner"
        shutil.copytree(FIXTURES / "sr_legacy", root)
        bundles = fdc.find_bundles(root.parent)
        self.assertEqual([(x.source, x.version) for x in bundles], [(fdc.SR_LEGACY, "unknown")])
        bundles = fdc.find_bundles(self.tmp / "nested")
        self.assertEqual([(x.source, x.version) for x in bundles], [(fdc.SR_LEGACY, "2018-04")])

    def test_version_from_path_ignores_stop_dir(self) -> None:
        self.assertEqual(fdc.version_from_path(Path("a/x_2025-04-24/b"), Path("a")), "2025-04-24")
        self.assertEqual(fdc.version_from_path(Path("a_2025-01/b"), Path("a_2025-01")), "unknown")
        self.assertEqual(fdc.version_from_path(Path("a_2025-01"), Path("a_2025-01")), "unknown")

    def test_missing_dir_raises(self) -> None:
        with self.assertRaises(InputError):
            fdc.find_bundles(FIXTURES / "nope")

    def test_missing_required_file_raises(self) -> None:
        (self.sr_legacy / "measure_unit.csv").unlink()
        with self.assertRaisesRegex(InputError, "measure_unit.csv"):
            fdc.find_bundles(self.fdc)


class ReaderErrorTests(FixtureCopyTests):
    def test_malformed_number_reports_file_and_line(self) -> None:
        self.set_rice_energy("abc")
        with self.assertRaisesRegex(InputError, r"food_nutrient\.csv:4: amount: 'abc'"):
            fdc.read_food_nutrients(self.sr_legacy)

    def test_negative_amount_clamped_to_zero_and_warned(self) -> None:
        self.set_rice_energy("-0.47505")
        with self.assertLogs("fooddb.fdc", level="WARNING") as logs:
            amounts = fdc.read_food_nutrients(self.sr_legacy)
        self.assertEqual(amounts[2002][1008], 0.0)
        self.assertEqual(len(logs.output), 1)
        self.assertIn("1 negative amounts clamped to 0", logs.output[0])

    def test_non_finite_amount_rejected(self) -> None:
        self.set_rice_energy("inf")
        with self.assertRaisesRegex(InputError, "not finite"):
            fdc.read_food_nutrients(self.sr_legacy)

    def test_missing_header_column_rejected(self) -> None:
        rewrite(self.sr_legacy / "food.csv", '"description"', '"desc"')
        with self.assertRaisesRegex(InputError, "missing columns description"):
            fdc.read_foods(self.sr_legacy)

    def test_empty_file_rejected(self) -> None:
        (self.sr_legacy / "food.csv").write_text("")
        with self.assertRaisesRegex(InputError, "no header row"):
            fdc.read_foods(self.sr_legacy)

    def test_bad_id_rejected(self) -> None:
        rewrite(self.sr_legacy / "food.csv", '"2002","sr_legacy_food"', '"2002.0","sr_legacy_food"')
        with self.assertRaisesRegex(InputError, r"food\.csv:3: fdc_id: '2002.0' is not an integer"):
            fdc.read_foods(self.sr_legacy)

    def test_duplicate_fdc_id_rejected(self) -> None:
        rewrite(self.sr_legacy / "food.csv", '"2003","sr_legacy_food"', '"2002","sr_legacy_food"')
        with self.assertRaisesRegex(InputError, "duplicate fdc_id 2002"):
            fdc.read_foods(self.sr_legacy)

    def test_short_row_yields_blank_description(self) -> None:
        with (self.sr_legacy / "food.csv").open("a") as handle:
            handle.write('"2009","sr_legacy_food"\n')
        foods = {food.fdc_id: food for food in fdc.read_foods(self.sr_legacy)}
        self.assertEqual(foods[2009].description, "")
        self.assertIsNone(foods[2009].food_category_id)

    def test_invalid_utf8_rejected(self) -> None:
        (self.sr_legacy / "food.csv").write_bytes(b'"fdc_id","description"\n"1","\xff"\n')
        with self.assertRaisesRegex(InputError, "not valid UTF-8"):
            fdc.read_foods(self.sr_legacy)


class ReaderWarningTests(FixtureCopyTests):
    def test_duplicate_nutrient_rows_keep_first_and_warn(self) -> None:
        rewrite(
            self.sr_legacy / "food_nutrient.csv",
            '"4","2002","1003","2.69"', '"4","2002","1008","999"',
        )
        with self.assertLogs("fooddb.fdc", level="WARNING") as logs:
            nutrients = fdc.read_food_nutrients(self.sr_legacy)
        self.assertEqual(nutrients[2002][1008], 130.0)
        self.assertNotIn(1003, nutrients[2002])
        self.assertEqual(len(logs.output), 1)
        self.assertIn("1 duplicate (fdc_id, nutrient_id)", logs.output[0])

    def test_data_type_mismatch_warns(self) -> None:
        rewrite(self.sr_legacy / "food.csv", '"2002","sr_legacy_food"', '"2002","branded_food"')
        with self.assertLogs("fooddb.fdc", level="WARNING") as logs:
            foods = fdc.read_foods(self.sr_legacy, "sr_legacy_food")
        self.assertEqual(len(foods), 4)
        self.assertIn("1 rows whose data_type is not 'sr_legacy_food'", logs.output[0])


if __name__ == "__main__":
    unittest.main()
