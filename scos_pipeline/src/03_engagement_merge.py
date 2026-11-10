"""
Job 3: Engagement Merge (multi-join + saveAsTable + MERGE)
Runs as a Spark Code Bundle on Snowflake warehouse compute.

Enriches raw HCP engagement events with dimension lookups (drug, territory,
region, therapeutic area) and MERGEs into the target engagement fact table.
Uses spark.sql() for standard queries and SnowflakeSession for Snowflake-native DDL.
"""
import os
from pyspark.sql import SparkSession
from pyspark.sql import functions as F
from pyspark.sql.functions import broadcast
from snowflake.snowpark_connect.snowflake_session import SnowflakeSession


def get_sessions():
    spark = SparkSession.builder.getOrCreate()
    sf_session = SnowflakeSession(spark)
    return spark, sf_session


def fqn(table_name):
    db = os.getenv("SNOWFLAKE_DATABASE", "DEMO")
    schema = os.getenv("SNOWFLAKE_SCHEMA", "HEALTHCARE_DEMO")
    return f"{db}.{schema}.{table_name}"


DEFAULT_KEY = "UNKNOWN"


def main():
    spark, sf_session = get_sessions()
    target = fqn("ENGAGEMENT_FINAL")
    staging = fqn("STG_ENGAGEMENT_TEMP")

    print("[Job 3] Engagement Merge — multi-join + MERGE pattern")

    print("  Step 1: Reading engagements with QUALIFY dedup...")
    engagements_df = sf_session.sql(f"""
        SELECT *
        FROM {fqn('RAW_HCP_ENGAGEMENTS')}
        QUALIFY ROW_NUMBER() OVER (
            PARTITION BY HCP_ID, DRUG_ID, ENGAGEMENT_DATE, ENGAGEMENT_TYPE
            ORDER BY UPDATED_AT DESC
        ) = 1
    """)

    print("  Step 2: Reading dimension tables...")
    dim_drug = sf_session.sql(f"SELECT DRUG_ID, DRUG_NAME, THERAPEUTIC_AREA FROM {fqn('DIM_DRUG')}")
    dim_territory = sf_session.sql(f"SELECT TERRITORY_ID, TERRITORY_KEY, REGION_ID FROM {fqn('DIM_TERRITORY')}")
    dim_region = sf_session.sql(f"SELECT REGION_ID, REGION_KEY FROM {fqn('DIM_REGION')}")
    dim_ta = sf_session.sql(f"SELECT THERAPEUTIC_AREA_ID, AREA_KEY FROM {fqn('DIM_THERAPEUTIC_AREA')}")

    print("  Step 3: Reading HCP profiles for territory/TA lookup...")
    hcp_attrs = sf_session.sql(f"""
        SELECT HCP_ID, TERRITORY_ID, THERAPEUTIC_AREA_ID
        FROM {fqn('RAW_HCP_PROFILES')}
        QUALIFY ROW_NUMBER() OVER (PARTITION BY HCP_ID ORDER BY ETL_UPDATE_DATETIME_UTC DESC) = 1
    """)

    print("  Step 4: Performing multi-join (6-way with broadcast hints)...")
    result_df = (
        engagements_df
        .join(hcp_attrs, "HCP_ID", "left")
        .join(broadcast(dim_drug), "DRUG_ID", "left")
        .join(broadcast(dim_territory), "TERRITORY_ID", "left")
        .join(broadcast(dim_region), "REGION_ID", "left")
        .join(broadcast(dim_ta), "THERAPEUTIC_AREA_ID", "left")
        .select(
            F.col("ENGAGEMENT_ID"),
            engagements_df["HCP_ID"],
            F.col("REP_ID"),
            F.coalesce(dim_drug["DRUG_NAME"], F.lit(DEFAULT_KEY)).alias("DRUG_NAME"),
            F.coalesce(dim_drug["THERAPEUTIC_AREA"], F.lit(DEFAULT_KEY)).alias("THERAPEUTIC_AREA"),
            F.coalesce(dim_territory["TERRITORY_KEY"], F.lit(DEFAULT_KEY)).alias("TERRITORY_KEY"),
            F.coalesce(dim_region["REGION_KEY"], F.lit(DEFAULT_KEY)).alias("REGION_KEY"),
            F.coalesce(dim_ta["AREA_KEY"], F.lit(DEFAULT_KEY)).alias("AREA_KEY"),
            F.col("ENGAGEMENT_TYPE"),
            F.col("CHANNEL"),
            F.col("DURATION_MINUTES"),
            F.col("SAMPLES_DROPPED"),
            F.col("ENGAGEMENT_DATE"),
        )
    )

    print("  Step 5: Validating (replaces isEmpty())...")
    if result_df.limit(1).count() == 0:
        raise ValueError("No rows to load — aborting")

    print("  Step 6: Writing to staging table (replaces Iceberg writeTo)...")
    result_df.write.mode("overwrite").saveAsTable(staging)

    staging_count = sf_session.sql(f"SELECT COUNT(*) FROM {staging}").collect()[0][0]
    print(f"  Staging rows: {staging_count}")

    print("  Step 7: MERGE into target...")
    merge_sql = f"""
        MERGE INTO {target} AS t
        USING {staging} AS s
        ON t.ENGAGEMENT_ID = s.ENGAGEMENT_ID
        WHEN MATCHED AND NOT (
            t.DRUG_NAME IS NOT DISTINCT FROM s.DRUG_NAME
            AND t.THERAPEUTIC_AREA IS NOT DISTINCT FROM s.THERAPEUTIC_AREA
            AND t.TERRITORY_KEY IS NOT DISTINCT FROM s.TERRITORY_KEY
            AND t.REGION_KEY IS NOT DISTINCT FROM s.REGION_KEY
            AND t.AREA_KEY IS NOT DISTINCT FROM s.AREA_KEY
            AND t.CHANNEL IS NOT DISTINCT FROM s.CHANNEL
            AND t.DURATION_MINUTES IS NOT DISTINCT FROM s.DURATION_MINUTES
            AND t.SAMPLES_DROPPED IS NOT DISTINCT FROM s.SAMPLES_DROPPED
        ) THEN UPDATE SET
            t.HCP_ID = s.HCP_ID,
            t.REP_ID = s.REP_ID,
            t.DRUG_NAME = s.DRUG_NAME,
            t.THERAPEUTIC_AREA = s.THERAPEUTIC_AREA,
            t.TERRITORY_KEY = s.TERRITORY_KEY,
            t.REGION_KEY = s.REGION_KEY,
            t.AREA_KEY = s.AREA_KEY,
            t.ENGAGEMENT_TYPE = s.ENGAGEMENT_TYPE,
            t.CHANNEL = s.CHANNEL,
            t.DURATION_MINUTES = s.DURATION_MINUTES,
            t.SAMPLES_DROPPED = s.SAMPLES_DROPPED,
            t.ENGAGEMENT_DATE = s.ENGAGEMENT_DATE
        WHEN NOT MATCHED THEN INSERT (
            ENGAGEMENT_ID, HCP_ID, REP_ID, DRUG_NAME, THERAPEUTIC_AREA,
            TERRITORY_KEY, REGION_KEY, AREA_KEY,
            ENGAGEMENT_TYPE, CHANNEL, DURATION_MINUTES, SAMPLES_DROPPED, ENGAGEMENT_DATE
        ) VALUES (
            s.ENGAGEMENT_ID, s.HCP_ID, s.REP_ID, s.DRUG_NAME, s.THERAPEUTIC_AREA,
            s.TERRITORY_KEY, s.REGION_KEY, s.AREA_KEY,
            s.ENGAGEMENT_TYPE, s.CHANNEL, s.DURATION_MINUTES, s.SAMPLES_DROPPED, s.ENGAGEMENT_DATE
        )
    """
    sf_session.sql(merge_sql).collect()

    print("  Step 8: Cleanup staging...")
    sf_session.sql(f"DROP TABLE IF EXISTS {staging}").collect()

    final_count = sf_session.sql(f"SELECT COUNT(*) FROM {target}").collect()[0][0]
    print(f"  SUCCESS: {final_count} rows in {target}")


if __name__ == "__main__":
    main()
