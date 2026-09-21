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
