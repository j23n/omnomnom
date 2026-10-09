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
3. **The write paths that touch a `ModelContext` have no test.** Reading one is covered:
   `BaselinePhraseTests`, `LineResolverTests`, `LineResolverToolsTests`, `PhotoTests`,
   `PhraseTests` and `TagTests` each build an in-memory container from `StoreSchema` and
   assert against it. So are the pure parts — roughly a hundred new assertions over the
   split of a line, the undo's wording, the mark, the tray, the headline, the run and the
   loose ends. What is untested is every path that *writes*: `undo`, `settle`,
   `replaceFood`, `logUsual`, `logTray`, and the loose-ends reading. `ComposerModel.submit`
   is untested for the same reason — it needs a live `LineResolver`.

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

8b. **With product search on, a line is looked up abroad food by food.** It used to go to
    Open Food Facts only where the bundled tables drew a blank; now every term a line names
    is sent, so a four-food line is four requests. It is one request per unrecalled item —
    a line recalled from memory asks nothing, and `ProductResults.isWorthSearching` drops
    the terms not worth a round trip — but it is a real change in what leaves the device and
    in how long a line takes to resolve on a slow connection. The Settings paragraph that
    governs the opt-in now says so. If it proves too slow, the fix is to ask both at once
    rather than one after the other; that was left out deliberately, because handing a
    main-actor closure to a child task is exactly the kind of change that should not be made
    blind in a session that cannot compile.

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

## Measured, settled or still to check

Moved here from the plan's open risks, which now carries only the risks that are properties
of the design. These are statements about what has been measured, what has been settled and
what nobody has looked at yet, which is this file's job rather than the plan's.

24. **Health app rendering of correlations is unverified.** The correlation is the right
    structure to write regardless, but no UX copy may promise a "meal" in Health until the
    milestone 2 device check confirms it. That check is listed, with its outcome, under
    "Milestone 2 › Device checks" in `MILESTONES.md`.
25. **Nutrient identifiers are unverified against the current FDC files.** The column
    mapping table is from the published FDC identifier list; the pipeline's first run
    confirms it and fails loudly otherwise.
26. **The curated popularity list is FDC-shaped.** It ranks foods by their FDC
    descriptions, so with FDC out of the build it matches nothing and search falls back to
    relevance alone. Rewriting it against the Ciqual and BLS names is a sitting's work once
    their real names are in front of us.
27. **Items 26 and 28 disagree and one of them is stale.** 26 says the list is FDC-shaped
    and matches nothing; 28 says it has been rewritten against the real BLS names and all of
    it matches. Both were carried in the plan at once. Whichever is current, the other
    should go — reading `Tools/fooddb` settles it.
28. **The popularity prior is settled, and it had to be stronger than a prior should be.**
    The list is rewritten against the real BLS names, and all of it matches. What the real
    data showed is that a prior cannot be a tie-breaker here: a derivative is often the
    *better* text match for a bare noun, because "Milk chocolate" really does start with
    "milk" while the table calls the drink "Whole milk, 3.5 % fat". No text scoring separates
    those correctly. So the prior is worth more than the gap between two match tiers, and it
    is mostly a flat floor for being on the list at all rather than a function of position.
    The licence for that is what the list holds: around seventy-five foods, each curated as
    *the* form a person means by its bare name, so the prior can only ever promote something
    somebody chose deliberately. A curated entry that is the wrong answer to a bare noun is
    therefore a bug in the list, and "Milk chocolate" was removed for being one.
29. **Auto-matching is measured rather than assumed, but only on the easy cases.** Bare-noun
    queries resolve correctly on 21 of 21 cases against the real 7,140-row table, against
    roughly 2 before four faults were found by running it. That is a floor, not a result:
    those are the easy cases, every one is a single word, and the honest test is a fixture
    set of real typed *lines*. What the exercise established is less the score than the
    method — the faults were invisible to reasoning and obvious to data, and two of them
    were in places nobody would have looked, the scorer disagreeing with the retriever about
    what a word is and a clamp quietly making every strong match identical. Why
    auto-matching is the bet at all stays in the plan.
