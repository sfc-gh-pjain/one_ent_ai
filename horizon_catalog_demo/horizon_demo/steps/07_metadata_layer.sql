USE ROLE SYSADMIN;
USE DATABASE HORIZON_DEMO_DB;
USE SCHEMA HEALTHCARE;
USE WAREHOUSE MY_WH;

-- ============================================================================
-- STEP 7: METADATA LAYER
-- Adds medallion layer tags, pipeline execution log, lineage cache,
-- and unified metadata catalog view for AI consumption.
-- ============================================================================

-- ============================================================================
-- 7.1 MEDALLION LAYER TAGS
-- ============================================================================

CREATE OR REPLACE TAG PIPELINE_LAYER
  ALLOWED_VALUES 'BRONZE', 'SILVER', 'GOLD'
  COMMENT = 'Medallion architecture layer: BRONZE=raw, SILVER=cleaned, GOLD=analytics';

CREATE OR REPLACE TAG SOURCE_SYSTEM
  COMMENT = 'Originating source system for this table';

CREATE OR REPLACE TAG LOAD_FREQUENCY
  ALLOWED_VALUES 'REAL_TIME', 'HOURLY', 'DAILY', 'WEEKLY'
  COMMENT = 'How often this table is refreshed';

CREATE OR REPLACE TAG SLA_FRESHNESS_SECONDS
  COMMENT = 'Maximum acceptable data staleness in seconds';

-- Apply layer tags to bronze tables
ALTER TABLE PATIENTS SET TAG PIPELINE_LAYER = 'BRONZE', SOURCE_SYSTEM = 'EHR', LOAD_FREQUENCY = 'DAILY', SLA_FRESHNESS_SECONDS = '86400';
ALTER TABLE DOCTORS SET TAG PIPELINE_LAYER = 'BRONZE', SOURCE_SYSTEM = 'EHR', LOAD_FREQUENCY = 'WEEKLY', SLA_FRESHNESS_SECONDS = '604800';
ALTER TABLE APPOINTMENTS SET TAG PIPELINE_LAYER = 'BRONZE', SOURCE_SYSTEM = 'EHR', LOAD_FREQUENCY = 'HOURLY', SLA_FRESHNESS_SECONDS = '3600';
ALTER TABLE PRESCRIPTIONS SET TAG PIPELINE_LAYER = 'BRONZE', SOURCE_SYSTEM = 'EHR', LOAD_FREQUENCY = 'DAILY', SLA_FRESHNESS_SECONDS = '86400';
ALTER TABLE BILLING SET TAG PIPELINE_LAYER = 'BRONZE', SOURCE_SYSTEM = 'BILLING_SYSTEM', LOAD_FREQUENCY = 'DAILY', SLA_FRESHNESS_SECONDS = '86400';
ALTER TABLE INSURANCE_CLAIMS SET TAG PIPELINE_LAYER = 'BRONZE', SOURCE_SYSTEM = 'CLAIMS_PORTAL', LOAD_FREQUENCY = 'DAILY', SLA_FRESHNESS_SECONDS = '86400';

-- Apply layer tags to silver views
ALTER VIEW STG_PATIENTS SET TAG PIPELINE_LAYER = 'SILVER', LOAD_FREQUENCY = 'DAILY';
ALTER VIEW STG_BILLING SET TAG PIPELINE_LAYER = 'SILVER', LOAD_FREQUENCY = 'DAILY';
ALTER VIEW STG_APPOINTMENTS SET TAG PIPELINE_LAYER = 'SILVER', LOAD_FREQUENCY = 'HOURLY';

-- Apply layer tags to gold objects
ALTER DYNAMIC TABLE PATIENT_ANALYTICS SET TAG PIPELINE_LAYER = 'GOLD', LOAD_FREQUENCY = 'HOURLY', SLA_FRESHNESS_SECONDS = '7200';
ALTER VIEW REVENUE_DASHBOARD SET TAG PIPELINE_LAYER = 'GOLD';
ALTER VIEW DEPARTMENT_METRICS SET TAG PIPELINE_LAYER = 'GOLD';

-- ============================================================================
-- 7.2 PIPELINE EXECUTION LOG
-- ============================================================================

