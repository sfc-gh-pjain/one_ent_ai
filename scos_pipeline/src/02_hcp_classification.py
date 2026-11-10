"""
Job 2: HCP Classification — rdd.mapPartitions() -> Snowflake Python UDTF
Runs as a Spark Code Bundle on Snowflake warehouse compute.

Classifies HCP specialty into standardized groups and assigns engagement tiers
based on prescription volume and engagement frequency. Replaces legacy Spark
mapPartitions-based API call pattern with a server-side UDTF.
"""
import argparse
import os
from pyspark.sql import SparkSession
from snowflake.snowpark_connect.snowflake_session import SnowflakeSession


def get_sessions():
    spark = SparkSession.builder.getOrCreate()
    sf_session = SnowflakeSession(spark)
    return spark, sf_session


def fqn(table_name):
    db = os.getenv("SNOWFLAKE_DATABASE", "DEMO")
    schema = os.getenv("SNOWFLAKE_SCHEMA", "HEALTHCARE_DEMO")
    return f"{db}.{schema}.{table_name}"


def create_hcp_tier_udtf(sf_session):
    udtf_sql = f"""
    CREATE OR REPLACE FUNCTION {fqn('CLASSIFY_HCP_TIER_UDTF')}(
        hcp_id VARCHAR, specialty VARCHAR, years_experience INTEGER,
        rx_count INTEGER, engagement_count INTEGER
    )
    RETURNS TABLE(
        HCP_ID VARCHAR,
        SPECIALTY VARCHAR,
        STANDARDIZED_SPECIALTY VARCHAR,
        SPECIALTY_GROUP_ID INTEGER,
        TIER VARCHAR,
        DECILE INTEGER,
        CONFIDENCE FLOAT
    )
    LANGUAGE PYTHON
    RUNTIME_VERSION='3.11'
    HANDLER='HCPTierHandler'
    AS $$
import hashlib
import random

SPECIALTY_MAP = {{
    "internal medicine": ("Primary Care", 1),
    "family medicine": ("Primary Care", 1),
    "oncology": ("Oncology", 2),
    "hematology": ("Oncology", 2),
    "cardiology": ("Cardiovascular", 3),
    "neurology": ("Neuroscience", 4),
    "psychiatry": ("Neuroscience", 4),
    "pulmonology": ("Respiratory", 5),
    "endocrinology": ("Metabolic", 6),
    "dermatology": ("Dermatology", 7),
    "rheumatology": ("Immunology", 8),
    "gastroenterology": ("GI", 9),
    "infectious disease": ("Anti-Infectives", 10),
    "nephrology": ("Renal", 11),
    "surgery": ("Surgical", 12),
}}

class HCPTierHandler:
    def __init__(self):
        self._call_count = 0

    def process(self, hcp_id, specialty, years_experience, rx_count, engagement_count):
        self._call_count += 1
        spec_lower = (specialty or "").strip().lower()

        std_specialty, group_id = SPECIALTY_MAP.get(spec_lower, ("Other", 99))

        # Tier logic: combines volume + experience + engagement
        score = (rx_count or 0) * 3 + (engagement_count or 0) * 2 + (years_experience or 0)
        if score >= 200:
            tier = "Tier 1 - High"
        elif score >= 100:
            tier = "Tier 2 - Medium"
        elif score >= 40:
            tier = "Tier 3 - Low"
        else:
            tier = "Tier 4 - Emerging"

        # Decile from hash for deterministic assignment
        seed = int(hashlib.md5((hcp_id or "").encode()).hexdigest()[:8], 16)
        decile = (seed % 10) + 1

        confidence = round(0.7 + (min(rx_count or 0, 50) / 50) * 0.25, 3)

        yield (hcp_id, specialty, std_specialty, group_id, tier, decile, confidence)
$$
    """
    print("  Creating CLASSIFY_HCP_TIER_UDTF...")
    sf_session.sql(udtf_sql).collect()
    print("  UDTF created successfully.")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--ds", required=True)
    parser.add_argument("--batch-size", type=int, default=50, help="Legacy param, ignored with UDTF approach")
    args = parser.parse_args()

    spark, sf_session = get_sessions()

    print(f"[Job 2] HCP Classification via UDTF — ds={args.ds}")

    create_hcp_tier_udtf(sf_session)

    print("  Running UDTF on HCP profiles with Rx/engagement counts...")
    source_table = fqn("RAW_HCP_PROFILES")
    udtf_name = fqn("CLASSIFY_HCP_TIER_UDTF")
    target_table = fqn("HCP_TIERED_PROFILES")

    process_sql = f"""
        CREATE OR REPLACE TABLE {target_table} AS
        WITH hcp_activity AS (
            SELECT
                h.HCP_ID,
                h.SPECIALTY,
                h.YEARS_EXPERIENCE,
                COALESCE(rx.rx_count, 0) AS rx_count,
                COALESCE(eng.eng_count, 0) AS eng_count
            FROM {source_table} h
            LEFT JOIN (
                SELECT HCP_ID, COUNT(*) AS rx_count
                FROM {fqn('RAW_PRESCRIPTIONS')}
                GROUP BY HCP_ID
            ) rx ON h.HCP_ID = rx.HCP_ID
            LEFT JOIN (
                SELECT HCP_ID, COUNT(*) AS eng_count
                FROM {fqn('RAW_HCP_ENGAGEMENTS')}
                GROUP BY HCP_ID
            ) eng ON h.HCP_ID = eng.HCP_ID
            WHERE h.ETL_UPDATE_DATETIME_UTC >= '2026-05-26 00:00:00'
        )
        SELECT
            n.HCP_ID,
            n.SPECIALTY,
            n.STANDARDIZED_SPECIALTY,
            n.SPECIALTY_GROUP_ID,
            n.TIER,
            n.DECILE,
            n.CONFIDENCE,
            CURRENT_TIMESTAMP() AS ETL_UPDATE_DATETIME_UTC
        FROM hcp_activity src,
             TABLE({udtf_name}(src.HCP_ID, src.SPECIALTY, src.YEARS_EXPERIENCE, src.rx_count, src.eng_count)) n
    """
    sf_session.sql(process_sql).collect()

    result_count = sf_session.sql(f"SELECT COUNT(*) FROM {target_table}").collect()[0][0]
    print(f"  SUCCESS: {result_count} rows written to {target_table}")

    print("  Tier distribution:")
    dist = sf_session.sql(f"""
        SELECT TIER, COUNT(*) AS cnt FROM {target_table} GROUP BY TIER ORDER BY cnt DESC
    """).collect()
    for row in dist:
        print(f"    {row[0]}: {row[1]}")

    print(f"  UDTF processed all rows SERVER-SIDE on warehouse — zero driver memory used.")


if __name__ == "__main__":
    main()
