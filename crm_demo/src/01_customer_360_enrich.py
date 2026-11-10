"""
Job 1: Customer 360 Enrichment
Runs as a Spark Code Bundle on Snowflake warehouse compute.

Joins accounts + opportunities + cases to produce a unified CUSTOMER_360
table with health scores, segments, win rates, and pipeline metrics.
Uses staging-validate-MERGE pattern.
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


def main():
    spark, sf = get_sessions()
    target = fqn("CUSTOMER_360")
    staging = fqn("STG_CUSTOMER_360_TEMP")

    print("[Job 1] Customer 360 Enrichment — multi-join + scoring + MERGE")

    # Step 1: Create staging table
    print("  Step 1: Creating staging table...")
    sf.sql(f"CREATE OR REPLACE TRANSIENT TABLE {staging} LIKE {target}").collect()

    # Step 2: Build enriched dataset via multi-join aggregation
    print("  Step 2: Computing opportunity metrics per account...")
    enrich_sql = f"""
        INSERT INTO {staging}
        SELECT
            a.ACCOUNT_ID,
            a.ACCOUNT_NAME,
            a.INDUSTRY,
            a.REGION,
            COALESCE(opp.TOTAL_PIPELINE, 0) AS TOTAL_PIPELINE,
            COALESCE(opp.WON_REVENUE, 0) AS WON_REVENUE,
            COALESCE(opp.WIN_RATE, 0) AS WIN_RATE,
            COALESCE(opp.OPEN_OPPS, 0) AS OPEN_OPPS,
            COALESCE(cs.AVG_CASE_RESOLUTION_DAYS, 0) AS AVG_CASE_RESOLUTION_DAYS,
            COALESCE(cs.OPEN_CASES, 0) AS OPEN_CASES,
            -- Health Score: composite of win_rate (40%), pipeline factor (30%), case factor (30%)
            ROUND(
                (COALESCE(opp.WIN_RATE, 0) * 40.0) +
                (LEAST(COALESCE(opp.TOTAL_PIPELINE, 0) / 500000.0, 1.0) * 30.0) +
                (GREATEST(1.0 - COALESCE(cs.AVG_CASE_RESOLUTION_DAYS, 0) / 30.0, 0.0) * 30.0),
                2
            ) AS HEALTH_SCORE,
            CASE
                WHEN (COALESCE(opp.WIN_RATE, 0) * 40.0) +
                     (LEAST(COALESCE(opp.TOTAL_PIPELINE, 0) / 500000.0, 1.0) * 30.0) +
                     (GREATEST(1.0 - COALESCE(cs.AVG_CASE_RESOLUTION_DAYS, 0) / 30.0, 0.0) * 30.0) >= 70
                THEN 'High Value'
                WHEN (COALESCE(opp.WIN_RATE, 0) * 40.0) +
                     (LEAST(COALESCE(opp.TOTAL_PIPELINE, 0) / 500000.0, 1.0) * 30.0) +
                     (GREATEST(1.0 - COALESCE(cs.AVG_CASE_RESOLUTION_DAYS, 0) / 30.0, 0.0) * 30.0) >= 40
                THEN 'Growth'
                ELSE 'At Risk'
            END AS SEGMENT,
            CURRENT_TIMESTAMP() AS ETL_TIMESTAMP
        FROM {fqn('RAW_ACCOUNTS')} a
        LEFT JOIN (
            SELECT
                ACCOUNT_ID,
                SUM(CASE WHEN NOT IS_CLOSED THEN AMOUNT ELSE 0 END) AS TOTAL_PIPELINE,
                SUM(CASE WHEN IS_WON THEN AMOUNT ELSE 0 END) AS WON_REVENUE,
                CASE WHEN COUNT(*) > 0
                     THEN COUNT(CASE WHEN IS_WON THEN 1 END)::FLOAT / COUNT(*)
                     ELSE 0 END AS WIN_RATE,
                COUNT(CASE WHEN NOT IS_CLOSED THEN 1 END) AS OPEN_OPPS
            FROM {fqn('RAW_OPPORTUNITIES')}
            GROUP BY ACCOUNT_ID
        ) opp ON a.ACCOUNT_ID = opp.ACCOUNT_ID
        LEFT JOIN (
            SELECT
                ACCOUNT_ID,
                AVG(CASE WHEN RESOLUTION_DAYS > 0 THEN RESOLUTION_DAYS END) AS AVG_CASE_RESOLUTION_DAYS,
                COUNT(CASE WHEN STATUS != 'Closed' THEN 1 END) AS OPEN_CASES
            FROM {fqn('RAW_CASES')}
            GROUP BY ACCOUNT_ID
        ) cs ON a.ACCOUNT_ID = cs.ACCOUNT_ID
    """
    sf.sql(enrich_sql).collect()

    # Step 3: Validate staging
    print("  Step 3: Validating staging data...")
    count_result = sf.sql(f"SELECT COUNT(*) AS CNT FROM {staging}").collect()
    row_count = count_result[0]["CNT"]
    print(f"    Staging rows: {row_count}")
    assert row_count > 0, "Staging table is empty!"

    # Step 4: MERGE into target
    print("  Step 4: MERGE into target...")
    merge_sql = f"""
        MERGE INTO {target} tgt
        USING {staging} src
        ON tgt.ACCOUNT_ID = src.ACCOUNT_ID
        WHEN MATCHED THEN UPDATE SET
            tgt.ACCOUNT_NAME = src.ACCOUNT_NAME,
            tgt.INDUSTRY = src.INDUSTRY,
            tgt.REGION = src.REGION,
            tgt.TOTAL_PIPELINE = src.TOTAL_PIPELINE,
            tgt.WON_REVENUE = src.WON_REVENUE,
            tgt.WIN_RATE = src.WIN_RATE,
            tgt.OPEN_OPPS = src.OPEN_OPPS,
            tgt.AVG_CASE_RESOLUTION_DAYS = src.AVG_CASE_RESOLUTION_DAYS,
            tgt.OPEN_CASES = src.OPEN_CASES,
            tgt.HEALTH_SCORE = src.HEALTH_SCORE,
            tgt.SEGMENT = src.SEGMENT,
            tgt.ETL_TIMESTAMP = src.ETL_TIMESTAMP
        WHEN NOT MATCHED THEN INSERT (
            ACCOUNT_ID, ACCOUNT_NAME, INDUSTRY, REGION,
            TOTAL_PIPELINE, WON_REVENUE, WIN_RATE, OPEN_OPPS,
            AVG_CASE_RESOLUTION_DAYS, OPEN_CASES, HEALTH_SCORE, SEGMENT, ETL_TIMESTAMP
        ) VALUES (
            src.ACCOUNT_ID, src.ACCOUNT_NAME, src.INDUSTRY, src.REGION,
            src.TOTAL_PIPELINE, src.WON_REVENUE, src.WIN_RATE, src.OPEN_OPPS,
            src.AVG_CASE_RESOLUTION_DAYS, src.OPEN_CASES, src.HEALTH_SCORE, src.SEGMENT, src.ETL_TIMESTAMP
        )
    """
    sf.sql(merge_sql).collect()

    # Step 5: Cleanup staging
    print("  Step 5: Dropping staging table...")
    sf.sql(f"DROP TABLE IF EXISTS {staging}").collect()

    # Verify
    final_count = sf.sql(f"SELECT COUNT(*) AS CNT FROM {target}").collect()[0]["CNT"]
    print(f"  CUSTOMER_360 now has {final_count} rows.")
    print("[Job 1] Complete.")


if __name__ == "__main__":
    main()
