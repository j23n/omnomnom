-- Output schema for foods.sqlite. Schema version 1.
CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT NOT NULL);
CREATE TABLE foods(
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL,
  name_locale TEXT NOT NULL,        -- 'en'
  source TEXT NOT NULL,             -- 'fdc_foundation' | 'fdc_sr_legacy'
  source_ref TEXT NOT NULL,         -- fdc_id as text
  category TEXT,                    -- food_category description, may be NULL
  kcal_100g REAL NOT NULL,
  protein_100g REAL, carb_100g REAL, fat_100g REAL, satfat_100g REAL,
  fiber_100g REAL, sugar_100g REAL, sodium_mg_100g REAL,
  is_estimated INTEGER NOT NULL DEFAULT 0,
  popularity INTEGER NOT NULL DEFAULT 0
);
CREATE VIRTUAL TABLE foods_fts USING fts5(name, content='foods', content_rowid='id', tokenize='unicode61 remove_diacritics 2');
CREATE TABLE portions(
  id INTEGER PRIMARY KEY,
  food_id INTEGER NOT NULL REFERENCES foods(id),
  label TEXT NOT NULL,
  grams REAL NOT NULL,
  seq INTEGER NOT NULL
);
CREATE INDEX portions_food ON portions(food_id, seq);
CREATE UNIQUE INDEX foods_source_ref ON foods(source, source_ref);
