# Databricks notebook source
# =============================================================================
# EnergyZero | Notebook: 02_silver_to_gold
# =============================================================================
# Purpose   : Read cleansed silver Delta table, compute Net Zero 2050 KPIs,
#             regional grid stability metrics, and executive-level aggregations.
#             Write to gold layer as Delta tables, optimised for Power BI
#             DirectQuery with Z-Ordering on key dimensions.
#
# Layer     : Silver → Gold
# Schedule  : Triggered by ADF after 01_bronze_to_silver completes
# Author    : Narendra Kalisetti
# GDPR      : Gold layer contains NO PII — only aggregated metrics.
#             customer_account_id_hashed is excluded at this layer.
# Net Zero  : Core output feeds the EnergyZero Net Zero 2050 dashboard.
# =============================================================================

# COMMAND ----------
dbutils.widgets.text("ingest_date", "", "Ingest Date (YYYY-MM-DD)")
dbutils.widgets.text("environment", "prod", "Environment")

ingest_date = dbutils.widgets.get("ingest_date")
environment = dbutils.widgets.get("environment")

print(f"Silver → Gold | ingest_date={ingest_date} | env={environment}")

# COMMAND ----------
storage_account = dbutils.secrets.get(scope="energyzero-kv-scope", key="adls-account-name")
SILVER_PATH = f"abfss://silver@{storage_account}.dfs.core.windows.net"
GOLD_PATH   = f"abfss://gold@{storage_account}.dfs.core.windows.net"

# COMMAND ----------
from pyspark.sql import functions as F
from delta.tables import DeltaTable

# Read silver grid_metrics Delta table
df_silver = (
    spark.read
    .format("delta")
    .load(f"{SILVER_PATH}/grid_metrics/")
    .filter(F.col("ingest_date") == ingest_date)  # Incremental: today's data only
)

silver_count = df_silver.count()
print(f"Silver records loaded for {ingest_date}: {silver_count:,}")

# COMMAND ----------
# =============================================================================
# GOLD TABLE 1: net_zero_summary
# Regional daily renewable output vs. carbon intensity — core Net Zero 2050 KPI
# =============================================================================
df_net_zero = (
    df_silver
    .groupBy("reading_date", "grid_region")
    .agg(
        # Renewable metrics
        F.avg("renewable_pct").alias("avg_renewable_pct"),
        F.min("renewable_pct").alias("min_renewable_pct"),
        F.max("renewable_pct").alias("max_renewable_pct"),
        # Carbon metrics
        F.avg("carbon_intensity_gco2").alias("avg_carbon_intensity_gco2"),
        F.sum("meter_reading_kwh").alias("total_energy_kwh"),
        # Net Zero progress
        F.sum(F.when(F.col("on_track_net_zero"), 1).otherwise(0)).alias("readings_on_track"),
        F.count("*").alias("total_readings"),
        # Grid stats
        F.avg("voltage_v").alias("avg_voltage_v"),
        F.avg("frequency_hz").alias("avg_frequency_hz"),
        F.countDistinct("station_id").alias("active_stations"),
    )
    # Derived: % of readings meeting Net Zero 2050 renewable threshold (70%)
    .withColumn(
        "net_zero_compliance_pct",
        F.round((F.col("readings_on_track") / F.col("total_readings")) * 100, 2)
    )
    # Traffic-light status for Power BI conditional formatting
    .withColumn(
        "net_zero_rag_status",
        F.when(F.col("avg_renewable_pct") >= 70, "GREEN")
         .when(F.col("avg_renewable_pct") >= 50, "AMBER")
         .otherwise("RED")
    )
    # Estimated carbon saved vs. 100% fossil baseline (kg CO2)
    .withColumn(
        "estimated_carbon_saved_kg",
        F.round(
            F.col("total_energy_kwh") *
            (F.col("avg_renewable_pct") / 100) *
            0.233,   # UK grid average carbon intensity factor (kg CO2/kWh)
            2
        )
    )
    # Metadata
    .withColumn("gold_load_timestamp", F.current_timestamp())
    .withColumn("data_classification", F.lit("INTERNAL"))
    .withColumn("gdpr_pii_present",    F.lit(False))   # No PII in gold
)

# Write gold net_zero_summary (upsert on reading_date + grid_region)
gold_net_zero_path = f"{GOLD_PATH}/net_zero_summary/"
if DeltaTable.isDeltaTable(spark, gold_net_zero_path):
    DeltaTable.forPath(spark, gold_net_zero_path).alias("t").merge(
        df_net_zero.alias("s"),
        "t.reading_date = s.reading_date AND t.grid_region = s.grid_region"
    ).whenMatchedUpdateAll().whenNotMatchedInsertAll().execute()
else:
    df_net_zero.write.format("delta").mode("overwrite") \
        .partitionBy("reading_date") \
        .save(gold_net_zero_path)

print(f"Gold net_zero_summary written: {df_net_zero.count():,} regional summaries")

