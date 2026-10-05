# Mocks

Each HTML file here is one board of phone frames, openable in a browser with
nothing else installed. They are design artefacts, not app code: nothing in the
app reads them and nothing here is generated from the app.

## The current direction

Six boards, one visual language, together covering every screen the app has.
The language is the system rounded face on a warm near-white, soft row groups
instead of hard rules, four tabs with icons, and the composer on every tab.

| File | What it holds |
| --- | --- |
| [`g2-today.html`](g2-today.html) | Today, Shape and the run — the three screens the language was decided on |
| [`g2-logging.html`](g2-logging.html) | First run, the usual, logged, a marked row opened, the weight, the entry editor |
| [`g2-finding-food.html`](g2-finding-food.html) | Search before typing, the tray, scanning, a product found, a photograph, the estimate draft |
| [`g2-library.html`](g2-library.html) | The shelf, a bundled food, writing a food, building a recipe, logging a serving, remembered lines |
| [`g2-settings.html`](g2-settings.html) | Settings, Health per type, who reads your lines, sources, both onboarding screens |
| [`g2-states.html`](g2-states.html) | Loose ends, all eight nutrients over time, a day you missed, the day picker, degraded states, the widget and Siri |

Two things on these boards are new and are specified rather than merely drawn:

**The mark.** A ring around a square. The ring is the record — four meal
segments, drawn where the meal has an answer. The square is the composition —
three bands whose heights are each macronutrient's share of the day's energy,
plus a hatched band for the part no figure covers. A square and not a disc
because a band inside a circle is wider in the middle, so its area would not
match its number.

**The underline.** A dotted tint underline under the words that produced a
match the matcher would defend but not insist on. It is an affordance and not a
warning: tint means "you can act on this" here as everywhere else in the app.
The three states map exactly onto `MatchConfidence` — `settled` is unmarked,
`probable` is underlined and logged, `unsure` is underlined and *not* logged
until a food is picked.

## Figures on the boards

Every nutrient figure is a real row from the bundled database rather than a
plausible-looking number, which is why some of them are awkward: coffee is 1
kcal per 100 g, feta carries no fibre figure at all, and 666 of the 10,440
bundled rows are short of at least one of the eight nutrients. The portion
steps read 90 / 125 / 180 / 250 g because that is what `AmountBucket` returns
for a 125 g reference under its own rounding.

## Not covered

The three passes a review would want next, none of which fits in a 390-wide
frame: iPad layout, dark mode, and the largest accessibility type sizes. The
mark's 46 pt core and the four-segment ring are the most likely things to break
at those sizes.

## Earlier

[`one-line-logging.html`](one-line-logging.html) is the design document for the
move to one line of text as the primary input. It argues the decision rather
than showing a finished screen, and the screens in it predate the language
above.
