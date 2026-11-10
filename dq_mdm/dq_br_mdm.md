# Data Quality, Business Rules & MDM — Snowflake Implementation

## Overview

This document describes how Snowflake implements **Data Quality (DQ)**, **Business Rules (BR)**, and **Master Data Management (MDM)** monitoring for the Healthcare Commercial Analytics pipeline.

---

## 1. Data Quality — Data Metric Functions (DMFs)

### What Are DMFs?

Data Metric Functions are Snowflake-native functions that measure data quality attributes on tables. They run on a schedule (or on change) and store results in a system view.

### Built-in DMFs (SNOWFLAKE.CORE)

| DMF | What It Measures |
|-----|-----------------|
| `NULL_COUNT` | Number of NULL values in a column |
| `DUPLICATE_COUNT` | Number of duplicate values in a column |
| `FRESHNESS` | Time since last table modification |
| `UNIQUE_COUNT` | Number of distinct values |
| `ROW_COUNT` | Total rows in the table |

### Custom DMFs (User-Defined)

You can create custom DMFs using `CREATE DATA METRIC FUNCTION`. They must:
- Accept a single `TABLE(ARG_T)` argument (table reference)
- Return a `NUMBER` value
- Be deterministic and idempotent

### Attaching DMFs to Tables

```sql
ALTER TABLE my_table SET DATA_METRIC_SCHEDULE = 'TRIGGER_ON_CHANGES';
ALTER TABLE my_table ADD DATA METRIC FUNCTION SNOWFLAKE.CORE.NULL_COUNT ON (column_name);
```

### Viewing Results

```sql
SELECT * FROM SNOWFLAKE.LOCAL.DATA_QUALITY_MONITORING_RESULTS
WHERE TABLE_NAME = 'MY_TABLE'
ORDER BY MEASUREMENT_TIME DESC;
```

---

## 2. Business Rules — Streams & Tasks

### Streams (Change Data Capture)

Streams track row-level DML changes (INSERT, UPDATE, DELETE) on a source table. They accumulate changes until consumed by a DML statement.

```sql
CREATE STREAM my_stream ON TABLE source_table;
-- Stream columns: METADATA$ACTION, METADATA$ISUPDATE, METADATA$ROW_ID
```

### Tasks (Scheduled/Triggered Execution)

Tasks execute SQL on a schedule or when a stream has data:

```sql
CREATE TASK my_task
  WAREHOUSE = MY_WH
  SCHEDULE = 'USING CRON 0 * * * * America/New_York'  -- or stream-triggered
  WHEN SYSTEM$STREAM_HAS_DATA('my_stream')
AS
  -- Business rule SQL here
;
```

### Common Business Rules for Healthcare MDM

| Rule | Implementation |
|------|---------------|
| **HCP Deduplication** | QUALIFY ROW_NUMBER() golden record selection |
| **Rx Volume Outlier Detection** | Flag Rx quantities > 5x territory average |
| **Engagement Attribution** | Validate DRUG_ID and TERRITORY_ID exist in dimensions |
| **HCP Tier Validation** | Tier must be 1-5, Decile 1-10 |
| **Temporal Consistency** | No future dates in RX_DATE or ENGAGEMENT_DATE |

---

## 3. Master Data Management (MDM)

### Golden Record Pattern

MDM in Snowflake uses the **Survive & Merge** pattern:
1. Stream detects new/changed raw records
2. Task applies dedup logic (QUALIFY ROW_NUMBER with ordering)
3. MERGE into golden record table
4. Quality metrics updated automatically via DMFs

### Constraints (Informational)

Snowflake supports PK/FK/UNIQUE constraints as metadata (not enforced at write time). They:
- Document data relationships
- Help query optimizer plan joins
- Enable BI tools to understand cardinality

```sql
ALTER TABLE DIM_DRUG ADD CONSTRAINT pk_dim_drug PRIMARY KEY (DRUG_ID);
ALTER TABLE RAW_PRESCRIPTIONS ADD CONSTRAINT fk_rx_drug
  FOREIGN KEY (DRUG_ID) REFERENCES DIM_DRUG (DRUG_ID);
```

---

## 4. Governance — Tags & Policies

### Object Tags

Tags classify columns by sensitivity level, domain, or ownership:

```sql
CREATE TAG SENSITIVITY_LEVEL ALLOWED_VALUES 'PII', 'PHI', 'PUBLIC', 'INTERNAL';
ALTER TABLE t MODIFY COLUMN HCP_NAME SET TAG SENSITIVITY_LEVEL = 'PHI';
```

### Row Access Policies

Control who sees which rows based on role:

```sql
CREATE ROW ACCESS POLICY region_filter AS (region VARCHAR)
RETURNS BOOLEAN -> CURRENT_ROLE() IN ('SYSADMIN') OR region = 'US';
```

### Masking Policies

Mask sensitive data for non-privileged roles:

```sql
CREATE MASKING POLICY mask_npi AS (val VARCHAR) RETURNS VARCHAR ->
  CASE WHEN CURRENT_ROLE() IN ('SYSADMIN','DATA_STEWARD') THEN val
       ELSE '***-***-' || RIGHT(val, 4) END;
```

---

## 5. Monitoring Dashboard

The Streamlit app (`streamlit/dq_monitor.py`) provides:

| Tab | Data Source | Metrics |
|-----|-------------|---------|
| DQ Scores | `SNOWFLAKE.LOCAL.DATA_QUALITY_MONITORING_RESULTS` | Pass/fail per DMF, overall score % |
| Business Rules | `INFORMATION_SCHEMA.TASK_HISTORY()` | Task runs, success/fail, violations count |
| Freshness | Target table `ETL_TIMESTAMP` columns | Hours since last refresh, SLA status |
| Lineage | `SNOWFLAKE.ACCOUNT_USAGE.ACCESS_HISTORY` | Upstream/downstream object graph |
| Data Catalog | `INFORMATION_SCHEMA.TAG_REFERENCES` | Tagged objects, sensitivity classification |

---

## 6. Architecture

```
RAW_PRESCRIPTIONS ──┐
RAW_HCP_PROFILES ───┤──▶ [Streams] ──▶ [Tasks: Business Rules] ──▶ Golden Records
RAW_HCP_ENGAGEMENTS ┘                                                    │
                                                                         ▼
                                                              DMFs (quality checks)
                                                                         │
                                                                         ▼
                                                              DQ_MONITORING_RESULTS
                                                                         │
                                                                         ▼
                                                              Streamlit Dashboard
```

---

## 7. Key Snowflake Views Used

| View | Purpose |
|------|---------|
| `SNOWFLAKE.LOCAL.DATA_QUALITY_MONITORING_RESULTS` | DMF measurement results |
| `INFORMATION_SCHEMA.TASK_HISTORY()` | Task execution history |
| `INFORMATION_SCHEMA.TAG_REFERENCES(...)` | Tag assignments |
| `SNOWFLAKE.ACCOUNT_USAGE.ACCESS_HISTORY` | Object access lineage |
| `SNOWFLAKE.ACCOUNT_USAGE.OBJECT_DEPENDENCIES` | Dependency graph |
