# Milestones

Status log for the build order in `PLAN.md`. Each milestone is planned, implemented, reviewed by a separate pass, then signed off here before the next one starts.

| # | Milestone | Status | Sign-off |
| --- | --- | --- | --- |
| 1 | Data pipeline (FDC) | done | 2026-09-21 |
| 2 | Log to Health end-to-end | in progress | |
| 3 | Reconciliation | pending | |
| 4 | Recipes | pending | |
| 5 | Barcode | pending | |
| 6 | AI estimation | pending | |
| 7 | Internationalization | pending | |

## Milestone 1: Data pipeline

### Plan

Deliverable: `Tools/fooddb`, a Python 3.11 package with no third-party dependencies, that turns the FDC Foundation Foods and SR Legacy CSV bundles into `Omnomnom/Resources/foods.sqlite` and `Omnomnom/Resources/sources.json`.

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

Bundle identifier `com.johanneswindelen.omnomnom`, no signing team set. Both outputs of the data pipeline must exist in `Omnomnom/Resources/` before building.

Sandbox constraint: no Swift toolchain here, so the code is reviewed but not compiled. First Xcode build on a Mac is the gate, and the device checks in PLAN.md close the milestone.

### Review

Pending.

### Sign-off

Pending.
