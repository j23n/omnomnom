# Milestones

Status log for the build order in `PLAN.md`. Each milestone is planned, implemented, reviewed by a separate pass, then signed off here before the next one starts.

| # | Milestone | Status | Sign-off |
| --- | --- | --- | --- |
| 1 | Data pipeline (FDC) | in progress | |
| 2 | Log to Health end-to-end | pending | |
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

Pending.

### Sign-off

Pending.
