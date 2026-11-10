"""
Job 3: Validate CRM Pipeline Outputs
Runs as a Spark Code Bundle on Snowflake warehouse compute.

Performs data quality assertions on CUSTOMER_360 and PIPELINE_FORECAST.
Fails fast with clear error messages if any check fails.
"""
import os
from pyspark.sql import SparkSession
from snowflake.snowpark_connect.snowflake_session import SnowflakeSession


def get_sessions():
    spark = SparkSession.builder.getOrCreate()
    sf_session = SnowflakeSession(spark)
    return spark, sf_session


def fqn(table_name):
    db = os.getenv("SNOWFLAKE_DATABASE", "DEMO")
    schema = os.getenv("SNOWFLAKE_SCHEMA", "CRM_DEMO")
    return f"{db}.{schema}.{table_name}"


def check(sf, description, sql, expected_fn):
    result = sf.sql(sql).collect()
    value = result[0][0] if result else None
    passed = expected_fn(value)
    status = "PASS" if passed else "FAIL"
    print(f"    [{status}] {description}: {value}")
    return passed


def main():
    spark, sf = get_sessions()

    print("[Job 3] Validate — CRM pipeline data quality gates")
    failures = []

    # --- CUSTOMER_360 checks ---
    print("  Checking CUSTOMER_360...")

    if not check(sf, "Row count > 0",
                 f"SELECT COUNT(*) FROM {fqn('CUSTOMER_360')}",
                 lambda v: v and v > 0):
        failures.append("CUSTOMER_360 is empty")

    if not check(sf, "Row count matches accounts",
                 f"SELECT COUNT(*) FROM {fqn('CUSTOMER_360')} WHERE ACCOUNT_ID IN (SELECT ACCOUNT_ID FROM {fqn('RAW_ACCOUNTS')})",
                 lambda v: v and v > 0):
        failures.append("CUSTOMER_360 has orphan accounts")

    if not check(sf, "No NULL health scores",
                 f"SELECT COUNT(*) FROM {fqn('CUSTOMER_360')} WHERE HEALTH_SCORE IS NULL",
                 lambda v: v == 0):
        failures.append("CUSTOMER_360 has NULL health scores")

    if not check(sf, "Health scores in range [0, 100]",
                 f"SELECT COUNT(*) FROM {fqn('CUSTOMER_360')} WHERE HEALTH_SCORE < 0 OR HEALTH_SCORE > 100",
                 lambda v: v == 0):
        failures.append("CUSTOMER_360 has out-of-range health scores")

    if not check(sf, "Win rates in range [0, 1]",
                 f"SELECT COUNT(*) FROM {fqn('CUSTOMER_360')} WHERE WIN_RATE < 0 OR WIN_RATE > 1",
                 lambda v: v == 0):
        failures.append("CUSTOMER_360 has invalid win rates")

    if not check(sf, "All segments are valid",
                 f"SELECT COUNT(*) FROM {fqn('CUSTOMER_360')} WHERE SEGMENT NOT IN ('High Value', 'Growth', 'At Risk')",
                 lambda v: v == 0):
        failures.append("CUSTOMER_360 has invalid segments")

    # --- PIPELINE_FORECAST checks ---
    print("  Checking PIPELINE_FORECAST...")

    if not check(sf, "Row count > 0",
                 f"SELECT COUNT(*) FROM {fqn('PIPELINE_FORECAST')}",
                 lambda v: v and v > 0):
        failures.append("PIPELINE_FORECAST is empty")

    if not check(sf, "No NULL weighted pipeline",
                 f"SELECT COUNT(*) FROM {fqn('PIPELINE_FORECAST')} WHERE WEIGHTED_PIPELINE IS NULL",
                 lambda v: v == 0):
        failures.append("PIPELINE_FORECAST has NULL weighted_pipeline")

    if not check(sf, "All forecast categories valid",
                 f"SELECT COUNT(*) FROM {fqn('PIPELINE_FORECAST')} WHERE FORECAST_CATEGORY NOT IN ('Commit', 'Best Case', 'Pipeline', 'Lost')",
                 lambda v: v == 0):
        failures.append("PIPELINE_FORECAST has invalid forecast categories")

    if not check(sf, "No orphan account IDs",
                 f"SELECT COUNT(*) FROM {fqn('PIPELINE_FORECAST')} pf WHERE NOT EXISTS (SELECT 1 FROM {fqn('RAW_ACCOUNTS')} a WHERE a.ACCOUNT_ID = pf.ACCOUNT_ID)",
                 lambda v: v == 0):
        failures.append("PIPELINE_FORECAST has orphan account references")

    # --- Summary ---
    print("")
    if failures:
        print(f"  FAILED — {len(failures)} check(s) failed:")
        for f in failures:
            print(f"    - {f}")
        raise AssertionError(f"Validation failed: {failures}")
    else:
        print("  ALL CHECKS PASSED.")
        print("[Job 3] Complete.")


if __name__ == "__main__":
    main()
