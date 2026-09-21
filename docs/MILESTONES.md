# Milestones

Status log for the build order in `PLAN.md`. Each milestone is planned, implemented, reviewed by a separate pass, then signed off here before the next one starts.

| # | Milestone | Status | Sign-off |
| --- | --- | --- | --- |
| 1 | Data pipeline (FDC) | done | 2026-09-21 |
| 2 | Log to Health end-to-end | done, awaiting first build | 2026-09-21 |
| 3 | Reconciliation | done, awaiting first build | 2026-09-21 |
| 4 | Recipes | done, awaiting first build | 2026-09-21 |
| 5 | Barcode | done, awaiting first build | 2026-09-21 |
| 6 | AI estimation | in progress | |
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

The device checks listed in PLAN.md close this milestone.

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

Pending.

### Sign-off

Pending.