CREATE OR REPLACE TABLE PIPELINE_EXECUTION_LOG (
    execution_id      VARCHAR DEFAULT UUID_STRING(),
    pipeline_name     VARCHAR NOT NULL,
    source_table      VARCHAR,
    target_table      VARCHAR,
    layer_from        VARCHAR,
    layer_to          VARCHAR,
    rows_read         NUMBER,
    rows_written      NUMBER,
    rows_rejected     NUMBER,
    warehouse_name    VARCHAR,
    warehouse_size    VARCHAR,
    execution_start   TIMESTAMP_NTZ,
    execution_end     TIMESTAMP_NTZ,
    duration_seconds  NUMBER,
    status            VARCHAR,
    error_message     VARCHAR,
    query_id          VARCHAR,
    created_at        TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-- Insert sample pipeline execution records (simulating real runs)
INSERT INTO PIPELINE_EXECUTION_LOG (pipeline_name, source_table, target_table, layer_from, layer_to, rows_read, rows_written, rows_rejected, warehouse_name, warehouse_size, execution_start, execution_end, duration_seconds, status, query_id)
VALUES
  -- Bronze to Silver runs
  ('bronze_to_silver_patients', 'HORIZON_DEMO_DB.HEALTHCARE.PATIENTS', 'HORIZON_DEMO_DB.HEALTHCARE.STG_PATIENTS', 'BRONZE', 'SILVER', 10000, 10000, 0, 'MY_WH', 'MEDIUM', '2026-08-12 06:00:00', '2026-08-12 06:00:12', 12, 'SUCCESS', 'demo-qid-001'),
  ('bronze_to_silver_billing', 'HORIZON_DEMO_DB.HEALTHCARE.BILLING', 'HORIZON_DEMO_DB.HEALTHCARE.STG_BILLING', 'BRONZE', 'SILVER', 40000, 40000, 0, 'MY_WH', 'MEDIUM', '2026-08-12 06:00:15', '2026-08-12 06:00:38', 23, 'SUCCESS', 'demo-qid-002'),
  ('bronze_to_silver_appointments', 'HORIZON_DEMO_DB.HEALTHCARE.APPOINTMENTS', 'HORIZON_DEMO_DB.HEALTHCARE.STG_APPOINTMENTS', 'BRONZE', 'SILVER', 50000, 50000, 0, 'MY_WH', 'MEDIUM', '2026-08-12 06:00:40', '2026-08-12 06:01:05', 25, 'SUCCESS', 'demo-qid-003'),
  -- Silver to Gold runs
  ('silver_to_gold_analytics', 'HORIZON_DEMO_DB.HEALTHCARE.STG_PATIENTS,STG_BILLING,STG_APPOINTMENTS', 'HORIZON_DEMO_DB.HEALTHCARE.PATIENT_ANALYTICS', 'SILVER', 'GOLD', 100000, 10000, 0, 'MY_WH', 'MEDIUM', '2026-08-12 06:02:00', '2026-08-12 06:02:45', 45, 'SUCCESS', 'demo-qid-004'),
  ('gold_dashboard_refresh', 'HORIZON_DEMO_DB.HEALTHCARE.PATIENT_ANALYTICS', 'HORIZON_DEMO_DB.HEALTHCARE.REVENUE_DASHBOARD', 'GOLD', 'GOLD', 10000, 185, 0, 'MY_WH', 'MEDIUM', '2026-08-12 06:03:00', '2026-08-12 06:03:08', 8, 'SUCCESS', 'demo-qid-005'),
  -- Historical runs (past days)
  ('bronze_to_silver_patients', 'HORIZON_DEMO_DB.HEALTHCARE.PATIENTS', 'HORIZON_DEMO_DB.HEALTHCARE.STG_PATIENTS', 'BRONZE', 'SILVER', 9950, 9950, 0, 'MY_WH', 'MEDIUM', '2026-08-11 06:00:00', '2026-08-11 06:00:11', 11, 'SUCCESS', 'demo-qid-006'),
  ('bronze_to_silver_billing', 'HORIZON_DEMO_DB.HEALTHCARE.BILLING', 'HORIZON_DEMO_DB.HEALTHCARE.STG_BILLING', 'BRONZE', 'SILVER', 39500, 39500, 0, 'MY_WH', 'MEDIUM', '2026-08-11 06:00:15', '2026-08-11 06:00:36', 21, 'SUCCESS', 'demo-qid-007'),
  ('silver_to_gold_analytics', 'HORIZON_DEMO_DB.HEALTHCARE.STG_PATIENTS,STG_BILLING,STG_APPOINTMENTS', 'HORIZON_DEMO_DB.HEALTHCARE.PATIENT_ANALYTICS', 'SILVER', 'GOLD', 99000, 9950, 0, 'MY_WH', 'MEDIUM', '2026-08-11 06:02:00', '2026-08-11 06:02:42', 42, 'SUCCESS', 'demo-qid-008'),
  -- A failed run (for demo)
  ('bronze_to_silver_patients', 'HORIZON_DEMO_DB.HEALTHCARE.PATIENTS', 'HORIZON_DEMO_DB.HEALTHCARE.STG_PATIENTS', 'BRONZE', 'SILVER', 10000, 0, 10000, 'MY_WH', 'MEDIUM', '2026-08-10 06:00:00', '2026-08-10 06:00:05', 5, 'FAILED', 'demo-qid-009'),
  ('bronze_to_silver_patients', 'HORIZON_DEMO_DB.HEALTHCARE.PATIENTS', 'HORIZON_DEMO_DB.HEALTHCARE.STG_PATIENTS', 'BRONZE', 'SILVER', 10000, 9980, 20, 'MY_WH', 'MEDIUM', '2026-08-10 06:05:00', '2026-08-10 06:05:14', 14, 'PARTIAL', 'demo-qid-010');

-- Update the failed run with error message
UPDATE PIPELINE_EXECUTION_LOG SET error_message = 'Source table locked by concurrent DDL operation'
WHERE query_id = 'demo-qid-009';

-- ============================================================================
-- 7.3 LINEAGE CACHE VIEW
-- ============================================================================

CREATE OR REPLACE VIEW LINEAGE_CACHE AS
SELECT 'PATIENTS' AS anchor_table, l.*
FROM TABLE(SNOWFLAKE.CORE.GET_LINEAGE('HORIZON_DEMO_DB.HEALTHCARE.PATIENTS', 'TABLE', 'DOWNSTREAM', 5)) l
UNION ALL
SELECT 'BILLING', l.*
FROM TABLE(SNOWFLAKE.CORE.GET_LINEAGE('HORIZON_DEMO_DB.HEALTHCARE.BILLING', 'TABLE', 'DOWNSTREAM', 5)) l
UNION ALL
SELECT 'APPOINTMENTS', l.*
FROM TABLE(SNOWFLAKE.CORE.GET_LINEAGE('HORIZON_DEMO_DB.HEALTHCARE.APPOINTMENTS', 'TABLE', 'DOWNSTREAM', 5)) l;

-- ============================================================================
-- 7.4 UNIFIED METADATA CATALOG VIEW
-- ============================================================================

CREATE OR REPLACE VIEW METADATA_CATALOG AS
WITH layer_tags AS (
    SELECT OBJECT_NAME, TAG_VALUE AS pipeline_layer
    FROM TABLE(INFORMATION_SCHEMA.TAG_REFERENCES('HORIZON_DEMO_DB.HEALTHCARE.PATIENTS', 'TABLE'))
    WHERE TAG_NAME = 'PIPELINE_LAYER' AND DOMAIN = 'TABLE'
    UNION ALL
    SELECT OBJECT_NAME, TAG_VALUE
    FROM TABLE(INFORMATION_SCHEMA.TAG_REFERENCES('HORIZON_DEMO_DB.HEALTHCARE.DOCTORS', 'TABLE'))
    WHERE TAG_NAME = 'PIPELINE_LAYER' AND DOMAIN = 'TABLE'
    UNION ALL
    SELECT OBJECT_NAME, TAG_VALUE
    FROM TABLE(INFORMATION_SCHEMA.TAG_REFERENCES('HORIZON_DEMO_DB.HEALTHCARE.APPOINTMENTS', 'TABLE'))
    WHERE TAG_NAME = 'PIPELINE_LAYER' AND DOMAIN = 'TABLE'
    UNION ALL
    SELECT OBJECT_NAME, TAG_VALUE
    FROM TABLE(INFORMATION_SCHEMA.TAG_REFERENCES('HORIZON_DEMO_DB.HEALTHCARE.BILLING', 'TABLE'))
    WHERE TAG_NAME = 'PIPELINE_LAYER' AND DOMAIN = 'TABLE'
    UNION ALL
    SELECT OBJECT_NAME, TAG_VALUE
    FROM TABLE(INFORMATION_SCHEMA.TAG_REFERENCES('HORIZON_DEMO_DB.HEALTHCARE.PRESCRIPTIONS', 'TABLE'))
    WHERE TAG_NAME = 'PIPELINE_LAYER' AND DOMAIN = 'TABLE'
    UNION ALL
    SELECT OBJECT_NAME, TAG_VALUE
    FROM TABLE(INFORMATION_SCHEMA.TAG_REFERENCES('HORIZON_DEMO_DB.HEALTHCARE.INSURANCE_CLAIMS', 'TABLE'))
    WHERE TAG_NAME = 'PIPELINE_LAYER' AND DOMAIN = 'TABLE'
),
pipeline_summary AS (
    SELECT
        target_table,
        MAX(execution_end) AS last_load_time,
        MAX(CASE WHEN execution_end = (SELECT MAX(execution_end) FROM PIPELINE_EXECUTION_LOG p2 WHERE p2.target_table = p.target_table) THEN status END) AS last_status,
        AVG(rows_written) AS avg_rows_per_load,
        AVG(duration_seconds) AS avg_duration_seconds,
        MAX(warehouse_name) AS warehouse_name,
        MAX(warehouse_size) AS warehouse_size,
        COUNT(*) AS total_runs,
        SUM(CASE WHEN status = 'SUCCESS' THEN 1 ELSE 0 END) AS successful_runs
    FROM PIPELINE_EXECUTION_LOG p
    GROUP BY target_table
),
lineage_summary AS (
    SELECT
        SOURCE_OBJECT_NAME AS table_name,
        COUNT(DISTINCT TARGET_OBJECT_NAME) AS downstream_count
    FROM LINEAGE_CACHE
    WHERE DISTANCE = 1
    GROUP BY SOURCE_OBJECT_NAME
)
SELECT
    t.TABLE_NAME,
    t.TABLE_TYPE,
    t.ROW_COUNT,
    t.CREATED,
    t.LAST_ALTERED,
    lt.pipeline_layer,
    ps.last_load_time,
    ps.last_status AS last_pipeline_status,
    ROUND(ps.avg_rows_per_load) AS avg_rows_per_load,
    ROUND(ps.avg_duration_seconds, 1) AS avg_load_duration_sec,
    ps.warehouse_name,
    ps.warehouse_size,
    ps.total_runs AS pipeline_run_count,
    ROUND(ps.successful_runs * 100.0 / NULLIF(ps.total_runs, 0), 1) AS pipeline_success_rate_pct,
    ls.downstream_count,
    DATEDIFF('second', t.LAST_ALTERED, CURRENT_TIMESTAMP()) AS staleness_seconds
FROM INFORMATION_SCHEMA.TABLES t
LEFT JOIN layer_tags lt ON lt.OBJECT_NAME = t.TABLE_NAME
LEFT JOIN pipeline_summary ps ON ps.target_table LIKE '%' || t.TABLE_NAME
LEFT JOIN lineage_summary ls ON ls.table_name = t.TABLE_NAME
WHERE t.TABLE_SCHEMA = 'HEALTHCARE'
  AND t.TABLE_NAME NOT IN ('PIPELINE_EXECUTION_LOG');

-- ============================================================================
-- VERIFICATION
-- ============================================================================

SELECT TABLE_NAME, pipeline_layer, last_pipeline_status, pipeline_success_rate_pct, downstream_count
FROM METADATA_CATALOG
ORDER BY
  CASE pipeline_layer WHEN 'BRONZE' THEN 1 WHEN 'SILVER' THEN 2 WHEN 'GOLD' THEN 3 ELSE 4 END,
  TABLE_NAME;
