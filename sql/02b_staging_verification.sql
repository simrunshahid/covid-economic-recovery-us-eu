-- Check 1: total row count (should be close to World Bank's 2,385)
SELECT COUNT(*) AS total_rows
FROM `global-macro-analytics.world_economic_data.stg_us_eu_comparison`;

-- Check 2: how many rows got a real OECD match (should be in the
-- hundreds, not zero, not close to 2,385 — not every country reports
-- to OECD)
SELECT COUNT(*) AS rows_with_oecd_match
FROM `global-macro-analytics.world_economic_data.stg_us_eu_comparison`
WHERE avg_annual_hours_worked IS NOT NULL;

-- Check 3: Austria should show real numbers across all columns, since
-- it's in all three source tables
SELECT *
FROM `global-macro-analytics.world_economic_data.stg_us_eu_comparison`
WHERE country_code = 'AUT'
ORDER BY year;

-- Check 4: the US specifically, since the whole project is US vs. EU
SELECT *
FROM `global-macro-analytics.world_economic_data.stg_us_eu_comparison`
WHERE country_code = 'USA'
ORDER BY year;