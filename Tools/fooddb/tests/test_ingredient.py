"""Rules for marking rows that are not a portion anyone eats.

The negative cases carry as much weight as the positive ones here. A false
positive demotes a food people really eat, and the obvious rule for catching raw
chicken also catches a raw apple, so `test_raw_plants_are_food` is the test this
module exists to keep passing.
"""

from __future__ import annotations

import sqlite3
import tempfile
import unittest
from pathlib import Path

from fooddb import build, ingredient, mapping, output
from fooddb.bundles import CIQUAL


class FoldTests(unittest.TestCase):
    def test_strips_case_diacritics_and_punctuation(self) -> None:
        self.assertEqual(ingredient.fold("Café soluble, 100%"), "cafe soluble 100")

    def test_collapses_whitespace(self) -> None:
        self.assertEqual(ingredient.fold("  Milk,\tdried \n skimmed "), "milk dried skimmed")

    def test_empty_text_folds_to_empty(self) -> None:
        self.assertEqual(ingredient.fold("   ,,,  "), "")


class NotAPortionTests(unittest.TestCase):
    """Rows that must be flagged, with the rule that should name them."""

    def assertFlagged(self, name: str, rule: str, alt: tuple[str, ...] = ()) -> None:
        why = ingredient.reasons(name, alt)
        self.assertTrue(ingredient.is_ingredient(name, alt), f"{name!r} not flagged")
        self.assertIn(rule, why, f"{name!r} flagged as {sorted(why)}, expected {rule}")

    def test_coffee_powder(self) -> None:
        # The case that justifies the whole mechanism: about 350 kcal per 100 g
        # against about 2 for the drink, so a cup logged here is out by a hundredfold.
        self.assertFlagged("Coffee, instant, powder", "powder")

    def test_soluble_coffee_in_french(self) -> None:
        self.assertFlagged("Café soluble", "instant")

    def test_dried_milk(self) -> None:
        self.assertFlagged("Milk, dried, skimmed", "dried-ingredient")

    def test_dried_egg(self) -> None:
        self.assertFlagged("Egg, whole, dried", "dried-ingredient")

    def test_raw_chicken(self) -> None:
        self.assertFlagged("Chicken, breast, raw", "raw-animal")

    def test_raw_fish(self) -> None:
        self.assertFlagged("Salmon, Atlantic, raw", "raw-animal")

    def test_cooking_oil(self) -> None:
        self.assertFlagged("Olive oil", "pure-fat")

    def test_lard(self) -> None:
        self.assertFlagged("Lard", "pure-fat")

    def test_salt(self) -> None:
        self.assertFlagged("Salt, table", "salt-or-spice")

    def test_ground_pepper(self) -> None:
        self.assertFlagged("Pepper, black, ground", "salt-or-spice")

    def test_baking_powder(self) -> None:
        self.assertFlagged("Baking powder", "powder")

    def test_yeast(self) -> None:
        self.assertFlagged("Yeast, baker's, active dry", "kitchen-base")

    def test_tomato_concentrate(self) -> None:
        self.assertFlagged("Tomato concentrate", "concentrate")

    def test_vanilla_extract(self) -> None:
        self.assertFlagged("Vanilla extract", "extract")


class GermanCompoundTests(unittest.TestCase):
    """BLS rows display German, and compounds have no word boundary to find."""

    def test_compound_powder_is_reached_by_fragment(self) -> None:
        self.assertTrue(ingredient.is_ingredient("Milchpulver, entrahmt"))
        self.assertIn("powder", ingredient.reasons("Milchpulver, entrahmt"))

    def test_compound_concentrate(self) -> None:
        self.assertTrue(ingredient.is_ingredient("Tomatenkonzentrat"))

    def test_english_alt_name_reaches_a_german_row(self) -> None:
        # BLS 4.0 publishes an English name beside the German one, which is what
        # keeps the English rules doing most of the work across both bundles.
        self.assertTrue(ingredient.is_ingredient("Rapsöl", ("Rapeseed oil",)))

    def test_raw_animal_in_german(self) -> None:
        self.assertTrue(ingredient.is_ingredient("Hähnchenbrust roh"))


