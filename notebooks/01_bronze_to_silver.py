# Databricks notebook source
# =============================================================================
# EnergyZero | Notebook: 01_bronze_to_silver
# =============================================================================
# Purpose   : Read raw Ofgem grid metrics CSV from bronze ADLS container,
#             apply data quality checks, cleanse and type-cast columns,
#             hash customer account IDs for GDPR compliance,
#             and write to silver layer as Delta Lake format.
#
# Layer     : Bronze → Silver
# Schedule  : Triggered by ADF pl_ingest_ofgem_bronze after each copy run
# Author    : Narendra Kalisetti
# GDPR      : Customer Account IDs hashed SHA-256 before silver write.
#             Raw account IDs never leave the bronze layer.
# Net Zero  : Cluster auto-terminates after 20 min idle (cluster policy enforced)
# =============================================================================

# COMMAND ----------
# Widget parameters injected by ADF trigger
dbutils.widgets.text("ingest_date", "", "Ingest Date (YYYY-MM-DD)")
dbutils.widgets.text("source", "ofgem", "Source system")
dbutils.widgets.text("environment", "prod", "Environment")

ingest_date = dbutils.widgets.get("ingest_date")
source      = dbutils.widgets.get("source")
environment = dbutils.widgets.get("environment")

print(f"Processing: source={source} | ingest_date={ingest_date} | env={environment}")

# COMMAND ----------
# Storage paths — secrets retrieved from Key Vault via Databricks secret scope
storage_account = dbutils.secrets.get(scope="energyzero-kv-scope", key="adls-account-name")

BRONZE_PATH = f"abfss://bronze@{storage_account}.dfs.core.windows.net"
SILVER_PATH = f"abfss://silver@{storage_account}.dfs.core.windows.net"

bronze_input = f"{BRONZE_PATH}/ofgem/ingest_date={ingest_date}/"
silver_output = f"{SILVER_PATH}/grid_metrics/"

print(f"Bronze input : {bronze_input}")
print(f"Silver output: {silver_output}")

# COMMAND ----------
from pyspark.sql import functions as F
from pyspark.sql.types import (
    StructType, StructField, StringType, DoubleType,
    IntegerType, TimestampType, DateType
)
from delta.tables import DeltaTable

# COMMAND ----------
# -----------------------------------------------------------------------------
# STEP 1 — Read raw bronze CSV
# -----------------------------------------------------------------------------
raw_schema = StructType([
    StructField("reading_timestamp",     StringType(),  True),
    StructField("grid_region",           StringType(),  True),
    StructField("station_id",            StringType(),  True),
    StructField("customer_account_id",   StringType(),  True),  # PII — will be hashed
    StructField("meter_reading_kwh",     StringType(),  True),
    StructField("voltage_v",             StringType(),  True),
    StructField("frequency_hz",          StringType(),  True),
    StructField("renewable_pct",         StringType(),  True),
    StructField("carbon_intensity_gco2", StringType(),  True),
    StructField("source_system",         StringType(),  True),
])

df_raw = (
    spark.read
    .schema(raw_schema)
    .option("header", "true")
    .option("nullValue", "NULL")
    .option("emptyValue", "")
    .csv(bronze_input)
)

raw_count = df_raw.count()
print(f"Raw records read from bronze: {raw_count:,}")

# COMMAND ----------
# -----------------------------------------------------------------------------
# STEP 2 — Data quality checks (fail-fast if critical rules violated)
# -----------------------------------------------------------------------------
# Rule 1: No null station_ids
null_stations = df_raw.filter(F.col("station_id").isNull()).count()
assert null_stations == 0, f"DATA QUALITY FAIL: {null_stations} rows with null station_id"

# Rule 2: Meter readings must be non-negative
invalid_readings = df_raw.filter(
    F.col("meter_reading_kwh").cast("double") < 0
).count()
assert invalid_readings == 0, f"DATA QUALITY FAIL: {invalid_readings} negative meter readings"

# Rule 3: Renewable percentage must be 0–100
invalid_renewable = df_raw.filter(
    (F.col("renewable_pct").cast("double") < 0) |
    (F.col("renewable_pct").cast("double") > 100)
).count()
assert invalid_renewable == 0, f"DATA QUALITY FAIL: {invalid_renewable} invalid renewable_pct values"

print(f"All data quality checks passed for {raw_count:,} records")

# COMMAND ----------
# -----------------------------------------------------------------------------
# STEP 3 — Cleanse, cast, and enrich
# -----------------------------------------------------------------------------
df_cleansed = (
    df_raw
    # Cast string columns to correct types
    .withColumn("reading_timestamp",     F.to_timestamp("reading_timestamp", "yyyy-MM-dd HH:mm:ss"))
    .withColumn("reading_date",          F.to_date("reading_timestamp"))
    .withColumn("meter_reading_kwh",     F.col("meter_reading_kwh").cast(DoubleType()))
    .withColumn("voltage_v",             F.col("voltage_v").cast(DoubleType()))
    .withColumn("frequency_hz",          F.col("frequency_hz").cast(DoubleType()))
    .withColumn("renewable_pct",         F.col("renewable_pct").cast(DoubleType()))
    .withColumn("carbon_intensity_gco2", F.col("carbon_intensity_gco2").cast(DoubleType()))
    # Standardise grid_region to uppercase trimmed
    .withColumn("grid_region",           F.upper(F.trim(F.col("grid_region"))))
    # Derived: is this reading from a renewable source?
    .withColumn("is_renewable_majority", F.col("renewable_pct") >= 50.0)
    # Derived: Net Zero 2050 flag — regions on track (renewable_pct >= 70%)
    .withColumn("on_track_net_zero",     F.col("renewable_pct") >= 70.0)
    # Drop duplicates on natural key
    .dropDuplicates(["station_id", "reading_timestamp"])
    # Drop rows with null mandatory fields
    .dropna(subset=["station_id", "reading_timestamp", "meter_reading_kwh"])
)

