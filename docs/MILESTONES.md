# Milestones

Status log for the build order in `PLAN.md`. Each milestone is planned, implemented, reviewed by a separate pass, then signed off here before the next one starts.

A log, not a design document. Entries are kept as they were written, so an older one can
describe a design that has since changed; where an entry disagrees with `PLAN.md`, `PLAN.md`
is current.

| # | Milestone | Status | Sign-off |
| --- | --- | --- | --- |
| 1 | Data pipeline | done | 2026-09-21 |
| 2 | Log to Health end-to-end | done, awaiting first build | 2026-09-21 |
| 3 | Reconciliation | done, awaiting first build | 2026-09-21 |
| 4 | Recipes | done, awaiting first build | 2026-09-21 |
| 5 | Barcode | done, awaiting first build | 2026-09-21 |
| 6 | AI estimation | done, awaiting first build | 2026-09-21 |
| 7 | Internationalization | sources bundled, UI pending | |
| 8 | The matcher: confidence, thresholds, popularity | done, awaiting first build | |
| 9 | Phrase memory | done, awaiting first build | |
| 10 | Composer and sign-off screen | rebuilt around a model, awaiting first build | |
| 11 | Buckets and coverage | done, awaiting first build | |
| 12 | Trends | done, awaiting first build | |
| 13 | Baseline days | done, awaiting first build | |
| 14 | Widget and Siri | done, awaiting first build | |
| 15 | Sampling | done, awaiting first build | |

Milestones 8 to 15 come from `PLAN.md` revision 4, which rethinks logging around one line of
natural language and puts trends back in scope. Steps 1 to 4 were the shippable app before
they existed; with them the shippable app is 1 to 4 plus 8 to 12 — the matcher, the memory,
the composer, coverage and the charts. Steps 13 to 15 are additive.

Revision 5 rebuilt milestone 10 rather than adding a milestone: the line is read by a model
and by nothing else. See "The model is the input" at the end of this log.

## Build order as planned

What each step was to deliver. Moved here from `PLAN.md`, which carries the dependency
ordering alone; what each one actually landed as is in the entries below.

1. **Data pipeline.** A standalone script producing `foods.sqlite` and `sources.json` from FDC. No app code. Single source, so the risk is the FDC file format and the Foundation versus SR Legacy overlap, not cross-source deduplication.
2. **Log to Health end-to-end.** Search a bundled food, enter grams, write the food correlation, see it in the Health app. Proves the write path and the correlation grouping. Ends with the Milestone 2 device checks.
3. **Reconciliation.** Observer queries, anchored queries, per-sample deletion handling, restore affordance. Tedious to retrofit once entries exist, so it comes before features.
4. **Recipes.** Ingredient rows, servings, snapshot on log.
5. **Barcode.** Scanner, lookup, cache, attribution, manual fallback.
6. **AI estimation.** Availability gate, image prompt, generable struct, editable draft.
7. **Internationalization.** Localised UI, and the user's language ranked first in search. The sources themselves are already bundled.

Steps 8 to 15 are ordered so that each one is useful on its own, and so that the riskiest
thing — auto-matching a food the model named well enough to log it without being asked — is
proved before anything is built on top of it.

8. **The matcher and its deterministic defences.** Confidence scoring on `SearchRelevance`, the two thresholds, a rewritten `popularity` list against real Ciqual and BLS names, and the `is_ingredient` flag in the pipeline with the demotion that reads it. No UI and no model. The gate is a fixture set of real typed lines with their expected matches, including the ingredient-form traps, because every later milestone assumes this one works.
9. **Phrase memory.** `Phrase` and `PhraseItem`, the normalisation function, recall before search, amounts from history. Testable without a model at all: a phrase is recorded and recalled whatever produced it.
10. **The composer, the estimator and the sign-off screen.** The estimator first, since nothing new resolves without one: Apple Intelligence where it answers, an endpoint of the user's own where it does not. Then the validation call and the three verdicts it returns. Keyboard dictation comes free with the text field. The screen has to make a validated row, an unvalidated one and a rejected one tell themselves apart without colour-coding any of them as good or bad, and it has to take a food the model never named. This is the milestone the redesign is for.
11. **Buckets and coverage.** Portion buckets with the reference ladder, `DayRecord`, marking a day complete, and partial-day totals on Today.
12. **Trends.** Statistics-collection queries per nutrient, the three charts, the coverage strip, the range switcher.
13. **Baseline days.** `BaselinePhrase`, proposals on Today, accept and deviate.
14. **Widget and Siri.** Top phrases on the home and Lock Screen, an App Intent for a spoken line. It shows lines to tap and no figure about a day, because a widget that fits three numbers is read as a score. The decision not to share the store, and its three reasons, is under "Milestone 14: Siri and the widget" below.
15. **Sampling.** Cadence setting, day nomination, means over in-sample complete days.

## Milestones 9 to 15: the one-line path

Written as one entry because they were built as one stretch and share a gate: no Swift
compiler exists in the environment they were written in, so every Swift claim below is
reasoned and arithmetically checked rather than built. The Python pipeline half of
milestone 8 is the only part genuinely verified by running it.

### What landed

**9, phrase memory.** `Phrase` and `PhraseItem`, and `PhraseKey` as the one tested
function the whole path rests on. Case, diacritics, punctuation and filler words in three
languages go; counts become digits; the remaining tokens are sorted. Sorting is what
makes recall survive how people actually retype a line — "oats with a banana" and "Banana
and oats!" reach one record, as do "a pancake with oats, peanut butter and banana" and
"Pancake, banana, peanut butter, oats". The price is that word order carries no meaning,
so two different meals could collapse into one key; a visible, correctable recall is what
makes that survivable. Writing replaces rather than merges, and a food reference nullifies
on delete so the line survives to be written over.

Also here: the model list stopped being copied into four places, which is a footgun with a
delay on it.

**10, the composer.** Four rungs in order — the whole line from memory, one familiar food,
the bundled tables, then Open Food Facts behind its opt-in. The first two never ask the
model, which is what keeps a repeat fast. `LineParser` works on every device and three of
its behaviours came out of running it over real lines rather than from reading it: a
number glued to its unit, a container word leaving a stranded "of", and a size word on its
own belonging to the food before it. Validation is all-or-nothing per line, so "not
checked" stays a property of the screen that one sentence carries.

**11, buckets and coverage.** Four steps against what this person last had, offered only
where there is a remembered amount to multiply; a first-time food shows its portions by
name instead. `DayState` derives what kind of day it is, with `assumed` beating `complete`
on purpose. The headline set became the user's choice.

**12, trends.** All eight nutrients, one measure and one axis each. Health supplies the
totals through one statistics-collection query per nutrient; the local store supplies what
a complete day is. The rolling mean breaks over a gap by construction — the series is
split into runs and each is drawn as its own line — rather than by hoping a missing value
interrupts one line. Coverage sits second rather than last.

**13, baseline days.** A slot's usual line offered as a proposal, accepted in one tap,
recorded with an origin that keeps the day `assumed`. Built only from a line logged four
or more times in that slot, never from a questionnaire.

**15, sampling.** The cadence changes what the app asks for and never what it computes
over: a complete day counts toward every mean whether or not the schedule asked about it.
Membership is derived from the date, which is also why the day record carries no sample
flag — it would have been a field nothing reads.

### Milestone 14: Siri and the widget

The App Intent runs the same four rungs without opening the app, logs only what settles,
and leaves anything else on `AppRouter` for the composer with the dialog saying so. Two
outcomes and no third, which is what makes it safe from a lock screen: it cannot put a
figure into Health that nobody stood behind.

The widget is a fourth target, `OmnomnomWidget`, plus a small `OmnomnomShared` folder that
both it and the app compile.

**The widget does not share the store, and that is the design rather than a compromise.**
It reads a small JSON snapshot the app writes into the App Group, and a tap deep-links
into the app, which resolves the line and logs it. Three reasons, worst first:

1. A widget extension is the wrong place to write to HealthKit, and logging a meal means
   eight samples and a correlation.
2. Sharing the SwiftData store would mean the whole model layer in both targets — the
   entities, the logger, the Health actor, the resolver — which is a local Swift package
   and a refactor, not a widget.
3. It leaves the store exactly where it is. Putting it in an App Group moves its
   container, which is a data migration for anyone who already has entries. Avoiding that
   is worth more than saving a screen transition, and it is what made this shippable now
   rather than after a migration.

It shows lines to tap and no figure about any day. A widget that fits three numbers will
be read as a score, which would be the most verdict-shaped surface in the app.

The project file was edited by hand and then checked structurally: every referenced id
resolves, every defined id is used, braces and parentheses balance, all fourteen sections
pair, and the widget is present in the targets list, the target attributes, the app's
dependencies, the embed phase and the products group. That is not the same as opening it
in Xcode, which is still the first thing to do.

**To verify on device, in this order:** that Xcode opens the project without repairing it;
that the App Group is provisioned for both bundle ids; and that a tap on a tile reaches
`onOpenURL`. WidgetKit routes a widget's own links to its host app, so the `omnomnom://`
scheme should need no registration — if it turns out to, that is a `CFBundleURLTypes`
entry and the app currently generates its Info.plist.

## Milestone 8: The matcher

### Plan

Auto-matching a typed fragment to a bundled row is what every later saving rests on, so
it comes first and its gate is behaviour rather than review: a confidence a threshold can
be hung on, an honest "not sure", and the deterministic defence against a row that is a
confidently wrong answer.

### What landed

- `Tools/fooddb/fooddb/ingredient.py` and an `is_ingredient` column, schema version 3.
  Named rules over a row's display name together with its other-language names, applied
  in one pass over every source. Thirty-three tests, weighted towards the negatives: raw
  fruit, dried fruit, boiled potatoes, salted peanuts and oat biscuits must all come back
  clean, since a false positive demotes a food people eat.
- `BundledFood` carries `altNames` and `isIngredient`, and the reader selects both.
  Scoring over the other-language names is not a nicety: a French query against a Ciqual
  row that displays English scores 0.829 with them and exactly 0 without, so without this
  auto-matching only ever worked in the language on screen.
- `FoodMatch` and `FoodMatcher`: a score with an ingredient penalty of 0.35 and a capped
  popularity prior, and three confidences — settled at 0.78, probable at 0.42, unsure
  below. An ingredient form is always unsure, never merely "not settled": typing "coffee"
  scores the powder at 0.49, which is probable, and a marker is not enough for a row that
  is wrong by a hundredfold.
- Twenty-two tests in `OmnomnomTests/FoodMatcherTests.swift`.

The thresholds were settled by running the same arithmetic over real Ciqual and BLS
names, not by choosing numbers that read well. "Coffee" gives brewed 0.838 and settled
against powder 0.489 and blocked; "chicken" gives grilled 0.846 against raw 0.503;
"milk" gives whole 0.829 against dried 0.480. The penalty is larger than the gap between
any two match tiers, which is what stops a powder outranking the drink it shares a name
with however the two happen to score.

### Settled against the real database

The BLS 4.0 table arrived and the pipeline read it on the first run: 418 columns, 7,140
rows, all eight nutrients matched with their units taken from the headers, nothing
dropped. Running the matcher over those 7,140 rows then found four separate faults that
no amount of reasoning had, and fixed each one:

| Typed | Before | Cause | After |
| --- | --- | --- | --- |
| oats | nothing at all | FTS5 prefix runs forwards only, so `"oats"*` misses "Oat flakes" | Oat flakes |
| oats | — | and the *scorer* still could not score it; "Oat groats" won because "groats" contains "oats" | — |
| coffee | Coffee ice cream, 171 kcal | the prior was zero, so the tie fell to name length | Coffee (infusion), 1 kcal |
| milk | Milk chocolate, 532 kcal | a derivative takes the better text tier, and the prior could not cross one | Whole milk, 62 kcal |
| cheese | Cheeseburger | the prior scaled by list position, so the fortieth entry got a third of the help | Gouda cheese |

