"""Validate all Healthcare SCOS demo outputs.
Runs as a Spark Code Bundle on Snowflake warehouse compute.
"""
import sys
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

EXPECTED_TARGETS = [
    ("RX_METRICS_OUTPUT", 100),
    ("HCP_TIERED_PROFILES", 1000),
    ("ENGAGEMENT_FINAL", 1000),
]


def main():
    spark, sf_session = get_sessions()
    print("=" * 50)
    print("  Healthcare Demo Validation (Code Bundle)")
    print("=" * 50)

    all_passed = True

    for table_name, min_rows in EXPECTED_TARGETS:
        full_table = fqn(table_name)
        count = sf_session.sql(f"SELECT COUNT(*) FROM {full_table}").collect()[0][0]
        status = "PASS" if count >= min_rows else "FAIL"
        if status == "FAIL":
            all_passed = False
        print(f"  [{status}] {table_name}: {count} rows (min expected: {min_rows})")

    print("")
    print("  NULL key validation:")
    null_checks = [
        ("RX_METRICS_OUTPUT", "DRUG_ID"),
        ("HCP_TIERED_PROFILES", "HCP_ID"),
        ("ENGAGEMENT_FINAL", "ENGAGEMENT_ID"),
    ]
    for table_name, key_col in null_checks:
        null_count = sf_session.sql(
            f"SELECT COUNT(*) FROM {fqn(table_name)} WHERE {key_col} IS NULL"
        ).collect()[0][0]
        status = "PASS" if null_count == 0 else "FAIL"
        if null_count > 0:
            all_passed = False
        print(f"  [{status}] {table_name}.{key_col} NULLs: {null_count}")

    print("")
    print("  MERGE idempotency check (ENGAGEMENT_FINAL):")
    dup_count = sf_session.sql(f"""
        SELECT COUNT(*) FROM (
            SELECT ENGAGEMENT_ID, COUNT(*) AS cnt
            FROM {fqn('ENGAGEMENT_FINAL')}
            GROUP BY ENGAGEMENT_ID
            HAVING cnt > 1
        )
    """).collect()[0][0]
    status = "PASS" if dup_count == 0 else "FAIL"
    if dup_count > 0:
        all_passed = False
    print(f"  [{status}] Duplicate ENGAGEMENT_IDs: {dup_count}")

    print("")
    print("  HCP tier distribution sanity check:")
    tier_count = sf_session.sql(f"""
        SELECT COUNT(DISTINCT TIER) FROM {fqn('HCP_TIERED_PROFILES')}
    """).collect()[0][0]
    status = "PASS" if tier_count >= 3 else "FAIL"
    if tier_count < 3:
        all_passed = False
    print(f"  [{status}] Distinct tiers: {tier_count} (expected >= 3)")

    print("")
    print("=" * 50)
    if all_passed:
        print("  ALL VALIDATIONS PASSED")
    else:
        print("  SOME VALIDATIONS FAILED")
        sys.exit(1)
    print("=" * 50)


if __name__ == "__main__":
    main()
