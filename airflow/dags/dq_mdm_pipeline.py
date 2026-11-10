"""
Airflow DAG: Data Quality & MDM Pipeline

Runs MDM stored procedures on-demand via SQL API.
Jobs: hcp_dedup → rx_outlier_detection → engagement_validation → tier_validation
"""
import sys
import os
from datetime import datetime

from airflow import DAG
from airflow.operators.python import PythonOperator

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "plugins"))
from snowflake_executor import run_sql

SCHEMA = "HEALTHCARE_DEMO"

default_args = {
    "owner": "data-engineering",
    "retries": 1,
    "retry_delay": 60,
}


def call_procedure(procedure_name, **kwargs):
    """Execute a stored procedure via SQL API."""
    sql = f"CALL DEMO.{SCHEMA}.{procedure_name}()"
    return run_sql(sql, schema=SCHEMA, **kwargs)


def run_outlier_detection(**kwargs):
    """Run Rx outlier detection inline (single-statement task body)."""
    sql = """
    INSERT INTO DEMO.HEALTHCARE_DEMO.MDM_VIOLATION_LOG
        (RULE_NAME, TABLE_NAME, RECORD_ID, VIOLATION_DETAIL, SEVERITY)
    SELECT
        'RX_VOLUME_OUTLIER',
        'RAW_PRESCRIPTIONS',
        rx.RX_ID,
        'Rx quantity ' || rx.QUANTITY || ' exceeds 5x territory avg (' || ROUND(avg_qty.avg_q, 1) || ')',
        'CRITICAL'
    FROM DEMO.HEALTHCARE_DEMO.RAW_PRESCRIPTIONS rx
    JOIN (
        SELECT TERRITORY_ID, AVG(QUANTITY) AS avg_q
        FROM DEMO.HEALTHCARE_DEMO.RAW_PRESCRIPTIONS
        GROUP BY TERRITORY_ID
    ) avg_qty ON rx.TERRITORY_ID = avg_qty.TERRITORY_ID
    WHERE rx.QUANTITY > avg_qty.avg_q * 5
      AND rx.RX_ID NOT IN (
          SELECT RECORD_ID FROM DEMO.HEALTHCARE_DEMO.MDM_VIOLATION_LOG
          WHERE RULE_NAME = 'RX_VOLUME_OUTLIER'
      )
    """
    return run_sql(sql, schema=SCHEMA, **kwargs)


def run_tier_validation(**kwargs):
    """Run HCP tier validation inline (single-statement task body)."""
    sql = """
    INSERT INTO DEMO.HEALTHCARE_DEMO.MDM_VIOLATION_LOG
        (RULE_NAME, TABLE_NAME, RECORD_ID, VIOLATION_DETAIL, SEVERITY)
    SELECT
        'INVALID_HCP_TIER',
        'HCP_TIERED_PROFILES',
        HCP_ID,
        'Invalid tier value: ' || COALESCE(TIER, 'NULL') || ', decile: ' || COALESCE(TO_VARCHAR(DECILE), 'NULL'),
        'WARNING'
    FROM DEMO.HEALTHCARE_DEMO.HCP_TIERED_PROFILES
    WHERE (TIER NOT IN ('Tier 1','Tier 2','Tier 3','Tier 4','Tier 5') OR TIER IS NULL
           OR DECILE < 1 OR DECILE > 10 OR DECILE IS NULL)
      AND HCP_ID NOT IN (
          SELECT RECORD_ID FROM DEMO.HEALTHCARE_DEMO.MDM_VIOLATION_LOG
          WHERE RULE_NAME = 'INVALID_HCP_TIER' AND RESOLVED = FALSE
      )
    """
    return run_sql(sql, schema=SCHEMA, **kwargs)


with DAG(
    dag_id="dq_mdm_pipeline",
    description="Data quality & MDM — run business rule procedures",
    start_date=datetime(2026, 1, 1),
    schedule=None,
    catchup=False,
    default_args=default_args,
    tags=["snowflake", "data-quality", "mdm", "healthcare"],
) as dag:

    hcp_dedup = PythonOperator(
        task_id="hcp_dedup",
        python_callable=call_procedure,
        op_kwargs={"procedure_name": "SP_MDM_HCP_DEDUP"},
    )

    rx_outlier_detection = PythonOperator(
        task_id="rx_outlier_detection",
        python_callable=run_outlier_detection,
    )

    engagement_validation = PythonOperator(
        task_id="engagement_validation",
        python_callable=call_procedure,
        op_kwargs={"procedure_name": "SP_MDM_ENGAGEMENT_VALIDATION"},
    )

    tier_validation = PythonOperator(
        task_id="tier_validation",
        python_callable=run_tier_validation,
    )

    hcp_dedup >> rx_outlier_detection >> engagement_validation >> tier_validation