Bare-noun queries now resolve correctly on 21 of 21 cases, against roughly 2 before.

The curated list is rewritten against the real names: 76 entries, all 76 matching a real
row, against 47 of 48 matching nothing. The prior became mostly a membership floor,
because every entry is there for being *the* form a bare noun means, so being on the list
matters far more than where.

The `is_ingredient` flag met real data for the first time and was wrong in two large
ways, both now fixed and both kept honest by tests naming the real rows: the BLS names
every cooked vegetable "... (with fat and salt)", and it specifies every dairy product by
fat content. A commodity word only counts in the *head* of a name, and the head ends at
the first comma, bracket or digit. 517 of 7,140 rows flagged, down from a first pass that
caught most of the vegetables in Germany.

### Open

- **A second language is not built.** The readers return the French and German names and
  the build drops them; shipping them needs a reversed-token index and a scorer that tells
  a compound's tail from its head. Both are prototyped and measured, neither is written.
  See "The bundle ships one language" below and "One language" in `PLAN.md`.
- **Composite-before-split** is specified in `PLAN.md` but lands with the parser, since
  there are no fragments to split until the composer exists.
- **"Butter" is a known gap in the flag.** Cocoa and shea butter are baking fats and are
  not flagged, because "butter" cannot trigger without also catching peanut butter, and
  exempting nut words would wrongly exempt sunflower *oil*. Asserted as a decision rather
  than left as a surprise.
- **No Swift compiler here.** The Swift half is reasoned, and every numeric expectation in
  its tests was checked by mirroring the same arithmetic in Python and running it over the
  real database. The Python half is genuinely verified: 184 tests, `ruff check` and `mypy
  --strict` clean.

### Settled against the real French table

Ciqual's composition file arrived truncated, which is enough to read: the export was cut
at a block boundary, so closing the root element and dropping a stray leading newline made
it valid XML, and the reader took it on the first run. 263 foods with values, all eight
nutrients, French names indexed beside the English ones, nothing implausible. The two
sources build together into one 7,395-row database with no unmatched curated entries.

The reader needed no changes. The `is_ingredient` rules needed five, because the French
table qualifies a food in ways the German one does not, and running the rules over all
3,484 French names — which `alim.xml` carries whether or not their values arrived — found
each one:

| Row | Was | Cause | Now |
| --- | --- | --- | --- |
| Orange juice, from concentrate | ingredient | every reconstituted juice is named "from concentrate" | portion |
| Pâté au poivre vert | ingredient | French says "with" by inflecting the preposition, so the head never ended | portion |
| Potato wedge, spiced | ingredient | "épicés" and "épices" fold to the same letters | portion |
| Wheat flour, Gerste Mehl | portion | "flour" was in no rule at all; 20 flours in Ciqual, 64 in the BLS | ingredient |
| Pizza dough, raw | portion | nor was "dough"; the baked twin is still a portion | ingredient |
| Margarine, 720 kcal | ingredient by accident | reached only through the word "oil" in a derivation note | ingredient by name |

So a commodity word now stops counting at a connective — "with", "avec", "mit", "au",
"aux", "à la", "à partir de" — as well as at a comma, a bracket or a digit. "from" was
tried there and taken back out: the juice row is cut at its comma anyway, and cutting at
"from" costs two margarines the only fat word they have. Across both tables the change
flags 150 rows it should have all along and releases 27, every one of them checked by
hand; 406 of 3,484 Ciqual rows and 638 of 7,140 BLS rows carry the flag.

Two gaps are left on purpose and asserted as tests rather than left to be discovered.
Tomato paste is not flagged, because "paste" cannot trigger without catching peanut butter
and marzipan, and "purée" without catching mashed potatoes. One flour of twenty escapes
because its note says "(for bread)" and the exemption list is checked first — which is the
exemption doing its job, since it is there to stop a word in a note flagging the bread.

### The bundle ships one language

The full composition file arrived and the whole table built: 3,341 Ciqual rows beside
7,099 from the BLS, 41 duplicate names dropped, one 1.8 MB database.

With it came the measurement that decided the language question. Indexing the French and
German names each table publishes alongside its English ones had looked free. It was not.
German builds a compound by putting the head noun last — "Vollmilch" is a milk,
"Milchschokolade" is a chocolate — and an FTS index can only be searched forwards, so
`"Milch"*` reached 176 rows and not one of the 29 that were milk. Scoring then made it
worse by reading the compound's *head* as the better match, so "Milch" settled,
confidently, on milk chocolate at 532 kcal against 62 for milk. Thirteen of 30 German
bare nouns were wrong the same way: "Tee" meant tea biscuits, "Wasser" watermelon,
"Brot" breadfruit, "Salat" salad cream.

A reversed-token index plus a tier that tells a compound's tail from its head fixes it,
and both were prototyped against the real database: "Milch" then finds whole milk, and
"Tee", "Wasser", "Brot", "Salat", "Zwiebel" and "Schinken" come right with it. Neither
ships. The app needs one language, a half-working second one is worse than none, and the
readers still return the other names so this stays a line to change rather than work to
redo. French went the same way for the same reason, having briefly been curated.

So the bundle is English-only, and the curated list was measured against it rather than
assumed. Reading the top match for eighty everyday bare nouns found that the words with
an entry resolved well and the words without one often did not: "cream" meant fruit ice
cream, "prawns" meant prawn crackers at 508 kcal against 91 for prawns, "fish" meant fish
stock at 8. Eighteen entries later, every one of those eighty resolves and nine are newly
correct. The list is 93 entries, all 93 matching a real row.

Three misses survive and are written down rather than left to be found. "Ham" means
hamburger and "burger" means burger sauce, because "hamburger" both begins with one and
ends with the other and an index read forwards favours the first — the English echo of
the German problem, rare enough to leave. "Peas" means pear, which costs nothing: both
are 58 kcal. And "oil" and "margarine" rank a dish containing them above the ingredient
itself, which is the ingredient flag working as designed; neither settles, so the user is
asked.

## Milestone 1: Data pipeline

### Plan

Deliverable: `Tools/fooddb`, a Python 3.9 or newer package with no third-party dependencies, that turns the FDC Foundation Foods and SR Legacy CSV bundles into `Omnomnom/Resources/foods.sqlite` and `Omnomnom/Resources/sources.json`.

- `python3 -m fooddb download --dest <dir>` fetches the two pinned zips from fdc.nal.usda.gov and verifies size and SHA-256 where known.
- `python3 -m fooddb build --fdc <dir> --out <sqlite> --sources-out <json>` reads the unzipped CSVs and writes both outputs. Idempotent: output is replaced atomically.
- Schema exactly as in PLAN.md, plus `popularity` on `foods` for the curated frequency boost and a `meta` table with schema version, build time and source versions.
- Nutrient mapping with fallbacks; the build fails loudly if a mapped nutrient id is absent from `nutrient.csv`.
- Foundation wins over SR Legacy on an identical normalised description.
- Unit tests on a synthetic fixture set that mirrors the FDC column layout, runnable with `python3 -m unittest`.

Constraint of this environment: the USDA hosts are blocked by the sandbox's egress policy, so the real download and a full build run on a Mac. The fixture tests are the sandbox gate.

### Review

Independent review on four lenses (maintainability, language and idiom, security, data correctness) plus a 24-case malformed-input matrix, a TLS downgrade stub and zip-guard probes. Nine should-fix findings, all resolved and re-verified:

- Portion labels lost the amount on undetermined-unit rows, which is most SR Legacy household measures. Now "1 medium", "0.5 cup, chopped".
- Downloads followed an https to http redirect; now refused, with a 60 s timeout.
- A cached zip failing its size or hash check is deleted so the next run refetches.
- Malformed CSV, duplicate ids, bad UTF-8, a short row, a missing popular list and an output path that is a directory all exit 1 with file and line instead of a traceback.
- NaN, infinite and negative amounts are rejected; implausible values warn.
- A bundle yielding no foods, a duplicate nutrient row and a blank description are each handled explicitly.
- Strict mypy and ruff are clean and reproducible via `ruff.toml`.

Nits applied: `collections.abc` imports, `dataclasses.replace`, one normalisation pass per row, output permissions follow the umask, `SOURCE_DATE_EPOCH` honoured, citation year from dataset versions, extract size cap, version detection ignores the input directory's own name.

### Sign-off

Signed off 2026-09-21. 62 tests pass. Outputs `foods.sqlite` and `sources.json` are generated, git-ignored, and built before opening Xcode.

Open operational item, not a code defect: the download pins carry no size or SHA-256 because the sandbox cannot reach fdc.nal.usda.gov. The first real download logs both values; paste them into `PINS` in `fooddb/download.py`.

## Milestone 2: Log to Health end-to-end

### Plan

Deliverable: an Xcode project that builds on iOS 26, lets the user search the bundled database, enter grams, and writes one food correlation to HealthKit. No reconciliation, no recipes, no opt-in modules.

Project
- `Omnomnom.xcodeproj` hand-written with Xcode 16 synchronized root groups (`PBXFileSystemSynchronizedRootGroup`) so no per-file entries are needed. Targets: `Omnomnom` (iOS 26.0, Swift 6, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, `SWIFT_STRICT_CONCURRENCY = complete`, `SWIFT_APPROACHABLE_CONCURRENCY = YES`) and `OmnomnomTests` (Swift Testing).
- `Omnomnom.entitlements`: HealthKit, background delivery (added now so milestone 3 needs no project change).
- Info.plist keys: `NSHealthShareUsageDescription`, `NSHealthUpdateUsageDescription`, specific wording.

FoodDB
- `SQLiteDatabase` actor: opens `foods.sqlite` read-only (`SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX`), three prepared statements, typed errors. `sqlite3` module import via a bridging-free `import SQLite3`.
- `FoodSearch`: FTS5 query building (prefix match on each token, escaped), ranked by `bm25(foods_fts) - popularity weight`, limit 50. Returns `BundledFood` value types.
- `Nutrition` value type with the eight fields, per-100 g maths, scaling by grams; `Nutrient` enum with the HealthKit identifier and unit for each case.

Model (SwiftData, CloudKit-compatible per PLAN.md rules)
- `Food` (custom/cached/bundled reference), `LogEntry` with frozen snapshot, `syncVersion`, `writtenNutrients`, `presentNutrients` stored as raw-value arrays, meal slot, timestamp. `Recipe`/`RecipeIngredient` deferred to milestone 4 but the `Food` relationships they need are optional so adding them is additive.

Health
- `HealthStore` actor behind `HealthWriting` protocol. Authorization request for the eight types. `write(entry:)` builds up to eight `HKQuantitySample`s and one `HKCorrelation`, sync identifiers `<uuid>.<nutrient>` and `<uuid>.meal`, `HKMetadataKeySyncVersion` on all, `HKMetadataKeyFoodType`, custom `mealSlot` metadata. Partial authorization rule from PLAN.md. Returns the set of nutrients written.
- No `HK` type crosses the actor boundary.

UI
- Today: date header, totals row (8 nutrients, primary and secondary), entries grouped by meal slot, add button.
- Add sheet: `.searchable`, recents before typing, results list.
- Quantity sheet: gram field with number pad, portion chips, live preview, meal slot, confirm. Logs entry, writes to Health, dismisses.
- Settings: Health status, Sources screen rendered from `sources.json`.
- Onboarding: two screens then permission request.

Tests (Swift Testing, no HealthKit)
- Nutrition scaling and snapshot maths.
- FTS query builder escaping.
- Sync identifier construction and metadata builder (pure function over value types, no HK objects).
- SQLite wrapper against the fixture build of `foods.sqlite`.

Bundle identifier `com.j23n.omnomnom`, no signing team set. Both outputs of the data pipeline must exist in `Omnomnom/Resources/` before building.

