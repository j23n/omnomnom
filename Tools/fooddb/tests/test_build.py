import contextlib
import json
import os
import shutil
import sqlite3
import stat
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from fooddb import build as b
from fooddb import output
from fooddb.__main__ import main
from fooddb.errors import InputError
from fooddb.fdc import FOUNDATION, SR_LEGACY, find_bundles
from fooddb.portions import PortionRow
from tests.test_fdc import FixtureCopyTests, rewrite

FIXTURES = Path(__file__).parent / "fixtures" / "fdc"


def food(name: str, source: str, ref: str = "1") -> b.FoodRow:
    return b.FoodRow(
        name=name, key=b.normalise_description(name), source=source, source_ref=ref,
        category=None, nutrients={"kcal_100g": 1.0}, portions=(PortionRow("1 cup", 100.0, 1),),
    )


class NormaliseTests(unittest.TestCase):
    def test_normalise(self) -> None:
        self.assertEqual(b.normalise_description("  Chicken,  breast. "), "chicken, breast")
        self.assertEqual(b.collapse_whitespace("Bananas,  raw"), "Bananas, raw")


class DedupTests(unittest.TestCase):
    def test_foundation_wins(self) -> None:
        summary = b.BuildSummary()
        rows = b.dedup([
            food("Chicken, breast", FOUNDATION, "1"),
            food("Chicken, breast.", SR_LEGACY, "2"),
            food("Rice", SR_LEGACY, "3"),
        ], summary)
        self.assertEqual(
            [(r.source, r.source_ref) for r in rows], [(FOUNDATION, "1"), (SR_LEGACY, "3")]
        )
        self.assertEqual(summary.dropped_duplicates, 1)