# COMMAND ----------
# =============================================================================
# GOLD TABLE 2: grid_kpis
# Daily grid stability KPIs — voltage and frequency deviation from nominal
# UK grid nominal: 230V, 50Hz (National Grid ESO standard)
# =============================================================================
df_grid_kpis = (
    df_silver
    .groupBy("reading_date", "grid_region", "station_id")
    .agg(
        F.avg("voltage_v").alias("avg_voltage_v"),
        F.stddev("voltage_v").alias("stddev_voltage_v"),
        F.avg("frequency_hz").alias("avg_frequency_hz"),
        F.stddev("frequency_hz").alias("stddev_frequency_hz"),
        F.count("*").alias("reading_count"),
        # Voltage deviation from UK nominal 230V
        F.avg(F.abs(F.col("voltage_v") - 230)).alias("avg_voltage_deviation_v"),
        # Frequency deviation from UK nominal 50Hz
        F.avg(F.abs(F.col("frequency_hz") - 50)).alias("avg_frequency_deviation_hz"),
        # Readings outside statutory limits (±6% voltage per ESQCR 2002)
        F.sum(
            F.when(
                (F.col("voltage_v") < 216.2) | (F.col("voltage_v") > 253.0), 1
            ).otherwise(0)
        ).alias("voltage_violations"),
    )
    .withColumn("grid_stability_score",
        # Score 0–100: higher is more stable
        F.round(
            100 - (F.col("avg_voltage_deviation_v") * 2) -
                  (F.col("avg_frequency_deviation_hz") * 100),
            2
        )
    )
    .withColumn("gold_load_timestamp", F.current_timestamp())
    .withColumn("data_classification", F.lit("INTERNAL"))
    .withColumn("gdpr_pii_present",    F.lit(False))
)

gold_kpis_path = f"{GOLD_PATH}/grid_kpis/"
if DeltaTable.isDeltaTable(spark, gold_kpis_path):
    DeltaTable.forPath(spark, gold_kpis_path).alias("t").merge(
        df_grid_kpis.alias("s"),
        "t.reading_date = s.reading_date AND t.station_id = s.station_id"
    ).whenMatchedUpdateAll().whenNotMatchedInsertAll().execute()
else:
    df_grid_kpis.write.format("delta").mode("overwrite") \
        .partitionBy("reading_date", "grid_region") \
        .save(gold_kpis_path)

print(f"Gold grid_kpis written: {df_grid_kpis.count():,} station KPI records")

# COMMAND ----------
# =============================================================================
# GOLD TABLE 3: executive_report
# Pre-aggregated national summary — feeds the Power BI executive dashboard
# =============================================================================
df_exec = (
    df_net_zero
    .groupBy("reading_date")
    .agg(
        F.avg("avg_renewable_pct").alias("national_avg_renewable_pct"),
        F.sum("total_energy_kwh").alias("national_total_energy_kwh"),
        F.sum("estimated_carbon_saved_kg").alias("national_carbon_saved_kg"),
        F.avg("avg_carbon_intensity_gco2").alias("national_avg_carbon_intensity"),
        F.sum("active_stations").alias("total_active_stations"),
        F.sum(F.when(F.col("net_zero_rag_status") == "GREEN", 1).otherwise(0)).alias("regions_green"),
        F.sum(F.when(F.col("net_zero_rag_status") == "AMBER", 1).otherwise(0)).alias("regions_amber"),
        F.sum(F.when(F.col("net_zero_rag_status") == "RED",   1).otherwise(0)).alias("regions_red"),
        F.count("grid_region").alias("total_regions"),
    )
    .withColumn(
        "national_net_zero_compliance_pct",
        F.round((F.col("regions_green") / F.col("total_regions")) * 100, 2)
    )
    .withColumn("uk_net_zero_2050_target_pct", F.lit(100.0))
    .withColumn("gap_to_target_pct",
        F.round(100.0 - F.col("national_avg_renewable_pct"), 2)
    )
    .withColumn("gold_load_timestamp", F.current_timestamp())
    .withColumn("report_generated_by", F.lit("EnergyZero Data Platform"))
)

gold_exec_path = f"{GOLD_PATH}/executive_report/"
if DeltaTable.isDeltaTable(spark, gold_exec_path):
    DeltaTable.forPath(spark, gold_exec_path).alias("t").merge(
        df_exec.alias("s"), "t.reading_date = s.reading_date"
    ).whenMatchedUpdateAll().whenNotMatchedInsertAll().execute()
else:
    df_exec.write.format("delta").mode("overwrite").save(gold_exec_path)

# COMMAND ----------
# Optimise all gold tables for Power BI DirectQuery performance
for path, zorder_col in [
    (gold_net_zero_path, "grid_region"),
    (gold_kpis_path, "station_id"),
    (gold_exec_path, "reading_date"),
]:
    spark.sql(f"OPTIMIZE delta.`{path}` ZORDER BY ({zorder_col})")

# COMMAND ----------
print("=" * 60)
print("SILVER → GOLD COMPLETE")
print(f"  net_zero_summary records : {df_net_zero.count():,}")
print(f"  grid_kpis records        : {df_grid_kpis.count():,}")
print(f"  executive_report records : {df_exec.count():,}")
print(f"  GDPR: No PII in gold     : CONFIRMED")
print(f"  Net Zero KPIs computed   : YES")
print("=" * 60)

dbutils.notebook.exit(f'{{"status":"success","ingest_date":"{ingest_date}","gold_tables":3}}')
