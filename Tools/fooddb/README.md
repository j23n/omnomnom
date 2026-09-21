# fooddb

Builds the bundled food database that the app ships read-only: `Omnomnom/Resources/foods.sqlite` and the attribution manifest `Omnomnom/Resources/sources.json`. Python 3.11, standard library only.

The v1 source is USDA FoodData Central (FDC), Foundation Foods plus SR Legacy, licensed CC0 1.0. The pipeline is written per source so a second source later is a mapping table and a dedup rule, not a rewrite.

## Download

The CSV bundles live under `https://fdc.nal.usda.gov/fdc-datasets/` (linked from the [FDC download page](https://fdc.nal.usda.gov/download-datasets)). The pinned versions are the defaults in `fooddb/download.py`.

```sh
cd Tools/fooddb
python3 -m fooddb download                 # into Tools/fooddb/downloads/ (git-ignored)
python3 -m fooddb download --dest ~/fdc    # elsewhere
python3 -m fooddb download --foundation-url https://fdc.nal.usda.gov/fdc-datasets/FoodData_Central_foundation_food_csv_2026-01-01.zip
```

Each zip is fetched over https into a temp file, renamed into place, verified, and unzipped into `<dest>/<zip name without .zip>/`. Members with absolute paths or `..` are rejected. An existing zip is not re-fetched unless `--force` is given.

If the sandbox blocks fdc.nal.usda.gov, download on a Mac (or with a browser) and point `build --fdc` at the folder holding the unzipped bundles.

### Pinning hashes

`download.py` holds a `PINS` table with an optional `size` and `sha256` per zip. When both are `None` the download logs the computed values as a warning:

```
WARNING fooddb.download: FoodData_Central_sr_legacy_food_csv_2018-04.zip: no pinned sha256, integrity NOT verified. Computed size=... sha256=...; paste both into PINS in fooddb/download.py to pin this file
```

Copy them into the `Pin(...)` entries. From then on a mismatch deletes the cached zip and fails with exit code 1, so the next run fetches it again. Redirects are followed only while they stay on https, and each request times out after 60 s. Overriding a URL on the command line drops the pin for that bundle, since the pinned hash belongs to the pinned file.

## Build

```sh
cd Tools/fooddb
python3 -m fooddb build --fdc downloads
python3 -m fooddb build --fdc ~/fdc --out /path/foods.sqlite --sources-out /path/sources.json
python3 -m fooddb build --fdc downloads --popular my_popular.txt   # alternative ranking list
python3 -m fooddb -v build --fdc downloads   # debug logging
```

`--popular` points at a different curated list (default `fooddb/curated/popular.txt`): one FDC description per line, most common first, `#` comments allowed. Entries that match no food are logged as warnings.

`--fdc` accepts either a directory containing the CSVs directly or a directory containing one subdirectory per bundle at any depth. Bundles are recognised by `food.csv` plus `foundation_food.csv` or `sr_legacy_food.csv`. The dataset version recorded in `meta` and `sources.json` is the first `YYYY-MM[-DD]` found in the bundle folder name or its parents (so keep the zip's folder name), else `unknown`.

The build is idempotent: outputs are written to a temp file beside the target and renamed over it. If `--out` or `--sources-out` is a symlink, the symlink itself is replaced by a regular file; the link target is left untouched. The default outputs are `Omnomnom/Resources/foods.sqlite` and `Omnomnom/Resources/sources.json`. Both are git-ignored; run the build before opening the Xcode project. Set `SOURCE_DATE_EPOCH` for a reproducible `built_at`.

It ends with a summary:

```
Build summary
  fdc_foundation: N foods kept, M dropped (no energy), B dropped (blank name)
  fdc_sr_legacy: N foods kept, M dropped (no energy), B dropped (blank name)
  SR Legacy duplicates of Foundation dropped: D
  portions: P
  unmatched popular entries: U
```

Any validation failure (missing bundle, missing nutrient id, unexpected unit, malformed CSV value, negative or non-finite amount, duplicate `fdc_id`, a bundle with no usable foods, unwritable output, bad zip) logs an error with file and line where known and exits 1. Implausible values (over 900 kcal, over 100 g of a macronutrient, or over 100 g of sodium per 100 g), duplicate nutrient rows and unexpected `data_type` values are warnings.

## Test

```sh
cd Tools/fooddb
python3 -m unittest -v
python3 -m mypy --strict fooddb tests   # optional: pip install mypy ruff
ruff check .
```

The tests run against synthetic bundles in `tests/fixtures/fdc/` that mirror the FDC column layout and cover the fallback, dedup, portion and dropping rules, plus an end-to-end build into a temp directory.

## Outputs

`foods.sqlite` (schema in `fooddb/schema.sql`, `journal_mode=DELETE`, vacuumed):

- `foods`: one row per food. `id` is assigned by the build; `source` (`fdc_foundation` / `fdc_sr_legacy`) and `source_ref` (the FDC id) carry provenance. Nutrients are per 100 g; `kcal_100g` is never null, everything else is null when FDC has no value (never 0). `is_estimated` is 0 for every FDC row. `popularity` is a ranking boost from `fooddb/curated/popular.txt` (100 for the first line, decreasing, 0 for everything else).
- `foods_fts`: FTS5 external-content index over `name` (`unicode61`, diacritics removed). Query with `SELECT ... FROM foods_fts WHERE foods_fts MATCH ?`.
- `portions`: household measures per food, `label` such as `1 cup, chopped`, `0.5 cup` or `1 medium (3" dia)`, with `grams` and a display `seq`. With a real measure unit the label is `amount unit[, modifier]`; with FDC's "undetermined" unit the label is `portion_description` verbatim (it already embeds the amount), else `amount modifier`. Rows with no gram weight or no usable label are skipped.
- `meta`: `schema_version`, `built_at`, `fdc_foundation_version`, `fdc_sr_legacy_version`, `food_count`, `portion_count`.

Rules applied while building: energy prefers nutrient 1008, then 2047, then 2048; fiber 1079 then 2033; sugar 2000 then 1063. A food without any energy value is dropped. An SR Legacy food whose normalised description (casefolded, whitespace collapsed, trailing period removed) equals a Foundation food's is dropped. Names are stored as FDC publishes them, whitespace-collapsed, never rewritten.

`sources.json` is a JSON array of sources for the Settings screen, with id, name, publisher, datasets and their versions, licence, URLs and a citation line.

## Adding a source later

Add a reader module beside `fdc.py` that yields `build.FoodRow` values (name, `name_locale`, `source`, `source_ref`, category, the eight nutrient columns with `None` for missing, portions, `is_estimated`), with its own id-to-column mapping table and unit validation in the style of `mapping.py`. Extend `build.assemble` to load it after FDC and add a dedup rule for cross-source overlap (the plan picks one primary source per food group at build time), append the source's entry to `output.sources_manifest`, and add fixtures under `tests/fixtures/<source>/`. The schema needs no change: `source`, `name_locale` and `is_estimated` already exist for this.
