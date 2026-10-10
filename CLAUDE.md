@.apple-ci/claude/j23n.md
@.apple-ci/claude/apps.md

# Omnomnom

An offline iOS nutrition tracker that writes to Apple Health (README.md). `PLAN.md` is the technical plan, `docs/MILESTONES.md` the build status log.

## Commits

Never reference milestones, phases, plan sections, revisions or review rounds. A reader without the plan must understand what changed and why from the message alone.

## Code

- No third-party dependencies in the app target or in `Tools/fooddb`. FeedbackKit is the one package (README.md, "Feedback").
- Swift: Swift 6 language mode, strict concurrency, default actor isolation `MainActor`. No `HK` type leaves the HealthKit actor.
- The app's own `make` targets build the food database: `make fooddb` and `make test-fooddb` (README.md, "Build the food database first").
- Feedback screenshots: FeedbackKit's `.allContent` redaction hides every text and image (`Omnomnom/Support/FeedbackSupport.swift`), so a new view needs nothing. Never mark a view that shows someone's data `.unredacted()`.
- Python: 3.9 or newer (Xcode's bundled `python3` is 3.9), standard library only, type hints, `python3 -m unittest` from `Tools/fooddb`.