Sandbox constraint: no Swift toolchain here, so the code is reviewed but not compiled. First Xcode build on a Mac is the gate, and the device checks below close the milestone.

### Review

Uncompiled code, so the reviewer acted as the compiler: every file read line by line for Swift 6.2 syntax, isolation under default MainActor, member import visibility, and iOS 26 API signatures verified against Apple's documentation. Eleven flagged API assumptions checked; all held except one. Findings resolved:

- Three files used a Foundation member without importing Foundation, which member import visibility rejects.
- Deleting an entry left all nine Health objects behind. Delete now queries by sync identifier and removes them in one batch; a revoked permission flags the entry as orphaned, and a second delete removes it locally.
- The snapshot was taken from the stored copy of a food rather than the live database row; prefill of the last amount worked only from recents; a relationship was set before insert; a local save failure after a successful Health write was blamed on Health.
- Nutrient columns are stored flat as eight optional doubles on each model rather than a composite Codable attribute, so every column stays a plain scalar for a CloudKit retrofit.
- Added a test pinning the eight HealthKit identifier strings, a grams range of 0.1 to 5000, midnight rollover of the Today view, and a shared Xcode scheme.

### Sign-off

Signed off 2026-09-21 subject to the first build. Nothing in this sandbox can compile Swift; the reviewer's first-build watch list is:

1. A diagnostic on the `@Entry` environment keys under default MainActor isolation. Fallback: hand-written nonisolated keys.
2. The date binding in the Today header may warn.
3. Both `foods.sqlite` copies must land in their bundles from the synchronized folders; a failing fixture test or a missing-database log line says otherwise.
4. The model initialisers assign through a computed setter as their last statement; if the macro objects, assign the eight scalars directly.
5. With all eight write permissions revoked, confirm Health reports `errorAuthorizationDenied` on delete so the orphaned path triggers.
6. Entries logged with a nil food relationship would mean insert-then-relate still misbehaves.

### Device checks

Each is a behaviour the plan assumes but Apple does not document. Run them on a real device
before milestone 3 starts and record the outcome against each one here; these six close this
milestone. Nothing here has been run yet, for the reason above: the code has never been built.

- Re-saving nine objects with bumped sync versions replaces them in place and leaves exactly one correlation. — *outcome: not yet run*
- Deleting the correlation alone leaves the samples behind, so the batched delete is required. — *outcome: not yet run*
- Deleting one nutrient in the Health app surfaces one deleted object with the expected sync identifier in its metadata. — *outcome: not yet run*
- Background delivery for dietary types fires at `.immediate`, or note the actual minimum frequency. — *outcome: not yet run*
- How the Health app displays the food correlation, and whether `HKMetadataKeyFoodType` appears anywhere a user can see. — *outcome: not yet run*
- A partial authorization set (energy denied, the rest allowed) produces a correlation that Health accepts. — *outcome: not yet run*

## Milestone 3: Reconciliation

### Plan

Deliverable: the local store and Health agree after edits and deletions made in the Health app, and foreign nutrition samples appear in daily totals.

- `HealthObserving` protocol extension of the Health surface: `startObserving(onChange:)` registers one `HKObserverQuery` per quantity type with background delivery at `.immediate`; `changes(since:)` runs one `HKAnchoredObjectQuery` per quantity type plus the food correlation type and returns added and deleted sync identifiers with new anchors; `daySamples(in:)` returns own and foreign nutrition samples for a day window as value types with source name and food type metadata.
- Anchors persisted per type as secure-coded data in the app's storage, missing anchor means full history.
- `Reconciler`, pure and tested: applies deleted identifiers to `presentNutrients`, applies added own identifiers back (a restore, or a re-save), ignores identifiers it did not write, parses `<uuid>.<nutrient>` and `<uuid>.meal`.
- Launch renders local state, then reconciles; observer wake reconciles and calls the completion handler last.
- Entry states `partial` and `gone` get a tappable badge with two actions: restore (re-save the whole entry with a bumped sync version, then mark present) or remove here (existing delete path). `unauthorized` shows once with a link to app settings.
- Foreign samples: totals row shows the combined day figure with the foreign share visually distinct; a section "Also in Health" lists foreign food correlations by name and source, not editable.
- Tests: reconciler tables, identifier parsing, anchor round trip, own versus foreign classification, restore bumps the version.

Sandbox constraint unchanged: reviewed, not compiled.

### Review

Every HealthKit signature used (observer queries, background delivery, anchored and sample query descriptors, deleted-object metadata, anchor archiving, earliest authorized sample date) was verified against Apple's documentation. Three rounds of findings, all resolved:

- Observer queries were registered from a view task, which a background HealthKit launch does not run. They are now registered from the app initializer, before the first read, so the wake's completion always fires after the change was handled.
- "Own" samples were classified by bundle identifier, so entries logged with this app on another device and leftovers of removed entries were counted nowhere. Own now means mirrored by a local entry; everything else is foreign, counted once, and labelled "Omnomnom, not in this log" when it came from this app.
- A read from no anchor never reports earlier deletions, so old entries read as synced forever. A complete read from no anchor is now authoritative for absence, guarded three ways: only for types with write permission, only for entries inside the user's readable window on iOS 27 where Health can limit history, and never when the read returned nothing for that nutrient while local entries wrote it.
- A stored anchor rejected after an iCloud restore stalled reconciliation for good; it is dropped and the type re-read from the start.
- Coalesced wakes called their HealthKit completion before anything was applied; every caller now awaits the in-flight run.
- Day reads failed silently; they log and keep the previous summary.

### Sign-off

Signed off 2026-09-21 subject to the first build and device checks. Residual by design: a type Health lists as limited without a specific earliest date reads as unlimited and could be pruned beyond its real window; the zero-seen guard catches the all-or-nothing case only.

First-build watch list additions:

1. The `@Entry` default that constructs the app services class; fallback is an optional entry.
2. The sort descriptor on the day read may need its root type spelled out.
3. The predicate `ids.contains` on entry identifiers; fallback is fetching the day and filtering in memory.

Device checks: background wakes are simulator-unsupported. On a device, a deletion of one nutrient in Health must surface one deleted identifier and flip the badge to partial without a re-push; a rejected foreign anchor must throw `errorInvalidArgument`; on iOS 27 a limited window for one type must not flip older entries; on iOS 26 pruning must still run for authorized types; the log order after a wake should show observers registered before the first read.

## Milestone 4: Recipes

### Plan

Deliverable: recipes as templates of raw ingredient weights, logged as frozen snapshots.

