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


class RealDatabaseTests(unittest.TestCase):
    """Rows from the real Bundeslebensmittelschlüssel 4.0.

    Every case here was wrong the first time the rules met the real table, and each one
    bought a change: the head rule, cutting the head at a digit, the prepared-dish
    exemption, and "fat" as a head word. They are kept because the rules are only as
    good as the names they were tested against, and these are the names.
    """

    def assertPortion(self, name: str) -> None:
        self.assertFalse(
            ingredient.is_ingredient(name),
            f"{name!r} wrongly flagged as {sorted(ingredient.reasons(name))}",
        )

    def assertNotPortion(self, name: str) -> None:
        self.assertTrue(ingredient.is_ingredient(name), f"{name!r} not flagged")

    def test_the_bls_names_every_cooked_vegetable_with_fat_and_salt(self) -> None:
        # The largest false-positive class there was: "salt" alone flagged most of the
        # vegetables in the German table.
        for name in (
            "Fennel boiled (with fat and salt)",
            "Pumpkin stewed (with fat and salt)",
            "Topinambur stewed (with fat and salt)",
            "Broccoli boiled (with fat and salt)",
        ):
            self.assertPortion(name)

    def test_dairy_is_specified_by_fat_content(self) -> None:
        # The second-largest: "fat" flagged every cheese and cream, because the BLS
        # states a fat percentage in the name.
        for name in (
            "Gouda cheese 48 % fat in dry matter",
            "Whipping cream min. 36 % fat",
            "Quark 20 % fat in dry matter",
            "Whole milk, 3.5 % fat, ultra-heated",
            "Yogurt mild, min. 3.5 % fat",
        ):
            self.assertPortion(name)

    def test_a_dish_that_merely_contains_an_ingredient(self) -> None:
        for name in (
            "Porridge sweetened, with milk 3.5 % fat and cocoa powder",
            "Glass noodles made from mung bean starch, boiled",
            "Egg pasta Tortelloni (ricotta and spinach filling) dried",
            "Wheat-rye roll (> 50 % and < 90 % wheat) with caraway seeds and salt",
            "Sweet pepper red, grilled",
        ):
            self.assertPortion(name)

    def test_the_pure_fats_the_table_names_as_fat(self) -> None:
        # Missed until "fat" became a head word; all of them are about 900 kcal.
        for name in (
            "Chicken fat",
            "Duck fat",
            "Palm fat hydrogenated",
            "Coconut fat hydrogenated",
        ):
            self.assertNotPortion(name)

    def test_what_must_stay_flagged(self) -> None:
        for name in (
            "Olive oil",
            "Gelatine",
            "Beef tallow/fat",
            "Lime concentrate",
            "Pork tenderloin, raw",
            "Beef marrow, raw",
            "Chicken breast fillet, raw",
        ):
            self.assertNotPortion(name)

    def test_known_gap_the_word_butter(self) -> None:
        """Cocoa and shea butter are baking fats and are not flagged.

        Deliberate. "butter" cannot be a trigger without also flagging peanut and
        almond butter, which are portions, and exempting nut words would wrongly
        exempt sunflower *oil*. Two rare fats slipping through costs less than a word
        list that will itself be wrong, and this is what the other two defences are
        for. Asserted so the gap is a decision rather than a surprise.
        """
        self.assertPortion("Cocoa butter")
        self.assertPortion("Shea butter")


