"""
Airflow DAG: CRM Pipeline (Salesforce One-Hop Reduction)

Orchestrates 3 Spark jobs on Snowflake via Code Bundles.
Includes incremental data generation to simulate new CRM data arriving each run.
Jobs: generate_data -> customer_360_enrich -> pipeline_forecast -> validate
"""
import sys
import os
import subprocess
import logging
from datetime import datetime

from airflow import DAG
from airflow.operators.python import PythonOperator

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "plugins"))
from snowflake_executor import submit_and_wait

BUNDLE = "CB_CRM_SPARK"
SCHEMA = "CRM_DEMO"
logger = logging.getLogger(__name__)

default_args = {
    "owner": "data-engineering",
    "retries": 1,
    "retry_delay": 60,
}


def generate_incremental_data(**kwargs):
    """Insert synthetic rows via snow sql CLI (simple, no polling)."""
    sql = (
        "INSERT INTO DEMO.CRM_DEMO.RAW_OPPORTUNITIES "
        "(OPP_ID, ACCOUNT_ID, OPP_NAME, STAGE, AMOUNT, CLOSE_DATE, CREATED_DATE, IS_CLOSED, IS_WON) "
        "SELECT UUID_STRING(), a.ACCOUNT_ID, "
        "'Auto-Deal-'||UNIFORM(1000,9999,RANDOM())::VARCHAR, "
        "CASE UNIFORM(1,6,RANDOM()) WHEN 1 THEN 'Prospecting' WHEN 2 THEN 'Qualification' "
        "WHEN 3 THEN 'Proposal' WHEN 4 THEN 'Negotiation' "
        "WHEN 5 THEN 'Closed Won' ELSE 'Closed Lost' END, "
        "ROUND(UNIFORM(10000,2000000,RANDOM())::FLOAT,2), "
        "DATEADD('day',UNIFORM(30,180,RANDOM()),CURRENT_DATE()), "
        "CURRENT_DATE(), "
        "CASE WHEN UNIFORM(1,6,RANDOM())>=5 THEN TRUE ELSE FALSE END, "
        "CASE WHEN UNIFORM(1,6,RANDOM())=5 THEN TRUE ELSE FALSE END "
        "FROM DEMO.CRM_DEMO.RAW_ACCOUNTS a LIMIT 20"
    )
    result = subprocess.run(
        ["snow", "sql", "-q", sql, "-c", "my_conn", "--silent"],
        capture_output=True, text=True, timeout=120
    )
    if result.returncode != 0:
        raise RuntimeError(f"snow sql failed: {result.stderr}")
    logger.info("Inserted 20 opportunities.")

    sql2 = (
        "INSERT INTO DEMO.CRM_DEMO.RAW_CASES "
        "(CASE_ID, ACCOUNT_ID, PRIORITY, STATUS, SUBJECT, CREATED_DATE, CLOSED_DATE, RESOLUTION_DAYS) "
        "SELECT UUID_STRING(), a.ACCOUNT_ID, "
        "CASE UNIFORM(1,4,RANDOM()) WHEN 1 THEN 'Low' WHEN 2 THEN 'Medium' "
        "WHEN 3 THEN 'High' ELSE 'Critical' END, "
        "CASE UNIFORM(1,4,RANDOM()) WHEN 1 THEN 'New' WHEN 2 THEN 'In Progress' "
        "WHEN 3 THEN 'Escalated' ELSE 'Closed' END, "
        "'Auto-generated support case', CURRENT_DATE(), NULL, NULL "
        "FROM DEMO.CRM_DEMO.RAW_ACCOUNTS a LIMIT 10"
    )
    result2 = subprocess.run(
        ["snow", "sql", "-q", sql2, "-c", "my_conn", "--silent"],
        capture_output=True, text=True, timeout=120
    )
    if result2.returncode != 0:
        raise RuntimeError(f"snow sql failed: {result2.stderr}")
    logger.info("Inserted 10 cases. Done.")


with DAG(
    dag_id="crm_pipeline",
    description="CRM one-hop-reduction pipeline — incremental data + 3 Code Bundle jobs",
    start_date=datetime(2026, 1, 1),
    schedule=None,
    catchup=False,
    default_args=default_args,
    tags=["snowflake", "spark", "code-bundles", "crm", "salesforce"],
) as dag:

    generate_data = PythonOperator(
        task_id="generate_incremental_data",
        python_callable=generate_incremental_data,
    )

    customer_360_enrich = PythonOperator(
        task_id="customer_360_enrich",
        python_callable=submit_and_wait,
        op_kwargs={
            "entrypoint": "01_customer_360_enrich.py",
            "bundle_name": BUNDLE,
            "schema": SCHEMA,
            "execution_name": "airflow_customer_360_enrich",
        },
    )

    pipeline_forecast = PythonOperator(
        task_id="pipeline_forecast",
        python_callable=submit_and_wait,
        op_kwargs={
            "entrypoint": "02_pipeline_forecast.py",
            "bundle_name": BUNDLE,
            "schema": SCHEMA,
            "execution_name": "airflow_pipeline_forecast",
        },
    )

    validate = PythonOperator(
        task_id="validate",
        python_callable=submit_and_wait,
        op_kwargs={
            "entrypoint": "03_validate.py",
            "bundle_name": BUNDLE,
            "schema": SCHEMA,
            "execution_name": "airflow_crm_validate",
        },
    )

    generate_data >> customer_360_enrich >> pipeline_forecast >> validate
