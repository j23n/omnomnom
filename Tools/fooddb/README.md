# fooddb

Builds the bundled food database that the app ships read-only: `Omnomnom/Resources/foods.sqlite` and the attribution manifest `Omnomnom/Resources/sources.json`. Python 3.9 or newer, standard library only.

Three sources are readable. Which of them ship is a command-line decision, not a code change.

| Flag | Source | Licence | In the shipped build |
| --- | --- | --- | --- |
| `--ciqual` | [Ciqual](https://ciqual.anses.fr/) (ANSES, France), \~3,500 foods | Licence Ouverte / Etalab | yes |
| `--bls` | [Bundeslebensmittelschlüssel 4.0](https://www.blsdb.de/) (Max Rubner-Institut), \~7,100 foods | CC BY 4.0, attribution required | yes |
| `--fdc` | [FoodData Central](https://fdc.nal.usda.gov/) (USDA), Foundation plus SR Legacy | CC0 1.0 | no |

FDC is left out because its names are US-shaped and its composite dishes are not the ones on a European plate. The reader, its pinned downloader and its tests all stay; adding `--fdc downloads` puts it back.

None of these holds a branded product. They are composition tables of generic foods, and no permissively licensed table of brands exists; a Kinder Bueno reaches the app through the barcode scanner or the Library, never through this database.

## Download

Nothing here is downloaded automatically except FDC, whose zips are pinned. The other two are behind a download page and are fetched by hand:

- **Ciqual**: the XML export, on the French research data repository at <https://entrepot.recherche.data.gouv.fr/dataset.xhtml?persistentId=doi:10.57745/RDMHWY> (DOI 10.57745/RDMHWY). ANSES no longer puts a zip on ciqual.anses.fr; the files are listed individually, so download `alim*.xml`, `alim_grp*.xml`, `compo*.xml` and `const*.xml` into one folder. The build finds them at any depth. The Excel edition is not read; the XML one carries both French and English names. <https://ciqual.anses.fr/> is the table itself, for looking a food up by hand.
- **BLS**: <https://www.blsdb.de/>, download area at <https://blsdb.de/download>, free since version 4.0 under CC BY 4.0. One table, `.xlsx` or a delimited export. The old binary `.xls` cannot be read without a third-party library, so save it as `.xlsx` first.

The version recorded in `meta` and `sources.json` is read from the folder name, so name the folder after the edition: a year for Ciqual (`ciqual-2025`), an edition number for the BLS (`BLS 4.0`), which is what its zip already unpacks to. A folder with no version in its name records `unknown`, which is only a label — the build itself is unaffected.

```sh
cd Tools/fooddb
python3 -m fooddb download                 # FDC only, into Tools/fooddb/downloads/ (git-ignored)
python3 -m fooddb download --dest ~/fdc    # elsewhere
```

Each FDC zip is fetched over https into a temp file, renamed into place, verified, and unzipped into `<dest>/<zip name without .zip>/`. Members with absolute paths or `..` are rejected. An existing zip is not re-fetched unless `--force` is given.

### Pinning hashes

`download.py` holds a `PINS` table with an optional `size` and `sha256` per zip. When both are `None` the download logs the computed values as a warning:

```
WARNING fooddb.download: FoodData_Central_sr_legacy_food_csv_2018-04.zip: no pinned sha256, integrity NOT verified. Computed size=... sha256=...; paste both into PINS in fooddb/download.py to pin this file
```

Copy them into the `Pin(...)` entries. From then on a mismatch deletes the cached zip and fails with exit code 1, so the next run fetches it again. Redirects are followed only while they stay on https, and each request times out after 60 s. Overriding a URL on the command line drops the pin for that bundle, since the pinned hash belongs to the pinned file.

## Inspect

Publishers rename columns and files between editions. Before a build, or after one fails on a missing column, ask what a download actually contains:

```sh
python3 -m fooddb inspect ~/downloads/ciqual
python3 -m fooddb inspect ~/downloads/bls --sheet Daten
```

It prints the files or sheets found, every column name, the first rows, and what each reader would make of them: which constituent codes carry which units for Ciqual, which header was matched to which nutrient for the BLS. Nothing is written. A wrong match is then one edit to `CONST_SPECS` in `fooddb/ciqual.py` or `COLUMN_SPECS` in `fooddb/bls.py`.

## Build

```sh
cd Tools/fooddb
python3 -m fooddb build --ciqual ~/downloads/ciqual --bls ~/downloads/bls
python3 -m fooddb build --ciqual ~/ciqual --out /path/foods.sqlite --sources-out /path/sources.json
python3 -m fooddb build --bls ~/bls --bls-sheet Daten          # a workbook with several sheets
python3 -m fooddb build --ciqual ~/ciqual --fdc downloads      # FDC back in
python3 -m fooddb -v build --ciqual ~/ciqual                   # debug logging
```

At least one source is required. `--popular` points at a different curated ranking list (default `fooddb/curated/popular.txt`): one description per line, most common first, `#` comments allowed. That list is written against FDC's descriptions, so with FDC out of the build it matches nothing and search falls back to relevance alone; rewriting it against the Ciqual and BLS names is the outstanding piece of work here.

`--fdc` accepts either a directory containing the CSVs directly or a directory containing one subdirectory per bundle at any depth. `--ciqual` accepts the folder the XML export was unzipped into; `--bls` accepts a folder or the table file itself.

The build is idempotent: outputs are written to a temp file beside the target and renamed over it. If `--out` or `--sources-out` is a symlink, the symlink itself is replaced by a regular file; the link target is left untouched. The default outputs are `Omnomnom/Resources/foods.sqlite` and `Omnomnom/Resources/sources.json`. Both are git-ignored; run the build before opening the Xcode project. Set `SOURCE_DATE_EPOCH` for a reproducible `built_at`.

It ends with a summary:

```
Build summary
  ciqual: N foods kept, M dropped (no energy), B dropped (blank name)
  bls: N foods kept, M dropped (no energy), B dropped (blank name)
  duplicate names dropped: D
  portions: P
  unmatched popular entries: U
```

Any validation failure (a missing file, a missing constituent or column, an unexpected unit, a malformed value, a non-finite amount, a duplicate identifier, a source with no usable foods, an unwritable output, a bad zip) logs an error with file and line where known and exits 1. Implausible values (over 900 kcal, over 100 g of a macronutrient, or over 100 g of sodium per 100 g), duplicate nutrient rows, negative amounts and unexpected data types are warnings.

## Test

```sh
cd Tools/fooddb
python3 -m unittest -v
python3 -m mypy --strict fooddb tests   # optional: pip install mypy ruff
ruff check .
```

The tests run against synthetic sources in `tests/fixtures/` that mirror each publisher's layout, and cover unit validation, the marker and unit rules, the dropping rules, cross-language search and an end-to-end build into a temp directory.

## Outputs

`foods.sqlite` (schema in `fooddb/schema.sql`, `journal_mode=DELETE`, vacuumed):

- `foods`: one row per food. `id` is assigned by the build; `source` (`ciqual` / `bls` / `fdc_foundation` / `fdc_sr_legacy`) and `source_ref` (the source's own identifier) carry provenance. Nutrients are per 100 g; `kcal_100g` is never null, everything else is null when the source has no value (never 0). `is_estimated` marks a food whose value came from a marker rather than a measurement. `popularity` is a ranking boost from `fooddb/curated/popular.txt` (100 for the first line, decreasing, 0 for everything else).
- `foods.alt_names`: the same food's names in the source's other languages, newline separated. Indexed, never displayed: typing "pomme" finds the row that reads "Apple, pulp and skin, raw".
- `foods_fts`: FTS5 external-content index over `name` and `alt_names` (`unicode61`, diacritics removed). Query with `SELECT ... FROM foods_fts WHERE foods_fts MATCH ?`.
- `portions`: household measures per food, `label` such as `1 cup, chopped` or `1 medium (3" dia)`, with `grams` and a display `seq`. FDC is the only source that publishes these.
- `meta`: `schema_version`, `built_at`, one `<source>_version` per source built, `food_count`, `portion_count`.

Rules applied while building: a food without any energy value is dropped, and so is one without a name. A row whose normalised name a previous source already claimed is dropped, in the order Ciqual, BLS, FDC Foundation, FDC SR Legacy. Names are stored as the source publishes them, whitespace-collapsed, never rewritten.

Per source: Ciqual's `traces` and `< x` become zero with `is_estimated` set, `-` stays null, and the unit in each constituent's name is checked against the mapping table. The BLS carries no units, so they are measured from the data (see `fooddb/bls.py`) and the result is checked against the same ceiling. FDC prefers nutrient 1008 for energy, then 2047, then 2048; fiber 1079 then 2033; sugar 2000 then 1063.

`sources.json` is a JSON array of the sources this build actually read, with id, name, publisher, datasets and their versions, licence, URLs and a citation line. A source that was not built in does not appear.

## Adding a source

Add a reader module beside `ciqual.py` that yields `build.FoodRow` values (name, `name_locale`, `alt_names`, `source`, `source_ref`, category, the eight nutrient columns with `None` for missing, portions, `is_estimated`), with its own mapping table and unit validation. Wide tables of any format go through `table.py`, which reads `.xlsx` and delimited text alike. Add a loader to `build.LOADERS`, the source's id to `bundles.SOURCE_ORDER`, its entry to `output.SOURCES`, a flag in `__main__.build_parser`, a branch in `inspection.describe`, and fixtures under `tests/fixtures/<source>/`. The schema needs no change.
