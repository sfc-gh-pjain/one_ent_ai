"""
Job 5: Market Share Analysis
Runs as a Spark Code Bundle on Snowflake warehouse compute.

Computes drug market share by therapeutic area and territory,
then MERGEs into the MARKET_SHARE_ANALYSIS table idempotently.

Usage:
    EXECUTE CODE BUNDLE CB_HEALTHCARE_SPARK
      ENTRYPOINT = '05_market_share_analysis.py'
      ARGUMENTS = ('--ds', '2026-09-14')
      EXECUTION_NAME = 'market_share_analysis';
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


class MarketShareAnalysisJob:
    def __init__(self, spark, sf_session, ds):
        self.spark = spark
        self.sf = sf_session
        self.ds = ds
        self.target = fqn("MARKET_SHARE_ANALYSIS")
        self.staging = fqn("STG_MARKET_SHARE_TEMP")

    def create_staging(self):
        print("  Creating staging table...")
        self.sf.sql(f"""
            CREATE OR REPLACE TRANSIENT TABLE {self.staging} (
                DS              VARCHAR,
                THERAPEUTIC_AREA VARCHAR,
                TERRITORY_NAME  VARCHAR,
                DRUG_NAME       VARCHAR,
                RX_VOLUME       NUMBER,
                TERRITORY_TOTAL NUMBER,
                MARKET_SHARE_PCT NUMBER(10, 2),
                RANK_IN_TERRITORY NUMBER,
                ANALYSIS_DATE   TIMESTAMP_NTZ
            )
        """).collect()

    def compute_market_share(self):
        print("  Computing market share by therapeutic area and territory...")
        sql = f"""
            INSERT INTO {self.staging}
            WITH drug_territory_volume AS (
                SELECT
                    d.THERAPEUTIC_AREA,
                    t.TERRITORY_NAME,
                    d.DRUG_NAME,
                    SUM(r.METRIC_VALUE) AS RX_VOLUME
                FROM {fqn('RX_METRICS_OUTPUT')} r
                JOIN {fqn('DIM_DRUG')} d ON r.DRUG_ID = d.DRUG_ID
                JOIN {fqn('DIM_TERRITORY')} t ON r.TERRITORY_ID = t.TERRITORY_ID
                WHERE r.DS = '{self.ds}'
                  AND r.METRIC_NAME = 'total_rx_volume'
                GROUP BY d.THERAPEUTIC_AREA, t.TERRITORY_NAME, d.DRUG_NAME
            ),
            territory_totals AS (
                SELECT
                    THERAPEUTIC_AREA,
                    TERRITORY_NAME,
                    SUM(RX_VOLUME) AS TERRITORY_TOTAL
                FROM drug_territory_volume
                GROUP BY THERAPEUTIC_AREA, TERRITORY_NAME
            )
            SELECT
                '{self.ds}' AS DS,
                v.THERAPEUTIC_AREA,
                v.TERRITORY_NAME,
                v.DRUG_NAME,
                v.RX_VOLUME,
                t.TERRITORY_TOTAL,
                ROUND(v.RX_VOLUME / NULLIF(t.TERRITORY_TOTAL, 0) * 100, 2) AS MARKET_SHARE_PCT,
                ROW_NUMBER() OVER (
                    PARTITION BY v.THERAPEUTIC_AREA, v.TERRITORY_NAME
                    ORDER BY v.RX_VOLUME DESC
                ) AS RANK_IN_TERRITORY,
                CURRENT_TIMESTAMP() AS ANALYSIS_DATE
            FROM drug_territory_volume v
            JOIN territory_totals t
              ON v.THERAPEUTIC_AREA = t.THERAPEUTIC_AREA
             AND v.TERRITORY_NAME = t.TERRITORY_NAME
        """
        self.sf.sql(sql).collect()

    def validate_staging(self) -> bool:
        print("  Validating staging data...")
        result = self.sf.sql(f"SELECT COUNT(*) FROM {self.staging}").collect()[0][0]
        print(f"  Staging rows: {result}")
        return result > 0

    def merge_to_target(self):
        print("  Merging staging -> target...")
        merge_sql = f"""
            MERGE INTO {self.target} AS tgt
            USING {self.staging} AS src
            ON  tgt.DS = src.DS
            AND tgt.THERAPEUTIC_AREA = src.THERAPEUTIC_AREA
            AND tgt.TERRITORY_NAME = src.TERRITORY_NAME
            AND tgt.DRUG_NAME = src.DRUG_NAME
            WHEN MATCHED THEN UPDATE SET
                tgt.RX_VOLUME = src.RX_VOLUME,
                tgt.TERRITORY_TOTAL = src.TERRITORY_TOTAL,
                tgt.MARKET_SHARE_PCT = src.MARKET_SHARE_PCT,
                tgt.RANK_IN_TERRITORY = src.RANK_IN_TERRITORY,
                tgt.ANALYSIS_DATE = src.ANALYSIS_DATE
            WHEN NOT MATCHED THEN INSERT (
                DS, THERAPEUTIC_AREA, TERRITORY_NAME, DRUG_NAME,
                RX_VOLUME, TERRITORY_TOTAL, MARKET_SHARE_PCT,
                RANK_IN_TERRITORY, ANALYSIS_DATE
            ) VALUES (
                src.DS, src.THERAPEUTIC_AREA, src.TERRITORY_NAME, src.DRUG_NAME,
                src.RX_VOLUME, src.TERRITORY_TOTAL, src.MARKET_SHARE_PCT,
                src.RANK_IN_TERRITORY, src.ANALYSIS_DATE
            )
        """
        self.sf.sql(merge_sql).collect()

    def cleanup(self):
        print("  Dropping staging table...")
        self.sf.sql(f"DROP TABLE IF EXISTS {self.staging}").collect()

    def print_summary(self):
        top = self.sf.sql(f"""
            SELECT THERAPEUTIC_AREA, TERRITORY_NAME, DRUG_NAME,
                   MARKET_SHARE_PCT, RANK_IN_TERRITORY
            FROM {self.target}
            WHERE DS = '{self.ds}' AND RANK_IN_TERRITORY = 1
            ORDER BY MARKET_SHARE_PCT DESC
            LIMIT 5
        """).collect()
        print("  Top drugs by territory (rank 1):")
        for row in top:
            print(f"    {row[0]:20s} | {row[1]:15s} | {row[2]:20s} | {row[3]:6.1f}%")

    def execute(self):
        print(f"[Job 5] Market Share Analysis — ds={self.ds}")
        self.create_staging()
        self.compute_market_share()
        if self.validate_staging():
            self.merge_to_target()
            self.cleanup()
            count = self.sf.sql(
                f"SELECT COUNT(*) FROM {self.target} WHERE DS = '{self.ds}'"
            ).collect()[0][0]
            print(f"  SUCCESS: {count} market share rows for ds={self.ds}")
            self.print_summary()
        else:
            self.cleanup()
            raise ValueError("Staging validation failed — no market share data computed")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--ds", required=True, help="Date partition (YYYY-MM-DD)")
    args = parser.parse_args()

    spark, sf_session = get_sessions()
    job = MarketShareAnalysisJob(spark, sf_session, args.ds)
    job.execute()


if __name__ == "__main__":
    main()
