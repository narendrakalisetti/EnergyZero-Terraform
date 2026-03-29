-- =============================================================================
-- EnergyZero | Gold Layer SQL Views
-- =============================================================================
-- Purpose : Create SQL views over Delta Lake gold tables for Power BI
--           DirectQuery connections and ad-hoc analyst queries.
-- Engine  : Databricks SQL / Azure Synapse Serverless (both supported)
-- GDPR    : No PII in any gold view — all customer data aggregated
-- Author  : Narendra Kalisetti
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. vw_net_zero_national_progress
-- Executive KPI: national renewable % vs. Net Zero 2050 target
-- Used by: Power BI Executive Dashboard (top-level KPI cards)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW energyzero_gold.vw_net_zero_national_progress AS
SELECT
    reading_date,
    ROUND(national_avg_renewable_pct, 2)          AS renewable_pct,
    100.0                                          AS net_zero_2050_target_pct,
    ROUND(100.0 - national_avg_renewable_pct, 2)  AS gap_to_target_pct,
    national_carbon_saved_kg,
    ROUND(national_total_energy_kwh / 1000, 2)    AS total_energy_mwh,
    national_net_zero_compliance_pct,
    regions_green,
    regions_amber,
    regions_red,
    total_active_stations,
    -- Year-over-year progress indicator (requires historical data)
    national_avg_renewable_pct - LAG(national_avg_renewable_pct, 365)
        OVER (ORDER BY reading_date)               AS yoy_renewable_change_pct,
    gold_load_timestamp
FROM delta.`abfss://gold@{storage_account}.dfs.core.windows.net/executive_report/`
WHERE reading_date >= DATEADD(DAY, -365, CURRENT_DATE());

-- ---------------------------------------------------------------------------
-- 2. vw_regional_net_zero_rag
-- Regional RAG status for map visualisation in Power BI
-- Used by: Power BI regional map tile
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW energyzero_gold.vw_regional_net_zero_rag AS
SELECT
    reading_date,
    grid_region,
    avg_renewable_pct,
    avg_carbon_intensity_gco2,
    net_zero_compliance_pct,
    net_zero_rag_status,
    estimated_carbon_saved_kg,
    ROUND(total_energy_kwh / 1000, 2)       AS total_energy_mwh,
    active_stations,
    -- Rolling 7-day average renewable %
    AVG(avg_renewable_pct)
        OVER (
            PARTITION BY grid_region
            ORDER BY reading_date
            ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
        )                                   AS rolling_7d_renewable_pct,
    gold_load_timestamp
FROM delta.`abfss://gold@{storage_account}.dfs.core.windows.net/net_zero_summary/`
WHERE reading_date >= DATEADD(DAY, -90, CURRENT_DATE());

-- ---------------------------------------------------------------------------
-- 3. vw_grid_stability_kpis
-- Station-level voltage and frequency stability for operations team
-- Used by: Operations Power BI report
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW energyzero_gold.vw_grid_stability_kpis AS
SELECT
    reading_date,
    grid_region,
    station_id,
    ROUND(avg_voltage_v, 2)                 AS avg_voltage_v,
    ROUND(avg_frequency_hz, 3)              AS avg_frequency_hz,
    ROUND(avg_voltage_deviation_v, 3)       AS avg_voltage_deviation_v,
    ROUND(avg_frequency_deviation_hz, 4)    AS avg_frequency_deviation_hz,
    voltage_violations,
    reading_count,
    ROUND(grid_stability_score, 1)          AS grid_stability_score,
    -- Classify station health
    CASE
        WHEN grid_stability_score >= 90 THEN 'HEALTHY'
        WHEN grid_stability_score >= 70 THEN 'DEGRADED'
        ELSE 'CRITICAL'
    END                                     AS station_health_status,
    -- Flag statutory violations (UK ESQCR 2002: ±6% of 230V = 216.2–253V)
    CASE WHEN voltage_violations > 0 THEN TRUE ELSE FALSE END AS has_esqcr_violations
FROM delta.`abfss://gold@{storage_account}.dfs.core.windows.net/grid_kpis/`
WHERE reading_date >= DATEADD(DAY, -30, CURRENT_DATE());

-- ---------------------------------------------------------------------------
-- 4. vw_carbon_saved_cumulative
-- Cumulative carbon saving vs. fossil-only baseline — for Net Zero reporting
-- Used by: Annual sustainability report data feed
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW energyzero_gold.vw_carbon_saved_cumulative AS
SELECT
    reading_date,
    national_carbon_saved_kg,
    ROUND(national_carbon_saved_kg / 1000, 2)   AS carbon_saved_tonnes,
    SUM(national_carbon_saved_kg)
        OVER (ORDER BY reading_date
              ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
                                                 AS cumulative_carbon_saved_kg,
    ROUND(
        SUM(national_carbon_saved_kg)
            OVER (ORDER BY reading_date ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
        / 1000, 2
    )                                            AS cumulative_carbon_saved_tonnes
FROM delta.`abfss://gold@{storage_account}.dfs.core.windows.net/executive_report/`
ORDER BY reading_date;

-- ---------------------------------------------------------------------------
-- 5. Quick validation query — run after each gold load to confirm data freshness
-- ---------------------------------------------------------------------------
-- SELECT
--     MAX(reading_date)       AS latest_reading_date,
--     COUNT(DISTINCT grid_region) AS regions_loaded,
--     SUM(total_readings)     AS total_readings_today
-- FROM energyzero_gold.vw_regional_net_zero_rag
-- WHERE reading_date = CURRENT_DATE();
