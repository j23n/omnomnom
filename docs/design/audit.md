# UI/UX audit, code-side

Read-only audit of the SwiftUI views under `Omnomnom/Features`, `Omnomnom/Modules` and `Omnomnom/App/RootView.swift`, done against `PLAN.md` "UI and UX", "Provenance in the UI", "Permissions, onboarding and empty states", "Accessibility", "Deliberately absent" and the opt-in module sections. Nobody has run the app; every claim below is from reading code, and the items marked "verify in preview" are the ones where layout behaviour cannot be settled by reading.

Design direction (decided): **stock iOS done well.** Tighten hierarchy, spacing, empty states, Dynamic Type and one-handed reach; stay inside the iOS 26 system look with Liquid Glass chrome; no custom type scale or colour language. Every proposal below stays inside that.

Severity: **must** = breaks a plan target or a stated requirement; **should** = visible quality gap that the screen pass ought to fix; **nice** = polish.

Paths are relative to `Omnomnom/` unless they start with `docs/` or `App/`.

---

## Yardstick summary

| Plan target | Status in code |
| --- | --- |
| Repeat meal in under five seconds and three taps | Met via `+` → recent row → Log (3 taps). Also met via leading swipe → Repeat (2 gestures). No long-press path (plan names both). |
| New food in under twenty seconds | Plausible. One trap: a prefilled gram field with focus appends typed digits (see Quantity finding 1). |
| Add sheet opens with keyboard up and recents before typing | Met: `Features/Add/AddFoodSheet.swift:26,58`, `Features/Add/RecentsList.swift`. |
| Quantity prefilled with last amount | Met: `Features/Quantity/QuantitySheet.swift:34-35`, `AddFoodSheet.swift:89-97`. |
| All eight totals visible, four large, four small | Met: `Features/Today/TotalsRow.swift:19-30`. |
| No colour-coded judgment | Met. Only colour outside system tints is `Color.red` on invalid text fields (validation, not judgment). |
| Foreign entries distinct, labelled, no edit affordance | Met: `Features/Today/ForeignMealsSection.swift`. |
| partial/gone: name missing nutrients, one tap restore, one tap remove | Met: `Features/Today/EntryHealthActions.swift:26-27,34-43`. |
| unauthorized shows once with a Settings link | Met, but the link goes to the wrong place (see Today finding 6). |
| One-handed reach at the bottom | **Not met.** `+` is top-right (`Features/Today/TodayView.swift:19-25`); Log/Done are top-right in every sheet. |
| Dynamic Type everywhere | Mostly. Onboarding pages have no scroll view; several caption HStacks will overflow at accessibility sizes; fixed 72/80/100 pt field widths. |
| VoiceOver on quantity fields reads the unit | Met: `Features/Quantity/AmountField.swift:54-55`, `Features/Library/IngredientRow.swift:21-22`. |
| First-run Today prompt, first-run Library shows the bundle | Today met (`Features/Today/DayEntriesView.swift:45-49`). Library met but the line is at the bottom of the screen (`Features/Library/LibraryView.swift:64-74`). |
| "Copy yesterday" on an empty day | **Missing.** No occurrence anywhere in `Omnomnom/`. |
| Onboarding two screens | Met: `Features/Onboarding/OnboardingView.swift:15-24`. |
| Modules introduced in context | **Not met.** Scan and Estimate exist only as Settings toggles; the Add sheet gives no hint they exist while off. |

---

## Today

Files: `Features/Today/TodayView.swift`, `DayEntriesView.swift`, `TotalsRow.swift`, `MealSection.swift`, `EntryRow.swift`, `ForeignMealsSection.swift`, `BannerView.swift`, `EntryHealthActions.swift`, `TodayViewModel.swift`, `DayHealthSummary.swift`; `App/RootView.swift`.

### 1. Fast path

(a) **Repeat a recent food**, from Today:
1. Tap `+` (`TodayView.swift:19-25`, top-right toolbar).
2. Add sheet opens with the search field focused and recents listed (`AddFoodSheet.swift:26,58`; `RecentsList.swift:48-50`). Tap the food row.
3. Quantity sheet opens with the last amount prefilled (`QuantitySheet.swift:34-35`) and the field focused after `prepare()` (`QuantitySheet.swift:105`). Tap **Log** (`QuantitySheet.swift:82`).

Three taps, no typing. Meets the target. Alternative: leading swipe on an existing row, tap **Repeat** (`MealSection.swift:29-36`), which re-logs at the current time. Two gestures, no sheet. The plan also names long-press; there is no `.contextMenu` anywhere (grep confirms), so long-press does nothing.

Hidden step: the Quantity sheet's focus is set only after `await foodRepository.portions(for:)` returns (`QuantitySheet.swift:93-105`), so for a bundled food the Add sheet's keyboard drops and the Quantity keyboard comes up a beat later. Verify in preview; if the gap is visible, focus first and load chips after.

(b) **New bundled food**: `+` → type a query (150 ms debounce, `AddFoodSheet.swift:120`) → tap a Database row → Quantity opens with the first portion prefilled when there is one (`QuantitySheet.swift:98-100`) or empty → type grams → **Log**. Three taps plus typing. Trap: when a portion is prefilled and the field is focused, typing "40" produces "18240" (see Quantity finding 1).

(c) **Recipe**: `+` → recipe row (in Recent if used before, else in "Yours", `RecentsList.swift:47-56`) → Quantity opens with "1" serving prefilled (`QuantitySheet.swift:34`) → **Log**. Three taps.

One-handed reach: `+` is top-right, Log is top-right, the date header is at the top. Nothing on the fast path is in the bottom third of the screen. The plan states this as a requirement.

### 2. Hierarchy and layout

- Container: `NavigationStack` → `VStack` of `DayHeader` and a `List(.insetGrouped)` (`TodayView.swift:11-15`, `DayEntriesView.swift:39,70`). Right container for grouped meals.
- Title: `.navigationTitle("Today")` inline (`TodayView.swift:16-17`) **and** a `DayHeader` whose centre button reads `Formatters.dayTitle` = "Today" on the default day (`TodayView.swift:66-69`, `Support/Formatters.swift:76`). On first run the screen says "Today" twice, one above the other. The header is a plain `HStack` with 8 pt vertical padding, outside the List, so it neither scrolls nor gets the iOS 26 scroll-edge treatment; it reads as a stray strip between the glass bar and the first card.
- Totals: first List section, one row (`DayEntriesView.swift:40-42`). Labels `.caption2` secondary, primary values `.title3.semibold` monospaced, secondary `.subheadline` (`TotalsRow.swift:63-69`). Reasonable hierarchy; the four/four split is visible.
- Entries: name `.body`, meta line `.caption` secondary, energy `.body.monospacedDigit()` trailing (`EntryRow.swift:20-40`). Good.
- Foreign meals: same row shape, energy in `.secondary`, section "Also in Health" (`ForeignMealsSection.swift:9-25`). Distinct enough.
- Add button: `ToolbarItem(.primaryAction)` with `Label("Add food", systemImage: "plus")` (`TodayView.swift:19-25`). Glass pill top-right on iOS 26.
- Banners: `safeAreaInset(edge: .bottom)` VStack with `.regularMaterial` rounded rectangles (`TodayView.swift:34-43`, `BannerView.swift:21,51`). Sits above the floating tab bar; material is fine on iOS 26.
- No `.presentationBackground`, `.scrollEdgeEffectStyle`, `.glassEffect` or `.buttonStyle(.glass)` anywhere. Defaults are correct for option A; nothing to remove.
- Colour: `.tint(.accentColor)` on the Repeat swipe (`MealSection.swift:35`) is system. No judgment cues.

### 3. States

| State | Where | Reachable | Distinct |
| --- | --- | --- | --- |
| Empty day / first run | `DayEntriesView.swift:43-51` "Nothing logged yet / Tap + to log one thing." | yes | Same view for first run and any empty day; no "copy yesterday". |
| Loading Health summary | none; local rows render, Health patched in (`DayEntriesView.swift:72-74`) | n/a | Correct per plan. |
| Health read failed | silent, previous summary kept (`DayEntriesView.swift:83`) | yes | Acceptable. |
| Banner after log/delete/repeat/restore | `TodayViewModel.swift:61,78,86,89,98,101`; texts in `Model/LogResult.swift:15-21,41-43` | yes | Tap to dismiss; never auto-dismisses. |
| Unauthorized notice | `BannerView.swift:31-54`, once per launch (`TodayViewModel.swift:65-69`) | yes | Separate component from `BannerView`. |
| `partial` / `gone` | badge "Partly in Health" / "Not in Health" (`Model/HealthState.swift:42-43`); tap opens dialog (`MealSection.swift:17-21`, `EntryHealthActions.swift`) | yes | Badge only; row looks identical to a normal row otherwise. |
| `unauthorized` | badge "Not written" (`HealthState.swift:44`) | yes | Not tappable; notice covers it. |
| `orphaned` | badge "Left in Health" (`HealthState.swift:45`); second delete removes locally (`Features/Quantity/EntryLogger.swift:42-45`) | yes | Nothing on the row says "delete again to remove". Banner said it once. |
| Estimated | badge "Estimated" (`EntryRow.swift:28-30`) | yes | Same badge style as health states. |
| Foreign | own section (`ForeignMealsSection.swift`) | yes | yes |
| Storage unavailable | `App/OmnomnomApp.swift:59-66` | yes | fine |

