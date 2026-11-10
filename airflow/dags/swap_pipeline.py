"""
Airflow DAG: Blue/Green Swap Pipeline

Demonstrates zero-downtime star schema refresh via zero-copy clone + atomic swap.
Steps: insert_new_data → call_refresh_procedure → verify_swap
"""
import sys
import os
from datetime import datetime

from airflow import DAG
from airflow.operators.python import PythonOperator

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "plugins"))
from snowflake_executor import run_sql

default_args = {
    "owner": "data-engineering",
    "retries": 1,
    "retry_delay": 60,
}


def insert_new_source_data(**kwargs):
    """Simulate ETL delivering fresh data to the source star schema."""
    sql = """
    INSERT INTO SWAP_DEMO.STAR_SCHEMA.FACT_ORDERS
        (ORDER_ID, CUSTOMER_ID, PRODUCT_ID, ORDER_DATE, QUANTITY, TOTAL_AMOUNT, CHANNEL)
    SELECT
        (SELECT MAX(ORDER_ID) FROM SWAP_DEMO.STAR_SCHEMA.FACT_ORDERS) + SEQ4() AS ORDER_ID,
        UNIFORM(1, 75, RANDOM()) AS CUSTOMER_ID,
        UNIFORM(1, 50, RANDOM()) AS PRODUCT_ID,
        DATEADD('day', -UNIFORM(0, 5, RANDOM()), CURRENT_DATE()) AS ORDER_DATE,
        UNIFORM(1, 10, RANDOM()) AS QUANTITY,
        ROUND(UNIFORM(10, 500, RANDOM())::FLOAT * UNIFORM(1, 10, RANDOM()), 2) AS TOTAL_AMOUNT,
        CASE UNIFORM(1, 4, RANDOM())
            WHEN 1 THEN 'ONLINE'
            WHEN 2 THEN 'IN_STORE'
            WHEN 3 THEN 'PARTNER'
            ELSE 'DIRECT'
        END AS CHANNEL
    FROM TABLE(GENERATOR(ROWCOUNT => 25))
    """
    return run_sql(sql, database="SWAP_DEMO", schema="STAR_SCHEMA", **kwargs)


def refresh_star_schema(**kwargs):
    """Call the REFRESH_STAR_SCHEMA procedure: clone → swap → drop staging."""
    sql = "CALL SWAP_DEMO.STAR_SCHEMA.REFRESH_STAR_SCHEMA()"
    return run_sql(sql, database="SWAP_DEMO", schema="STAR_SCHEMA", **kwargs)


def verify_swap(**kwargs):
    """Verify PROD tables reflect the latest data after swap."""
    sql = """
    SELECT
        'dim_customer' AS tbl, COUNT(*) AS row_count FROM SWAP_DEMO.PROD.DIM_CUSTOMER
    UNION ALL
        SELECT 'dim_product', COUNT(*) FROM SWAP_DEMO.PROD.DIM_PRODUCT
    UNION ALL
        SELECT 'fact_orders', COUNT(*) FROM SWAP_DEMO.PROD.FACT_ORDERS
    """
    return run_sql(sql, database="SWAP_DEMO", schema="PROD", async_mode=False, **kwargs)


with DAG(
    dag_id="swap_pipeline",
    description="Blue/green zero-copy clone swap — star schema refresh",
    start_date=datetime(2026, 1, 1),
    schedule=None,
    catchup=False,
    default_args=default_args,
    tags=["snowflake", "swap", "blue-green", "zero-copy-clone"],
) as dag:

    insert_data = PythonOperator(
        task_id="insert_new_source_data",
        python_callable=insert_new_source_data,
    )

    refresh = PythonOperator(
        task_id="refresh_star_schema",
        python_callable=refresh_star_schema,
    )

    verify = PythonOperator(
        task_id="verify_swap",
        python_callable=verify_swap,
    )

    insert_data >> refresh >> verify