class RealCiqualNameTests(unittest.TestCase):
    """Rows from the real Ciqual table (ANSES), French name beside the English one.

    The German table taught the rules that a qualifier after a comma, a bracket or a
    digit is a note. The French table taught them that a qualifier often arrives with
    no punctuation at all: it says "Pâté au poivre vert" and "Boisson préparée à
    partir de boisson concentrée", where the food is everything before the connective
    and what follows is the recipe. Every case here was wrong the first time the rules
    met the table.

    These pass the French name explicitly, which the shipped build no longer does: it
    keeps English names only, so in the bundle `alt_names` is empty. They are kept
    because they pin `reasons`, whose contract is unchanged and whose foreign-language
    vocabulary is what a second language would be built on — and because the English
    half of each name is a real Ciqual row either way. Where a case turns on the French
    name alone, it says so.
    """

    def assertPortion(self, name: str, *alt: str) -> None:
        self.assertFalse(
            ingredient.is_ingredient(name, tuple(alt)),
            f"{name!r} wrongly flagged as {sorted(ingredient.reasons(name, tuple(alt)))}",
        )

    def assertNotPortion(self, name: str, *alt: str) -> None:
        self.assertTrue(ingredient.is_ingredient(name, tuple(alt)), f"{name!r} not flagged")

    def test_juice_from_concentrate_is_a_glass_of_juice(self) -> None:
        # The costliest false positive the French table held: Ciqual names every
        # reconstituted juice "from concentrate", so the whole shelf was demoted and
        # "orange juice" could never settle, which is the tedium this is all against.
        self.assertPortion("Orange juice, from concentrate", "Jus d'orange, à base de concentré")
        self.assertPortion("Apple juice, from concentrate", "Jus de pomme, à base de concentré")
        self.assertPortion(
            "Fruit juice, from concentrate (average)",
            "Jus de fruits, à base de concentré (aliment moyen)",
        )

    def test_a_concentrate_that_is_the_row_itself(self) -> None:
        # The other side of the same rule: when the concentrate is the subject rather
        # than where the row came from, it stays flagged.
        self.assertNotPortion(
            "Concentrate beverage (to be diluted), no added sugars and with sweetener(s)"
        )
        self.assertNotPortion(
            "Condensed milk, no added sugars, whole", "Lait concentré non sucré, entier"
        )
        self.assertNotPortion("Tomato concentrate")

    def test_a_beverage_prepared_from_a_concentrate(self) -> None:
        # "à partir de" is the French "from", and the row is the drink, not the syrup.
        self.assertPortion(
            "Preparation for beverage diluted in water (eg. mint, strawberry etc.), "
            "no added sugars",
            "Boisson préparée à partir de boisson concentrée à diluer type menthe, fraise",
        )

    def test_french_says_with_by_inflecting_the_preposition(self) -> None:
        # "au", "aux" and "à la" end the name of the food as surely as a comma does.
        self.assertPortion("Pâté with green pepper", "Pâté au poivre vert")
        self.assertPortion("Cream sauce with spices", "Sauce à la crème aux épices")
        self.assertPortion("Spicy pork sausage with red pepper", "Chorizo")

    def test_a_seasoning_that_is_still_the_subject(self) -> None:
        self.assertNotPortion("Salt, with celery", "Sel au céleri")
        self.assertNotPortion("Spice (average)", "Épices (aliment moyen)")

    def test_the_french_adjective_for_spiced(self) -> None:
        """A seasoned food is not a seasoning.

        "épicés" and "épices" fold to the same letters, so the French noun had to go:
        it flagged oven chips, and spared "Pain d'épices" only because "pain" is
        exempt. The English name carries "spice" on every row that means the spice.
        """
        self.assertPortion(
            "Potato wedge, spiced, frozen, raw",
            "Potatoes ou wedges ou quartiers de pommes de terre épicés, surgelées, à cuire",
        )
        self.assertPortion("Gingerbread, prepacked", "Pain d'épices, préemballé")

    def test_flour_and_raw_dough(self) -> None:
        # Twenty flours in Ciqual and sixty-four in the BLS went unflagged until
        # "flour" was named, reaching the German compounds as the fragment "mehl".
        self.assertNotPortion("Wheat flour, type 55", "Farine de blé tendre ou froment, type 55")
        self.assertNotPortion("Spelt flour", "Farine d'épeautre")
        self.assertNotPortion("Gerste Mehl", "Barley flour")
        self.assertNotPortion("Weizen Vollkornmehl", "Wheat wholemeal flour")
        self.assertNotPortion("Pizza dough, prepacked, raw", "Pâte à pizza, préemballée, crue")
        self.assertNotPortion("Pizzateig (mit Hefe) roh", "Pizza dough with yeast, raw")

    def test_baked_dough_is_a_portion(self) -> None:
        # The pair that shows the preparation exemption still decides the question.
        self.assertPortion("Pizzateig (mit Hefe) gebacken", "Pizza dough with yeast, baked")

    def test_margarine_is_named_rather_than_inferred(self) -> None:
        """Two margarines at 720 kcal were reached only by the word "oil" in their
        English name, and cutting the head at a connective would have lost them. A
        commodity the table sells by the tub belongs in the rule by name.
        """
        self.assertNotPortion(
            "Sonnenblumenmargarine Vollfett, angereichert mit Vitamin D",
            "Margarine made from sunflower oil, fortified with vitamin D",
        )
        self.assertNotPortion("Ziehmargarine", "Margarine for making puff pastry")

    def test_a_tortilla_is_a_portion(self) -> None:
        # The one row "flour" got wrong: the English spells out what it is made of.
        self.assertPortion("Weizentortilla", "Wheat flour tortilla")

    def test_an_alt_name_could_close_a_gap_the_display_name_leaves_open(self) -> None:
        """What a second name buys, on the one row that shows it.

        Ciqual calls cocoa butter "Huile ou beurre de cacao" — it says oil where the
        English says butter — so the rules flag it when handed both names and not when
        handed one. The shipped bundle hands them one, so `Cocoa butter` really is
        unflagged there, exactly as `test_known_gap_the_word_butter` says. Asserted
        from both sides so the cost of shipping one language is written down rather
        than inferred.
        """
        self.assertNotPortion("Cocoa butter", "Huile ou beurre de cacao")
        self.assertPortion("Cocoa butter")

    def test_a_row_that_says_it_is_already_drinkable(self) -> None:
        """Ciqual names a cup of coffee for the powder it came from.

        "Instant coffee, no added sugars, ready-to-drink" is 1.6 kcal, and `instant`
        demoted it along with ten other drinks — the cups of coffee, cocoa and chicory
        a person is most likely to say out loud. A row that says it is ready to drink
        is saying the figures are the serving's, which is the exact inverse of why
        `powder`, `instant` and `concentrate` exist.
        """
        for name in (
            "Instant coffee, no added sugars, ready-to-drink",
            "Instant cocoa or chocolate beverage, with sugar(s), ready-to-drink",
            "Broth or stock, beef, dehydrated and reconstituted",
            "Pastry cream or custard, instant, reconstituted",
        ):
            self.assertPortion(name)

    def test_the_unprepared_twin_stays_flagged(self) -> None:
        # The exemption turns on the words "ready to drink" and "reconstituted" and
        # nothing else, so the packet each of these describes is still a packet.
        for name in ("Coffee, powder, instant", "Broth or stock, beef, dehydrated"):
            self.assertNotPortion(name)

    def test_known_gap_tomato_paste(self) -> None:
        """Tomato paste is not flagged, and that is the price of the juice fix.

        Ciqual writes "Tomato paste, concentrated, canned" with the French
        "Tomate, concentré, appertisé", so the trigger sits after a comma in both and
        reads as a note. "paste" cannot be a trigger without flagging peanut butter
        and marzipan, and "purée" without flagging mashed potatoes, so two rows at
        about 80 kcal are left to the other two defences. Asserted so the gap is a
        decision rather than a surprise.
        """
        self.assertPortion("Tomato paste, concentrated, canned", "Tomate, concentré, appertisé")

    def test_known_gap_a_flour_whose_note_mentions_bread(self) -> None:
        """One flour of twenty escapes, because its note says what it is for.

        The exemption list is checked before the rules and over the whole name, so
        "(for bread)" spares it. Narrowing the exemption to the head would be worse:
        it is there to stop a commodity word in a note flagging the bread itself.
        """
        self.assertPortion("Wheat flour, type 55 (for bread)")


