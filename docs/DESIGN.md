# Design

Decisions for how the app looks and behaves. Written down so the next feature does not drift.

## Direction

Stock iOS done well. The app stays inside the iOS 26 system look: system type roles, system materials and Liquid Glass chrome, one accent colour, standard containers. Effort goes into hierarchy, spacing, empty states, Dynamic Type and one-handed reach, not into a custom visual language. A distinctive identity can come later as a skin over this base.

Room is left for light branding: an app icon and, later, a mascot in a few fixed places such as onboarding, first-run empty states and the Sources screen. The mascot never carries information the interface does not also show in text, and never comments on what was eaten.

## Brand

A small kit, applied in a few fixed places, on top of the stock look.

**Accent colour, "tangerine".** Light `#E8641C` (sRGB 0.910, 0.392, 0.110), dark `#F0701F` (0.941, 0.439, 0.122), both in `Assets.xcassets/AccentColor`. Both values are chosen so white text on a glass-prominent button passes 3:1; system orange does not. The dark variant is a little lighter so it holds up against the dark background.

**The mark, "the bite".** A disc with one round bite taken out of its upper right and two crumbs. One file defines the geometry: `Support/Brand/BiteMark.swift`, a `Shape` whose values are all relative to its square (disc centre 0.50, 0.53 and radius 0.30; bite subtracted at 0.695, 0.325 with radius 0.135; crumbs at 0.80, 0.235 with radius 0.024 and 0.855, 0.31 with radius 0.016). The icon script `Tools/icon/make_icon.py` and `docs/design/icon/mark.svg` follow it; change the shape first and mirror it into both. In the app the mark is always filled with the tint; on the icon it is white on the light accent colour.

**Rounded bold, twice.** The rounded system design at bold weight appears in exactly two places: the wordmark "Omnomnom" (`Support/Brand/Wordmark.swift`, title2) and the energy figure at the top of Today (large title). Nowhere else. Body text and every other figure keep the default face.

**Meal symbols.** Each meal slot has an SF Symbol, kept on `MealSlot.symbolName`: breakfast `sunrise`, lunch `sun.max`, dinner `moon.stars`, snack `carrot`. It sits in the tint next to the section header on Today; the header text keeps the list's own styling and VoiceOver reads the meal name once.

**Voice.** Plain, short, dry, second person. No exclamation marks, no praise, no judgement of what was eaten. A little warmer in two places only: the onboarding intro and the first-run empty day.

**Explanatory text.** A sentence earns its place by changing what the user does or by preventing a surprise. Anything that describes what the screen already shows is cut. Anything the user agreed to once — what leaves the device, what is kept, what is sent to Health — is said where they agreed to it, in Settings, and not repeated at every use. A footer that appears only when it applies is worth more than one that is always there, so a caveat about an unmatched row shows only when there is one.

**Deliberately plain.** Nutrient values, badges, Health states and provenance are never tinted and never carry the mark or the rounded face. The tint means "you can act on this" or "this is the app", nothing else.

## Yardstick

Every screen is held to the plan's targets rather than to taste:

- A repeat meal in under five seconds and three taps.
- A food never logged before in under twenty seconds.
- The add sheet opens with the keyboard up and recents listed before typing.
- The quantity sheet is prefilled with the last amount used for that food.
- All eight daily totals always visible: energy, protein, carbohydrates and fat large, the other four small.
- No colour-coded judgment, no over or under indicators, no traffic lights.
- Entries written by other apps, and entries partly or wholly missing from Health, are visually distinct and carry only the affordances the plan names.
- Primary actions reachable one-handed at the bottom of the screen.
- Dynamic Type everywhere, including the totals row.

## Process

1. Code-side audit per screen against the yardstick, recorded in `design/audit.md`.
2. A preview per screen and per notable state, using an in-memory seeded store and fake Health, repository and estimator services. Static renders never reach HealthKit, the network, the camera or the language model; in a live canvas, tapping Scan or Estimate does run the real availability checks, and the scanner's camera state is deliberately not previewed. With the pipeline not yet run, the bundled-food preview shows no portion chips and the Sources screen shows the missing-manifest row.
3. Screenshots from the simulator in light and dark mode and at the largest accessibility size, kept in `design/screenshots/`.
4. Screen-by-screen pass in fast-path order: Today, Add, Quantity, then Library, Settings, onboarding, then the two module sheets. One commit per screen.
5. The outcomes land here: type roles, spacing, how provenance and partial states look, and what stays deliberately plain.

## Decisions

Filled in as the screen-by-screen pass settles each one.

- Copy yesterday re-logs each entry at the same time of day, never in the future, keeping its meal slot; each copy is mirrored to Health like a repeat.
- One accent colour, tangerine, in a light and a dark value, both passing 3:1 for white text on a glass-prominent button; the asset catalog is the only place the values live.
- The mark appears on the app icon, on the onboarding intro, on the empty day, in Settings › About and on the thumbnail placeholder. Nowhere else without a decision here.
- The rounded system design at bold weight is used for the wordmark and the energy total, and for nothing else.
- Photos are the user's own: taken or picked on the device, downscaled to 1024 px JPEG, kept with an estimate's entries, a recipe or a custom food, shown as a 44 pt thumbnail on Today, in the Library and in the Add sheet, and opened full size from Today. Never fetched from a database or from Open Food Facts, never written to Health, never sent anywhere. An entry logged from a recipe or food shows that photo.
- Every food, recipe and entry shows a thumbnail; without a photo it is the mark on a tinted square, decorative only, so lists keep one left edge. At accessibility type sizes the placeholder gives way, since the name needs the width more than the list needs its edge; a real photo always stays.
- Finding a food is a screen of its own, presented full width, with the search field in the layout from the first frame rather than a `.searchable` bar that arrives after the list. Scan and Estimate live in its content, under the field and in reach of a thumb, not in a navigation bar the eye does not visit while typing. `.searchable` stays on the Library, where the list is the point and the search is not. Log on the Quantity sheet and Continue in onboarding use the same bottom glass capsule as Add food on Today.
- An estimate never carries invented nutrition: the model names the foods and the portions, every value comes from the bundled database, and the matched food is shown under each row and can be changed before logging. A row with no food cannot be logged.
- Tags are flat and shared by recipes and foods, edited as chips in both editors, filtered by chips in the Library, and matched by search on both screens. No folders: a folder makes an item pick one home, and porridge is breakfast and meal prep at once. A tag is resolved by name when an editor saves and deleted when its last use goes.
- Branded products come from Open Food Facts by name as well as by barcode, behind an opt-in of their own, because a barcode and a typed query are not the same disclosure. A search hit is resolved by its barcode before anything is logged, so a product reaches the Library through one path and carries one attribution.
- A search hit is offered only with energy and all three macronutrients. Open Food Facts is crowdsourced and a great many entries hold a name and nothing else; one of those in a list is a dead end. A scanned barcode is held to the lower bar of energy alone, because the user is holding the packet and can type the rest.
- The search field is debounced twice: briefly for the Library and the bundled database, which are on the device, and for a full second before anything is sent to Open Food Facts. The last query's products are cleared as soon as the text changes, because showing Kinder Bueno under a search for cola is worse than showing nothing.