Missing: "copy yesterday" (plan, fast path section). Missing: a first-run variant that differs from a plain empty day (plan: "a single prompt to log one thing"; today's copy is close enough, but the empty state has no button, so the prompt costs a reach to the top-right).

### 4. Dynamic Type and layout risk

- `TotalsRow.swift:18-35`: `ViewThatFits` with a `Grid` and a `VStack` fallback. Good. `lineLimit(1)` on values (`:69`) is safe only because the fallback exists; verify at AX5 that the Grid's ideal width is measured from text and not from the `frame(maxWidth: .infinity)` (`:71`), otherwise the Grid always "fits" and values truncate.
- `EntryRow.swift:21-34`: caption `HStack` of grams · time · up to two badges. `HStack` does not wrap; at AX sizes "1.5 servings · 300 g", a time, "Estimated" and "Partly in Health" will be clipped or squeeze the name column. Same shape in `ForeignMealsSection.swift:14-17`.
- `BannerView.swift:35-49` (`UnauthorizedNoticeView`): text + `Spacer` + Link + xmark in one `HStack`; at AX sizes the text column gets narrow and tall.
- `EntryBadge` (`EntryRow.swift:49-58`): padding 6/1 in points, fine.
- `DayHeader` (`TodayView.swift:58-93`): fine, three items.
- No `minimumScaleFactor`, no fixed widths on this screen.

### 5. Accessibility

- Totals: eight combined elements labelled "Energy 1,234 kcal" (`TotalsRow.swift:72-73`). No container, so VoiceOver gives no cue that these are the day's totals; the foreign note is a separate element. Unknown values read as "–" (`Support/Formatters.swift:7`), which VoiceOver may read as "en dash" or skip.
- Entry rows combined (`EntryRow.swift:42`); `isButton` trait and hint only when actionable (`:43-44`). Empty string hint on non-actionable rows is harmless.
- Tap handling is `.onTapGesture` on a non-button row (`MealSection.swift:16-21`): no highlight, no default button semantics; the trait is bolted on.
- Swipe actions on List rows are exposed as VoiceOver custom actions by SwiftUI. Good.
- Date button: label is the date text; no hint that it opens a picker (`TodayView.swift:66-69`). Chevrons labelled (`:64,89`).
- `BannerView.swift:25`: label "Notice: …. Double tap to dismiss." puts a hint into the label; VoiceOver already announces "button" and its own activation hint.
- Reduce Motion: no custom animations on this screen.

### 6. Copy

| String | Where | Verdict |
| --- | --- | --- |
| "Today" (tab) | `RootView.swift:30` | keep |
| "Library", "Settings" (tabs) | `RootView.swift:33,36` | keep |
| "Today" (nav title) | `TodayView.swift:16` | remove; duplicate of the header (finding 2) |
| "Add food" (toolbar label) | `TodayView.swift:23` | keep |
| "Previous day" / "Next day" | `TodayView.swift:64,89` | keep |
| "Day" (picker label) | `TodayView.swift:72` | keep (hidden) |
| "Today" / "Yesterday" / "Tomorrow" / abbreviated date | `Formatters.swift:76-79` | keep; consider adding the weekday to the date form ("Mon, 15 Sep") |
| "Nothing logged yet" / "Tap + to log one thing." | `DayEntriesView.swift:46-48` | reword once the button moves: "Nothing logged yet" / "Log one thing to start." with a button |
| "Breakfast", "Lunch", "Dinner", "Snack" | `Model/MealSlot.swift:13-16` | keep |
| "Energy", "Protein", "Carbs", "Fat", "Sat. fat", "Fiber", "Sugar", "Sodium" | `Model/Nutrient.swift:45-65` | keep |
| "incl. 250 kcal from Health" / "incl. nutrients from Health" | `TotalsRow.swift:50-51` | reword: "Includes 250 kcal from other apps" / "Includes entries from other apps" |
| "Also in Health" | `ForeignMealsSection.swift:9` | keep |
| "Omnomnom, not in this log" | `DayHealthSummary.swift:30` | reword: "Omnomnom on another device" |
| "Written by another app" (hint) | `ForeignMealsSection.swift:27` | keep |
| "Delete", "Repeat" | `MealSection.swift:26,34` | keep |
| "Estimated" | `EntryRow.swift:29` | keep |
| "Partly in Health", "Not in Health", "Not written", "Left in Health" | `HealthState.swift:42-45` | keep the first two; "Not written" → "Not in Health" is ambiguous with `gone`, keep as is but see finding 6; "Left in Health" → "Still in Health" |
| "Restore to Health" / "Remove here" | `EntryHealthActions.swift:26-27` | keep |
| "Health no longer has this entry." / "Health no longer has protein and fiber." + "Restore writes it to Health again; Remove deletes it from this app only." | `EntryHealthActions.swift:38-42` | keep |
| "Double tap to restore it to Health or remove it here" | `EntryRow.swift:14` | shorten: "Restore to Health or remove here" (VoiceOver adds "double tap") |
| "Some entries never reached Health because no nutrient may be written." | `BannerView.swift:36` | reword: "Nothing is being written to Health. Allow it in Health › Sharing." |
| "Settings" (link) | `BannerView.swift:41` | reword to match destination (finding 6) |
| "Dismiss" | `BannerView.swift:48` | keep |
| "Notice: \(message). Double tap to dismiss." | `BannerView.swift:25` | shorten to the message; move "Dismisses" to a hint |
| "Logged locally. Health did not accept it: …" | `LogResult.swift:15` | keep |
| "Saved to Health but could not update the local record: …" | `LogResult.swift:18` | keep |
| "Logged locally. Nothing reached Health; check Settings." | `LogResult.swift:21` | reword: "Logged here. Nothing reached Health." (the notice carries the link) |
| "Health no longer lets this app delete its data. Delete again to remove the entry here; remove it in Health separately." | `LogResult.swift:41` | shorten: "Health refused the delete. Swipe again to remove it here; remove it in Health yourself." |
| "Could not delete: …" | `LogResult.swift:43` | keep |
| "Restored \(name) to Health." / "Could not restore the entry." | `TodayViewModel.swift:86,89` | keep |
| "Logged \(name) again." / "Could not log the entry again." | `TodayViewModel.swift:98,101` | keep, but do not require a tap to dismiss a success (finding 7) |
| "Storage unavailable" / "The app could not open its local store. Restart the app; if this persists, reinstall it." | `OmnomnomApp.swift:62,64` | keep |

### 7. Findings

1. **must** — `TodayView.swift:19-25`, `:34-43`. The only add affordance is top-right. Add a bottom, thumb-reachable primary action: an "Add food" button in the existing `safeAreaInset(edge: .bottom)` VStack, `.buttonStyle(.glassProminent)` (iOS 26; falls back to `.borderedProminent` if unavailable at build), `.controlSize(.large)`, trailing-aligned or full-width above the tab bar. Keep the toolbar `+` for discoverability. The banners stack above it in the same inset.

2. **must** — `TodayView.swift:16-17,54-93`. Duplicate "Today" and a non-scrolling header strip. Drop `.navigationTitle("Today")`; make the date the navigation title (`.navigationTitle(model.dayTitle)`, inline) with a `.toolbarTitleMenu` or a tap on the title opening the graphical picker, and move the chevrons to `ToolbarItemGroup(placement: .topBarLeading)` or a `.bottomBar` group. Alternative that keeps `DayHeader`: move it inside the List as the first row so it scrolls with content and gets the edge effect. Either way there is one date on screen.

3. **must** — `DayEntriesView.swift:43-51`. Add "Copy yesterday" to the empty state when the previous day has entries: `ContentUnavailableView { … } actions: { Button("Copy yesterday") … }`. Needs a small `TodayViewModel.copyPreviousDay(using:)` that re-logs each entry via `EntryLogger.repeatEntry(_:at:)` with the same wall-clock times on the selected day. Also give the empty state a "Log something" button so the prompt is one tap and reachable.

4. **should** — `MealSection.swift:16-21`, `EntryRow.swift:43`. Make actionable rows real buttons: wrap `EntryRow` in `Button { onHealthAction(entry) }` with `.buttonStyle(.plain)` only when `needsAttention`, else leave it a plain row. Removes the manual `.isButton` trait, gives highlight and hit testing for free. Add `.contextMenu` with Repeat and Delete on every own row to satisfy "swipe or long-press".

5. **should** — `EntryRow.swift:21-36`, `ForeignMealsSection.swift:14-19`. The caption HStack does not wrap. Introduce a shared `MetaLine` (see cross-cutting) that lays its children out in an `HStack` normally and a `VStack` when `dynamicTypeSize.isAccessibilitySize`, or use `ViewThatFits`. Use it in all five row types.

6. **should** — `BannerView.swift:40-43`, `HealthStatusView.swift:37-39`. `UIApplication.openSettingsURLString` opens the app's page in iOS Settings, while the footer in `HealthStatusView.swift:41` correctly says permissions live in Health › Sharing › Apps. Point the notice at the in-app Health screen (a `NavigationLink` or a tab switch to Settings › Health) whose footer already says where to go, and change the link text to "Health settings". Do not promise a deep link into the Health app.

7. **should** — `TodayViewModel.swift:61,86,98`, `BannerView.swift:6-27`. Success banners ("Logged oats again.") stay until tapped, which adds a tap to the fastest path. Either show no banner on a clean success (the row appears and is the confirmation) or auto-dismiss after a few seconds with `Task.sleep`, keeping tap-to-dismiss. Reserve persistent banners for problems.

8. **should** — `DayEntriesView.swift:75-77`, `TodayViewModel.swift:61,65-69`. On the first log without permission, both the LogResult banner ("Logged locally. Nothing reached Health; check Settings.") and the unauthorized notice appear stacked. Suppress the banner when `showsUnauthorizedNotice` is about to be true, or fold both into one component.

9. **should** — `TotalsRow.swift:17-45`. Wrap the grid in `.accessibilityElement(children: .contain)` with `.accessibilityLabel("Daily totals")` so VoiceOver announces the group. In `TotalCell` use an explicit `.accessibilityValue` that says "not recorded" instead of the en dash.

10. **nice** — `BannerView.swift:25,48`. Label is the message alone; hint "Dismisses the notice". Same pattern for `UnauthorizedNoticeView`, which should be the same view as `BannerView` with an optional action.

11. **nice** — `HealthState.swift:45`, `EntryLogger.swift:42-45`. An `orphaned` row gives no cue that a second swipe removes it. Make the badge "Still in Health" and the row's hint "Swipe to delete removes it here only".

---

## Add sheet

Files: `Features/Add/AddFoodSheet.swift`, `RecentsList.swift`, `SearchResultsList.swift`, `ChoiceRow.swift`, `BarcodeEntryPoint.swift`, `EstimationEntryPoint.swift`.

### 1. Fast path

- Opens as a full-height sheet (no detents set) with `NavigationStack`, inline title, `.searchable(text:isPresented:prompt:)` with `searchPresented = true` (`AddFoodSheet.swift:26,58`), so the keyboard is up on appear. Meets the plan.
- Recents before typing (`:51-55`; `RecentsList.swift:47-50`), merged foods and recipes by `lastUsed`, cap 20. "Yours" lists never-logged custom foods and recipes (`:52-56`). No frequency weighting; the plan says "recent and frequent". Acceptable for v1.
- Search: `.task(id: searchText)` with 150 ms debounce (`AddFoodSheet.swift:110-133`). Local matches first ("Yours"), FTS second ("Database").
- Row tap → `present()` → for a bundled hit, a synchronous SwiftData fetch for `lastGrams` (`:89-97`) → `QuantitySheet` as a nested sheet with `[.medium, .large]` (`:65-74`).
- Pick mode (recipe ingredient) returns immediately (`:83-87`). Scan and Estimate buttons are `.primaryAction` toolbar items added by two modifiers (`BarcodeEntryPoint.swift:32-38`, `EstimationEntryPoint.swift:26-32`), shown only when the module is on.

Extra steps: none on the happy path. Behaviour that adds a step: after a log, `self.choice = nil; onLogged(result); dismiss()` (`:68-71`) closes both sheets, which is right.

### 2. Hierarchy and layout

- `List(.plain)` in both sub-lists (`RecentsList.swift:58`, `SearchResultsList.swift:51`); right for a search UI.
- Rows: name `.body`, caption `.caption` secondary (`ChoiceRow.swift:10-26`, `SearchResultsList.swift:59-68`). The caption packs brand · "Last 40 g" · "389 kcal per 100 g" · "Open Food Facts". For the fast path, "Last 40 g" is the useful part and it sits in the middle of a secondary line.
- Rows are `Button(.plain)` so they highlight on tap. Good.
- Toolbar: Cancel leading, up to two icon buttons trailing. On iOS 26 these render as glass pills; fine.
- Section names: "Recent", "Yours", "Database". "Database" is an implementation word.

### 3. States

| State | Where | Note |
| --- | --- | --- |
| First run, nothing logged, nothing custom | `RecentsList.swift:40-45` "No recent foods / Search to find a food. Foods you log appear here." | fine |
| Typing, no results | `SearchResultsList.swift:12-15` `ContentUnavailableView.search` | shown during the 150 ms debounce and while FTS runs, so every keystroke flashes "No Results" before results land. |
| Database unavailable | `SearchResultsList.swift:29-36` "Search unavailable" + raw `error.localizedDescription` (`AddFoodSheet.swift:131`) | raw SQLite text reaches the user. |
| Module off | nothing in the sheet | modules are not introduced in context (plan). |
| Estimation on but model unavailable | alert "Meal estimation unavailable" (`EstimationEntryPoint.swift:41-45`) | names the reason; good. |
| Pick mode | title "Add ingredient", recipes hidden (`AddFoodSheet.swift:36-39,56`) | fine |

### 4. Dynamic Type and layout risk

- `ChoiceRow.swift:12-23` and `ResultRow` (`SearchResultsList.swift:61-66`): caption HStacks that do not wrap; at AX sizes a product row (brand + last + per-100 g + "Open Food Facts") overflows. Same fix as Today finding 5.
- No fixed frames.

### 5. Accessibility

- Rows combined (`ChoiceRow.swift:28`, `SearchResultsList.swift:71`), and inside `Button`, so they get the button trait. Good.
- Toolbar buttons use `Button("Scan", systemImage:)` and `Button("Estimate", systemImage:)`, labelled. Good.
- Search field: system.

### 6. Copy

| String | Where | Verdict |
| --- | --- | --- |
| "Add food" / "Add ingredient" | `AddFoodSheet.swift:56` | keep |
| "Search foods" | `AddFoodSheet.swift:58` | keep |
| "Cancel" | `:62` | keep |
| "No recent foods" / "Search to find a food. Foods you log appear here." | `RecentsList.swift:41-43` | reword: "Nothing logged yet" / "Search the bundled foods. What you log shows up here." |
| "Recent" | `RecentsList.swift:48` | keep |
| "Yours" | `RecentsList.swift:53`, `SearchResultsList.swift:17` | reword: "Your library" |
| "Database" | `SearchResultsList.swift:30,39` | reword: "Foods" |
| "Search unavailable" | `SearchResultsList.swift:32` | keep; replace the description with a plain sentence (finding 3) |
| "Last 40 g" / "Last 1.5 servings" | `ChoiceRow.swift:17` | keep |
| "389 kcal per 100 g" / "… per serving" | `ChoiceRow.swift:19`, `SearchResultsList.swift:65` | keep |
| "Open Food Facts" | `ChoiceRow.swift:21` | keep |
| "Scan" / "Estimate" | `BarcodeEntryPoint.swift:35`, `EstimationEntryPoint.swift:29` | keep |
| "Meal estimation unavailable" / "OK" | `EstimationEntryPoint.swift:41-42` | keep |

### 7. Findings

1. **must** — `SearchResultsList.swift:12-15`, `AddFoodSheet.swift:111-133`. Introduce modules in context. When a search yields nothing, show the empty state with actions: "Scan a barcode" and "Describe or photograph the meal" (label per availability), each of which turns the module on (`@AppStorage` key) after a one-line explanation of what leaves the device, then continues into the module's sheet. Plan: "introduced in context at the moment they would help, not in a carousel up front." The Settings toggles stay as the off switch.

2. **should** — `SearchResultsList.swift:12-15`. Add an `isSearching` flag set in `AddFoodSheet.search()` around the awaited FTS call and pass it in; show nothing (or the previous results) while true, so "No Results" appears only after a search actually returned empty.

3. **should** — `AddFoodSheet.swift:131`, `SearchResultsList.swift:34`. Map the repository error to one plain sentence ("The bundled food database could not be opened. Reinstall the app if this keeps happening.") and keep `localizedDescription` in the log only. Same for `LibraryView.swift:101`.

4. **should** — `ChoiceRow.swift:12-23`. Put the last amount first and make it the row's trailing element in `.body.monospacedDigit()` ("40 g"), keeping brand and per-unit energy in the caption. The fast path reads "Oats … 40 g" at a glance.

5. **nice** — `RecentsList.swift:16-28`. Add a simple frequency tie-break (count of uses in the last 30 days) so a daily food outranks a one-off from this morning. Needs a counter on `Food`/`Recipe`; defer if the schema should stay still.

---

## Quantity sheet

Files: `Features/Quantity/QuantitySheet.swift`, `AmountSection.swift`, `AmountField.swift`, `AmountChips.swift`, `NutritionPreview.swift`, `EntryLogger.swift`, `EntryLogger+Choice.swift`; `Modules/Barcode/OpenFoodFactsAttribution.swift`.

### 1. Fast path

- Presented with `[.medium, .large]` (`AddFoodSheet.swift:72`). `Form` with: name, brand, amount field, range hint, recipe caveat, chips; Nutrition section (8-cell grid, raw weight for recipes, attribution footer); Meal picker + Time picker; error section (`QuantitySheet.swift:48-74`).
- Prefill: last amount, else 1 serving for a recipe, else first portion of a bundled food, else empty (`:34-35,98-100`). Focus set at the end of `prepare()` (`:105`).
- Confirm: **Log** in `.confirmationAction` (top-right), disabled until the amount parses (`:81-86`). Cancel top-left.
- `confirm()` awaits the local save and the Health mirror before `onLogged` (`:108-120`, `EntryLogger+Choice.swift:25-42`). Nothing on screen indicates saving; the button is just disabled.

Steps that add friction: (1) typing over a prefilled value appends; (2) at `.medium` with the keyboard up the Nutrition section is probably below the fold, so the "catches decimal-place mistakes" purpose of the live preview is not served on the default detent (verify in preview); (3) Log is top-right, not one-handed.

### 2. Hierarchy and layout

- Name `.headline`, brand `.footnote` secondary, field `.largeTitle.semibold` trailing with unit `.title2` secondary (`AmountSection.swift:15-21`, `AmountField.swift:49-59`). Clear.
- Chips: horizontal `ScrollView` of `.bordered` buttons (`AmountChips.swift:31-45`), **below** the field. The plan puts them above.
- Preview: `LazyVGrid(.adaptive(minimum: 88))`, labels `.caption`, primary values `.body.semibold`, secondary `.body` (`NutritionPreview.swift:7-20`). Values are not `monospacedDigit`, so the live preview jitters as digits are typed.
- Meal picker (menu style in a Form) and compact `DatePicker` with date and time (`QuantitySheet.swift:61-66`). Two system pills; fine.
- Title "Amount" inline. Generic but harmless.
- Nothing custom; `.bordered` chips are system.

### 3. States

| State | Where | Note |
| --- | --- | --- |
| Out-of-range / non-numeric | "Enter between 0.1 and 5000 g" (`AmountSection.swift:23-27`) | good, inline |
| Saving | `isSaving` disables Log only (`:85`) | no indicator |
| Local save failed | section with "Could not save: …" secondary text (`:68-73,117`) | fine |
| Source deleted meanwhile | "This item no longer exists." (`EntryLogger+Choice.swift:14`) | fine |
| Empty recipe | "This recipe has no ingredients." (`:15`) | fine; could be prevented upstream |
| Product from OFF | attribution footer (`OpenFoodFactsAttribution.swift:26-39`) | good |

### 4. Dynamic Type and layout risk

- `AmountField.swift:51`: `.largeTitle` scales to ~60 pt at AX5; the HStack with "g" still fits because the field is trailing-aligned and flexible. OK.
- `AmountChips.swift:38`: `lineLimit(1)` on chip labels inside a horizontal scroller; acceptable since the scroller absorbs width.
- `NutritionPreview.swift:7`: adaptive 88 pt minimum; at AX sizes "1,234 kcal" in body exceeds 88 and the grid drops to fewer columns. Fine.
- `QuantitySheet.swift:53` `LabeledContent("Raw weight", …)` fine.

### 5. Accessibility

- Field: label "Grams"/"Servings", value "40 g" / "no amount" (`AmountField.swift:54-55`); unit text hidden (`:61`). Meets the plan.
- Chips: label duplicates the text (`AmountChips.swift:41`); no hint. Add "Sets the amount".
- Preview cells combined (`NutritionPreview.swift:19`); unknown reads "–".
- Log disabled state: fine.

### 6. Copy

| String | Where | Verdict |
| --- | --- | --- |
| "Amount" (title) | `QuantitySheet.swift:75` | keep, or use the food name if it fits in one line |
| "Cancel" / "Log" | `:79,82` | keep |
| "Nutrition" | `:56` | keep |
| "Raw weight" | `:53` | keep |
| "Meal" / "Time" | `:61,66` | keep |
| "Could not save: …" | `:117` | keep |
| "0" (placeholder) | `AmountField.swift:49` | keep |
| "g" / "servings" | `AmountField.swift:13-14` | keep |
| "Enter between 0.1 and 5000 g" | `AmountSection.swift:24`, `Formatters.swift:44-51` | keep |
| "Servings are portions of the raw total" | `AmountSection.swift:29` | keep (plan requires it here) |
| "½ serving", "1 serving", "2 servings" | `AmountChips.swift:16-18` | keep |
| "1 medium, 182 g" | `AmountChips.swift:11` | keep |
| "Data from Open Food Facts · ODbL" / "Product page" / "Licence" | `OpenFoodFactsAttribution.swift:28-34` | keep |
| "This item no longer exists." / "This recipe has no ingredients." | `EntryLogger+Choice.swift:14-15` | keep |

### 7. Findings

1. **must** — `AmountField.swift:49-57`, `QuantitySheet.swift:105`. A focused, prefilled field appends typed digits. Bind a `TextSelection` (`TextField("0", text: $text, selection: $selection)`, iOS 18+) and set `selection = TextSelection(range: text.startIndex..<text.endIndex)` when focus lands, so the first digit typed replaces the prefill while a tap on Log still uses it. Verify in preview that the selection survives the `.decimalPad` keyboard appearing.

2. **must** — `AddFoodSheet.swift:72`, `QuantitySheet.swift:48-67`. Make the preview visible on the default detent. Options in order of preference: (a) present with `[.large]` only, since the sheet has a keyboard and three sections; (b) keep `.medium` but move the Meal/Time section into a single compact row and put the eight-cell preview immediately under the chips. Decide from the preview at default and AX3 sizes.

3. **should** — `AmountSection.swift:22-35`. Put `AmountChips` above `AmountField` as the plan says, so the eye goes shortcut → value → preview.

4. **should** — `NutritionPreview.swift:16-17`. Add `.monospacedDigit()` and a fixed-width label column so live updates do not reflow. Reuse the same `ValueText` helper as `TotalsRow`.

5. **should** — `QuantitySheet.swift:82-86,108-120`. Show progress while saving: swap the Log label for a `ProgressView()` when `isSaving`. Longer term, dismiss after the local save and let `mirror` finish in the background (the entry already exists locally; the Health outcome arrives as a banner on Today), which shortens the perceived fast path.

6. **should** — one-handed confirm. In addition to the toolbar Log, add a bottom `safeAreaInset` "Log" button (`.glassProminent`, `.controlSize(.large)`) that sits above the keyboard. With the keyboard up this is the closest control to the thumb. Same pattern as Today finding 1; share it.

7. **nice** — `AmountChips.swift:41`. Add `.accessibilityHint("Sets the amount")`.

---

## Library

Files: `Features/Library/LibraryView.swift`, `LibraryRows.swift`, `RecipeEditorView.swift`, `IngredientRow.swift`, `RecipeDraft.swift`, `RecipeWriter.swift`, `CustomFoodEditorView.swift`, `CustomFoodDraft.swift`, `NutrientField.swift`.

### 1. Fast path

Not a logging screen. Creating a recipe: Library → `+` menu → "New recipe" → Name → Stepper → "Add ingredient" → pick sheet (search, tap) → edit grams inline → repeat → Done. The pick sheet returns one ingredient per open (`RecipeEditorView.swift:88-90`, `AddFoodSheet.swift:83-87`), so a five-ingredient recipe opens the sheet five times. Creating a custom food: `+` → "New custom food" → name + up to eight fields → Done.

### 2. Hierarchy and layout

- `LibraryView.swift:27-75`: `List` (default inset grouped inside NavigationStack) with sections Recipes, "Custom foods and products", an error row, and "Bundled database" last. Large title. `+` is a `Menu` with two items (`:78-85`).
- Rows: name + caption (`LibraryRows.swift:21-33,40-54`), `Button(.plain)` so no disclosure chevron although the row opens an editor.
- `RecipeEditorView.swift:29-76`: `Form`. Name + Stepper whose label is a two-line VStack (servings, "= 62.5 g raw per serving" caption), footer with the raw-total caveat; Ingredients section with `EditButton` in the header `HStack` (`:52-56`), "Add ingredient" as the last row, footer "Raw total 450 g"; "Per serving" preview; conditional "Previously logged servings are unchanged."; error section. Cancel/Done top.
- `IngredientRow.swift:8-26`: name + energy caption, trailing `TextField` `frame(maxWidth: 80)` and "g".
- `CustomFoodEditorView.swift:49-82`: `Form`. Optional product section (reason sentence + Barcode), Name, eight `NutrientField`s (`LabeledContent` with trailing field and unit), footer, conditional "Previously logged entries are unchanged.", error. Cancel/Done top.
- Colour: `Color.red` on invalid text (`IngredientRow.swift:20`, `NutrientField.swift:22`). Validation, not judgment, but colour is the only signal.

### 3. States

| State | Where | Note |
| --- | --- | --- |
| No recipes / no custom foods | inline secondary text rows (`LibraryView.swift:30,45`) | plain; fine |
| Bundle count loading / ready / failed | `LibraryView.swift:65-73` | count is unformatted (`\(foodCount)`), error is raw |
| Delete failed | section with text (`:58-63,115`) | fine |
| Editing recipe with logged entries | one line (`RecipeEditorView.swift:63-69`) | matches plan |
| Editing a food | one line (`CustomFoodEditorView.swift:69-74`) | good |
| Product from barcode miss | reason + barcode (`CustomFoodEditorView.swift:50-54`) | reasons are fragments ("No connection") shown as a full row |
| Invalid grams / value | red text | no message |
| Done disabled until valid | `RecipeEditorView.swift:85`, `CustomFoodEditorView.swift:91` | nothing explains why |

Missing: first-run Library puts the promise ("Bundled database ready") last, under two empty sections.

### 4. Dynamic Type and layout risk

- `IngredientRow.swift:19` `frame(maxWidth: 80)`: at AX sizes "1000" in body does not fit 80 pt; the field scrolls its text. Use `@ScaledMetric` or no max width with `.fixedSize(horizontal: false, vertical: true)` on the name column.
- `RecipeEditorView.swift:33-40`: Stepper label VStack, fine. Header `HStack` with `EditButton` (`:52-56`) is fine.
- `NutrientField.swift:17-30`: `LabeledContent` handles wrapping.
- `LibraryRows.swift:24-27,43-48`: caption HStacks, same wrap issue as Today.

### 5. Accessibility

- Rows combined and buttons. Good.
- `IngredientRow.swift:21-22`: label "Grams of oats", value "100 grams". Good.
- `NutrientField.swift:23`: "Energy per 100 grams, in kcal". Good.
- `EditButton` in a section header: reachable, but reorder handles are only exposed in edit mode; fine.
- Red-only validation gives VoiceOver nothing; add `.accessibilityValue` "invalid" or a hint.
- Stepper: label reads "1 serving, = 100 g raw per serving"; fine.

### 6. Copy

| String | Where | Verdict |
| --- | --- | --- |
| "Library" | `LibraryView.swift:76` | keep |
| "Recipes" | `:28` | keep |
| "No recipes yet. Add one with +." | `:30` | keep |
| "Custom foods and products" | `:43` | shorten: "Your foods" |
| "No custom foods yet. Add one with +, or scan a product." | `:45` | reword: "No foods of your own yet. Add one with +." (scanning is off by default; mention it only when on) |
| "Bundled database" / "Bundled database ready: 7900 foods" / "Checking the bundled database…" | `:64-71` | reword: "Built in" / "7,900 foods ready offline" / "Checking…" |
| "Could not delete the recipe: …" | `:115` | keep |
| "Add" / "New recipe" / "New custom food" | `:80-83` | keep |
| "1 serving" · "150 kcal per serving" | `LibraryRows.swift:25-26` | keep |
| "Brand" · "389 kcal per 100 g" | `:44-47` | keep |
| "Name" | `RecipeEditorView.swift:31`, `CustomFoodEditorView.swift:57` | keep |
| "= 62.5 g raw per serving" | `RecipeEditorView.swift:36` | reword: "62.5 g raw each" |
| "Servings are portions of the raw total, not of the cooked weight." | `:42` | keep (plan) |
| "Ingredients" / "Add ingredient" / "Raw total 450 g" | `:53,50,58` | keep |
| "Per serving" | `:60` | keep |
| "Previously logged servings are unchanged." | `:65` | keep (plan) |
| "Could not save: …" | `:100`, `CustomFoodEditorView.swift:127` | keep |
| "New recipe" / "Edit recipe" | `:77` | keep |
| "Cancel" / "Done" | `:81,84` | keep |
| "The recipe needs a name, at least one ingredient, and a gram amount on every row." | `RecipeWriter.swift:83` | keep; surface it as the footer while Done is disabled |
| "0" / "g" | `IngredientRow.swift:16,23` | keep |
| "New product" / "Edit product" / "Edit custom food" / "New custom food" | `CustomFoodEditorView.swift:42-44` | keep |
| "Barcode" | `:53` | keep |
| "Per 100 g" / "Type the values from the label, per 100 g" | `:65` | keep |
| "Energy is required. Leave a value blank when it is not known; it is then not written to Health." | `:67` | shorten: "Energy is required. Blank values are not written to Health." |
| "Previously logged entries are unchanged." | `:71` | keep |
| "required" / "unknown" (placeholders) | `NutrientField.swift:19` | keep |
| "Energy", "Protein", "Carbohydrates", "Fat", "Saturated fat", "Fiber", "Sugar", "Sodium" | `Nutrient.swift:45-56` | keep |

### 7. Findings

1. **should** — `LibraryView.swift:27-75`. Move the "Built in" section to the top, or show it as a header note above Recipes. On first run the screen should open on "7,900 foods ready offline", which is the paid app's promise. Format the count with `foodCount.formatted()`.

2. **should** — `LibraryView.swift:33-40,48-55`. Rows open an editor but show no chevron. Use `NavigationLink`-style disclosure (`Button` label wrapped in `LabeledContent` with a chevron, or present the editor via `.navigationDestination` and push instead of sheet). Pushing is the stock pattern for editing a library item; keep sheets for creation.

3. **should** — `RecipeEditorView.swift:88-90`, `AddFoodSheet.swift:83-87`. In pick mode, keep the Add sheet open after a pick and show a running count ("3 added") in the title or a Done button, so a multi-ingredient recipe does not reopen the sheet per ingredient. `onPick` already appends; only `dismiss()` needs to move to a Done button.

4. **should** — `IngredientRow.swift:20`, `NutrientField.swift:22`, `EstimateDraftRowView.swift:29,69`. Red text alone marks invalid input. Keep the red (system semantic) but add the inline range sentence used by `AmountSection` and an `.accessibilityValue` suffix "invalid". Share one `ValidatedDecimalField` for all four sites.

5. **nice** — `RecipeEditorView.swift:84-85`, `CustomFoodEditorView.swift:90-91`. Done is disabled with no explanation. Show `RecipeWriteError.invalidDraft.errorDescription` / "Name and energy are required" as the last section's footer while invalid.

6. **nice** — `CustomFoodEditorView.swift:50-54`. The reason row shows a fragment. Map `ProductPrefill.reason` to full sentences (see Barcode copy table).

---

## Settings

Files: `Features/Settings/SettingsView.swift`, `HealthStatusView.swift`, `SourcesView.swift`, `SourceManifest.swift`; `Modules/Barcode/OpenFoodFactsAttribution.swift` (`OpenFoodFactsSource`), `Modules/Estimation/EstimationSource.swift`.

### 1. Fast path

Not applicable. Health status is two taps from Today (tab, row).

### 2. Hierarchy and layout

- `SettingsView.swift:14-45`: `List` with "Health" (NavigationLink with a two-line label: "Health" + summary caption), "Modules" (two toggles, conditional unavailable message, long footer), "Data" (Sources). Large title.
- `HealthStatusView.swift:14-44`: summary row + footer; "Writing to Health" with eight rows "Energy — Writing allowed"; a section with "Ask for Health access" button and "Open app settings" link + footer. Title "Health".
- `SourcesView.swift:14-60`: a section per manifest source with Publisher, dataset versions, Licence (as a Link wrapping `LabeledContent`), Website, citation footnote; then Open Food Facts; then On-device estimation.
- All stock. No colour.

### 3. States

| State | Where | Note |
| --- | --- | --- |
| Health unavailable | summary "Health is not available on this device" (`HealthAuthorization.swift:28`); per-nutrient section hidden (`HealthStatusView.swift:20`) | fine |
| No / partial / all authorized | summary strings (`HealthAuthorization.swift:29-33`) | fine |
| After a refusal | "Ask for Health access" does nothing visible; footer explains once-per-nutrient | acceptable |
| Estimation toggle on, model unavailable | message under the toggles (`SettingsView.swift:30-34`) | good |
| sources.json failed | raw error row (`SourcesView.swift:15-18`) | fine for a manifest error |

Missing: nothing required. The "Open app settings" link contradicts the footer (see Today finding 6).

### 4. Dynamic Type and layout risk

- `HealthStatusView.swift:23-28`: `HStack` name + `Spacer` + status. At AX sizes "Carbohydrates" and "Writing not allowed" collide. Use `LabeledContent`, which wraps.
- `SettingsView.swift:19-24`: two-line link label, fine.

### 5. Accessibility

- Health rows combined (`HealthStatusView.swift:29`). Good.
- Toggles: system.
- `Link(destination:) { LabeledContent("Licence", value:) }` (`SourcesView.swift:26-28`): reads as a link with label "Licence, CC0"; fine.

### 6. Copy

| String | Where | Verdict |
| --- | --- | --- |
| "Settings" | `SettingsView.swift:46` | keep |
| "Health" (section, row, nav title) | `:15,20`, `HealthStatusView.swift:45` | keep |
| "Health is not available on this device" / "No nutrient can be written" / "All eight nutrients can be written" / "3 of 8 nutrients can be written" | `HealthAuthorization.swift:28-33` | keep |
| "Barcode scanning" / "Meal estimation" | `SettingsView.swift:28-29` | keep |
| "Modules" | `:36` | reword: "Optional" |
| "Barcode scans run on this device. Looking up a product sends its barcode to Open Food Facts; results are kept on this device.\n\nEstimates are produced on this device by Apple Intelligence. Nothing is sent anywhere. They are rough and you confirm every value before it is logged." | `:56-60` | keep; split into two footers by making each toggle its own section |
| "Data" / "Sources" | `:40-41` | keep |
| "Health only tells apps what they may write. Entries are kept locally either way." | `HealthStatusView.swift:18` | reword: "Health only reports what apps may write. Entries stay in this app either way." |
| "Writing to Health" | `:21` | keep |
| "Writing allowed" / "Writing not allowed" | `HealthAuthorization.swift:23` | shorten: "Allowed" / "Not allowed" (header already says writing) |
| "Ask for Health access" | `HealthStatusView.swift:33` | keep |
| "Open app settings" | `:38` | remove or relabel; it does not lead to Health permissions |
| "Health shows the sheet once per nutrient. Permissions live in Health › Sharing › Apps." | `:41` | reword: "Health asks once per nutrient. Change it later in the Health app under Sharing › Apps › Omnomnom." |
| "Sources" | `SourcesView.swift:61` | keep |
| "Publisher" / "Licence" / "Website" | `:21,27,33` | keep |
| "Open Food Facts" / "Open Food Facts (association loi 1901, France)" / "Open Database License 1.0" / "Used only for barcode lookups; results are cached on this device." | `OpenFoodFactsAttribution.swift:7-12` | keep |
| "On-device estimation" / "Apple Intelligence, on this device" / "Estimates come from Apple's on-device model, not from any database, and are only as good as the description or photo." | `EstimationSource.swift:5-7` | keep |

### 7. Findings

1. **should** — `HealthStatusView.swift:23-28`. Replace the `HStack` with `LabeledContent(nutrient.displayName, value: …)` so it wraps at AX sizes and matches `SourcesView`.

2. **should** — `HealthStatusView.swift:37-39`, footer `:41`. Remove the "Open app settings" link or relabel it "Open iOS Settings" and keep the footer sentence as the real instruction. Do not claim the link reaches Health permissions.

3. **nice** — `SettingsView.swift:27-39`. One section per module with its own footer sentence; the combined two-paragraph footer reads as a wall under two toggles.

4. **nice** — `SettingsView.swift:15-26`. Show which nutrients are blocked in the caption when partial ("Fiber and sodium not allowed") rather than a count; it is the actionable information.

---

## Onboarding

Files: `Features/Onboarding/OnboardingView.swift`, `PermissionPrimerView.swift`; `App/RootView.swift`.

### 1. Fast path

Two pages in a `TabView(.page)` (`OnboardingView.swift:15-26`): Intro (Continue) → Primer (Connect Health / Continue without Health). `finish()` requests authorization, marks onboarding complete whatever happens, starts reconciliation (`:29-39`). Two taps to Today. Matches the plan. The page indicator lets the user swipe past Intro without tapping; fine.

### 2. Hierarchy and layout

- Intro: `VStack(spacing: 24)` with Spacers, SF symbol at `.font(.system(size: 72))` tinted, `.largeTitle.bold()` title, secondary body, `.borderedProminent` `.controlSize(.large)` Continue, `.padding(32)` (`OnboardingView.swift:46-61`). Button is not full width.
- Primer: leading-aligned `VStack(spacing: 20)`, `.largeTitle.bold()`, secondary text, eight `Label(…, systemImage: "checkmark")` in `.callout`, secondary text, full-width prominent button (`PermissionPrimerView.swift:10-31`).
- Neither page scrolls. Two different button widths and alignments between the pages.
- No custom colour; `.tint` on the symbol is system.

### 3. States

| State | Where | Note |
| --- | --- | --- |
| Health unavailable | button "Continue without Health" (`PermissionPrimerView.swift:25`) | good |
| Requesting | button disabled (`:28`) | no spinner; system sheet covers it anyway |
| Authorization threw | logged, proceeds (`OnboardingView.swift:31-35`) | fine |

### 4. Dynamic Type and layout risk

- **Both pages clip at accessibility sizes.** `PermissionPrimerView.swift:10-31` has a title, two paragraphs, eight rows and a button in a non-scrolling VStack; at AX3+ this exceeds an iPhone 11 height. Same for Intro with a long paragraph.
- `OnboardingView.swift:49`: `.font(.system(size: 72))` does not scale with Dynamic Type.

### 5. Accessibility

- Checkmark labels read "Energy", "Protein", …; the checkmark is decorative, fine.
- Page control: system.
- `withAnimation { page = 1 }` (`OnboardingView.swift:17`) is the only explicit animation in the app; it respects Reduce Motion via the system.

### 6. Copy

| String | Where | Verdict |
| --- | --- | --- |
| "Log what you eat" | `OnboardingView.swift:51` | keep |
| "Omnomnom is an entry mask for Apple Health. Search a food, type the grams, and the nutrients go to Health. No scores, no advice, no account, and it works offline." | `:53` | reword: "entry mask" is jargon. "Omnomnom logs food into Apple Health. Search a food, type the grams, done. No scores, no advice, no account, works offline." |
| "Continue" | `:57` | keep |
| "Writing to Health" | `PermissionPrimerView.swift:12` | keep |
| "Each entry is written to Health as one food with these nutrients:" | `:14` | keep |
| "Health shows write permission only; if you decline, the app keeps a local log." | `:22` | reword: "Health will ask which of these Omnomnom may write. If you decline, entries stay in this app." |
| "Connect Health" / "Continue without Health" | `:25` | keep |

### 7. Findings

1. **must** — `OnboardingView.swift:46-61`, `PermissionPrimerView.swift:10-31`. Wrap each page's content in a `ScrollView` and pin the button with `.safeAreaInset(edge: .bottom)`, full width, `.controlSize(.large)`, same on both pages. Verify at AX5 in preview.

2. **should** — `OnboardingView.swift:49`. Replace the fixed 72 pt symbol with `.font(.largeTitle)` + `.imageScale(.large)` or a `@ScaledMetric(relativeTo: .largeTitle) var size = 72`.

3. **nice** — `OnboardingView.swift:53`. Copy per the table; the plan's own words "entry mask" should not reach users.

---

## Barcode sheet

Files: `Modules/Barcode/BarcodeScanSheet.swift`, `BarcodeScannerView.swift`, `BarcodeAvailability.swift`, `BarcodeLookupFlow.swift`; entry point `Features/Add/BarcodeEntryPoint.swift`.

### 1. Fast path

Add sheet → Scan (toolbar, only when the module is on) → sheet appears; camera permission is requested on appear if undetermined (`BarcodeScanSheet.swift:72-78`) → camera reads one code → `resolve` → sheet dismisses → `onDismiss` advances to Quantity (hit) or the food editor (miss) (`BarcodeEntryPoint.swift:39-48,53-62`). Hit: three taps plus the scan. Miss: editor with barcode, name when known, then eight fields.

### 2. Hierarchy and layout

- `VStack(spacing: 0)` with the scanner at a fixed `frame(height: 280)` (`:22-28`), then a `Form` with: message section (availability or error, plus "Open app settings" when denied), "Enter barcode" section (numeric field, "Look up" button, footer with the accepted lengths), progress section (`:29-58`). Title "Scan barcode", Cancel.
- Manual entry is always present, as the plan requires.
- The scanner has no frame overlay or hint text; VisionKit highlights recognised codes itself (`BarcodeScannerView.swift:26`).

### 3. States

| State | Where | Note |
| --- | --- | --- |
| Unsupported device | "This device cannot scan barcodes. Type the digits instead." (`BarcodeAvailability.swift:23`) | good |
| Camera in use / restricted | `:24` | good |
| Camera denied | `:25` + Settings link (`BarcodeScanSheet.swift:33-35`) | here the app-settings link is correct |
| Not determined | `:26`, prompt shown at once | fine |
| Scanner failed to start | `BarcodeScannerView.swift:60,82,84,86` | fine |
| Invalid typed code | `BarcodeScanSheet.swift:85` | good |
| Resolving | "Looking up…" with spinner (`:50-57`) | fine; the camera keeps running above it |
| Miss reasons | `BarcodeLookupFlow.swift:66,71,73,75,77,116,120` | fragments shown verbatim by the editor |
| Module off but sheet reached | "Barcode lookup is off" (`:66`) | unreachable in practice |

### 4. Dynamic Type and layout risk

- `frame(height: 280)` (`:25`) is a fixed height; on an iPhone 11 in landscape or with a large keyboard the Form below has little room. Use `.aspectRatio(4/3, contentMode: .fit)` with a `maxHeight` instead.

### 5. Accessibility

- Scanner labelled "Camera viewfinder. Point it at a barcode." (`:27`). Good.
- Field labelled "Barcode digits" (`:41`). Good.
- Nothing announces a successful read before the sheet closes; the next sheet appearing is the cue. Acceptable.

### 6. Copy

| String | Where | Verdict |
| --- | --- | --- |
| "Scan barcode" | `BarcodeScanSheet.swift:60` | keep |
| "Camera viewfinder. Point it at a barcode." | `:27` | keep |
| "Open app settings" | `:34` | keep (camera permission does live there) |
| "Digits under the bars" | `:39` | keep |
| "Look up" | `:43` | keep |
| "Enter barcode" | `:46` | reword: "Or type it" |
| "8 digits (EAN-8), 12 (UPC-A) or 13 (EAN-13)." | `:48` | keep |
| "Looking up…" | `:54` | keep |
| "That is not a valid barcode. Check the digits, including the last one." | `:85` | keep |
| "This device cannot scan barcodes. Type the digits instead." | `BarcodeAvailability.swift:23`, `BarcodeScannerView.swift:82` | keep |
| "The camera is in use by another app or restricted right now." | `BarcodeAvailability.swift:24` | keep |
| "Camera access is not allowed. Turn it on in Settings to scan." | `:25` | keep |
| "Allow camera access to scan barcodes." | `:26` | keep |
| "The camera could not start: …" / "The camera is restricted or in use by another app." / "The scanner stopped: …" | `BarcodeScannerView.swift:60,84,86` | keep |
| "Barcode lookup is off" | `BarcodeLookupFlow.swift:66` | reword: "Barcode lookup is turned off. Type the values from the label." |
| "No nutrition values on Open Food Facts" | `:71` | reword: "Open Food Facts has this product but no nutrition values. Type them from the label." |
| "Not on Open Food Facts" | `:73` | reword: "Open Food Facts does not know this barcode. Type the values from the label." |
| "No connection" | `:75` | reword: "No connection, so the product could not be looked up. Type the values from the label." |
| "Lookup failed" | `:77,120` | reword: "The lookup failed. Type the values from the label." |
| "Could not save the product" | `:116` | reword: "The product could not be saved. Type the values from the label." |
| "Product 4006381333931" (fallback name) | `:104` | keep |

### 7. Findings

1. **should** — `BarcodeLookupFlow.swift:66-77,116,120`, `CustomFoodEditorView.swift:52`. Reasons are fragments displayed as a full row. Make each a sentence that ends with the next step (table above). Since `step` is pure and tested, the tests need the new strings.

2. **should** — `BarcodeScanSheet.swift:25`. Replace the fixed 280 pt height with an aspect-ratio frame capped by `maxHeight`.

3. **nice** — `BarcodeScanSheet.swift:22-28`. Add a one-line caption under the viewfinder ("Hold the code inside the frame") so an empty camera view is not the only content above the fold.

---

## Estimation sheet and draft

Files: `Modules/Estimation/EstimationSheet.swift`, `EstimationPhotoSection.swift`, `EstimateDraftView.swift`, `EstimateDraftRowView.swift`, `EstimateDraft.swift`, `EstimateConversion.swift`, `EstimateLogger.swift`, `EstimationAvailability.swift`, `EstimationError.swift`; entry point `Features/Add/EstimationEntryPoint.swift`.

### 1. Fast path

Add sheet → Estimate (toolbar, module on; availability checked at tap, alert if not) → sheet: description field (not focused), optional photo section on iOS 27, "Estimate" button in a Form section → progress with Cancel → draft pushed via `navigationDestination(item:)` (`EstimationSheet.swift:80-82`) → "Log N items" top-right → both sheets close, banner on Today. Taps: Estimate, field, Estimate, Log = 4 plus typing. The field not being focused adds a tap.

### 2. Hierarchy and layout

- `EstimationSheet.swift:38-72`: `Form` with "Describe the meal" (vertical-axis `TextField`, 1…4 lines), photo section (thumbnail 72×72, "Choose photo", "Take photo", "Remove"), unavailable message, an action section holding the Estimate button or the progress row, an error line, and a footer. The primary action is an in-form button, unlike every other sheet where it is a `.confirmationAction`.
- `EstimateDraftView.swift:38-77`: `Form` with "Assumptions" (note + warnings), "Items" (editable rows), "Totals" (`NutritionPreview`), Meal/Time, error. "Log N items" top-right; back button returns to the input.
- `EstimateDraftRowView.swift:12-42`: name field + remove button, "Portion" row with a 100 pt field, then a `LazyVGrid(.adaptive(minimum: 150))` of eight `EstimateValueField`s (caption label, 72 pt field, unit). Dense but structured.
- Colour: red on invalid (`:29,69`).

### 3. States

| State | Where | Note |
| --- | --- | --- |
| Unavailable (four reasons) | `EstimationAvailability.swift:39-51`; alert at the entry point, message in the sheet | names the reason, as the plan asks |
| Text-only tier (iOS 26) | photo section hidden (`EstimationSheet.swift:44-46`); message "photos need iOS 27" only via availability text | fine |
| Estimating | spinner + Cancel (`:54-60`) | good |
| Nothing recognisable | `:109` | good |
| Model errors | `EstimationError.swift:22-27,50-58,66-77` | fine; mixed sentence case (see copy) |
| Photo load errors | `EstimationPhotoSection.swift:62,85,91,104` | fine |
| Draft invalid | Log disabled (`EstimateDraftView.swift:85`) | no explanation |
| Saving | Log disabled only | no spinner |
| Logged | banner "Logged 3 estimated items." + problems (`EstimateLogger.swift:12`) | good |

### 4. Dynamic Type and layout risk

- `EstimateDraftRowView.swift:30,70`: `frame(maxWidth: 100)` and `72` on text fields; at AX sizes four-digit values will not fit 72 pt. Use `@ScaledMetric` or drop the cap and let `LabeledContent` lay out label/field.
- `:63` `lineLimit(1)` on nutrient short names inside a 150 pt-min cell: "Sat. fat" truncates at AX sizes. Remove the limit; the grid already adapts to one column.
- `EstimationPhotoSection.swift:31` 72×72 thumbnail: fixed but decorative; fine.
- `EstimationSheet.swift:41` `lineLimit(1...4)`: fine.

### 5. Accessibility

- Description field labelled (`EstimationSheet.swift:42`). Name, portion and value fields labelled with unit (`EstimateDraftRowView.swift:15,31,71`). Remove button labelled with the item name (`:20`). Thumbnail labelled (`EstimationPhotoSection.swift:33`). Good coverage.
- Progress row: `ProgressView` + "Estimating…" are separate elements; combine.
- No announcement when the draft is pushed; navigation handles focus.

### 6. Copy

| String | Where | Verdict |
| --- | --- | --- |
| "Estimate a meal" | `EstimationSheet.swift:73` | keep |
| "Describe the meal" | `:39` | keep |
| "Two scrambled eggs and a slice of rye toast" (placeholder) | `:40` | keep |
| "Estimating…" / "Cancel" / "Estimate" | `:57,59,62` | keep |
| "Estimates are rough and made on this device. You check every value before it is logged." | `:70` | keep |
| "Nothing recognisable came back. Try a fuller description or a clearer photo." | `:109` | keep |
| "Photo" / "The photo stays in memory on this device and is not saved anywhere." | `EstimationPhotoSection.swift:75,77` | keep |
| "Choose photo" / "Choose another photo" / "Take photo" / "Remove" / "Photo of the meal" | `:41,52,35,33` | keep |
| "The photo could not be encoded." / "That item could not be read as a photo." / "Could not load the photo: …" / "That file is not a photo the device can read." | `:62,85,91,104` | keep |
| "Ready. Describe a meal or add a photo of it." / "Ready. Describe a meal in words; photos need iOS 27." | `EstimationAvailability.swift:40,42` | keep (Settings only) |
| "This device does not support Apple Intelligence, so meals cannot be estimated." | `:44` | keep |
| "Turn on Apple Intelligence in Settings to estimate meals." | `:46` | keep |
| "The on-device model is not ready yet; it downloads on its own. Try again later." | `:48` | keep |
| "Meal estimation is not available right now: …" | `:50` | keep |
| "Photos need iOS 27. Describe the meal in words instead." / "Cancelled." / "The on-device model declined this request. Try a plainer description of the food." / "The description is too long for the on-device model. Shorten it and try again." | `EstimationError.swift:22-25` | keep |
| "Estimation failed: too many requests; try again in a moment." etc. | `:26,52-56,71-75` | reword the fragments to start with a capital and stand alone: "Too many requests. Try again in a moment." |
| "Check the estimate" | `EstimateDraftView.swift:78` | keep |
| "Assumptions" | `:40` | keep |
| "Energy for X was computed from its macros." | `EstimateConversion.swift:43` | keep |
| "Items" / "Values are for the portion. Blank means unknown." | `:56,58` | keep |
| "Totals" / "Meal" / "Time" | `:60,64,69` | keep |
| "Log 1 item" / "Log 3 items" | `:34` | keep |
| "Could not save: …" | `:98` | keep |
| "Name" / "Food name" / "Remove item" / "Portion" / "Portion in grams" / "unknown" | `EstimateDraftRowView.swift:14-15,20,23,31,65` | keep |
| "Unnamed food" | `EstimateConversion.swift:23` | keep |
| "Logged 3 estimated items." | `EstimateLogger.swift:12` | keep |

### 7. Findings

1. **should** — `EstimationSheet.swift:40-42`. Focus the description field on appear (`@FocusState` + `.task`), matching the Add and Quantity sheets.

2. **should** — `EstimationSheet.swift:53-71`. Move Estimate to `ToolbarItem(.confirmationAction)` and show the progress/Cancel pair in its place while running, so the sheet follows the same top-right confirm pattern as Quantity and the editors. Keep the footer sentence.

3. **should** — `EstimateDraftRowView.swift:30,63,70`. Drop the fixed field widths and the `lineLimit(1)`; use `LabeledContent(nutrient.shortName) { TextField … }` per cell so AX sizes wrap cleanly.

4. **nice** — `EstimateDraftView.swift:80-87`. Add a `ProgressView` in the toolbar while saving and a footer sentence when Log is disabled ("Every item needs a name and a weight").

5. **nice** — `EstimationSheet.swift:54-60`. `.accessibilityElement(children: .combine)` on the progress row.

---

## Cross-cutting

### Repeated patterns to unify

| Pattern | Occurrences | Proposal |
| --- | --- | --- |
| Caption meta line (`HStack(spacing: 6)` of secondary `.caption` texts) | `EntryRow.swift:21-36`, `ForeignMealsSection.swift:14-19`, `ChoiceRow.swift:12-25`, `SearchResultsList.swift:61-68`, `LibraryRows.swift:24-29,43-50` | `MetaLine` view: takes an array of `Text`, joins with " · " in an `HStack`, switches to a `VStack` when `dynamicTypeSize.isAccessibilitySize`. |
| Badge capsule | `EntryRow.swift:49-58` (private) | Promote to `Badge(text)`; reuse for "Estimated", health states and, later, a source badge on foreign rows. |
| Two-line name + caption trailing value row | Today, foreign, Add, Library rows | `TitleCaptionRow(title:, caption:, trailing:)` built on `MetaLine`; one file instead of five near-copies. |
| Notice at the bottom | `BannerView.swift:6-27,31-54` | One `Notice(message:, action: (title, run)?, dismiss:)` with `.regularMaterial`, optional auto-dismiss. Both Today notices use it. |
| Bottom primary action | Today (missing), Quantity (missing), Onboarding (two variants) | `BottomAction(title:, action:)` = `safeAreaInset(edge: .bottom)` + full-width `.glassProminent` (fallback `.borderedProminent`) `.controlSize(.large)`. |
| Numeric values | `TotalsRow.swift:66-68`, `NutritionPreview.swift:16-17`, `EntryRow.swift:39-40`, `ForeignMealsSection.swift:22-23` | `ValueText(value, unit:, emphasis:)` with `.monospacedDigit()` and an `.accessibilityValue` that says "not recorded" for nil. |
| Validated decimal field | `AmountField.swift`, `IngredientRow.swift:16-22`, `NutrientField.swift:17-30`, `EstimateDraftRowView.swift:26-34,59-76` | `DecimalField(text:, unit:, label:, isValid:)` with select-all-on-focus, red-on-invalid plus an accessibility value, and the unit hidden from VoiceOver. |
| Error/status row in a Form | `QuantitySheet.swift:68-73`, `RecipeEditorView.swift:70-75`, `CustomFoodEditorView.swift:76-81`, `LibraryView.swift:58-63`, `EstimateDraftView.swift:71-76`, `EstimationSheet.swift:65-68` | `FormMessage(text)`; same secondary style. Better: `.alert` for save failures, footer for validation. |
| Raw `error.localizedDescription` to the user | `AddFoodSheet.swift:131`, `LibraryView.swift:101`, `SourcesView.swift:70`, save errors | Map repository errors to fixed sentences; keep the raw text in `AppLog`. |
| Section titles | "Yours" ×2, "Database", "Modules", "Custom foods and products", "Bundled database" | Per copy tables. |
| Toolbar placement | Cancel `.cancellationAction` + confirm `.confirmationAction` in Quantity, both editors; Estimate in-form; Add sheet has up to two `.primaryAction` icons from separate modifiers | Same top pair everywhere; Estimate moves to the toolbar. |
| Sheet detents | Only Quantity sets `[.medium, .large]` | Decide from the preview; likely `[.large]` for Quantity. Leave the rest at the default. |
| Formatters | `\(foodCount)` unformatted (`LibraryView.swift:66`); "–" for unknown (`Formatters.swift:7`) | `formatted()` everywhere; keep "–" visually, add an accessibility form. |
| "Previously logged … unchanged." lines | `RecipeEditorView.swift:65`, `CustomFoodEditorView.swift:71` | Same wording; fine as is, could share a `Text` constant. |

### Thin helpers worth introducing

Each is a single small file under `Features/Shared/` (new folder), no dependencies, no custom colours or type sizes:

- `Badge` — capsule caption on `.quaternary`.
- `MetaLine` — wrapping caption row.
- `ValueText` — monospaced-digit number with unit and an accessible nil form.
- `Notice` — bottom material banner with optional action and auto-dismiss.
- `BottomAction` — one-handed primary button in a bottom safe-area inset.
- `DecimalField` — validated numeric field with select-all-on-focus.

No spacing or type tokens beyond these; system fonts and default List/Form metrics carry the layout.

### Screens and states for the preview step

Preview each at Default and AX3 (and AX5 for Today totals and Onboarding), light and dark:

1. Today: empty day; empty day with yesterday logged (copy affordance); three meals with a recipe entry and an estimated entry; entries in `partial`, `gone`, `unauthorized`, `orphaned`; foreign meals section with the foreign note; banner + unauthorized notice stacked; date picker popover; a past day.
2. Add sheet: first run (no recents); recents + "Yours"; typing with results in both sections; no results; database error; pick mode; module buttons present.
3. Quantity: bundled food with portions (prefilled first portion, keyboard up, medium detent); bundled with last amount; recipe with servings chips; product with brand and attribution; invalid amount hint; saving.
4. Library: first run; populated; delete error; recipe editor new and editing-with-entries; custom food editor new, editing, and product-from-miss with each reason.
5. Settings: unavailable, none, partial, all authorized; estimation unavailable message; Sources with the manifest and both static sections.
6. Onboarding: both pages at AX5; Health unavailable variant.
7. Barcode: available with camera; denied; unsupported; typed invalid; resolving.
8. Estimation: text tier; photo tier with thumbnail; estimating; each error; draft with two items, one invalid; draft Log disabled.

### Proposed order for the screen pass, with estimated change counts

| Step | Scope | Changes |
| --- | --- | --- |
| 1 | Shared helpers (`Badge`, `MetaLine`, `ValueText`, `Notice`, `BottomAction`, `DecimalField`, error mapping) | 6 new files, ~4 edits to adopt |
| 2 | Today (findings 1–11) | ~10: bottom add, title/date, copy-yesterday + empty-state button, button rows + context menu, `MetaLine`, notice link, banner behaviour, dedupe, totals a11y, copy |
| 3 | Quantity (findings 1–7) | ~7: selection, detent, chip order, monospaced preview, saving state, bottom Log, chip hint |
| 4 | Add sheet (findings 1–5) | ~5: in-context modules, searching state, error text, row layout, copy |
| 5 | Onboarding (findings 1–3) | 3 |
| 6 | Library and editors (findings 1–6) | ~7 |
| 7 | Settings (findings 1–4) | 4 |
| 8 | Barcode (findings 1–3) | 3 |
| 9 | Estimation (findings 1–5) | 5 |

Roughly fifty edits, front-loaded on the two screens the fast path runs through. Steps 2 and 3 should be previewed together, since the bottom action and the detent decision interact with the keyboard.

## Screenshot findings

Recorded from the first simulator captures (22 September 2026), light and dark at default size and at accessibility 5. These supersede the code-side guesses above where they differ.

### Today

Agreed change list, implemented as one commit:

1. The date becomes the navigation title with the full date as subtitle; day chevrons and a calendar button move to the toolbar; the sticky day bar goes. The duplicate "Today" was visibly a bug.
2. A bottom "Add food" glass-prominent button in the safe-area bar; the toolbar plus stays.
3. Totals card: energy as a hero line, then protein, carbs and fat, then the four secondaries. The energy value "1.189…" was truncated at default size in the four-column grid.
4. One notice slot in the bottom bar: transient banners auto-dismiss, the permission notice persists with plain copy and an "Open Health" action.
5. One badge style; wording "Partly in Health", "Missing from Health", "Not written to Health", "Only in Health"; a chevron on rows that open the restore dialog.
6. Captions: integer grams and a middle dot separator everywhere.
7. Empty day: "Nothing logged", the bottom button as the call to action, and "Copy yesterday" when yesterday has entries.

Confirmed fine: dark mode; the accessibility 5 single-column totals; the foreign share line.

### Add sheet

- **Module buttons are never visible.** Scan and Estimate sit in the top toolbar, and iOS 26 hides the navigation bar while search is active, which this sheet is from the moment it opens. Move them into the content: a row of two bordered buttons above Recent when enabled, and in the no-results and no-recents states. Done: `ModuleButtonsRow` (two large bordered buttons, side by side or stacked at large type) is a list row above Recent, under the no-recents and no-results placeholders, only in log mode and only with a module on; the entry-point modifiers no longer add toolbar items and start their flow from a `Binding<Bool>` the row flips, with the same availability checks as before.
- **Captions interleave at large sizes.** "Last 1,5 servings" and "313 kcal per serving" are side-by-side texts, so at accessibility 5 they wrap into each other's lines. One `Text` with " · " separators that wraps naturally. Done: `ChoiceRow` and the bundled `ResultRow` each build one `ValueText` joined with " · ".
- Double spaces between caption parts at default size; same fix. Done: gone with the single joined caption.
- The bottom search field with the circular close button is the right shape for one-handed use; keep. Done: unchanged.
- "Yours" mixes recipes, custom foods and products with only "per serving" versus "per 100 g" to tell them apart; acceptable, revisit with the Library pass.

### Quantity sheet

- **Log is top-right.** Bottom "Log" glass-prominent button in the safe-area bar; the field stays focused above it.
- **Prefilled field appends digits.** Cursor sits after the prefilled value; select all on focus.
- **Accessibility 5 breaks the card.** The unit label hyphenates to "serv-ings" beside the field, chips clip off the right edge, and the three-column nutrition grid hyphenates its labels. Unit below the field at large sizes, chips in a wrapping layout, and the nutrition grid degrading to a single column like Today.
- "Raw weight 350,6 g" and the prefilled "33,9 g" carry decimals; integers in captions and prefill rounding to one decimal at most.
- The title "Amount" is neutral; the food name in the card carries the meaning. Keep.
- Brand line, attribution footer, meal and time rows: fine.
