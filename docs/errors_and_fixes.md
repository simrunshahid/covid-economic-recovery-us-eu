# Data Cleaning: Errors, Decisions & Alternatives Log

This documents the real problems encountered while building this
project's data pipeline — what went wrong, how it was diagnosed, how it
was resolved, and what could have been done differently. Kept as prose
here (not just code comments) so the reasoning survives even if a
notebook or script gets rewritten later.

---

## Phase 1: BigQuery direct-upload attempts (World Bank)

Before any Python cleaning existed, the original plan was to upload raw
CSVs straight into BigQuery and clean them there with SQL.

### Schema misread — string_field_0
Uploading the raw World Bank CSV with BigQuery's Auto-detect schema
produced generic column names ('string_field_0', 'string_field_1'...)
instead of real headers like 'Country Name'. Diagnosed by opening the
raw file in TextEdit: the World Bank inserts 4 metadata lines ("Data
Source", "Last Updated Date", 2 blank lines) above the real header row.
BigQuery's auto-detect had no way to know this and treated the metadata
text as if it were the header.

**Attempted fix:** setting "Header rows to skip" to 4 in BigQuery's
upload UI. This did not fully resolve the issue on its own.

### Quoted commas in country names
Country names like '"Venezuela, RB"' and '"Yemen, Rep."' contain commas
inside quoted fields — valid CSV, but a source of parsing errors when
the file had already been touched by Excel (Excel can strip quoting on
re-save, turning one field into two broken columns).

### The SQL "raw text dump" detour (abandoned)
To route around persistent auto-detect failures, attempted a fallback:
load the entire file as a single unparsed STRING column
('raw_row_data'), then write a SQL script using 'SPLIT()',
'SAFE_OFFSET()', and 'REGEXP_REPLACE()' to manually parse commas and
strip quotes column-by-column.

**Outcome:** this approach was ultimately unnecessary. The actual fix
that worked was simpler: manually trimming the file in Excel (removing
the 4 metadata rows and the 1960-2016 year columns, since only 2017-2025
was needed) before upload, with "Header rows to skip" set to 1. The SQL
split-parsing script was more complex than the problem required and was
not used in the final pipeline.

### GCP billing scare
A later BigQuery table creation attempt failed with a billing-disabled
error. Investigated via the GCP billing console and found the linked
billing account was intact — the real error turned out to be unrelated
(see OECD section below: a duplicate-column schema error), not a
billing issue at all. Worth noting for future reference: BigQuery error
messages are not always specific to the actual root cause.

### Decision: move cleaning to Python
Given the repeated friction with BigQuery's raw CSV ingestion —
metadata rows, quoted commas, and (later) duplicate columns — cleaning
was moved to Python (pandas, via Google Colab) before loading anything
into BigQuery. Pandas' 'read_csv' handles quoted commas correctly by
default, which resolved the root cause of several of the above issues
without needing any SQL workarounds.

---

## Phase 2: Python cleaning - World Bank GDP data

### Header rows
Same 4-metadata-row issue as above. Resolved directly and simply in
pandas with 'skiprows=4' - the number confirmed in advance by manually
inspecting the raw file.

### Missing values policy
After trimming to 2017-2025, roughly 19 countries/year are missing
through 2022, rising to 33 by 2025. Investigated specific cases (Yemen,
South Sudan, Venezuela) - gaps align with conflict/instability, not
data corruption. The rising gap count toward 2025 reflects normal
reporting lag (the most recent year is always the least complete).

**Decision:** missing values are left as true nulls. No imputation, no
dropped rows - filling them would misrepresent real instability as a
normal data point; dropping rows would silently erase countries with no
indication they were ever included.

### Wide to long reshape
Reshaped from one row per country (years as columns) to one row per
country-year using '.melt()', to match OECD's structure and support SQL
joins / Tableau's year-based animation.

---

## Phase 3: Python cleaning - OECD hours-worked data

### Duplicate column name (BigQuery-specific)
The raw OECD export has both 'MEASURE' and 'Measure' columns (a
case-different code/label pair). BigQuery treats column names as
case-insensitive, so these collided, producing
'Failed to create table: Duplicate column 'Measure''. This was the
actual cause of the "billing disabled" scare noted above - an
unrelated, oddly-worded error masked what was really a schema problem.
Pandas loaded the file without issue (it's case-sensitive), reinforcing
the decision to clean in Python before touching BigQuery.

### "OECD" aggregate rows
The raw file includes 9 rows (one per year, 2017-2025) where
'country_name'/'country_code' are both literally "OECD" - not a
country, but the organization's own calculated average across all ~38
member countries.

**Decision:** produced two versions:
- 'oecd_clean.csv' - OECD aggregate rows removed. Primary working file,
  since this project compares the US against specific EU countries, not
  an OECD-wide blend.
- 'oecd_clean_with_agg.csv' - OECD aggregate rows kept in, retained in
  case an "OECD average" reference line is wanted later on a chart. If
  used, must be filtered out of any per-country join/aggregation.

### Column selection
The raw file has 40 columns (SDMX code/label pairs plus bookkeeping
fields like 'STRUCTURE', 'OBS_STATUS', 'DECIMALS'). Only 4 were
relevant: country name, country code, year, hours-worked value. Selected
and renamed these explicitly, matching the naming convention used for
World Bank ('country_name', 'country_code', 'year') to keep the eventual
join straightforward.

---

## Phase 4: Python cleaning - UN Human Development Index data

### Encoding error on load
'pd.read_csv()' failed with
'UnicodeDecodeError: 'utf-8' codec can't decode byte 0xf4'. Likely an
accented character in a country name, saved by Excel in a non-UTF-8
encoding during an earlier manual header-cleaning pass.
**Fix:** loaded with 'encoding="latin-1"' instead, which accepts any
byte value without erroring.

### Oversized file - 1112 columns
The UN's "all composite indices and components" export bundles dozens
of indicators (HDI, life expectancy, schooling, GNI, gender-
disaggregated variants, inequality-adjusted HDI, CO2, population, etc.),
each repeated across every year since 1990. Only 'hdi_*' (core metric)
and 'pop_total_*' (for possible bubble-sizing) were relevant to this
project. Selected down to 16 columns before doing anything else with
the file.

### Data only goes through 2023
Unlike World Bank/OECD (through 2025), UN HDI has a ~2-year reporting
lag - 2023 is the most current year available. Expected, not a data
quality issue.

### Wide to long reshape - two metrics, one alternative not taken
This file needed two year-suffixed metrics ('hdi_*', 'pop_total_*')
reshaped together, unlike World Bank's single metric. Approach taken:
melted 'hdi_*' and 'pop_total_*' separately, cleaned each resulting
'year' column, then merged the two long tables back together on 'iso3'
+ 'year'.

**Simpler alternative not used:** 'pd.wide_to_long()' can do this in one
call:

    pd.wide_to_long(df_hdi_clean, stubnames=["hdi", "pop_total"],
                     i=["iso3", "country", "hdicode"], j="year", sep="_").reset_index()

This replaces the two melts, the year-cleanup lines, and the merge step
entirely. Not used here because this was the first file needing a
multi-metric reshape, and doing it manually made each transformation
step visible and easier to debug. Recommended as the faster choice for
any future file shaped this way.

---

## Cross-cutting decisions

- **Missing values:** consistent policy across all three sources -
  never imputed, never dropped, always left as true nulls. Missingness
  is treated as real signal (conflict, reporting lag, non-reporting
  territories), not a defect to paper over.
- **Naming convention:** cleaned outputs use shared column names
  ('country_name'/'country_code', 'year') across sources specifically
  to make the eventual SQL join straightforward.
- **Cleaning location:** all structural cleaning (headers, encoding,
  reshaping, column selection) happens in Python before data reaches
  BigQuery. BigQuery is used for staging/joining already-clean data, not
  for parsing raw exports - this was a deliberate shift after Phase 1's
  repeated ingestion failures.

---

## Phase 5: BigQuery staging - joining the three cleaned sources

### Column name mismatch - "Country Code" with a space
**In plain terms:** a column name in the database had a tiny spelling
difference from what I typed in my code, a space instead of an
underscore, so SQL couldn't find it until I matched it exactly.

The staging join initially failed with:
'Name Country_Code not found inside wb at [27:9]'

World Bank's table schema uses "Country Code" and "Country Name" with a
space (not an underscore), a side effect of how BigQuery's auto-detect
read the column headers from the original CSV. SQL requires exact column
names, so referencing 'wb.Country_Code' (underscore) failed to match
the real column 'Country Code' (space).

**Fix:** wrapped the column name in backticks to reference it exactly
as it exists: '' wb.'Country Code' ''. A reminder that even after
Python cleaning, the exact column names landing in BigQuery are worth
checking against the Schema tab before writing SQL against them.
Auto-detect can still introduce small naming quirks (spaces, casing)
even on well-structured files.

### Verifying a join actually worked, not just ran
**In plain terms:** combining three data tables into one "ran without
an error," but that's not the same as "worked correctly." I had to
actually check the numbers to be sure it lined countries up right.

After the join succeeded, previewing the result showed 'NULL' for
'avg_annual_hours_worked', 'hdi_value', 'hdicode', and 'pop_total' on
the first several rows (Afghanistan, Africa Eastern and Southern,
etc.). At first glance this looked like the join had failed entirely.

Investigated further with a spot-check: those specific countries
genuinely aren't part of the OECD or don't appear the same way across
all three sources, so 'NULL' there is correct, not a bug. Confirmed by
querying two countries known to be in all three sources, Austria and
USA, which showed complete data across every column for
2017-2023, with expected 'NULL's only in 2024-2025 (OECD and UN HDI
data doesn't extend that far yet).

**Lesson:** a join "running successfully" and a join "working
correctly" are different claims. Previewing the first alphabetical
rows of a join result can be misleading if those happen to be
non-matching entities. A targeted spot-check on known-good rows is a
more reliable way to confirm a join, along with sanity-checking row
counts before and after (2,385 rows in, 2,385 rows out; 337 rows with
a real OECD match, in the expected range for a ~38-country
organization).

### Staging table design
**In plain terms:** I combined the three cleaned datasets into one
table, keeping every country from the base table even when the other
two sources didn't have matching data for it.

Built 'stg_us_eu_comparison' as a single 'LEFT JOIN' chain: World Bank
as the base table, OECD and UN HDI attached wherever a country/year
match exists. Chose 'LEFT JOIN' specifically (not 'INNER JOIN') to
preserve every World Bank row even when a match is missing elsewhere,
the same missing-values philosophy carried over from the Python
cleaning phase: never silently drop a row because one source doesn't
have data for it.