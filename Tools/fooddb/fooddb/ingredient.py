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
    `head_only` restricts a trigger to the head of the name — see `head`. Set it
    for any word that names a commodity, because those turn up in preparation
    notes constantly and a note is not what the row is.
    """

    name: str
    words: tuple[str, ...] = ()
    fragments: tuple[str, ...] = ()
    requires: tuple[str, ...] = ()
    head_only: bool = False


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

# Preparations. A row that names one is a cooked dish, whatever a note after it says
# went into the pan.
_PREPARED = (
    "boiled", "stewed", "grilled", "fried", "roasted", "baked", "cooked", "braised",
    "steamed", "poached", "simmered", "sauteed", "gekocht", "gebraten", "gegrillt",
    "gebacken", "gedunstet", "gedampft", "cuit", "cuite", "bouilli", "grille", "rotie",
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
    #
    # "fat" is here and head-only, which is what tells "Chicken fat" and "Palm fat
    # hydrogenated" from "Fennel boiled (with fat and salt)". "butter" is deliberately
    # absent: peanut and almond butter are portions, and no rule short of a word list
    # separates them from the dairy kind.
    Rule(
        name="pure-fat",
        words=(
            "oil", "lard", "tallow", "shortening", "ghee", "dripping", "fat",
            "schmalz", "butterschmalz", "huile", "saindoux", "suif", "fett",
        ),
        fragments=("speisefett", "pflanzenfett", "brataufett"),
        head_only=True,
    ),
    # Leavening, thickening and seasoning bases, where 100 g is not a serving and
    # the sodium figure in particular would swamp a day.
    Rule(
        name="kitchen-base",
        words=(
            "yeast", "gelatine", "gelatin", "starch", "rennet", "baking",
            "hefe", "backpulver", "starke", "lab",
            "levure", "amidon", "presure",
        ),
        fragments=("backpulver", "speisestarke", "starkemehl"),
        head_only=True,
    ),
    Rule(
        name="salt-or-spice",
        words=(
            "salt", "pepper", "peppercorns", "spice", "spices", "seasoning",
            "salz", "pfeffer", "gewurz", "gewurze",
            "sel", "poivre", "epice", "epices",
        ),
        head_only=True,
    ),
)

# Rows whose name contains one of these are food however the rules read, because
# the commodity word is doing adjectival work: salted nuts, oiled bread, egg in a
# dish. Checked after the rules and wins over them.
#
# The pasta and noodle entries earn their place from the real data: the BLS calls a
# dried filled pasta "Egg pasta Tortelloni (ricotta and spinach filling) dried",
# which is a portion however many of the dry-form words it carries, and a glass
# noodle is named after the starch it is made from.
_EXEMPT_WORDS: tuple[str, ...] = (
    "salted", "salzig", "gesalzen", "sale", "salee",
    "peanuts", "nuts", "crisps", "chips", "crackers", "biscuit", "biscuits",
    "bread", "brot", "pain", "cake", "kuchen", "gateau",
    "salad", "salat", "salade", "soup", "suppe", "soupe",
    "sardines", "anchovies", "olives", "pickles",
    "pasta", "noodle", "noodles", "nudeln", "spaghetti", "macaroni", "lasagne",
    "tortellini", "tortelloni", "ravioli", "gnocchi", "dumpling", "dumplings",
    "roll", "rolls", "brotchen", "porridge", "muesli", "cereal",
    # Sweet and bell peppers are vegetables; the spice is "pepper" alone.
    "sweet", "bell",
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


def head(name: str) -> str:
    """The part of a name that says what the row *is*.

    Composition tables put the food first and qualify it afterwards, so everything
    from the first comma, bracket or *digit* onwards is a qualifier, and a commodity
    word appearing only there is a note rather than the subject of the row.

    Both halves of that came from running the rules over the real BLS rather than
    from thinking about it:

    - Cutting at a comma or bracket: without it, "salt" alone flagged every cooked
      vegetable in the German table, because they are all named
      "Fennel boiled (with fat and salt)".
    - Cutting at a digit: without it, "fat" flagged every dairy product, because the
      BLS specifies them by fat content — "Gouda cheese 48 % fat in dry matter",
      "Whipping cream min. 36 % fat". A number before a commodity word makes it a
      specification, not the food.

    A name that opens with a digit has no head and matches no rule, which is the
    right answer for "7-grain bread" and costs nothing.
    """
    for separator in (",", "(", ";"):
        name = name.split(separator)[0]
    for index, character in enumerate(name):
        if character.isdigit():
            return name[:index]
    return name


# Shortest a required word may be before it is also looked for inside a compound.
# Four and below stays whole-word: "ei" would otherwise be found in "Weizen".
_COMPOUND_MINIMUM = 5


def _present(term: str, folded: str, words: frozenset[str]) -> bool:
    """Whether a required word is there, as a word or inside a German compound."""
    if term in words:
        return True
    return len(term) >= _COMPOUND_MINIMUM and term in folded


def _fires(
    rule: Rule, folded: str, words: frozenset[str], head_words: frozenset[str]
) -> bool:
    # Triggers stay strict: whole words, plus the compounds a rule lists itself.
    # "oil" must not fire on "boiled", so no length rule applies here.
    candidates = head_words if rule.head_only else words
    triggered = any(word in candidates for word in rule.words) or any(
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
    # A row that names a preparation is a cooked dish, whatever a note after it says
    # went into the pan.
    if any(prepared in words for prepared in _PREPARED):
        return frozenset()
    head_words = _words(fold(" ".join([head(name), *(head(alt) for alt in alt_names)])))
    return frozenset(
        rule.name for rule in RULES if _fires(rule, folded, words, head_words)
    )


def is_ingredient(name: str, alt_names: tuple[str, ...] = ()) -> bool:
    """Whether the row is an ingredient or a dry form rather than a portion."""
    return bool(reasons(name, alt_names))
