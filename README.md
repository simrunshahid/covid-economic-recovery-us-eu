# COVID-19 Economic Recovery: US vs. Europe

## What this is
A data pipeline and analysis comparing economic recovery, labor patterns, and
wellbeing outcomes in the US and Europe across the pandemic (2017–2025).

## The question
The US and European countries took different approaches to work: the US
model leans toward longer average work hours, while many European countries
prioritize fixed hours and time off. This project uses public economic and
labor data to look at whether that difference actually shows up in the
numbers — did one region's approach lead to a stronger post-pandemic
recovery, and at what cost?

## Data sources
- **World Bank** — GDP per capita (PPP), life expectancy (2017–2025)
- **OECD** — average annual hours worked, GDP per hour worked (2017–2025)
- **UN Human Development Index** — composite wellbeing/development index
  (2017–2023; UN data has a ~2-year reporting lag)

## Timeline structure
- Pre-COVID: 2017–2019
- Mid-COVID shock: 2020–2021
- Post-COVID recovery: 2022–2023
- Post-COVID "new normal": 2024–2025

## Pipeline
1. **Clean (Python / pandas, via Colab)** — raw World Bank/OECD/UN files
   arrive with irregular headers, wide year-column layouts, and quoted
   commas in country names (e.g. "Venezuela, RB"). Notebooks in
   'notebooks/' reshape each source into a clean long format
   ('country_code, year, value').
2. **Warehouse (Google BigQuery)** — cleaned data is loaded into raw tables,
   then transformed through a staging layer ('stg_') and joined into one
   analytical table keyed on 'country_code' + 'year'. SQL scripts are in
   'sql/'.
3. **Visualize (Tableau)** — the joined table feeds an animated scatter
   plot (GDP per capita vs. a wellbeing/labor metric, bubble size =
   population, year on the Pages/play axis), inspired by Hans Rosling's
   Gapminder charts.

## Repo structure

```
notebooks/     Python cleaning notebooks (per data source)
sql/           BigQuery staging and join scripts
data/
  raw_samples/    small samples of raw source files, for reference
  clean_samples/  small samples of cleaned output
docs/          notes on data issues encountered and how they were fixed
```

## Status
Actively in progress. See commit history for current stage.

## License
MIT — see LICENSE.