- Models: `Recipe` (name, servings, `ingredients: [RecipeIngredient]?`, timestamps) and `RecipeIngredient` (grams, `sortIndex`, `food: Food?` with a second inverse on `Food`, plus a frozen copy of the ingredient's name and per-100 g values so a deleted or refreshed food never changes the recipe). CloudKit rules unchanged.
- Maths in a pure, tested function: total raw weight, total nutrition, per serving; fractional servings on log.
- `Food.kind` gains a custom case now: custom foods are created in the Library with name and per-100 g values, since a recipe builder without them cannot express home ingredients. Custom foods are searchable in the add sheet alongside bundled results.
- Library tab: sections for recipes and custom foods, create and edit. Recipe builder: ingredient rows with inline gram fields, add ingredient via the existing search sheet, running raw total, servings stepper with the raw-weight caveat inline, live per-serving nutrition. Editing shows one line that logged servings stay unchanged.
- Add sheet: recipes and custom foods appear before typing (recents already do) and in search results by name match.
- Logging a recipe: serving count with fractions, snapshot equals per-serving times servings, `foodName` is the recipe name, the entry keeps an optional `recipe` relationship for display only. Repeat works from the snapshot.
- Health write path unchanged: the entry's snapshot is what is written.
- Tests: recipe maths, per-serving rounding, snapshot independence after editing, custom food search integration in the query builder.

Sandbox constraint unchanged: reviewed, not compiled.

### Review

Every SwiftUI, SwiftData and Foundation form used was verified against Apple's documentation; the recipe maths test expectations were recomputed by hand. Verdict on first pass: ready to sign off with three hygiene items, applied:

- A failed save on the shared main context could leave partial edits to be autosaved later; every catch now rolls the context back.
- A predicate error can echo the search text; it is logged privately.
- Repeat on a custom food that still exists recomputes from its current values, since the user may have corrected them; recipes and entries without a live food link repeat from the frozen snapshot.

Confirmed by review: frozen ingredient copies are the only input to recipe maths, so editing or deleting a food never changes a recipe or a past entry; relationships are declared once each with cascade on ingredients and nullify elsewhere; the Health write path is unchanged.

### Sign-off

Signed off 2026-09-21 subject to the first build. Watch list additions: the automatic store migration on a device with entries from the previous build; the edit button inside a form section header enabling reorder; a ternary producing an optional double in the quantity prefill; sort descriptor overload on model name key paths; the enum-case-with-nil pattern in the recipe writer.

## Milestone 5: Barcode

### Plan

Deliverable: opt-in barcode scanning with Open Food Facts lookup, permanent local cache, attribution, and a manual fallback. The app is complete without it.

- Settings gains a "Barcode scanning" toggle, off by default, with one line of explanation and the network note. The scanner button appears in the add sheet only when the toggle is on.
- `BarcodeScannerView`: a `UIViewControllerRepresentable` over `DataScannerViewController` recognising EAN-13, EAN-8, UPC-E and Code 128, confined to the module; availability gated on `isSupported` and `isAvailable`, camera authorization requested through `AVCaptureDevice`; every unavailable reason gets its own sentence.
- `OpenFoodFactsClient` actor: `GET https://world.openfoodfacts.org/api/v2/product/{barcode}.json?fields=product_name,brands,nutriments` with a descriptive User-Agent carrying the app name, version and a contact URL, a 10 s timeout, decoding only the eight nutrients from `nutriments` (`energy-kcal_100g`, `proteins_100g`, `carbohydrates_100g`, `fat_100g`, `saturated-fat_100g`, `fiber_100g`, `sugars_100g`, `sodium_100g` else `salt_100g` divided by 2.5), `status == 1` else not found. Sodium arrives in grams and is stored in milligrams. No images ever.
- Cache: a `Food` of kind `product` with `barcode`, `brand`, `source = "off"` and fetch date, kept permanently; a rescanned barcode hits the cache and never the network. Product foods are searchable and appear in recents like any food.
- Flow: scan, cache hit or lookup, then the existing quantity sheet with the product name and brand. Not found, offline or an error opens the custom food editor prefilled with the barcode so the user can type the label; that food is kind `product` with source `manual`.
- Attribution: product rows and the quantity sheet for a product show "Data from Open Food Facts" linking to the product page and the ODbL; the Sources screen adds Open Food Facts with licence and link.
- Privacy manifest `PrivacyInfo.xcprivacy` declaring no tracking, no collected data, the user-defaults accessed-API reason, and the Open Food Facts domain is not a tracking domain. Camera usage description added.
- Tests: nutriment decoding including salt fallback and unit conversion, missing fields, status handling, User-Agent composition, barcode validation (checksum for EAN-13 and EAN-8), cache-before-network via a fake transport.

Sandbox constraint unchanged: reviewed, not compiled.

### Review

Security and privacy weighted highest, since this is the first code touching the network and the camera. Verified: the barcode is validated to digits before it reaches a URL; the endpoint is https with a fixed field list and no App Transport Security exceptions, so a redirect to plain http is refused by the system; an ephemeral session with no cache, no cookies and a 10 second timeout, created per lookup; only the code leaves the device, only when the toggle is on, and only on a cache miss; camera access requested once, the scanner stopped after the first read and on dismissal, no frames stored; the privacy manifest declares no tracking and no collected data, which is defensible because the barcode services one request in real time and never reaches the developer. The GS1 check-digit and UPC-E expansion logic was cross-checked with an independent implementation. Findings resolved:

- Fetched nutrient values now carry the same plausibility bounds as manual entry, so a wrong or hostile record cannot reach Health unbounded.
- Response bodies are capped at one megabyte before decoding.
- The barcode and any error text that could echo it are logged privately.
- The camera area and the manual field have VoiceOver labels.
- Product names are capped, cookies are refused explicitly, and editing a fetched product marks it manual so the attribution stays honest.

### Sign-off

Signed off 2026-09-21 subject to the first build. Keep the App Store privacy label at "Data Not Collected" and name Open Food Facts in the privacy policy as the recipient of barcodes and the device's address for lookups.

Watch list: if the scanner shows nothing when started from the representable update, start it from the view controller's appearance instead; the scanner is simulator-unsupported, so the availability sentences, a real EAN-13, EAN-8 and UPC-E scan, airplane-mode fallback to the editor within the timeout, a cached rescan with no network activity, and the privacy manifest landing at the bundle root are device checks; a typed 12-digit UPC-A is sent in its 13-digit form and may need the 12-digit form as a fallback request if a real product misses.

## Milestone 6: AI estimation

### Plan

Deliverable: opt-in on-device estimation of a meal from a typed description on iOS 26 and from a photo on iOS 27, through one prompt and one draft-and-confirm screen. Never written to Health without confirmation. The app is complete without it.

- Settings toggle "Meal estimation", off by default, with the availability reason shown in words when the model is unavailable: device not eligible, Apple Intelligence off, model not ready. Gate order: `SystemLanguageModel.default.availability` first, then `#available(iOS 27, *)` for the photo path.
- `MealEstimate` as a `@Generable` structure: a list of items with name, estimated grams, and estimated energy, protein, carbohydrates, fat, saturated fat, fiber, sugar and sodium for that portion, plus a one-line note. `@Guide` descriptions and ranges keep the model inside plausible bounds.
- One instruction text and one prompt scaffold in a pure, tested builder; the text tier passes the description, the photo tier attaches the image with the same text. The session is created per request and discarded.
- `EstimationSheet`: description field always; on iOS 27 with the model available, a photo picker and a camera capture. Runs the request with a cancel button, then shows the draft: editable rows with name and grams and the eight values, per-row delete, totals, and a Log button that creates one entry per item with a frozen snapshot, no food link, and an `isEstimate` flag shown as an "Estimated" badge on Today. The photo never leaves memory and is not stored.
- Entry point: the add sheet gains an "Estimate" button when the toggle is on and the model is available.
- The Sources screen notes that estimates are produced on this device and are not from any database.
- Tests: prompt builder text, generable-to-snapshot conversion with bounds and unit handling, draft editing maths, availability reason wording.

Sandbox constraint unchanged: reviewed, not compiled. The image-attachment API is iOS 27 and must be verified against Apple's documentation by the implementer; if it cannot be verified, the photo tier ships behind its availability check with the best-documented form and is first on the watch list.

### Review

Every Foundation Models, PhotosUI and ImageIO signature was verified against Apple's documentation, including the iOS 27 image attachment inside a prompt builder, which follows Apple's own multimodal prompting article. Ready to sign off on the first pass with no findings beyond nits. Confirmed: gate order is model availability then OS version; instructions carry the no-advice, no-scoring boundary and user text appears only in the prompt, quoted and capped; every generated value is bounded twice, by guided-generation ranges and by the conversion clamps, and must pass an editable draft before logging; the photo lives in memory only and nothing leaves the device; one estimated entry per item, single save with rollback, then the unchanged Health mirror.

### Sign-off

Signed off 2026-09-21 subject to the first build. Watch list: a deprecation warning on the iOS 26 generation error type when building with the iOS 27 SDK, kept for iOS 26 devices; attachment initializer overload resolution on the iOS 27.2 SDK; text tier on an iOS 26 device and photo tier on iOS 27, each unavailable reason's alert text, cancelling mid-estimate leaving no draft or entries, camera capture orientation, and peak memory when decoding a large library photo.

## Design pass and photos

Status log for the work after milestone 6, all on the same review loop (implementer, independent reviewer, fixes, sign-off) and each screen its own commit.

- Today: date as title with the full date as subtitle, day chevrons and a calendar popover in the toolbar, a bottom Add food glass capsule, energy as a hero line over the other seven totals, one notice slot, one badge style, integer captions, Copy yesterday on an empty day.
- Brand kit: accent colour tangerine, the bite mark (one `Shape` defines it; icon script and SVG follow), rounded bold for the wordmark and the energy figure only, meal symbols, the About row. Recorded in `docs/DESIGN.md` under Brand.
- Add sheet: Scan and Estimate as list content, single-text captions. Quantity sheet: bottom Log capsule, select-all on focus, accessibility layouts, whole-gram captions.
- Photos: a `Photo` model with external-storage data, related to an estimate's entries, a recipe or a food; picker section shared by the estimation sheet and both editors; thumbnails and a viewer. This supersedes the milestone 6 note that the photo is never stored: it is stored only when the user keeps it, on the device, and never reaches Health.
- Estimates grounded in the bundled database: the model returns a name, a generic lookup term and a weight per item and no nutrient values at all; each item is searched in the database and the best hit supplies every number. The draft shows the matched food per row and opens the Add sheet in pick mode to change it; a row without a food cannot be logged. An estimated entry is now an ordinary entry with a food link and a database snapshot, carrying only the `isEstimate` flag. This supersedes the milestone 6 note that an estimate's values are the model's, typed into the draft and logged without a food link.

### Sign-off

Signed off 2026-09-22 subject to the first build. Watch list: `nonisolated struct BiteMark: Shape` and `nonisolated struct FlowLayout: Layout` under default main-actor isolation; `TextField("0", text:selection:)` overload resolution and whether select-all survives programmatic focus; the bottom bar rising above the keyboard on the Quantity sheet at the medium detent; `Section` header `Label` styling; `ContentUnavailableView` honouring the 56 pt mark; the `Photo` schema validating at container creation (one-to-one cascade from recipe and food, inverse from `Photo.entries`); `PhotoData.stored(from:)` ImageIO bridging; the thumbnail button not swallowing the row tap; and the icon rendering with the system's glass treatment.

## European sources

The bundle moved from USDA FoodData Central to Ciqual and the Bundeslebensmittelschlüssel. FDC's names are US-shaped and its composite dishes are not the ones on a European plate; the reader, its pinned downloader and its tests stay, and `--fdc` puts it back in one flag.

- Which sources ship is a command-line decision. `build` takes any combination of `--ciqual`, `--bls` and `--fdc`, at least one, and the attribution manifest names only what was read.
- Ciqual is read from its XML export, keyed by constituent code, with the unit taken from each constituent's own name so a renumbering or a unit change fails the build. `traces` and a `< x` detection limit are stored as zero with the food marked estimated; `-` stays null.
- The BLS is one wide table read through a new `table.py` that reads `.xlsx` (zip and XML, no third-party library) and delimited text alike, in either decimal convention and either common encoding. Version 4.0's real layout is 418 columns: a BLS code, a German name, an English name, and three columns per component. Columns are matched on the component code alone, which is what tells `NA Natrium [mg/100g]` from `NA Datenherkunft` and `NA Referenz`.
- Every BLS value column states its unit in its header, so the unit is read and converted by a stated factor rather than guessed at, and one the pipeline does not know stops the build. A cell that is neither a number nor one of the "not determined" markers is counted and read as unknown, because half a million cells should not be stopped by one of them.
- Schema 2 adds `foods.alt_names`, the same food's names in the source's other languages, and indexes it beside `name` in FTS5. Ciqual rows display their English name and are found by the French one; BLS rows display German and are found by English. Nothing else in the app changed: it selects named columns and matches without naming one.
- `python3 -m fooddb inspect <folder>` prints what a download contains — files or sheets, every column name, first rows, and what each reader would make of them — so a renamed column is diagnosed rather than guessed at.

The sandbox's egress policy blocks ciqual.anses.fr and blsdb.de, so both readers were written from each publisher's documented layout and `inspect` was the way to correct them against the real files. Ciqual parsed on the first run; the BLS did not, and its reader was rewritten around the published 4.0 layout and its per-column units. The fixtures now mirror that layout.

Still open: the curated popularity list is written against FDC's descriptions, so with FDC out of the build it matches nothing and search falls back to relevance alone until the list is rewritten against the real Ciqual and BLS names.

## Library, search and products

Work after the source change, on the same loop of implement, review, fix. Four things the app was missing rather than doing badly.

- **Finding a food is its own screen.** The old sheet drew the list, then slid a search bar in over it and took the navigation bar with it, then raised the keyboard: three movements for one intention. `FoodSearchView` puts the field in the layout from the first frame and is presented full screen. `.searchable` is gone from this screen; it stays on the Library, where the list is the point and the search is not.
- **Picking ingredients is one trip.** `AddFoodMode.pick` gained `multiple`: the screen stays open, clears the field, says what it has gathered and closes on Done. The estimate draft uses the single form for changing one row's food, the recipe builder the multiple form.
- **Tags.** A `Tag` model, many-to-many with `Recipe` and `Food`, edited as chips in both editors, filtered by chips in the Library and matched by the search on both screens. Flat rather than a hierarchy: a folder forces one home per item and then has to answer where porridge lives when it is both breakfast and meal prep. Names are resolved case-insensitively at save time, because a CloudKit-ready schema cannot hold a unique index, and a tag whose last use goes is deleted with it.
- **An estimate can be corrected and kept.** The draft takes an extra item from the same search screen, and saves its matched rows as a recipe through the recipe editor, prefilled with the photo if it is being kept and the typed description as the name. Unmatched rows are left out, as they are for logging.
- **Products by name.** A second opt-in, separate from scanning because a barcode and a typed query are not the same disclosure. Full text is answered by `search.openfoodfacts.org`, which is the only Open Food Facts service that does it; a hit is a name, a brand and a code, and the product the user picks is then fetched by barcode through the flow a scan already uses, so it is cached and attributed identically. The envelope reader accepts both `hits` and the older `products`, so moving between endpoints is a URL.

- **Two groups of results.** The Library, the bundled database and Open Food Facts were three sections. They are two now: "Yours" first, ordered by what was last eaten and then by match, and "Other foods" below it, where the bundled tables and Open Food Facts are read as one list ranked by `SearchRelevance`. Each source's own score is discarded — bm25 and Elasticsearch's relevance are not comparable — and every candidate is rescored from the query and its own text, including its brand and its tags. The only weighting left is a small penalty on a crowdsourced row; the bonuses the user's own foods used to carry went with the grouping, since those rows no longer compete with anything. A product already saved in the Library is dropped from the network half, so the same barcode cannot appear twice. Pills appear only under "Other foods", the one list where the answer varies. `SearchResultRow` is the only food row in the app now and `ChoiceRow` is gone.

Watch list for the first build: the full-screen cover over a sheet in the estimate draft and the recipe editor; `@FocusState.Binding` into `FoodSearchField` and whether the field keeps focus after a multiple pick clears it; `.safeAreaBar` with conditional content; the single sheet slot with `onDismiss` handing a typed-in product on to the Quantity sheet; SwiftData's many-to-many between `Tag` and both `Recipe` and `Food` validating at container creation; whether the search index actually returns `nutriments` for a hit, which decides whether a product row shows its energy before it is fetched; and how the merged list reads when the products land a second after everything else, since that is the one moment rows move under a thumb.

## Camera

Visual search was removed rather than shipped: the camera moved into the primary
input, where the composer's text field attaches a picture to the model prompt.

## iPad

One target, both device families: `TARGETED_DEVICE_FAMILY = "1,2"`. The iPhone keeps its portrait lock through `INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone`; the iPad gets all four through the `_iPad` key, which multitasking requires. The generated scene manifest and launch screen were already in place, so nothing else in the project had to move.

Every framework the app needs is on iPadOS and was checked rather than assumed: HealthKit since iPadOS 17, when the Health app arrived there; `DataScannerViewController` since iPadOS 16; Foundation Models on iPadOS 26. So this is a layout change, not a port.

- `ReadableColumn` caps a read-down list at 700 pt and a tapped control at 420 pt, centring both. Every measure is wider than any iPhone, so the modifier is a no-op on one by construction — which is the point: there is no second layout to keep in step.
- Applied to the food search field, the search results, the recents and the Add food capsule. The inset-grouped lists on Today, in the Library and in Settings are left full width, because that is what Apple's own apps do with them and they are already shaped for the iPad.
- Six previews at 1024 pt, one per screen whose measure the cap governs, so the thing this change is about is visible in the canvas rather than only on a device. `RecentsList` had no previews at all; it has four now.

Watch list for the first build: whether a capped `List` frame leaves the plain-style separators and scroll indicators where they belong; the full-screen search cover on an iPad, which is a lot of display for one column and may want to be a sheet in the regular size class; the barcode scanner in a centred iPad sheet, which is a small window for a camera; and `presentationDetents` on the Quantity sheet and the day picker, which an iPad ignores in favour of a centred card.

Not done: a `NavigationSplitView` for the Library, and a second column on Today. Both are redesigns rather than an iPad pass, and the app should be looked at on a real iPad before either is decided.

## The model is the input

Revision 5. The composer's parser is deleted and a model reads the line instead. Written
across several rounds with the app running on a device between them, which is new for this
log: the earlier entries were reasoned, this one was partly driven by what the app actually
did when used.

### What the parser could not do

It split on commas and read a quantity off the front of each fragment. That covers a list
and nothing else. Two reports from the device settled it, and they point opposite ways:
"yogurt with bananas, seeds, peanuts" searched for the whole phrase "yogurt with bananas"
and found nothing, while "spaghetti bolognese" matched a prepacked ready meal instead of
breaking into parts. Splitting on "with" fixes the first and breaks nothing about the
second; keeping dishes whole fixes the second and breaks the first. There is no rule that
answers both, because the difference between them is knowledge about food, not grammar.

So: `LineParser` and its 188 lines of tests are gone, nothing is interpreted while typing
— the chips that showed what the field had understood went with it — and `ResolvableItem`
replaces `ParsedItem` as what a model names rather than what a scanner cut out.

### Two providers behind one prompt

`EstimationInput` is text, or a photo with whatever words came with it. `MealEstimate` is
what comes back. Two things can answer:

- **Apple Intelligence**, through the `LanguageModelSession` the photo module already used.
- **An OpenAI-compatible endpoint** the user names: base URL, model, key. Chat completions
  with a JSON schema, falling back to `json_object` where a server rejects the schema;
  vision as a base64 data URL; photos behind a second switch, because plenty of such
  servers cannot read an image and a picture of a kitchen is a larger disclosure than a
  sentence about lunch. The key is in the keychain, device-only, never `UserDefaults`, and
  nothing logs the key, the body or the user's text.

The endpoint exists for a reason beyond availability: a larger model is simply better at
breaking a named dish into the foods it is made of, which is the one job this prompt has.

### The screen you sign off on

It was a sheet and is now pushed. A sheet cannot present what its own presenter owns, so
the food picker opened from it was being put up by Today *behind* it — which is why
changing a food and choosing a weight had both been broken since the sheet existed. Pushed,
the screen is topmost and its own controls work. The amount became its own control rather
than text inside the button that changes the food, because one row answering two questions
with one tap can only answer the wrong one.

Three further things it now does. The model says which meal this is and the timestamp
follows the slot rather than the hour of typing, so oats described at nine in the evening
are a breakfast logged at eight and never a time in the future. A food the model missed can
be added from search, which closes the one hole that made a whole line disposable: a model
naming four of five things on a plate used to leave nothing to do about the fifth. And a
food the user picked says "You chose this" instead of "Matched by name", which had been
shown under every row whose food had been corrected.

### What "spaghetti bolognese" needed

The report was that it produced "spaghetti" and "bolognese" and matched neither. Three
independent faults, each measured against the built database:

- The prompt said "list each distinct food or drink as one item", which read as the words
  of a dish's name. It now says a dish named rather than described is the foods it is made
  of, with that meal as the worked example, and defines `lookupTerm` as the wording a
  composition table uses: "Pasta, cooked", not "spaghetti".
- `spaghetti` retrieves spaghetti *squash* at 32 kcal and the prepacked row, so declining
  that shortlist was correct. There is no row called spaghetti.
- A good decomposition would still have blocked. "Every word of the query is present" was
  worth 0.3 against a 0.42 bar for showing a row at all, so `minced beef` scored 0.352 and
  seven of twelve generic two-word terms blocked the log. At 0.44 three block, and no bare
  noun's settled answer changed across twenty-two of them.
- `rolled oats` retrieved nothing at all, because the index ands a term's words together
  and the tables say "Oat flakes". A per-token fallback, used only when the whole term
  finds nothing worth showing, settles it: Oat flakes at 1.088, Chicken grilled at 1.084,
  Wholemeal bread at 1.132.

### Two faults from use, fixed after

**The keyboard came back by itself after a log, over the field, with no way out.** The field
kept focus while the model answered, so it still held the keyboard when the sign-off screen
pushed over it; UIKit hands the keyboard back to whatever held it when a pushed screen pops.
SwiftUI, never told of a focus change, then laid the bottom bar out as though no keyboard
existed — so the keyboard stood over the field and over the only control that dismisses it.
Sending now resigns focus first, through one function every path uses, and the dismiss
control sends a plain `resignFirstResponder` as well, for the case where the field holds the
keyboard while SwiftUI believes nothing is focused.

**The text field had been in a `.safeAreaBar`**, which does not move for the keyboard; it is
a `.safeAreaInset` now, which does. That is the same fault as the one above seen from the
layout side, and both are why the control whose point is being within a thumb's reach kept
ending up underneath a keyboard.

### Not verified

No Swift compiler in this environment, so every Swift claim here is reasoned, not built.
What was verified mechanically: the brace and paren balance of each changed file, every
`Type.member` reference against the type's own declarations, and each retrieval figure above
against the real 1.8 MB database through a Python mirror of the scorer.

Watch list for the next build: the pushed sign-off screen presenting the food picker as a
sheet while a `Menu` is open on a row; `.safeAreaInset` holding the composer above the
keyboard with the suggestions card expanded; the keyboard not returning after a log, which
is the fix above and the thing to check first; adding several foods in one visit to the
picker, where the row count grows behind an open sheet; and the remote estimator against a
real endpoint, which has never run.

## A generated project

`Omnomnom.xcodeproj` is generated from `project.yml` by XcodeGen and is no longer in git.
A `.pbxproj` is a graph of random identifiers, and both project-level mistakes this build
has made were hand edits to one: a widget whose `NSExtension` dictionary could not be
expressed by the `INFOPLIST_KEY_` settings that were meant to generate it, and the plist
that replaced it having to live outside every target folder so a synchronised folder would
not copy it in as a resource. Neither is visible in a diff of the project file. Both are one
readable line in the spec.

- **The folders stay synchronised folders.** `type: syncedFolder` keeps the Xcode 16
  behaviour the project already had, so the spec lists no source files and adding one needs
  no regeneration. It also keeps `Resources/foods.sqlite` working: the pipeline builds it,
  git does not carry it, and a project that enumerated files would either miss it or have to
  be generated after every pipeline run. XcodeGen 2.46 is the floor, because a folder shared
  by two targets — `OmnomnomShared`, in the app and the widget — became one folder rather
  than two in 2.45.4.
- **Nothing is inherited from the tool.** `settingPresets: none`, so every warning flag and
  every concurrency setting is written in the spec rather than supplied by whichever version
  of XcodeGen ran. A build that changes behaviour when a tool is updated is not worth a
  shorter file.
- **Verified by comparison, not by running it.** XcodeGen needs a Swift toolchain, which
  this environment has no way to install, so the spec was checked by computing the effective
  build settings for all six target configurations from the YAML and diffing them against
  the ones in the checked-in project: 0 differences. What that does not check is the parts
  XcodeGen assembles itself — the embed phase, the synchronised groups, the scheme — which
  were read out of its source instead.
- **Two cosmetic things are not reproduced** and are listed so they are not mistaken for
  faults later: `CreatedOnToolsVersion` per target, and `TestTargetID` in the project's
  target attributes. The test host is set by `TEST_HOST` and `BUNDLE_LOADER`, which is what
  the build actually reads; `TestTargetID` is template metadata for Xcode's own UI.

One-time setup, and then it is `xcodegen generate` whenever `project.yml` changes:

```sh
brew install xcodegen
xcodegen generate
```

## The fourth rung, and what a step measures from

Two of the four loose ends written down with revision 5, closed. Both were the same kind of
fault: a thing the plan described, implemented in one place and not reached from the other.

**A product can answer for a food the tables do not hold.** `LineResolver` had taken a
`products` closure for the fourth rung since it was written, and nothing ever passed one, so
a line naming a particular jar dead-ended on a row with no food whatever the product opt-in
said. `ProductRung` is that closure: the term goes to the search index the Add screen
already uses, the hits are ranked by `SearchRelevance` exactly as that screen ranks them,
and the best one is fetched by barcode through the flow a scan uses, so it is cached and
attributed identically. Today passes it only when the product-search opt-in is on, which is
the switch that already governs sending a typed query abroad.

Three deliberate limits, because this rung sends what the user typed to a service abroad and
answers with a stranger's entry:

- **The tables are always tried first**, and the rung is reached only when they answer
  nothing at all. Offline, licence-clean and analytically measured beats crowdsourced, and a
  test fails if the rung is asked for a food the tables answered.
- **One fetch, not several.** The row reads the best hit, so every further candidate would
  be a second request abroad for something nothing looks at.
- **A hit whose name and brand do not hold every word of the term is not a candidate.** The
  index matches more than this app asks it to — categories and labels among them — so it
  answers a narrow term with a wide list. The bar is `SearchRelevance.everyToken` less the
  penalty a crowdsourced row carries, which is the rule the bundled index applies by
  construction, since its query ands a term's words together.

A product row is also `probable` at best, never settled, and it no longer claims to have
been checked. The validator chooses among rows the *tables* returned, so a product has never
been through it — and `RowOrigin.product` had a "Checked, Open Food Facts" wording that only
became reachable once the rung was wired, at which point it would have been a sentence about
something that did not happen.

**A step now has something to measure from.** `FoodChoice(bundled:)` is built from the table
row alone, so its `lastAmount` is always nil, and the resolver never read the stored `Food`
the way the Quantity sheet always has. A food logged ten times through search therefore
reached the sign-off screen with the model's estimate and no Less or More at all: the
buckets were arriving once a food had been *recalled* as a phrase, not once it had been
eaten. One read of `Food.lastGrams` fixes it, in the two places a row's food is decided — the
best match, and a food the validator moved the row to.

The amount is untouched by that read, which is the distinction the whole thing rests on: the
model's weight is what was eaten today, the stored amount is what this person usually has,
and stepping down from "a big plate" has to mean less than usual rather than less than big.

Tests: six on the bar a product has to clear, which is pure and needs no network; five on
the rungs, including one that fails if the product rung is asked for a food the tables
answered, and one that proves a food never eaten still offers no steps.

## A comma was the difference between a match and a blocked row

From a report that "a slice of Margherita pizza" showed as "pizza" with nothing behind it.
The tables hold two good rows for it — *Pizza margherita (with tomato sauce, mozzarella)* at
238 kcal and *Pizza, cheese and tomato (Margherita), prepacked* at 224 — so nothing was
missing from the data. Three faults, measured against the real 10,440-row database.

**A query was split on spaces while a name was split on punctuation.** So a query word
arrived carrying a comma, no name word could begin with it, and the bottom tier of the
scorer — every word of the query present — never fired. The prompt asks the model for the
wording a composition table uses, which is full of commas, so this was the common case
rather than an edge:

| Term | Against | Before | After |
| --- | --- | --- | --- |
| `Pizza, Margherita` | Pizza margherita (with tomato sauce, mozzarella) | **0.000** | 0.493 |
| `Pizza Margherita` | the same row | 0.850 | 0.850 |
| `Oats, rolled` | Oat flakes | **0.000** | 1.088 |
| `Banana, raw` | Banana raw | 0.532, and it chose *Plantain banana* | 0.825, settled |

`FoodQuery.words(of:)` is the one definition now, used by the scorer for both sides and by
the FTS expression. The expression had the same fault with a second consequence: the plural
heuristic cannot tell that `"Oats,"` ends in an "s", so the singular form that reaches "Oat
flakes" was never searched, and `"Oats,"* AND "rolled"*` retrieved nothing at all.

**The fallback was answering with whatever the table had cooked.** This is the worse half,
and it was mine: when the whole term finds nothing worth showing, each word is tried alone
and the best answer kept. "Cooked" names 390 rows, and the curated prior lifted the best of
them above everything:

| Term | What it logged, settled and unasked |
| --- | --- |
| `Pasta, cooked` | Fish, cooked (average) — 0.887 |
| `Rice, cooked` | Fish, cooked (average) — 0.887 |
| `Oats, rolled` | Rolled pork roast with sauce — 0.832 |
| `Pizza, margherita, prepacked` | Hummus, prepacked — 0.920 |
| `spaghetti bolognese, cooked` | Fish, cooked (average) — 0.887 |

Two rules bound it. A word saying how a food was prepared or packed never carries the
fallback, and the list of fifteen such words is the app's own vocabulary rather than a guess
about language — the prompt asks the model to say "cooked or raw where it matters", so these
are the words it asked to be given. And a narrowed match is never settled: the app threw
part of what was said away to get an answer, so the row is marked for a glance however well
the one word scored. The validator can still settle it afterwards, which is the right order.

After both: `Pasta, cooked` → *Spinach-filled pasta squares cooked*; `Rice, cooked` → *Rice,
red, cooked, no added salt*; `Oats, rolled` → *Oat flakes*; `Pizza, margherita, prepacked` →
*Pizza, cheese and tomato (Margherita), prepacked*; `spaghetti bolognese, cooked` →
*Bolognese sauce with beef mince*. Every one of twenty-two bare nouns answers exactly as it
did before, which is the check that matters most: the fix must not move what already worked.

Tests: six on what a word is and which words are preparation words, two on a comma costing
a tier rather than a match, and four on the resolver — the pizza term itself, the fish case
with the curated prior that made it win, the cap on a narrowed match, and a whole-term match
still settling so the cap is about narrowing rather than about distrusting the tables.

## Six drawings, one language, and the three things it asked for

The design was settled by drawing it six ways rather than by arguing: a stream that logs on
send, a board of tiles that never needs the keyboard, a page you write the day onto, then
the chosen combination of the three, then the same flow with charts, then three
typographic branches of that. The boards for the one that won are in `design/mocks/`, six
files covering every screen the app has — thirty-three of them, from first run to the
widget.

What it changed, in one line each: grey cards became warm row groups, the system rounded
face took every title and figure, composition took the headline from the calorie total,
and the tab bar kept its icons while the composer appeared on all four tabs. `DESIGN.md`
holds the decisions and the two contrast corrections that came out of measuring them.

Three things the drawing needed that the app did not have.

**What a day was made of.** `MacroComposition` reads protein, carbohydrate and fat out of
a `Nutrition` at 4, 4 and 9 kcal per gram and carries whatever they do not account for as
its own band. On the typical day drawn on the boards that is 252 + 672 + 369 against a
stated 1,320, so 27 kcal belongs to nothing — and it is drawn rather than divided into the
three that are known. Where the macronutrients claim *more* energy than the row's own
figure, which rounding alone causes, the energy figure gives way instead: shrinking a
measured gram to fit it would be inventing a correction. Either direction, the shares sum
to one.

**What counts as answering a meal.** `DayAnswers` unions the slots holding an entry with
the slots the user said held nothing, and that second set is the only new storage in any of
this: `DayRecord.skippedSlotNames`, strings so the attribute stays an array of a primitive.
It is needed because the absence of an entry cannot tell a meal nobody ate from a meal
nobody recorded — and without it the ring in the mark could never close on a day someone
genuinely skipped dinner.

**The run.** `DayRun` counts consecutive answered days and needs no storage at all:
`SamplingCadence.asks(about:)` already decides which days are asked about, and `DayState`
already says whether a day was answered. Three rules keep it from punishing a normal week.
Days the cadence does not ask about are stepped over rather than failed, which is what
makes three days a week usable. A day still open neither extends the run nor breaks it, so
today is never a loss and yesterday has until tomorrow. And a gap ends the run in hand
without touching the best one, which stays on screen beside it. `complete` and `assumed`
both answer a day; `partial` does not, because entries existing is not the user saying that
was all of it.

Tests: thirteen on the composition, including both directions of the energy disagreement
and the difference between a nutrient that is zero and one that has no figure; fourteen on
the run, covering today, the grace day, a gap, the cadence stepping over four days at a
time, and a window reaching into the future; seven on the answers.

One stale test went with it. `FoodQuery.ftsMatchExpression` stopped escaping quotes when it
started building terms from `words(of:)`, which splits on everything that is not a letter or
a number — a quote is a separator now and cannot reach a term at all. The test still
expected the doubling, so it was asserting behaviour the code had already dropped. It now
asserts the property that replaced it.

## A hundred written lines, and the fallback that was inventing answers

The ten lines the design was drawn against all resolved sensibly, so the set was widened to
a hundred — bare lists, full sentences, shorthand, amounts in words, dishes, loanwords,
vague gestures at a meal, typos, dictation, drinks and packaged things — and measured item
by item against the real built database. A hundred and seventy-seven items. Forty-five of
them went down the fallback that looks a term up by part of itself, and a dozen of those
came back confidently wrong:

| What was searched | What answered | Score |
| --- | --- | --- |
| `yogurt, natural` | Natural mineral water | 1.10 |
| `baked beans in tomato sauce` | Tomato raw | 1.12 |
| `croissant with chocolate` | Chocolate | 1.35 |
| `tonic water` | Watermelon raw | 0.85 |
| `beer, lager` | Beer ham | 0.88 |
| `wholemeal pasta, cooked` | Wholemeal bread | 1.13 |
| `potato crisps, salted` | Potatoe peeled, boiled | 1.06 |
| `spaghetti with bolognese sauce` | Asparagus boiled (without sauce) | 0.89 |

Every one of those scored above the line a row needs to be logged without being questioned,
because a single word of a term scores perfectly against a row that is a different food —
and the fallback was scoring against the surviving word rather than against what was said.
The last row is the worst of them: a row naming the *absence* of the thing asked for.

Three rules replaced trying every word.

**The fallback sees only the head phrase**, which is the term up to its first comma or
preposition, with preparation words dropped. Three shapes of wording and one rule covers
all of them: a composition table inverts the compound, so the head is first and the comma
separates it from its qualifiers; a plain compound puts the head last; and a prepositional
phrase qualifies whatever preceded it. So "yogurt, natural" is about yogurt, "wholemeal
pasta" is about pasta, and "croissant with chocolate" is a croissant.

**Combinations of that phrase are tried largest first**, so "rye bread, toasted" asks for
rye bread before it asks for bread. Searching the words alone answered it with *Bread,
bagel*.

**A candidate has to be what the word names**, which means the row's own first word, whole.
Matching a word anywhere in a name is what let "sauce" answer with the asparagus row;
prefix-matching the head is what let "water" answer with a melon.

Measured again afterwards: eighteen of a hundred and twenty distinct terms changed, all but
two of them repairs, and every one of the twenty-two bare nouns and all five of the terms
recorded in the entry above answer exactly as they did. The cost is two rows that now block
and ask instead of guessing — "lasagne with beef" and "spag bol", neither of which the
bundled tables hold under a head the model offered. Blocking is the honest answer there and
the sheet is built for it.

Two of the hundred lines were the harness's fault rather than the app's, and the correction
matters more than the finding. "Spag bol" and "the rest of the lasagne" were given the
lookup terms "spaghetti with bolognese sauce" and "lasagne with beef" — and the prompt
already forbids exactly that, in as many words: a dish named rather than described is to be
broken into the staples it is made of, and `lookupTerm` is never a dish name. Measured again
with items a model obeying that instruction would return — pasta, minced beef, tomato puree,
onion, olive oil — both lines resolve completely, and the fix above costs no blocked rows at
all rather than the two first reported.

What it does leave open is a handful of mediocre-but-marked rows, all of them underlined
rather than silently logged: "peanut" answers with *Peanut butter*, "minced lamb" with
*Minced meat soup*, and "aubergine, cooked" with *Aubergine salad with lemon marinade*. The
first is the clearest: a prefix match on a compound beating the plain ingredient. None of
them is a wrong row logged quietly, which is the line that matters, and all of them are
candidates for the next pass at the scorer.

Tests: fourteen on the head phrase and the function words, five on whether a word answers a
row's head — the asparagus row and the melon among them — and five on the resolver, one per
fault above, each failing before the change.

## Sending is logging, and the way back from it

The sign-off screen stood between every line and the log. It is gone from that path. A line
with a food behind it is written the moment it is understood — `ComposerModel.submit` logs
rather than presents — and what used to be approval is now an offer to take it back.

`LoggedLine` is what makes that defensible rather than merely quick. It holds the identifiers
of the entries one send created, the count of rows worth a look, and the sentence the bar
reads; `EntryLogger.undo` puts each of them through the same delete the swipe action uses, so
Health is mirrored first and an entry it will not release stays visible instead of vanishing
here and surviving there. The offer sits above the field, on no timer. The transient banner
goes after four seconds, which is the wrong shape for the only way back from a write nobody
confirmed, so this one stays until the next send, a change of day, or a dismissal.

What the line taught is deliberately left alone. A phrase records that this wording means
these foods, which taking the log back does not make untrue — and a line undone because the
reading was wrong is re-sent corrected, which `Phrase.remember` replaces those items on.

A line is rarely all or nothing, so the rows split. `LineResolution.placed` is everything
with a food and no question over it, including a probable match — logged and marked, never
held back, which is the whole point. `LineResolution.unplaced` is what nothing matched or
matched too weakly to assert on someone's behalf, and it is a question beside the field
rather than a gate in front of it: four foods of five in the day beats none of them, the
same rule `logLine` already followed row by row. The sign-off screen survives as the answer
to that question alone, opened when the user asks for it.

One thing this loses, stated plainly: an outstanding question is held in memory. Quit with
one open and the words that raised it are gone. Nothing was logged for them, so the record is
not wrong — only unanswered — and making it survive a launch means storing a resolved row,
which is a schema decision and not a detail to slip in here.

Tests: sixteen, over the split, the counts, the sentences and their singulars, that an
implausible amount is still written, and that a second question about a line takes a fresh
identity rather than looking to the navigation stack like the first one still being up.

## The mark, and answering it

Logging on send puts a row in the day that the user never approved. The mark is what keeps
that honest: a row whose food the app chose rather than the person carries an underlined
name — as a word a spellchecker is unsure of is underlined — and under it, what the line
actually called it. "Matched from “oats”" beside *Oat flakes* is unarguable; the same mark
beside *Oat drink* is obviously wrong, and only the person can tell which it is.

Two new columns carry it. `LogEntry.wording` is what the line called the food, kept for
every line-logged row whether or not the match was sure, because a settled match that is
wrong is exactly the case where the app has to be able to show what it was answering.
`LogEntry.guessed` is the mark itself, set from `ResolvedRow.isSettled` at log time. Both
default, so every entry logged before today reads as what it was: nobody guessed it.

The mark is a button and leads to one sheet with three answers. Yes, that's right — which
takes the mark off and touches nothing else, since the mark was never part of what Health
holds. Or one of the other foods the word could have meant, which is deliberately the same
shortlist the guess came from (`LineResolver.candidates(for:)` runs the same search, head
phrase and all) rather than a fresh one that might not even contain the row being corrected.
Or none of them, and the search screen opens.

Correcting a row is written as a delete and a fresh log rather than as an edit in place.
Every kind of food — bundled, custom, product, recipe — already reaches an entry through
one path, and a second path that rebuilt a snapshot from a choice would be that code again
with its own way of being wrong. The delete goes to Health first, so a correction never
leaves two versions of a meal there, and if Health will not release the old samples nothing
is logged and the row stays as it was. What the line said is carried over, and so is how the
entry came to exist: it was still typed, and a day's coverage must not change because one
row was corrected.

The amount is the one judgement in it. The number on the row is the number logged — 45 of
whatever it turned out to be — because that figure is already in the food's own unit and is
a fact about this meal, where what this person usually has of the new food is a fact about
other meals. Servings are the exception in both directions: a serving of one recipe is not a
serving of another and is certainly not 45 of anything, so a recipe at either end falls back
to what was last had of it, or to one.

Tests: thirteen, over what the mark says with and without words behind it, what the question
asks, and every branch of the amount a correction logs.

## A tray, so four foods cost one visit

Logging four foods by searching meant opening the search screen four times: a tap opened the
Quantity sheet, the sheet logged one food and closed the screen, and the second food started
from the beginning. Every row in log mode now carries a plus, which puts that food in a tray
and leaves the screen exactly where it is, field cleared for the next word.

The tray is a `LineResolution` of `chosen`, settled rows, which is the whole reason this cost
so little: the screen a typed line is signed off on already edits amounts, adds a food,
removes a row and picks the meal and the time, so it is the tray's screen too, and
`EntryLogger.logLine` is the one path both reach Health through. The bar at the bottom says
what is in the tray, what it comes to, and that none of it is logged yet — in those words,
because a row that goes quietly into a tray looks exactly like a row that was logged.

One rule holds while a tray is up: nothing is logged until Log is tapped. So a row tap, which
opens the Quantity sheet and logs the one food as it always did, adds to the tray instead
once the tray has something in it. The alternative was a sheet that logged one food and
closed the screen on four others the user had gathered.

No undo is offered afterwards and none is owed: Log *is* the sign-off here, which is what the
tray is for. The typed line has no sign-off and that is why it has `LoggedLine`.

A tray teaches the app nothing. A phrase is remembered under a key made from the line that
was typed, there was no line, and `PhraseKey.normalise("")` is `nil` — so `logLine` writes
the entries and remembers nothing, which is right. Nobody said anything.

Row editing moved onto `LineResolution` itself (`replace`, `append`, `remove`) rather than
being written twice, once in the composer and once here. A row whose identity is not in the
line is ignored rather than appended, which is the guarantee that a late callback from a
screen the user has left cannot put a food back into a meal they have moved on from.

Tests: eleven, over what the bar says with one food, several, and a food the tables hold no
energy figure for, every row edit including the late callback, and that nothing gathered
blocks or carries a mark.

## The field over the tab bar, the mark on Today, and the run

Three things that only make sense together.

**The field belongs to the app, not to Today.** It is a `safeAreaInset` on the `TabView`
now, so it is on all four tabs, and one `ComposerModel` in the environment backs it — a
line half typed survives a change of tab, and an Undo stays reachable from wherever the
user went next. Today is where you look at what you ate, which is a different activity from
saying what you ate and was in the way of it.

What that cost: `TodayBottomBar` is down to this screen's own notices, `TodayViewModel` lost
the undo offer to `ComposerModel`, and the sign-off screen is presented rather than pushed,
because three of the four tabs have no stack to push onto. The day a line goes into is held
on the composer: Today sets it to whatever is on screen, since it holds the app's one day
selector, and leaving Today sets it back to today, which is the only day the other three
tabs could mean. `LineResolver.app(context:repository:estimationEnabled:productSearchEnabled:)`
is the one place the four rungs are wired from, since both the field and the widget path
need them.

**The mark is Today's headline.** `DayHeadline` puts the ring-and-square beside one
sentence — "3 of 4 meals", and under it what is still owed, named rather than counted,
because "breakfast and dinner" is something to act on and "2 unanswered" is only a score.
`DayAnswers.sentence` is that count and it is a count: no percentage of a day appears
anywhere, for the reason in `DayState.note`. Under it, the composition bar and its legend,
drawn from exactly the figures the totals row below shows — what other sources wrote to
Health for the day included, or the shape would disagree with the row under it. The legend
drops its gram figures there, since the totals are directly beneath and the same number
twice on one screen reads as two different numbers.

**Trends became Shape.** A trend is a line going somewhere, which is a thing to be pleased
or displeased about; the shape of what someone eats is a description. Nothing about the
charts changed. What was added is one row at the bottom leading to the run.

**The run has a screen.** `RunModel` reads it locally and cheaply — the run counts days
*this app* was told about, because that is what answering means, which is a deliberate
difference from Shape, which reads Health and says so. Two figures, the current run and the
best, the best never touched by a gap. One prompt, for a day still inside the grace window,
and it says what closing the day claims about the food rather than what it does for the
streak: a run is not a reason to assert something untrue about a Tuesday. Then the month as
marks, seven across so a week is a row, with nothing drawn after today — a square for a day
that has not happened looks exactly like a day someone missed.

The window is two years, bounded so the fetch behind it cannot grow without limit, which
makes "your best" a fact about the person rather than about the window.

Four places where the code differs from the boards are now written down in `DESIGN.md`
rather than left to be discovered: Today keeps its eight totals and the user's choice of
which three are large, the composition bar is on Today rather than Shape, counts are digits,
and an unanswered meal is a faint ring segment rather than a dotted one.

Tests: twenty-two, over the headline's sentence and its note, the run row's wording with a
broken run and with none at all, the month the grid draws at its edges, and what a cell says
aloud including a day the cadence does not ask about.

## Every gap in one queue

The last screen the boards asked for: loose ends. One card per thing left to answer about a
day, each with its fix on it, reached from a row under Today's headline that is there only
when there is something in it.

`LooseEnd.items(rows:answers:usual:isAsked:isClosed:)` is where the rules are and it knows
nothing about the store. Four kinds, in the order they are worked: an unanswered meal, which
is the only card that changes what the day says it holds; a row whose food the app chose; a
nutrient the day's total is a floor for; and the day itself, which only appears once there
is nothing else owed — closing it would otherwise claim the day holds everything eaten while
the cards above it say it does not.

Three rules hold it to being a queue rather than a chore list:

- **Nothing in it is a percentage and nothing fills a bar.** A count goes down, the mark's
  ring closes, the run holds. There is no progress to be at 60 per cent of, and a test
  asserts that no card and no heading can carry a `%`.
- **Every card's second answer costs nothing.** "Nothing tonight" closes a meal without
  inventing food; "it is right" closes a question about a match without changing anything;
  "leave it" drops a missing figure for the visit. A queue where every exit writes something
  is a queue that teaches people to invent food.
- **A day the cadence does not ask about raises nothing.** The cadence decides when the app
  speaks, and this is the app speaking.

A missing figure is one card per nutrient and not one per row: 666 of the 10,440 bundled
rows are short of something, so a card per row would bury everything else on an ordinary
day — and the day's total is what a floor is a floor of, not the row. Where exactly one row
is short, the card carries that row and offers to swap it for a fuller one; where two are,
it offers nothing but the words, because there is no single answer.

"Leave it" is remembered for the visit and not stored. A dismissal that outlived the day
would be a standing instruction never to mention a nutrient again, which is not what the
button says.

Offering a slot's usual meal moved to `EntryLogger.logUsual(_:for:on:resolver:)`: the
proposal card on Today and this queue offer the same thing in two places and must not do it
two ways.

Tests: eighteen, over every kind of card, the order they come in, the day the cadence is
quiet about, a figure missing from one row against two, and that nothing anywhere in the
queue can be a percentage.

## Sending shows the parse, every time

A reversal, from use rather than from argument: the field no longer logs. Sending resolves
the line and puts the sign-off screen up, and that screen is the only thing in the app that
writes a typed line to Health.

The reason is the honest one. On-device estimation is not good enough to be trusted
silently. What a model made of a sentence is a reading, not a record — it picks the foods,
it estimates the weights, it decides which meal this was — and all three of those are
guesses that land wrong often enough that somebody has to see them. So all three are shown,
all three are changeable, and nothing reaches Health until the button is tapped. "Four foods
of five in the day beats none of them" was the right rule for a matcher that is right most
of the time, and the matcher is not that yet.

What that removed: the split of a line into what could be written and what could not
(`LineResolution.placed` / `.unplaced`), and the bar over the field that asked about the
remainder. A row that blocks blocks the line again, which is what `canLog` already said and
what the screen was already built to carry — three tiers in a sentence above the button
rather than a fourth surface somewhere else. The field keeps what was typed until the screen
logs it, so backing out is never how a sentence gets lost.

What stayed, and is worth keeping: `LoggedLine` and the undo. Two paths still write in one
tap and nothing else — a widget tap, which is the tap, and accepting a slot's usual meal —
and for those the offer is the only way back. After a line signed off it is a courtesy
rather than a necessity and reads the same either way.

The screen is presented with a navigation stack of its own rather than pushed, which is the
other change. Pushing was chosen because the food picker has to come up *over* the sign-off
screen, and a sheet presented by Today could not host it. A sheet carrying its own stack
has the property pushing had — it is the topmost thing — and unlike pushing it can come up
over any of the four tabs, which is what the field being on all four requires.

Tests: the four that asserted the split now assert what the screen gates on instead —
settled and probable both log, unsure and unmatched both block, an amount the model doubted
is worth a look and not a block, and an empty line logs nothing.

## Open Food Facts competes, and every row says what it is short of

Two changes from use, and they turn out to be the same subject: which row you get, and how
you tell two rows apart.

**The fourth rung stops being a rescue.** It was asked only where the bundled tables
returned nothing at all, which meant the index was never consulted about the foods people
mostly eat — and whether it is the better source for them was unanswerable rather than
answered. Now every term a line names goes to both and the better score wins, which is
what the Add screen has always done: it reads the bundled tables and Open Food Facts as one
ranked list. `ProductRung.best(for:in:)` returns a scored `ProductMatch` on the same 0-to-1
scale a bundled match carries, with the crowdsourced penalty already taken off, so the
comparison needs no second rule — `LineResolver.tablesWin(bundled:wasNarrowed:product:)` is
four lines and the thumb on the scale is one number, `SearchRelevance.bonus(isCrowdsourced:)`.
If brands start winning too often, that is the number to turn.

One exception, and it is the case the rung was built for: a bundled match found by
*narrowing* the term loses outright. Narrowing means nothing answered what was said and a
word of it was tried instead, so its score is against a question nobody asked. "Spaghetti
with bolognese sauce" reaches a plain spaghetti row by dropping three words, and a ready
meal of that name is what was eaten.

A product row is still `probable` at best and never settles: nothing has checked a
stranger's entry. What makes the whole change safe is the sign-off screen, which every line
now goes through — a product winning where it should not have costs one tap on a screen the
user is already reading.

What it costs is said where the opt-in is given. A line is looked up abroad food by food
now, not only where the tables draw a blank, and the Settings paragraph says so.

**Every search row says which of the eight figures it holds.** `SearchResult.Figures` is a
pill: "All 8", or "No fibre figure" where there is one gap, or "3 figures missing" past
that. It is the only thing that tells two otherwise identical rows apart — the same cheese
twice, where one of them has no figure for fibre — and that matters because everything
summed over a row with a gap in it is a floor rather than a total. The gap is named where
there is one of it, because *which* figure is missing is what decides whether the row will
do: someone watching sodium cares about a different absence than someone watching fibre.

A count and never a grade. A row short of a figure is often the right answer anyway — a
brand that declares only what a label must declare is still that brand — so the pill says
what is there and takes no view. A test asserts that neither the pill nor its spoken form
can carry a percentage or a word like "poor" or "better".

It lands hardest on the rung above: a crowdsourced record with an energy figure and nothing
else used to be indistinguishable from a measured row, and now it is one pill apart.

`Nutrition.missingNutrients` and `.isComplete` are where that reading lives, which the
loose-ends queue now shares rather than filtering the eight by hand.

Tests: twelve on the pill, including that zero is a figure and not a gap — feta holds no
fibre and the table says so with a 0, which makes it a complete row — and four on which of
the two sources answers, plus three on a product's score being on the same scale as a table
row's.

## A model that holds the search

Two changes, and the second is what the first was in the way of.

**The validator was undoing the product rung.** Inclusion in the validation prompt was
decided by the table shortlist, which `LineResolver` stores for every item whichever source
then won the row. That was harmless while Open Food Facts only rescued a dead end — a
product appeared only where the tables were empty, and the shortlist was empty with it. Once
the rung competed, a product that beat the tables on score was handed to the model as an
item whose candidates were the table rows it had just beaten, and both answers available to
the model threw it away: an id moved the row onto a table row, and 0 — the honest answer for
a food that is not on the list — emptied the row and blocked the log. `check` now skips a row
the product rung won, which is what `RowOrigin` already said happened, reading "Matched by
name, Open Food Facts" with no checked branch at all. The product row is left out of the
count as well as the prompt, so a line of one table row and one product still counts as
checked rather than tripping the all-or-nothing rule.

Every product test had built the resolver with `validator` at its `nil` default, which is why
nothing caught it.

**Claude is a third provider, and it holds the search.** The ladder exists because the model
naming the foods cannot see the database: `lookupTerm` is a guess at the wording a
composition table uses, the prompt spends five lines describing that corpus, the head-phrase
subsets recover from the guess being wrong, and validation is a second request spent checking
what a retriever did with it. A model that can call a tool searches instead, reads what came
back, and searches again under different wording when nothing fits.

So `LineDriving` is a separate seam from `MealEstimating` rather than a third endpoint behind
it. `AnthropicLineResolver` runs the loop — ask, run the searches on this device, send the
rows back, until it answers or five rounds are up — and the two searches are the app's own:
FTS5 through `FoodMatcher`, and Open Food Facts behind the opt-in it already had. The database
stays on the phone; what travels is the terms it chose and the rows they returned, which
Settings says in as many words.

`LineCandidatePool` is where the can't-invent-a-food invariant moved to. The validation prompt
gets that property from a shortlist fixed in advance; here the model chooses what to search
for, so the pool numbers every row the searches returned during one request and an id outside
it reads as "none of these" exactly as 0 does. One counter spans both sources, which is also
what lets a product be named: a table row id and a barcode share no namespace.

`tablesWin` has nothing to arbitrate on this path — rows of both kinds arrive as candidates in
one list — and narrowing has nothing to recover from. Phrase memory stays in front of all of
it, because a repeat under five seconds is worth more than any of this.

Two caps on what certainty can buy, and both are deliberate rather than defensive. An
ingredient or dry form never settles unasked even on `certain`: the model is told which
candidates carry that marker and told they are rarely what was eaten, so choosing one is a
deliberate act and worth more than a score — but coffee powder settled at a portion weight is
a hundredfold energy error landing silently in a trend. And a product never settles, for the
reason it never did: the model can confirm which product this is, but not whether a stranger
typed the figures in correctly.

`temperature` is rejected on the current models, so this is the one path without the
determinism greedy sampling gives the others. Phrase memory is what actually keeps a repeat
stable, and it answers before any model is asked.

Tests: two on the validator fix, covering a product that wins beside a checked table row and
a verdict of 0 that can no longer empty one; twenty-three on the wire format, including that
no temperature or thinking field is sent, that the schema carries no numeric bounds strict
mode would reject, that the product search is declared only behind its opt-in, and that a
reply's own turn goes back untouched down to a reasoning block's signature; eight on the loop,
driven by a scripted transport; four on the pool and its prompt lines; and twelve on what an
answered line becomes on the sheet.

Unbuilt. Written without a Swift toolchain, so nothing here has been compiled or run.

## A pass over what the app had stopped needing

Not a milestone: a sweep for machinery the app had outgrown, done by reading rather than by
building, because there is still no Swift toolchain here. Swift went from 32,255 lines to
31,683 and from 438 top-level types to 417, four files fewer; the Python pipeline lost 90
lines with its 184 tests green after every change.

**The largest single thing was the two request schemas.** Both remote paths described their
bodies as trees of single-use `Encodable` structs — nineteen types between them whose only
job was to emit a constant. The schema is a constant, so the types restated the JSON one
level further from it, and every key the spec spells with an underscore or reserves as a
Swift keyword needed a `CodingKeys` of its own. `JSONValue` already carried the blocks of a
replayed turn and now carries these; the leaf shapes, which are the only part that repeated,
are shared. `AnthropicPayload` went from thirteen top-level types to three.

**Two copies had already drifted, which is the argument for not having two.** `fetch` was
byte-identical in both estimators and the `URLError` mapping differed by one case, so a base
URL typed as `http` got a clear sentence on one path and "the request failed" on the other.
The nutrient cell was written twice and only one copy spelled its figure out for VoiceOver,
so the same number read as "Prot 12 g" on one screen and "Protein, 12 grams" on the other.
Both now have one copy, and the better behaviour is the one that survived.

**Two features were finished, tested and never called.** `BaselinePhrase` could work out
which line to offer from use counts, and the only caller outside its tests seeds a preview.
`AmountBucket` could read a size word in three languages, and the line parser rewrites
"half" to 0.5 before any size-word lookup could see it, so the two could not have agreed
anyway. `EntryOrigin` offered `photo` and `repeated`, which nothing writes.

**Several things were left alone on purpose.** `Food` and `RecipeIngredient` really do repeat
nineteen lines of per-100 pack and unpack, and a protocol with eight requirements is not an
improvement on that — the duplication is the cheaper of the two. Fourteen redundant
`import DeveloperToolsSupport` lines stay, because the case for removing them rests on
sibling files compiling without it and nothing here has ever compiled. `MealEstimator+Photo`
stays its own file, which is what its own header asks for: it is the only caller of the
iOS 27 image-prompt API, and keeping that contained is worth more than ten lines.
`ForeignMealsSection` stays out of `DayHealthSummary`, because that type is SwiftUI-free by a
convention that marks the HealthKit boundary at a glance.

**Four claims in `PLAN.md` were wrong.** It said `DayRecord` holds sample membership, which
the same section denied twenty-six lines later; listed three day states where there are four;
described `origin` as recording a photograph or a repeat; and gave Trends as charting three
nutrients where it charts all eight. One passage said the tool-using loop deletes narrowing
and the two-retriever arbitration, which reads as permission to delete code that is live for
the other providers and covered by ten tests. The plan now states the design and the log
carries the history, which is what `CLAUDE.md` asked for all along.

One test was failing before any of this: it expected "Barcode lookup is off" where the flow
returns "Product lookup is off". The flow is right — a lookup is allowed when either module
toggle is on, so the sentence cannot name one of them.

Unbuilt. Every claim rests on grep, on a brace-and-paren scanner over all 269 Swift files,
and on the Python suite. The first build is still the thing to do next, and these are the
changes to look at first: `WidgetPhrase` now relies on the synthesised memberwise init,
`WidgetSnapshot.init` lost a parameter, `PickableResultRow`'s memberwise init is synthesised
where it used to be written out, and the library editors' toolbar reads `dismiss` from inside
a `ViewModifier` rather than from the view that presents them.

## The ladder comes out

Not a milestone either: the deletion that "A model that holds the search" made possible.
One path reads a typed line now, where there were two.

**What went.** `ResolvableItem`, `MatchValidating`, `FoundationMatchValidator`,
`MatchVerdict`, `MatchVerdicts`, `ValidationItem`, `ValidationPrompt`, `ProductRung`,
`ProductMatch`, `LineResolver.tablesWin`, `LineResolver.databaseRow`, the per-item phrase
recall, and the `estimator:`, `validator:` and `products:` fields that wired them together —
four files out of the app target, and `LineResolver` from 622 lines to 304. Every one of
them existed because the model naming the foods could not see the database: the guess at a
composition table's wording, the search on that guess, the arbitration between the tables
and Open Food Facts, the dropping of words when the whole term answered nothing, and the
second request spent asking a model to choose among what the retriever had found. A model
that searches needs none of it, so they went together rather than one at a time. What is
left in front of the driving model is phrase recall, untouched, because a repeat under five
seconds is worth more than anything a deletion buys.

**The searches survive, and `candidates(for:)` is why.** `search`, `subsets` and `shortlist`
keep every narrowing rule and the preparation-word rule exactly as they were. Their one
caller is the "other foods this could have been" list a row offers when someone questions
the food it was given, which is a question a person reads the answer to rather than one a
score settles unasked. What went is the ladder's *use* of them to resolve a line, and with
it the rule that a narrowed match never settles — that rule guarded a row the retriever had
picked without being asked, and nothing picks one now.

**The opt-in now governs what it reads as governing.** Meal estimation gated the validator,
which meant the switch did not govern the request that actually sent the line. It gates the
model that reads a line, so with it off nothing is asked of anything and a line never logged
before resolves to nothing. `LogLineIntent` used to assemble its resolver by hand and read
neither switch; it goes through `LineResolver.app` as the composer does, so a spoken line is
governed by the same two.

**What on device lost, which is the price of one path.** Apple's Foundation Models path does
not conform to `LineDriving`. Recorded wrongly here at first, as though it could not: the
framework has had tool calling since iOS 26 — a `Tool` with a name, a description,
`@Generable` arguments and `call`, given to `LanguageModelSession(tools:)` — and iOS 27 adds
a mode governing when the model may use one. So the conformer is writable and merely was not
written. What the ladder did instead was guess a term rather than search for one, which is
the thing the validator existed to paper over — the case measured in this log is
"Pasta, cooked" answered with *Fish, cooked (average)*, settled and unasked.
So on device reads neither a typed line nor a photograph attached to one in the composer,
and it is still the default provider: the app as installed answers a line from memory or not
at all until a key is set. What it keeps is the photograph-and-description estimate on the
Add screen, one request with no searching in it, which is now the only thing `MealEstimating`
serves. `RemoteMealEstimator` went for being unreachable rather than for being a rung —
`Estimators.current()` was its only caller and existed to build the ladder's estimator, and
the Add screen has always constructed the on-device one — so the remote one-shot estimate
`PLAN.md` described was a standing error rather than something this change removed.

`LineDriving` itself is provider-neutral, and an OpenAI-compatible conformer lands beside
the Anthropic one, so "Your own endpoint" reads a line the same way rather than being
stranded by the deletion.

**The one request that got more careful.** The Anthropic request sends `fallbacks: "default"`
with the server-side-fallback beta header, so a safety refusal is routed by category instead
of failing outright. That was a nicety while a retriever could still answer a line on its
own; it is the primary input's only path now.

Unbuilt, and more so than usual. There is still no Swift toolchain here, so nothing has been
compiled or run, and a deletion of this shape is exactly what a compiler finds cheaply and
reading does not. The tests of the deleted machinery went with it. The first build is still
the thing to do next.
