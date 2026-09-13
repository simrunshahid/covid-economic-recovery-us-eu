-- Creates a new table that lines up World Bank, OECD, and UN data side
-- by side — one row per country per year, with GDP, hours worked, and
-- HDI all sitting next to each other instead of in three separate places.
CREATE OR REPLACE TABLE `global-macro-analytics.world_economic_data.stg_us_eu_comparison` AS

-- World Bank spells things like "Country Code" with capitals and a
-- space, but OECD and UN use lowercase with underscores — renaming
-- everything here to one consistent style so column names match
-- across all three sources.
SELECT
  wb.`Country Code` AS country_code,
  wb.`Country Name` AS country_name,
  wb.year,
  wb.gdp_per_capita_ppp,
  oecd.avg_annual_hours_worked,
  hdi.hdi_value,
  hdi.hdicode,
  hdi.pop_total

-- Starting from World Bank as the base table.
FROM `global-macro-analytics.world_economic_data.raw_world_bank_metrics` AS wb

-- Attaching OECD's numbers wherever the country and year match. LEFT
-- JOIN keeps every row from World Bank even if OECD has nothing for
-- that country/year — the row just comes back empty there instead of
-- getting dropped, same policy as during cleaning.
LEFT JOIN `global-macro-analytics.world_economic_data.raw_oecd_working_hours` AS oecd
  ON wb.`Country Code` = oecd.country_code
  AND wb.year = oecd.year

-- Same idea for UN data. Its country-code column is named "iso3"
-- instead of "country_code" — just a different name for the same
-- kind of thing.
LEFT JOIN `global-macro-analytics.world_economic_data.raw_un_hdi_data` AS hdi
  ON wb.`Country Code` = hdi.iso3
  AND wb.year = hdi.year