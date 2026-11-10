"""
Airflow DAG: Healthcare SCOS Spark Pipeline

Orchestrates 4 Spark jobs on Snowflake warehouse compute via Code Bundles.
Includes incremental data generation to simulate new data arriving each run.
Jobs: generate_data -> rx_metrics_load -> hcp_classification -> engagement_merge -> validate
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

BUNDLE = "CB_HEALTHCARE_SPARK"
SCHEMA = "HEALTHCARE_DEMO"
logger = logging.getLogger(__name__)

default_args = {
    "owner": "data-engineering",
    "retries": 1,
    "retry_delay": 60,
}


def generate_incremental_data(**kwargs):
    """Insert synthetic rows via snow sql CLI (simple, no polling needed)."""
    sql = (
        "INSERT INTO DEMO.HEALTHCARE_DEMO.RAW_PRESCRIPTIONS "
        "(RX_ID, DRUG_ID, HCP_ID, TERRITORY_ID, QUANTITY, TOTAL_UNITS, RX_DATE, PAYER_TYPE, IS_NEW_PATIENT, DS) "
        "SELECT UUID_STRING(), d.DRUG_ID, h.HCP_ID, UNIFORM(1,100,RANDOM()), UNIFORM(1,500,RANDOM()), "
        "ROUND(UNIFORM(10,5000,RANDOM())::FLOAT,1), CURRENT_DATE(), "
        "CASE UNIFORM(1,5,RANDOM()) WHEN 1 THEN 'Commercial' WHEN 2 THEN 'Medicare' "
        "WHEN 3 THEN 'Medicaid' WHEN 4 THEN 'Cash Pay' ELSE 'VA/Military' END, "
        "CASE WHEN UNIFORM(1,10,RANDOM())<=3 THEN TRUE ELSE FALSE END, "
        "TO_CHAR(CURRENT_DATE(),'YYYY-MM-DD') "
        "FROM DEMO.HEALTHCARE_DEMO.DIM_DRUG d "
        "CROSS JOIN (SELECT HCP_ID FROM DEMO.HEALTHCARE_DEMO.RAW_HCP_PROFILES LIMIT 34) h "
        "LIMIT 500"
    )
    result = subprocess.run(
        ["snow", "sql", "-q", sql, "-c", "my_conn", "--silent"],
        capture_output=True, text=True, timeout=120
    )
    if result.returncode != 0:
        raise RuntimeError(f"snow sql failed: {result.stderr}")
    logger.info(f"Inserted 500 prescriptions. Output: {result.stdout[:200]}")

    sql2 = (
        "INSERT INTO DEMO.HEALTHCARE_DEMO.RAW_HCP_ENGAGEMENTS "
        "(ENGAGEMENT_ID, HCP_ID, REP_ID, DRUG_ID, ENGAGEMENT_TYPE, CHANNEL, "
        "ENGAGEMENT_DATE, DURATION_MINUTES, SAMPLES_DROPPED, NOTES, SENTIMENT_SCORE, UPDATED_AT) "
        "SELECT UUID_STRING(), h.HCP_ID, 'REP-'||UNIFORM(1,200,RANDOM())::VARCHAR, d.DRUG_ID, "
        "CASE UNIFORM(1,6,RANDOM()) WHEN 1 THEN 'Detail Visit' WHEN 2 THEN 'Sample Drop' "
        "WHEN 3 THEN 'Lunch and Learn' WHEN 4 THEN 'Conference' "
        "WHEN 5 THEN 'Webinar' ELSE 'Peer-to-Peer Speaker' END, "
        "CASE UNIFORM(1,5,RANDOM()) WHEN 1 THEN 'In-Person' WHEN 2 THEN 'Virtual' "
        "WHEN 3 THEN 'Hybrid' WHEN 4 THEN 'Phone' ELSE 'Email' END, "
        "CURRENT_DATE(), UNIFORM(5,60,RANDOM()), UNIFORM(0,10,RANDOM()), "
        "'Incremental engagement - auto generated', "
        "ROUND(UNIFORM(-1,1,RANDOM())::FLOAT,2), CURRENT_TIMESTAMP() "
        "FROM DEMO.HEALTHCARE_DEMO.DIM_DRUG d "
        "CROSS JOIN (SELECT HCP_ID FROM DEMO.HEALTHCARE_DEMO.RAW_HCP_PROFILES LIMIT 4) h "
        "LIMIT 50"
    )
    result2 = subprocess.run(
        ["snow", "sql", "-q", sql2, "-c", "my_conn", "--silent"],
        capture_output=True, text=True, timeout=120
    )
    if result2.returncode != 0:
        raise RuntimeError(f"snow sql failed: {result2.stderr}")
    logger.info(f"Inserted 50 engagements. Done.")


with DAG(
    dag_id="healthcare_pipeline",
    description="Healthcare SCOS Spark pipeline — incremental data + 4 Code Bundle jobs",
    start_date=datetime(2026, 1, 1),
    schedule=None,
    catchup=False,
    default_args=default_args,
    tags=["snowflake", "spark", "code-bundles", "healthcare"],
) as dag:

    generate_data = PythonOperator(
        task_id="generate_incremental_data",
        python_callable=generate_incremental_data,
    )

    rx_metrics_load = PythonOperator(
        task_id="rx_metrics_load",
        python_callable=submit_and_wait,
        op_kwargs={
            "entrypoint": "01_rx_metrics_load.py",
            "bundle_name": BUNDLE,
            "schema": SCHEMA,
            "arguments": ["--ds", datetime.now().strftime('%Y-%m-%d')],
            "execution_name": "airflow_rx_metrics_load",
        },
    )

    hcp_classification = PythonOperator(
        task_id="hcp_classification",
        python_callable=submit_and_wait,
        op_kwargs={
            "entrypoint": "02_hcp_classification.py",
            "bundle_name": BUNDLE,
            "schema": SCHEMA,
            "arguments": ["--ds", datetime.now().strftime('%Y-%m-%d'), "--batch-size", "50"],
            "execution_name": "airflow_hcp_classification",
        },
    )

    engagement_merge = PythonOperator(
        task_id="engagement_merge",
        python_callable=submit_and_wait,
        op_kwargs={
            "entrypoint": "03_engagement_merge.py",
            "bundle_name": BUNDLE,
            "schema": SCHEMA,
            "execution_name": "airflow_engagement_merge",
        },
    )

    validate = PythonOperator(
        task_id="validate",
        python_callable=submit_and_wait,
        op_kwargs={
            "entrypoint": "04_validate.py",
            "bundle_name": BUNDLE,
            "schema": SCHEMA,
            "execution_name": "airflow_validate",
        },
    )

    generate_data >> rx_metrics_load >> hcp_classification >> engagement_merge >> validate