# COMMAND ----------
# -----------------------------------------------------------------------------
# STEP 4 — GDPR: Hash customer_account_id (UK GDPR Article 25 — Privacy by Design)
#
# The customer_account_id links energy consumption to a natural person.
# Under UK GDPR, this is personal data and must be pseudonymised before
# being written to any layer beyond bronze.
#
# SHA-256 is used here for deterministic pseudonymisation — the same
# account_id always produces the same hash, allowing joins across tables
# without exposing the raw identifier.
#
# The hashing salt is stored in Azure Key Vault (secret: 'customer-hash-salt').
# Without the salt, the hash alone cannot be reversed to the original ID.
# This satisfies UK GDPR Art. 25 pseudonymisation requirements.
# -----------------------------------------------------------------------------
hash_salt = dbutils.secrets.get(scope="energyzero-kv-scope", key="customer-hash-salt")

df_gdpr = (
    df_cleansed
    .withColumn(
        "customer_account_id_hashed",
        F.sha2(F.concat(F.col("customer_account_id"), F.lit(hash_salt)), 256)
    )
    # Drop the raw PII column — it MUST NOT reach silver or beyond
    .drop("customer_account_id")
)

print("GDPR: customer_account_id hashed and raw column dropped")
assert "customer_account_id" not in df_gdpr.columns, "CRITICAL: raw PII column still present!"

# COMMAND ----------
# -----------------------------------------------------------------------------
# STEP 5 — Add pipeline metadata for lineage (Microsoft Purview auto-lineage)
# -----------------------------------------------------------------------------
from datetime import datetime

df_final = (
    df_gdpr
    .withColumn("silver_load_timestamp", F.current_timestamp())
    .withColumn("silver_load_date",      F.to_date(F.current_timestamp()))
    .withColumn("ingest_date",           F.lit(ingest_date))
    .withColumn("pipeline_name",         F.lit("pl_ingest_ofgem_bronze"))
    .withColumn("source_system",         F.lit(source))
    .withColumn("data_classification",   F.lit("CONFIDENTIAL"))
    .withColumn("gdpr_pii_hashed",       F.lit(True))
    .withColumn("layer",                 F.lit("silver"))
)

# COMMAND ----------
# -----------------------------------------------------------------------------
# STEP 6 — Write to Silver Delta Lake (merge/upsert on natural key)
# Using MERGE to handle re-runs idempotently — safe for retry logic in ADF
# -----------------------------------------------------------------------------
silver_count = df_final.count()
print(f"Writing {silver_count:,} records to Silver Delta at: {silver_output}")

if DeltaTable.isDeltaTable(spark, silver_output):
    # UPSERT: merge on station_id + reading_timestamp (idempotent re-runs)
    delta_table = DeltaTable.forPath(spark, silver_output)
    (
        delta_table.alias("target")
        .merge(
            df_final.alias("source"),
            "target.station_id = source.station_id AND target.reading_timestamp = source.reading_timestamp"
        )
        .whenMatchedUpdateAll()
        .whenNotMatchedInsertAll()
        .execute()
    )
    print("Silver Delta table: MERGE (upsert) complete")
else:
    # First run: create the Delta table partitioned by reading_date
    (
        df_final.write
        .format("delta")
        .mode("overwrite")
        .partitionBy("reading_date", "grid_region")
        .option("mergeSchema", "true")
        .save(silver_output)
    )
    print("Silver Delta table: Initial WRITE complete")

# COMMAND ----------
# STEP 7 — Optimise Delta table for query performance
spark.sql(f"OPTIMIZE delta.`{silver_output}` ZORDER BY (station_id, reading_timestamp)")
spark.sql(f"VACUUM delta.`{silver_output}` RETAIN 168 HOURS")  # 7-day retention on old files

# COMMAND ----------
# Summary
silver_final_count = spark.read.format("delta").load(silver_output).count()
print("=" * 60)
print("BRONZE → SILVER COMPLETE")
print(f"  Bronze records processed : {raw_count:,}")
print(f"  Silver records after load: {silver_final_count:,}")
print(f"  GDPR: PII hashed         : YES (SHA-256 + salt)")
print(f"  Delta location           : {silver_output}")
print("=" * 60)

# Return summary for ADF monitoring
dbutils.notebook.exit(f'{{"status":"success","silver_records":{silver_final_count},"ingest_date":"{ingest_date}"}}')
