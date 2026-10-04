"""Marking rows that are not a portion anyone eats.

A composition table is full of foods that are real foods and are never a serving:
coffee powder, dried milk, raw chicken, cooking oil. They match the same words as
the thing the user meant — "coffee" ranks `Coffee, instant, powder` highly — and a
relevance score cannot tell them apart, because by its own measure the match is
good. The cost is not a mild ranking error: instant coffee powder is about 350
kcal per 100 g against about 2 for the drink, so a cup logged against the powder
is wrong by a factor of a hundred and silently so.

The flag this module computes demotes such a row for a "what I ate" query and
stops it ever being accepted without the user looking. It is the only one of the
three defences against this that needs neither a language model nor a correction
from the user, so it is the one that has to work on every device.

Matching runs over a row's display name *and* the names the source publishes in
its other languages. That is what keeps the English rules doing most of the work:
Ciqual rows display English, and BLS 4.0 publishes an English name beside the
German one, so "Milchpulver" is also reachable as "milk powder". The German and
French patterns are a backstop for the rows that lack an English name rather than
the main event.

Being wrong in either direction costs something, so the rules are deliberately
narrow and each one is named, which is what makes a flag auditable rather than
mysterious. The rule that earns its narrowness is `raw`: raw fruit and raw
vegetables are exactly what people eat, and `Apple, pulp and skin, raw` must not
be touched, so `raw` only counts beside an animal protein.
"""

from __future__ import annotations

import unicodedata
from dataclasses import dataclass


@dataclass(frozen=True)
class Rule:
    """One named reason a row is not a portion.

    `words` match on word boundaries, so "oil" does not fire on "boiled".
    `fragments` match anywhere, which is how German compounds are reached
    ("Milchpulver" holds "pulver" with no boundary to find).
    `requires` narrows a trigger that is otherwise far too broad: with it set, one
    of those words must appear as well. A required word of five characters or more
    also matches inside a compound, which is how "roh" is confirmed by
    "Hähnchenbrust"; shorter ones stay whole-word, because "ei" inside "Weizen"
    would confirm anything.
    """

    name: str
    words: tuple[str, ...] = ()
    fragments: tuple[str, ...] = ()
    requires: tuple[str, ...] = ()


# Animal protein, for the `raw` rule alone. Raw plants are food; raw meat is not.
_ANIMAL = (
    "meat", "beef", "veal", "pork", "lamb", "mutton", "chicken", "poultry", "turkey",
    "duck", "goose", "game", "venison", "liver", "kidney", "fish", "salmon", "cod",
    "tuna", "herring", "mackerel", "trout", "prawn", "prawns", "shrimp", "shrimps",
    "egg", "eggs", "offal", "bacon", "sausage",
    "fleisch", "rind", "kalb", "schwein", "lamm", "huhn", "hahn", "pute", "ente",
    "wild", "leber", "niere", "fisch", "lachs", "kabeljau", "thunfisch", "hering",
    "makrele", "forelle", "garnele", "garnelen", "ei", "eier", "wurst",
    # Compound stems, reached as fragments by the length rule in `_present`.
    "hahnchen", "rinder", "schweine", "hackfleisch", "putenfleisch",
    "viande", "boeuf", "veau", "porc", "agneau", "poulet", "volaille", "dinde",
    "canard", "gibier", "foie", "rognon", "poisson", "saumon", "cabillaud", "thon",
    "hareng", "maquereau", "truite", "crevette", "crevettes", "oeuf", "oeufs",
)

