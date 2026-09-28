"""Building from more than one source, end to end."""

from __future__ import annotations

import json
import sqlite3
import tempfile
import unittest
from pathlib import Path

from fooddb.__main__ import main

FIXTURES = Path(__file__).parent / "fixtures"


class MultiSourceBuildTests(unittest.TestCase):
    def setUp(self) -> None:
        self.dir = Path(tempfile.mkdtemp())
        self.addCleanup(lambda: __import__("shutil").rmtree(self.dir, ignore_errors=True))
        self.out = self.dir / "foods.sqlite"
        self.sources = self.dir / "sources.json"

    def build(self, *extra: str) -> int:
        return main([
            "build",
            "--ciqual", str(FIXTURES / "ciqual"),
            "--bls", str(FIXTURES / "bls"),
            "--out", str(self.out),
            "--sources-out", str(self.sources),
            *extra,
        ])

    def test_build(self) -> None:
        self.assertEqual(self.build(), 0)
        conn = sqlite3.connect(self.out)
        self.addCleanup(conn.close)

        counts = dict(conn.execute("SELECT source, count(*) FROM foods GROUP BY source").fetchall())
        self.assertEqual(counts, {"ciqual": 2, "bls": 5})

        # Both sources publish English names beside their own, so a row reads in
        # English wherever one exists and in the source's language where it does not.
        locales = {
            (source, locale)
            for source, locale in conn.execute("SELECT DISTINCT source, name_locale FROM foods")
        }
        self.assertEqual(locales, {("ciqual", "en"), ("bls", "en"), ("bls", "de")})

        meta = dict(conn.execute("SELECT key, value FROM meta").fetchall())
        self.assertEqual(meta["schema_version"], "2")
        self.assertEqual(meta["food_count"], "7")
        self.assertEqual(meta["ciqual_version"], "unknown")
        self.assertEqual(meta["bls_version"], "4.0")

    def test_a_food_is_found_by_any_of_its_names(self) -> None:
        self.assertEqual(self.build(), 0)
        conn = sqlite3.connect(self.out)
        self.addCleanup(conn.close)

        def search(text: str) -> list[str]:
            rows = conn.execute(
                "SELECT f.name FROM foods_fts JOIN foods f ON f.id = foods_fts.rowid "
                "WHERE foods_fts MATCH ? ORDER BY f.name", (text,)
            ).fetchall()
            return [row[0] for row in rows]

        self.assertEqual(search("pomme"), ["Apple, pulp and skin, raw"])
        self.assertEqual(search("apfel"), ["Apple raw"])
        self.assertEqual(search("hafer"), ["Oat whole grain, raw"])
        self.assertEqual(search("bread"), ["Sandwich bread"])
        self.assertEqual(search("apple"), ["Apple raw", "Apple, pulp and skin, raw"])

    def test_the_manifest_names_only_what_shipped(self) -> None:
        self.assertEqual(self.build(), 0)
        manifest = json.loads(self.sources.read_text())
        self.assertEqual([source["id"] for source in manifest], ["ciqual", "bls"])
        bls_entry = manifest[1]
        self.assertEqual(bls_entry["licence"], "CC BY 4.0")
        self.assertIn("Max Rubner-Institut", bls_entry["publisher"])
        self.assertIn("Version 4.0", bls_entry["citation"])
        self.assertEqual(bls_entry["datasets"][0]["version"], "4.0")

    def test_naming_no_source_fails(self) -> None:
        self.assertEqual(main(["build", "--out", str(self.out)]), 1)

    def test_fdc_can_still_be_added(self) -> None:
        self.assertEqual(self.build("--fdc", str(FIXTURES / "fdc")), 0)
        conn = sqlite3.connect(self.out)
        self.addCleanup(conn.close)
        sources = {row[0] for row in conn.execute("SELECT DISTINCT source FROM foods")}
        self.assertEqual(sources, {"ciqual", "bls", "fdc_foundation", "fdc_sr_legacy"})
        manifest = json.loads(self.sources.read_text())
        self.assertEqual([source["id"] for source in manifest], ["ciqual", "bls", "fdc"])


class InspectTests(unittest.TestCase):
    def test_reports_a_ciqual_export(self) -> None:
        self.assertEqual(main(["inspect", str(FIXTURES / "ciqual")]), 0)

    def test_reports_a_bls_table(self) -> None:
        self.assertEqual(main(["inspect", str(FIXTURES / "bls")]), 0)

    def test_missing_path_fails(self) -> None:
        self.assertEqual(main(["inspect", str(FIXTURES / "nope")]), 1)


if __name__ == "__main__":
    unittest.main()