class FoodTests(unittest.TestCase):
    """Rows that must not be flagged. A false positive demotes a real food."""

    def assertFood(self, name: str, alt: tuple[str, ...] = ()) -> None:
        why = ingredient.reasons(name, alt)
        self.assertFalse(why, f"{name!r} wrongly flagged as {sorted(why)}")

    def test_raw_plants_are_food(self) -> None:
        # The reason `raw` requires an animal protein beside it. Raw fruit and
        # vegetables are precisely what people eat.
        self.assertFood("Apple, pulp and skin, raw")
        self.assertFood("Carrots, raw")
        self.assertFood("Tomato, raw")
        self.assertFood("Spinach, raw")

    def test_dried_fruit_is_a_snack(self) -> None:
        # Drying a fruit does not change what a portion is, so `dried` alone
        # must not fire.
        self.assertFood("Apricots, dried")
        self.assertFood("Dates, dried")
        self.assertFood("Raisins")

    def test_cooked_animal_protein(self) -> None:
        self.assertFood("Chicken, breast, grilled")
        self.assertFood("Salmon, baked")

    def test_brewed_coffee(self) -> None:
        self.assertFood("Coffee, beverage, brewed")

    def test_oil_does_not_fire_inside_another_word(self) -> None:
        # Word-boundary matching, not substring: "boiled" holds "oil".
        self.assertFood("Potatoes, boiled")
        self.assertFood("Egg, boiled")

    def test_commodity_words_used_adjectivally(self) -> None:
        # Salted peanuts are food; the bare commodity is not.
        self.assertFood("Peanuts, salted")
        self.assertFood("Crisps, salted")
        self.assertFood("Bread, salted")

    def test_oats_and_oat_biscuits_are_both_food(self) -> None:
        # Neither is an ingredient form; telling them apart is the matcher's job
        # and the model's, not this flag's.
        self.assertFood("Oats, rolled")
        self.assertFood("Biscuits, oat")

    def test_blank_name(self) -> None:
        self.assertFood("")
        self.assertFood("   ")


class ReasonsTests(unittest.TestCase):
    def test_several_rules_can_fire_at_once(self) -> None:
        why = ingredient.reasons("Coffee, instant, powder")
        self.assertEqual(why, {"instant", "powder"})

    def test_a_portion_has_no_reasons(self) -> None:
        self.assertEqual(ingredient.reasons("Banana, raw"), frozenset())

    def test_every_rule_has_a_distinct_name(self) -> None:
        names = [rule.name for rule in ingredient.RULES]
        self.assertEqual(len(names), len(set(names)))

    def test_every_rule_can_fire(self) -> None:
        # A rule with no trigger would be dead weight nobody notices.
        for rule in ingredient.RULES:
            self.assertTrue(rule.words or rule.fragments, f"{rule.name} has no trigger")


class DatabaseTests(unittest.TestCase):
    """The flag has to survive the pass and reach the column the app reads."""

    def _row(self, name: str, ref: str, alt: tuple[str, ...] = ()) -> build.FoodRow:
        return build.FoodRow(
            name=name,
            key=name.casefold(),
            source=CIQUAL,
            source_ref=ref,
            category=None,
            nutrients={column: 1.0 for column in mapping.NUTRIENT_COLUMNS},
            portions=(),
            alt_names=alt,
        )

    def test_the_pass_flags_and_counts(self) -> None:
        rows = [
            self._row("Coffee, instant, powder", "1"),
            self._row("Coffee, beverage, brewed", "2"),
            self._row("Apple, pulp and skin, raw", "3"),
            self._row("Chicken, breast, raw", "4"),
        ]
        summary = build.BuildSummary()
        flagged = build.apply_ingredient_flags(rows, summary)
        self.assertEqual([row.is_ingredient for row in flagged], [1, 0, 0, 1])
        self.assertEqual(summary.ingredients, 2)

    def test_the_pass_leaves_other_fields_alone(self) -> None:
        rows = [self._row("Olive oil", "1", ("Huile d'olive",))]
        flagged = build.apply_ingredient_flags(rows, build.BuildSummary())
        self.assertEqual(flagged[0].name, "Olive oil")
        self.assertEqual(flagged[0].alt_names, ("Huile d'olive",))
        self.assertEqual(flagged[0].source_ref, "1")

    def test_the_column_is_written(self) -> None:
        rows = build.apply_ingredient_flags(
            [
                self._row("Salt, table", "1"),
                self._row("Oats, rolled", "2"),
            ],
            build.BuildSummary(),
        )
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / "foods.sqlite"
            output.write_sqlite(target, rows, {})
            conn = sqlite3.connect(target)
            try:
                found = dict(
                    conn.execute("SELECT name, is_ingredient FROM foods").fetchall()
                )
                self.assertEqual(found["Salt, table"], 1)
                self.assertEqual(found["Oats, rolled"], 0)
                self.assertEqual(
                    dict(conn.execute("SELECT key, value FROM meta").fetchall())[
                        "schema_version"
                    ],
                    "3",
                )
            finally:
                conn.close()
