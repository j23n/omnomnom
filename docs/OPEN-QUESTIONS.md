# Open questions and flags

Kept while the G2 design was implemented. Everything here is either a decision somebody
other than the implementer should make, a thing that is true and worth knowing, or a place
the next pass should look first. Nothing here is a bug report: what is known to be wrong is
fixed or written down as a deviation in `DESIGN.md`.

## Not verified by a build

1. **Nothing in the design implementation has been compiled or run.** There is no Swift
   toolchain in the container this was written in. Every Swift change is reviewed by hand,
   with imports checked against member-import visibility and braces checked mechanically,
   and that is not the same as a build. **This is the first thing to do next.**
2. **Three schema additions have not been migrated against a real store.** `LogEntry.wording`,
   `LogEntry.guessed` and `DayRecord.skippedSlotNames` all have defaults, so SwiftData's
   lightweight migration should take them, but nobody has watched it happen.
3. **Nothing that touches a `ModelContext` has a test.** The pure parts are covered —
   roughly a hundred new assertions over the split of a line, the undo's wording, the mark,
   the tray, the headline, the run and the loose ends. What is untested is every path that
   writes: `undo`, `settle`, `replaceFood`, `logUsual`, `logTray`, and the loose-ends
   reading. `ComposerModel.submit` is untested for the same reason — it needs a live
   `LineResolver`.

## Decisions somebody should take

4. **Dark mode for the three macronutrient colours is unresolved, and deliberately so.**
   Measured, not overlooked: inside the dark lightness band, tangerine and the fat hue
   cannot be got 15 ΔE apart under normal vision. The honest options are a different third
   hue or two hues and a neutral. `NutrientPalette.darkModeIsUnresolved` records it, and
   until it is answered the light values are used in both appearances and are too heavy in
   the dark one.
5. **Answering all four meals does not close the day.** The ring in the mark fills when
   every meal has an answer; the run counts `DayState.isAnswered`, which needs the day
   *marked* complete. The loose-ends queue bridges them with a last card, so clearing the
   queue does close the day — but the question stands: should four answers close it by
   themselves? Doing it automatically would assert "this is everything I ate" without a
   tap, which is the one thing the app has never done.
6. **The field is on Settings too.** That is what "the composer on every tab" means and it
   was asked for twice, but Settings is the one tab where a food field may read as a
   mistake. Worth looking at on a device before defending it.
7. **A tray changes what a row tap does.** Once a tray has something in it, tapping a
   search result adds to the tray instead of opening the Quantity sheet, because one rule
   has to hold while a tray is up: nothing is logged until Log is tapped. The bar says so
   in words. The alternative was a sheet that logged one food and closed the screen on
   four others the user had gathered. Needs trying on someone.
8. **The undo offer is on no timer.** It stays until the next send, a change of day, or a
   dismissal, because for the two paths that write in one tap — a widget tap, and accepting
   a usual meal — it is the only way back. It is also therefore in the way for as long as
   it is up.

## True, and worth knowing

9. **A resolved line lives in memory until it is signed off.** Quit with the sign-off
   screen up and the parse is gone; the typed line is gone with it. Nothing was logged, so
   the record is not wrong — only the retyping is annoying. Making it survive a launch
   means storing a resolved row, which is a schema decision.
10. **One undo offer at a time.** A second send replaces the first offer, so the earlier
    line's entries lose their one-tap undo. They are still one swipe each on the day.
11. **"Leave it" on a missing figure is remembered for the visit only.** It will be back
    tomorrow. A dismissal that outlived the day would be a standing instruction never to
    mention a nutrient again, which is not what the button says.
12. **Correcting a guessed food is a delete and a fresh log.** The entry takes a new
    identity, so its Health samples are deleted and written rather than versioned, and an
    unshared photo would go with the row it belonged to. No markable row carries a photo
    today, so that last part is theory.
13. **The run and Shape can disagree about a day.** The run counts days *this app* was told
    about, because that is what answering means; Shape reads Health, which counts every
    source once. A day logged only in another app is a day Shape draws and the run does
    not.
14. **The run's window is two years.** Bounded so the fetch behind it cannot grow without
    limit, which makes "your best" a fact about the last two years rather than about all
    time.
15. **A tray teaches the app nothing.** No line was typed, so no phrase is remembered. The
    entries carry `EntryOrigin.picked`, which is what they are.
16. **Several screens now stack three sheets deep** — Today, the loose ends, the match
    question, and the food search over that. Legal, and worth looking at on a device.
17. **`picksSeveral` in `FoodSearchView` is dead** and was before this work started.

## Where the matcher is still mediocre

Measured against the real `foods.sqlite` with a hundred written lines. None of these is a
wrong row logged quietly — every one is underlined and asks — but they are the next pass's
list.

18. **"peanut" answers with *Peanut butter***, which is a prefix match on a compound
    beating the plain ingredient. The clearest of the three.
19. **"minced lamb" answers with *Minced meat soup*.**
20. **"aubergine, cooked" answers with *Aubergine salad with lemon marinade*.**
21. **"pasta, cooked" has no good answer in the tables.** The best is
    *Spinach-filled pasta squares*; there is no plain cooked-pasta row with a competitive
    name.

## Already corrected, recorded so it is not re-derived

22. An earlier entry in `MILESTONES.md` claimed the estimation prompt "ought to ask for the
    dish's own name first". It already asks for the opposite, deliberately: a dish is to be
    broken into the staples it is made of and `lookupTerm` is never a dish name. The test
    stub violated the prompt, not the other way round. Re-measured with prompt-faithful
    items, the matcher fix costs no blocked rows at all.

## The three passes not done

23. iPad layout, dark mode, and the largest accessibility type sizes. None of them fits in a
    390-wide frame, and all three are most likely to break on the mark's 46 pt core and its
    four-segment ring. `DESIGN.md` says the same under "Not yet drawn".