class PopularityTests(unittest.TestCase):
    def test_scores_and_unmatched(self) -> None:
        summary = b.BuildSummary()
        rows = b.apply_popularity(
            [food("Apples, raw", FOUNDATION), food("Kale", FOUNDATION)],
            ["apples, raw", "bananas, raw"], summary,
        )
        self.assertEqual([r.popularity for r in rows], [100, 0])
        self.assertEqual(summary.unmatched_popular, ["bananas, raw"])
        self.assertEqual(b.popularity_scores(["x"] * 150)["x"], 1)

    def test_read_popular_skips_comments_and_warns_on_duplicates(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "p.txt"
            path.write_text("# c\nApples, raw. # trailing\n\nbananas\nAPPLES, RAW\n")
            with self.assertLogs("fooddb.build", level="WARNING") as logs:
                self.assertEqual(b.read_popular(path), ["apples, raw", "bananas"])
            self.assertIn("p.txt:5: duplicate popular entry", logs.output[0])
            with self.assertRaisesRegex(InputError, "cannot read popular list"):
                b.read_popular(Path(tmp) / "missing.txt")

    def test_curated_file_has_no_duplicates(self) -> None:
        with self.assertNoLogs("fooddb.build", level="WARNING"):
            entries = b.read_popular(b.DEFAULT_POPULAR)
        self.assertGreater(len(entries), 30)


class PlausibilityTests(unittest.TestCase):
    def test_warns_but_keeps(self) -> None:
        values: dict[str, float | None] = {"kcal_100g": 950.0, "fat_100g": 100.0}
        with self.assertLogs("fooddb.build", level="WARNING") as logs:
            b.check_plausible(values, FOUNDATION, "7")
        self.assertEqual(len(logs.output), 1)
        self.assertIn("kcal_100g=950.0", logs.output[0])
        with self.assertNoLogs("fooddb.build", level="WARNING"):
            b.check_plausible({"protein_100g": 100.0, "sodium_mg_100g": 100000.0}, FOUNDATION, "8")


class LoadBundleTests(FixtureCopyTests):
    def test_blank_description_dropped_and_counted(self) -> None:
        rewrite(self.sr_legacy / "food.csv", '"Egg, whole, raw, fresh"', '"   "')
        summary = b.BuildSummary()
        with self.assertLogs("fooddb.build", level="WARNING") as logs:
            rows = b.load_bundle(find_bundles(self.fdc)[1], summary)
        self.assertEqual(len(rows), 3)
        self.assertEqual(summary.dropped_blank_name, {SR_LEGACY: 1})
        self.assertIn("2004: blank description", logs.output[0])
        self.assertIn("1 dropped (blank name)", summary.format())

    def test_bundle_without_usable_foods_raises(self) -> None:
        (self.sr_legacy / "food.csv").write_text('"fdc_id","data_type","description"\n')
        with self.assertRaisesRegex(InputError, "yielded no usable foods"):
            b.load_bundle(find_bundles(self.fdc)[1], b.BuildSummary())

    def test_implausible_value_warns_in_context(self) -> None:
        self.set_rice_energy("950")
        with self.assertLogs("fooddb.build", level="WARNING") as logs:
            rows = b.load_bundle(find_bundles(self.fdc)[1], b.BuildSummary())
        self.assertEqual(len(rows), 4)
        self.assertIn("fdc_sr_legacy 2002: implausible kcal_100g=950.0", logs.output[0])


class OutputTests(unittest.TestCase):
    def test_build_time_honours_source_date_epoch(self) -> None:
        with mock.patch.dict(os.environ, {"SOURCE_DATE_EPOCH": "1700000000"}):
            self.assertEqual(output.build_time().isoformat(), "2023-11-14T22:13:20+00:00")
        with mock.patch.dict(os.environ, {"SOURCE_DATE_EPOCH": "soon"}):
            with self.assertRaisesRegex(InputError, "SOURCE_DATE_EPOCH"):
                output.build_time()

    def test_citation_year(self) -> None:
        versions = {FOUNDATION: "2025-04-24", SR_LEGACY: "2018-04"}
        self.assertEqual(output.citation_year(versions), 2025)
        with mock.patch.dict(os.environ, {"SOURCE_DATE_EPOCH": "1700000000"}):
            self.assertEqual(output.citation_year({FOUNDATION: "unknown"}), 2023)
        manifest = output.sources_manifest({SR_LEGACY: "2018-04"})
        self.assertIn("FoodData Central, 2018.", str(manifest[0]["citation"]))


class EndToEndTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp)
        self.out = self.tmp / "foods.sqlite"
        self.sources = self.tmp / "sources.json"

    def run_build(self, fdc: Path = FIXTURES, out: Path | None = None) -> int:
        return main([
            "build", "--fdc", str(fdc), "--out", str(out or self.out),
            "--sources-out", str(self.sources),
        ])

    def connect(self) -> sqlite3.Connection:
        conn = sqlite3.connect(self.out)
        self.addCleanup(conn.close)
        return conn

    def counts(self) -> dict[str, int]:
        with contextlib.closing(sqlite3.connect(self.out)) as conn:
            foods = conn.execute("SELECT COUNT(*) FROM foods").fetchone()[0]
            portions = conn.execute("SELECT COUNT(*) FROM portions").fetchone()[0]
        return {"foods": int(foods), "portions": int(portions)}

    def test_build(self) -> None:
        self.assertEqual(self.run_build(), 0)
        self.assertEqual(self.counts(), {"foods": 7, "portions": 10})
        conn = self.connect()
        names = conn.execute("SELECT name FROM sqlite_master WHERE type IN ('table','index')")
        tables = {r[0] for r in names}
        expected = {"meta", "foods", "foods_fts", "portions", "portions_food", "foods_source_ref"}
        self.assertTrue(expected <= tables)
        self.assertEqual(conn.execute("PRAGMA journal_mode").fetchone()[0], "delete")

        # unicode61 does not stem, so type-ahead queries use a prefix; an exact token also matches.
        def search(term: str) -> list[tuple[str]]:
            query = "SELECT name FROM foods_fts WHERE foods_fts MATCH ?"
            return sorted(conn.execute(query, (term,)).fetchall())

        apple = [("Apples, raw, with skin",)]
        self.assertEqual(search("apple*"), apple)
        self.assertEqual(search("apples"), apple)
        self.assertEqual(
            search("raw"),
            [("Apples, raw, with skin",), ("Bananas, raw",), ("Egg, whole, raw, fresh",)],
        )
        row = conn.execute(
            "SELECT source, source_ref, category, kcal_100g, fiber_100g, popularity "
            "FROM foods WHERE name='Apples, raw, with skin'"
        ).fetchone()
        self.assertEqual(row, (FOUNDATION, "1001", "Fruits and Fruit Juices", 52.0, 2.4, 100))
        def food(ref: str, columns: str) -> tuple[object, ...] | None:
            row = conn.execute(f"SELECT {columns} FROM foods WHERE source_ref=?", (ref,)).fetchone()
            return tuple(row) if row is not None else None

        self.assertEqual(food("1002", "name, kcal_100g, satfat_100g"), ("Bananas, raw", 89.0, None))
        self.assertEqual(food("1005", "kcal_100g"), (61.0,))
        self.assertIsNone(food("1003", "id"))
        chicken = conn.execute("SELECT source FROM foods WHERE name LIKE 'Chicken, broilers%'")
        self.assertEqual(chicken.fetchall(), [(FOUNDATION,)])
        self.assertEqual(food("2004", "category, is_estimated, name_locale"), (None, 0, "en"))

        def labels(ref: str) -> list[tuple[str, float, int]]:
            return conn.execute(
                "SELECT p.label, p.grams, p.seq FROM portions p JOIN foods f ON f.id=p.food_id "
                "WHERE f.source_ref=? ORDER BY p.seq", (ref,)
            ).fetchall()

        self.assertEqual(
            labels("1001"),
            [('1 medium (3" dia)', 182.0, 1), ("1 cup, chopped", 125.0, 2), ("0.5 cup", 62.5, 3)],
        )
        self.assertEqual(labels("1002"), [('1 medium (7" to 7-7/8" long)', 118.0, 1)])
        self.assertEqual(labels("1005"), [("1 tbsp", 15.3, 1), ("2.25 cup", 549.0, 2)])
        self.assertEqual(labels("2003"), [("1 slice", 43.0, 1)])
        self.assertEqual(labels("2004"), [("1 large", 50.0, 1)])

        meta = dict(conn.execute("SELECT key, value FROM meta").fetchall())
        self.assertEqual(meta["schema_version"], "1")
        self.assertEqual(meta["food_count"], "7")
        self.assertEqual(meta["portion_count"], "10")
        self.assertEqual(meta["fdc_foundation_version"], "unknown")
        self.assertEqual(meta["fdc_sr_legacy_version"], "unknown")
        self.assertRegex(meta["built_at"], r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\+00:00$")

        manifest = json.loads(self.sources.read_text())
        self.assertEqual(manifest[0]["id"], "fdc")
        self.assertEqual(manifest[0]["licence"], "CC0 1.0")
        self.assertEqual([d["id"] for d in manifest[0]["datasets"]], [FOUNDATION, SR_LEGACY])

    def test_outputs_have_normal_permissions(self) -> None:
        self.assertEqual(self.run_build(), 0)
        mask = os.umask(0)
        os.umask(mask)
        expected = 0o666 & ~mask
        for path in (self.out, self.sources):
            self.assertEqual(stat.S_IMODE(path.stat().st_mode), expected, path)

    def test_idempotent(self) -> None:
        self.assertEqual(self.run_build(), 0)
        first = self.counts()
        self.assertEqual(self.run_build(), 0)
        self.assertEqual(self.counts(), first)
        self.assertEqual([p.name for p in self.tmp.iterdir() if p.name.startswith(".")], [])

    def test_summary_with_custom_popular_list(self) -> None:
        popular = self.tmp / "popular.txt"
        popular.write_text("Apples, raw, with skin\nEgg, whole, raw, fresh\nNot a food\n")
        rows, summary = b.assemble(find_bundles(FIXTURES), popular)
        self.assertEqual(summary.kept, {FOUNDATION: 4, SR_LEGACY: 3})
        self.assertEqual(summary.dropped_no_energy, {FOUNDATION: 1, SR_LEGACY: 0})
        self.assertEqual(summary.dropped_blank_name, {FOUNDATION: 0, SR_LEGACY: 0})
        self.assertEqual(summary.dropped_duplicates, 1)
        self.assertEqual(summary.portions, 10)
        self.assertEqual(summary.unmatched_popular, ["not a food"])
        scored = {r.source_ref: r.popularity for r in rows if r.popularity}
        self.assertEqual(scored, {"1001": 100, "2004": 99})

    def test_unit_mismatch_exits_1(self) -> None:
        bad = self.tmp / "bad"
        shutil.copytree(FIXTURES, bad)
        rewrite(
            bad / "sr_legacy" / "nutrient.csv",
            '"1093","Sodium, Na","MG"',
            '"1093","Sodium, Na","G"',
        )
        self.assertEqual(self.run_build(bad), 1)
        self.assertFalse(self.out.exists())

    def test_malformed_csv_exits_1(self) -> None:
        bad = self.tmp / "bad"
        shutil.copytree(FIXTURES, bad)
        rewrite(
            bad / "foundation" / "food_nutrient.csv",
            '"1","1001","1008","52"',
            '"1","1001","1008","fifty"',
        )
        with self.assertLogs("fooddb", level="ERROR") as logs:
            self.assertEqual(self.run_build(bad), 1)
        self.assertIn("food_nutrient.csv:2: amount: 'fifty' is not a number", logs.output[0])

    def test_out_is_directory_exits_1(self) -> None:
        directory = self.tmp / "outdir"
        directory.mkdir()
        with self.assertLogs("fooddb", level="ERROR") as logs:
            self.assertEqual(self.run_build(out=directory), 1)
        self.assertIn("cannot write", logs.output[0])
        self.assertEqual([p.name for p in self.tmp.iterdir() if p.name.startswith(".")], [])

    def test_missing_popular_file_exits_1(self) -> None:
        self.assertEqual(main([
            "build", "--fdc", str(FIXTURES), "--out", str(self.out),
            "--sources-out", str(self.sources), "--popular", str(self.tmp / "nope.txt"),
        ]), 1)


if __name__ == "__main__":
    unittest.main()
