"""
Job 1: Prescription Metrics Load (staging-validate-merge pattern)
Runs as a Spark Code Bundle on Snowflake warehouse compute.

Aggregates prescription volume and revenue metrics by drug and territory,
then MERGEs into the target metrics table idempotently.
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


class RxMetricsLoadJob:
    def __init__(self, spark, sf_session, ds):
        self.spark = spark
        self.sf = sf_session
        self.ds = ds
        self.target = fqn("RX_METRICS_OUTPUT")
        self.staging = fqn("STG_RX_METRICS_TEMP")

    def create_staging(self):
        print("  Creating staging table...")
        self.sf.sql(f"CREATE OR REPLACE TRANSIENT TABLE {self.staging} LIKE {self.target}").collect()

    def load_staging(self):
        print("  Loading prescription volume metrics into staging...")
        load_sql = f"""
            INSERT INTO {self.staging}
            SELECT
                '{self.ds}' AS DS,
                'total_rx_volume' AS METRIC_NAME,
                'Daily' AS PERIOD_GRAIN,
                DRUG_ID,
                TERRITORY_ID,
                SUM(TOTAL_UNITS) AS METRIC_VALUE,
                CURRENT_TIMESTAMP() AS ETL_TIMESTAMP
            FROM {fqn('RAW_PRESCRIPTIONS')}
            WHERE DS = '{self.ds}'
            GROUP BY DRUG_ID, TERRITORY_ID
        """
        self.sf.sql(load_sql).collect()

        print("  Loading new patient metrics into staging...")
        np_sql = f"""
            INSERT INTO {self.staging}
            SELECT
                '{self.ds}' AS DS,
                'new_patient_starts' AS METRIC_NAME,
                'Daily' AS PERIOD_GRAIN,
                DRUG_ID,
                TERRITORY_ID,
                COUNT(*) AS METRIC_VALUE,
                CURRENT_TIMESTAMP() AS ETL_TIMESTAMP
            FROM {fqn('RAW_PRESCRIPTIONS')}
            WHERE DS = '{self.ds}' AND IS_NEW_PATIENT = TRUE
            GROUP BY DRUG_ID, TERRITORY_ID
        """
        self.sf.sql(np_sql).collect()

    def validate_staging(self) -> bool:
        print("  Validating staging data...")
        result = self.sf.sql(f"SELECT COUNT(*) FROM {self.staging}").collect()[0][0]
        print(f"  Validation result: count={result}")
        return result > 0

    def merge_to_target(self):
        print("  Merging staging -> target...")
        merge_sql = f"""
            MERGE INTO {self.target} AS tgt
            USING {self.staging} AS src
            ON tgt.DS = src.DS
               AND tgt.METRIC_NAME = src.METRIC_NAME
               AND tgt.DRUG_ID = src.DRUG_ID
               AND tgt.TERRITORY_ID = src.TERRITORY_ID
            WHEN MATCHED THEN UPDATE SET
                tgt.METRIC_VALUE = src.METRIC_VALUE,
                tgt.ETL_TIMESTAMP = src.ETL_TIMESTAMP
            WHEN NOT MATCHED THEN INSERT (
                DS, METRIC_NAME, PERIOD_GRAIN, DRUG_ID, TERRITORY_ID, METRIC_VALUE, ETL_TIMESTAMP
            ) VALUES (
                src.DS, src.METRIC_NAME, src.PERIOD_GRAIN, src.DRUG_ID, src.TERRITORY_ID,
                src.METRIC_VALUE, src.ETL_TIMESTAMP
            )
        """
        self.sf.sql(merge_sql).collect()

    def cleanup(self):
        print("  Dropping staging table...")
        self.sf.sql(f"DROP TABLE IF EXISTS {self.staging}").collect()

    def execute(self):
        print(f"[Job 1] Rx Metrics Load — ds={self.ds}")
        self.create_staging()
        self.load_staging()
        if self.validate_staging():
            self.merge_to_target()
            self.cleanup()
            count = self.sf.sql(f"SELECT COUNT(*) FROM {self.target} WHERE DS = '{self.ds}'").collect()[0][0]
            print(f"  SUCCESS: {count} rows in target for ds={self.ds}")
        else:
            self.cleanup()
            raise ValueError("Staging validation failed — no data loaded")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--ds", required=True)
    args = parser.parse_args()

    spark, sf_session = get_sessions()
    job = RxMetricsLoadJob(spark, sf_session, args.ds)
    job.execute()


if __name__ == "__main__":
    main()