RULES: tuple[Rule, ...] = (
    # Reconstituted before eating, so the per-100 g figures describe the packet.
    Rule(
        name="powder",
        words=("powder", "powdered", "poudre", "pulver"),
        fragments=("pulver",),
    ),
    Rule(
        name="instant",
        words=("instant", "soluble", "loslich", "instantane"),
    ),
    Rule(
        name="concentrate",
        words=("concentrate", "concentrated", "concentre", "concentree", "konzentrat"),
        fragments=("konzentrat",),
    ),
    Rule(
        name="extract",
        words=("extract", "extrakt", "extrait", "essence", "essenz"),
    ),
    # Dried matters only where drying changes what a portion is. Dried fruit is a
    # snack and stays alone; dried milk and dried egg are an ingredient.
    Rule(
        name="dried-ingredient",
        words=("dried", "dehydrated", "getrocknet", "seche", "sechee", "deshydrate"),
        requires=(
            "milk", "egg", "eggs", "yeast", "soup", "broth", "stock", "bouillon",
            "cream", "whey", "gravy",
            "milch", "ei", "eier", "hefe", "suppe", "bruhe", "sahne", "molke",
            "lait", "oeuf", "oeufs", "levure", "soupe", "bouillon", "creme",
        ),
    ),
    # Raw animal protein. Narrow by construction; see the module docstring.
    Rule(
        name="raw-animal",
        words=("raw", "uncooked", "roh", "cru", "crue"),
        requires=_ANIMAL,
    ),
    # Eaten by the spoonful at most, so a portion bucket means nothing on them.
    Rule(
        name="pure-fat",
        words=(
            "oil", "lard", "tallow", "shortening", "ghee", "dripping",
            "schmalz", "butterschmalz", "huile", "saindoux", "suif",
        ),
        fragments=("speisefett", "pflanzenfett", "brataufett"),
    ),
    # Leavening, thickening and seasoning bases, where 100 g is not a serving and
    # the sodium figure in particular would swamp a day.
    Rule(
        name="kitchen-base",
        words=(
            "yeast", "gelatine", "gelatin", "starch", "rennet", "baking",
            "hefe", "backpulver", "starke", "lab",
            "levure", "gelatine", "amidon", "presure",
        ),
        fragments=("backpulver", "speisestarke", "starkemehl"),
    ),
    Rule(
        name="salt-or-spice",
        words=(
            "salt", "pepper", "peppercorns", "spice", "spices", "seasoning",
            "salz", "pfeffer", "gewurz", "gewurze",
            "sel", "poivre", "epice", "epices",
        ),
        # "salted peanuts" and "salt beef" are food; the bare commodity is not.
        requires=(),
    ),
)

# Rows whose name contains one of these are food however the rules read, because
# the commodity word is doing adjectival work: salted nuts, oiled bread, egg in a
# dish. Checked after the rules and wins over them.
_EXEMPT_WORDS: tuple[str, ...] = (
    "salted", "salzig", "gesalzen", "sale", "salee",
    "peanuts", "nuts", "crisps", "chips", "crackers", "biscuit", "biscuits",
    "bread", "brot", "pain", "cake", "kuchen", "gateau",
    "salad", "salat", "salade", "soup", "suppe", "soupe",
    "sardines", "anchovies", "olives", "pickles",
)


def fold(text: str) -> str:
    """Casefolded, diacritics stripped, punctuation turned to spaces.

    The same shape `remove_diacritics` gives the FTS index, so a rule written in
    plain ASCII reaches "Milchpulver, entrahmt" and "Café soluble" alike.
    """
    decomposed = unicodedata.normalize("NFKD", text)
    stripped = "".join(c for c in decomposed if not unicodedata.combining(c))
    cleaned = "".join(c if c.isalnum() else " " for c in stripped.casefold())
    return " ".join(cleaned.split())


def _words(folded: str) -> frozenset[str]:
    return frozenset(folded.split())


# Shortest a required word may be before it is also looked for inside a compound.
# Four and below stays whole-word: "ei" would otherwise be found in "Weizen".
_COMPOUND_MINIMUM = 5


def _present(term: str, folded: str, words: frozenset[str]) -> bool:
    """Whether a required word is there, as a word or inside a German compound."""
    if term in words:
        return True
    return len(term) >= _COMPOUND_MINIMUM and term in folded


def _fires(rule: Rule, folded: str, words: frozenset[str]) -> bool:
    # Triggers stay strict: whole words, plus the compounds a rule lists itself.
    # "oil" must not fire on "boiled", so no length rule applies here.
    triggered = any(word in words for word in rule.words) or any(
        fragment in folded for fragment in rule.fragments
    )
    if not triggered:
        return False
    if not rule.requires:
        return True
    return any(_present(required, folded, words) for required in rule.requires)


def reasons(name: str, alt_names: tuple[str, ...] = ()) -> frozenset[str]:
    """Every rule that fires on a row, by name. Empty when the row is a portion.

    Returned rather than a bare boolean so `inspect` can say *why* a row was
    demoted. A flag nobody can explain is a flag nobody can correct.
    """
    folded = fold(" ".join([name, *alt_names]))
    if not folded:
        return frozenset()
    words = _words(folded)
    if any(exempt in words for exempt in _EXEMPT_WORDS):
        return frozenset()
    return frozenset(rule.name for rule in RULES if _fires(rule, folded, words))


def is_ingredient(name: str, alt_names: tuple[str, ...] = ()) -> bool:
    """Whether the row is an ingredient or a dry form rather than a portion."""
    return bool(reasons(name, alt_names))