class ConnectiveHeadTests(unittest.TestCase):
    """What `head` keeps and what it drops, connective by connective."""

    def test_a_note_introduced_by_a_connective_is_dropped(self) -> None:
        self.assertEqual(ingredient.head("Still soft drink with tea extract"), "Still soft drink")
        self.assertEqual(ingredient.head("Pâté au poivre vert"), "Pâté")
        self.assertEqual(ingredient.head("Sauce à la crème aux épices"), "Sauce")
        self.assertEqual(
            ingredient.head("Boisson préparée à partir de boisson concentrée"), "Boisson préparée"
        )

    def test_from_is_not_a_connective(self) -> None:
        """"Margarine made from sunflower oil" says what the row is.

        The row that started the connective rule — "Orange juice, from concentrate" —
        is cut at its comma anyway, so "from" buys nothing and costs the only fat word
        two margarines have.
        """
        self.assertEqual(
            ingredient.head("Margarine made from sunflower oil"),
            "Margarine made from sunflower oil",
        )

    def test_a_connective_at_the_start_introduces_nothing(self) -> None:
        # Returning an empty head here would make the name match no head-only rule at
        # all, which is a worse answer than reading it whole.
        self.assertEqual(ingredient.head("With love"), "With love")

    def test_punctuation_still_ends_the_head_first(self) -> None:
        self.assertEqual(ingredient.head("Salt, with celery"), "Salt")
        self.assertEqual(
            ingredient.head("Fennel boiled (with fat and salt)").strip(), "Fennel boiled"
        )
        self.assertEqual(
            ingredient.head("Gouda cheese 48 % fat in dry matter").strip(), "Gouda cheese"
        )