30. **Four tabs and a composer is a bigger surface.** Three tabs kept the fast path fast.
    Trends is a fourth, and the composer adds a persistent control to the busiest screen in
    the app. The counter-argument is that the composer *replaces* the Add sheet as the
    default path rather than joining it, so the common case gets shorter even as the surface
    grows. Worth re-checking against the yardstick once it is drawn.
31. **The twenty-second target is measured on a population selected against it.** Drawing
    the journeys exposed this and it is worth stating carefully, because it makes a
    reassuring number untrustworthy. Logging something new clears twenty seconds comfortably
    *when the database words the food the way the user does*. But a food whose wording
    matched would have been resolved by the matcher and would never have reached that
    journey in the first place, so the cases that actually arrive there are exactly the ones
    where the wording did not match — and those need a search, possibly a second screen of
    it, and land at or over the target. The measurement is not wrong; the thing being
    measured is selected against. The fix is not a design change: it is instrumentation on
    real lines, counting how often an item reaches the search at all, which is another
    reason the matcher is the critical path.

## What one path for a line leaves open

With the ladder deleted, a model that searches the database for itself is the only thing
that reads a typed line. This is what follows from that, and not one of these is answerable
by reading.

32. **Apple's on-device model no longer reads a typed line, and whether it could is a device
    question.** It takes no tools, so it cannot search the tables, and guessing their
    wording is exactly what was deleted — the measured case is "Pasta, cooked" resolving to
    *Fish, cooked (average)*. On device is still the default provider, so out of the box the
    composer answers only a line logged before. Whether something loop-shaped can be built
    on Foundation Models at all — a session asked for a search term, handed rows, and asked
    again, which is the loop done by hand — is not a thing to settle in a document: it needs
    a device with Apple Intelligence, the real tables, and the twenty-second budget measured
    against a few real lines. Until somebody runs it, the honest position is that the
    primary input needs a key.
33. **The composer's camera went with it, and the choice there is a product decision.** A
    photograph attached in the composer is `.photo` input to the same `LineDriving` path a
    typed line takes, so on device it cannot be read either and the composer says no model
    is set up to read it. The Add screen's photo estimate still works on-device by
    construction, so the capability has moved rather than vanished — but one of three has to
    be chosen: the composer's photo falls back to a description-only on-device estimate with
    no database grounding behind it, or the composer's camera button hides itself when the
    provider cannot read a photograph, or it stays as it is and Settings carries the
    explanation. Settings currently says the on-device provider "cannot read a typed line",
    which is honest about the typed case and silent about the photographed one.
34. **"OpenAI-compatible" is a family resemblance, and there is no longer anything to fall
    back to.** `LineDriving` needs a server that takes tool definitions, returns tool calls
    and accepts tool results back, and plenty of what answers at `/v1/chat/completions`
    does one of those badly or not at all. Before, an endpoint that could not hold a
    conversation could still name foods for a retriever to look up; now an endpoint without
    working tool support cannot read a line at all, and what the user sees is a line that
    resolves to nothing rather than a feature that is missing. What that should do — refuse
    at the point the endpoint is configured, degrade to something, or say so after the first
    line fails — is unanswered, and the first step is finding out what the common
    self-hosted servers actually do with a tool definition.
35. **Nothing grades a row from a score any more, and two measured numbers have no reader.**
    `settledAt` and `FoodMatch.confidence` are how a row was graded while the app matched
    foods on a model's behalf: the score decided whether a row settled, was marked for a
    glance, or blocked. With one path left, a row's confidence is the certainty of the model
    that chose it, capped by the ingredient rule, so `FoodMatch.confidence` has no caller
    and `settledAt` is a measured number nothing reads. Only `probableAt` is live, as the
    bar that decides whether a term found its food well enough to stop dropping words from
    it. The question is whether anything should ever grade a row without a model again — a
    food picked from search is `chosen` and settled by the act of picking it, and a line
    nothing can read has no rows at all, so there may be no case left to serve — and if
    there is not, those thresholds are a measurement worth keeping written down rather than
    code worth calling. Related: the sign-off sheet's unchecked sentence for a bundled row,
    "Matched by name", now has no path that produces it for the same reason.
