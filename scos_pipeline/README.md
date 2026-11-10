# Part 1: SCOS Pipeline — Healthcare Data Transformations

PySpark jobs running as Snowflake Code Bundles on warehouse compute.
Transforms raw commercial pharma data (prescriptions, HCP profiles, engagements) into analytics-ready outputs.

## Jobs

| # | File | Pattern | Output Table |
|---|------|---------|--------------|
| 1 | `01_rx_metrics_load.py` | Staging → Validate → MERGE | `RX_METRICS_OUTPUT` |
| 2 | `02_hcp_classification.py` | Python UDTF (replaces mapPartitions) | `HCP_TIERED_PROFILES` |
| 3 | `03_engagement_merge.py` | 6-way JOIN → saveAsTable → MERGE | `ENGAGEMENT_FINAL` |
| 4 | `04_validate.py` | Data quality checks | — |

## Key Patterns Demonstrated

1. **Staging-Validate-Merge** (Job 1): Idempotent load using TRANSIENT staging table, validation gate, and MERGE upsert.
2. **UDTF replaces mapPartitions** (Job 2): Server-side Python UDTF for HCP specialty classification and tier assignment — zero driver memory.
3. **Multi-Join + MERGE** (Job 3): 6-way broadcast join enriching engagement events with drug, territory, region, and therapeutic area dimensions.
4. **SnowflakeSession for native DDL** (all jobs): Uses `SnowflakeSession(spark)` for MERGE, QUALIFY, TRANSIENT, CREATE FUNCTION — the Spark SQL parser doesn't support these.

## Running Manually

```bash
SNOW=".venv/bin/snow"
CONNECTION="my_conn"
DATABASE="DEMO"
SCHEMA="HEALTHCARE_DEMO"
WAREHOUSE="MY_WH"

# Create the code bundle
$SNOW bundle create CB_HEALTHCARE_SPARK --source src --exclude "__pycache__" --overwrite \
    -c $CONNECTION --database $DATABASE --schema $SCHEMA --warehouse $WAREHOUSE

# Execute jobs in sequence
$SNOW bundle execute CB_HEALTHCARE_SPARK --entrypoint 01_rx_metrics_load.py \
    -c $CONNECTION --database $DATABASE --schema $SCHEMA --warehouse $WAREHOUSE -- --ds 2026-05-26

$SNOW bundle execute CB_HEALTHCARE_SPARK --entrypoint 02_hcp_classification.py \
    -c $CONNECTION --database $DATABASE --schema $SCHEMA --warehouse $WAREHOUSE -- --ds 2026-05-26

$SNOW bundle execute CB_HEALTHCARE_SPARK --entrypoint 03_engagement_merge.py \
    -c $CONNECTION --database $DATABASE --schema $SCHEMA --warehouse $WAREHOUSE

$SNOW bundle execute CB_HEALTHCARE_SPARK --entrypoint 04_validate.py \
    -c $CONNECTION --database $DATABASE --schema $SCHEMA --warehouse $WAREHOUSE
```
