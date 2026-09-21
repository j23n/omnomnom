# Working conventions

## Commits

Commit messages describe the change on its own terms. Never reference milestones, phases, plan sections, revisions or review rounds; a reader without the plan must understand what changed and why from the message alone. Subject line in the imperative, under 72 characters, body explains the reasoning where it is not obvious.

## Code

- No third-party dependencies in the app target or in `Tools/fooddb`.
- Swift: Swift 6 language mode, strict concurrency, default actor isolation `MainActor`. No `HK` type leaves the HealthKit actor.
- Python: 3.11, standard library only, type hints, `python3 -m unittest` from `Tools/fooddb`.

## Documents

`PLAN.md` is the technical plan, `docs/MILESTONES.md` the build status log.
