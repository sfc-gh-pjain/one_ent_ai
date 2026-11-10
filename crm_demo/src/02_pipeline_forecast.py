"""
Job 2: Pipeline Forecast
Runs as a Spark Code Bundle on Snowflake warehouse compute.

Calculates weighted pipeline, forecast categories, days-to-close,
and velocity scores for each open opportunity. MERGEs into PIPELINE_FORECAST.
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
    target = fqn("PIPELINE_FORECAST")
    staging = fqn("STG_PIPELINE_FORECAST_TEMP")

    print("[Job 2] Pipeline Forecast — weighted pipeline + velocity scoring")

    # Step 1: Create staging table
    print("  Step 1: Creating staging table...")
    sf.sql(f"CREATE OR REPLACE TRANSIENT TABLE {staging} LIKE {target}").collect()

    # Step 2: Compute pipeline forecast metrics
    print("  Step 2: Computing forecast metrics...")
    forecast_sql = f"""
        INSERT INTO {staging}
        SELECT
            o.OPP_ID,
            o.ACCOUNT_ID,
            a.ACCOUNT_NAME,
            a.REGION,
            a.INDUSTRY,
            o.STAGE,
            o.AMOUNT,
            -- Weighted pipeline: amount * stage probability
            o.AMOUNT * CASE o.STAGE
                WHEN 'Prospecting' THEN 0.10
                WHEN 'Qualification' THEN 0.25
                WHEN 'Proposal' THEN 0.50
                WHEN 'Negotiation' THEN 0.75
                WHEN 'Closed Won' THEN 1.00
                WHEN 'Closed Lost' THEN 0.00
                ELSE 0.10
            END AS WEIGHTED_PIPELINE,
            -- Forecast category
            CASE
                WHEN o.STAGE IN ('Negotiation', 'Closed Won') THEN 'Commit'
                WHEN o.STAGE = 'Proposal' THEN 'Best Case'
                WHEN o.STAGE = 'Closed Lost' THEN 'Lost'
                ELSE 'Pipeline'
            END AS FORECAST_CATEGORY,
            -- Days to close
            DATEDIFF('day', CURRENT_DATE(), o.CLOSE_DATE) AS DAYS_TO_CLOSE,
            -- Velocity score: inverse of days-to-close normalized (faster = higher)
            ROUND(
                GREATEST(0, LEAST(100,
                    100.0 - (DATEDIFF('day', CURRENT_DATE(), o.CLOSE_DATE)::FLOAT / 180.0 * 100.0)
                )),
                2
            ) AS VELOCITY_SCORE,
            CURRENT_TIMESTAMP() AS ETL_TIMESTAMP
        FROM {fqn('RAW_OPPORTUNITIES')} o
        JOIN {fqn('RAW_ACCOUNTS')} a ON o.ACCOUNT_ID = a.ACCOUNT_ID
        WHERE NOT o.IS_CLOSED
    """
    sf.sql(forecast_sql).collect()

    # Step 3: Validate staging
    print("  Step 3: Validating staging data...")
    count_result = sf.sql(f"SELECT COUNT(*) AS CNT FROM {staging}").collect()
    row_count = count_result[0]["CNT"]
    print(f"    Staging rows: {row_count}")
    assert row_count > 0, "No open opportunities found for forecast!"

    # Step 4: Replace target (full refresh since we filter on IS_CLOSED=false)
    print("  Step 4: MERGE into target...")
    merge_sql = f"""
        MERGE INTO {target} tgt
        USING {staging} src
        ON tgt.OPP_ID = src.OPP_ID
        WHEN MATCHED THEN UPDATE SET
            tgt.ACCOUNT_ID = src.ACCOUNT_ID,
            tgt.ACCOUNT_NAME = src.ACCOUNT_NAME,
            tgt.REGION = src.REGION,
            tgt.INDUSTRY = src.INDUSTRY,
            tgt.STAGE = src.STAGE,
            tgt.AMOUNT = src.AMOUNT,
            tgt.WEIGHTED_PIPELINE = src.WEIGHTED_PIPELINE,
            tgt.FORECAST_CATEGORY = src.FORECAST_CATEGORY,
            tgt.DAYS_TO_CLOSE = src.DAYS_TO_CLOSE,
            tgt.VELOCITY_SCORE = src.VELOCITY_SCORE,
            tgt.ETL_TIMESTAMP = src.ETL_TIMESTAMP
        WHEN NOT MATCHED THEN INSERT (
            OPP_ID, ACCOUNT_ID, ACCOUNT_NAME, REGION, INDUSTRY, STAGE, AMOUNT,
            WEIGHTED_PIPELINE, FORECAST_CATEGORY, DAYS_TO_CLOSE, VELOCITY_SCORE, ETL_TIMESTAMP
        ) VALUES (
            src.OPP_ID, src.ACCOUNT_ID, src.ACCOUNT_NAME, src.REGION, src.INDUSTRY,
            src.STAGE, src.AMOUNT, src.WEIGHTED_PIPELINE, src.FORECAST_CATEGORY,
            src.DAYS_TO_CLOSE, src.VELOCITY_SCORE, src.ETL_TIMESTAMP
        )
    """
    sf.sql(merge_sql).collect()

    # Also remove closed opps from target
    sf.sql(f"""
        DELETE FROM {target}
        WHERE OPP_ID NOT IN (SELECT OPP_ID FROM {staging})
    """).collect()

    # Step 5: Cleanup staging
    print("  Step 5: Dropping staging table...")
    sf.sql(f"DROP TABLE IF EXISTS {staging}").collect()

    # Verify
    final_count = sf.sql(f"SELECT COUNT(*) AS CNT FROM {target}").collect()[0]["CNT"]
    print(f"  PIPELINE_FORECAST now has {final_count} rows (open opps only).")
    print("[Job 2] Complete.")


if __name__ == "__main__":
    main()
