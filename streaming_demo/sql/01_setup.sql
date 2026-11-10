-- ============================================================
-- Snowpipe Streaming Demo: Setup
-- Real-time HCP Engagement Event Ingestion
-- ============================================================
-- Run as SYSADMIN (or role with CREATE TABLE + CREATE PIPE)

USE ROLE SYSADMIN;
USE WAREHOUSE MY_WH;
USE SCHEMA DEMO.HEALTHCARE_DEMO;

-- ============================================================
-- 1. Real-time events table
-- ============================================================

CREATE OR REPLACE TABLE HCP_EVENTS_RT (
    EVENT_ID        VARCHAR(36),
    HCP_ID          VARCHAR(36),
    REP_ID          VARCHAR(36),
    EVENT_TYPE      VARCHAR(50),
    CHANNEL         VARCHAR(30),
    DRUG_ID         VARCHAR(36),
    TERRITORY_ID    INTEGER,
    DURATION_SECONDS INTEGER,
    SENTIMENT_SCORE FLOAT,
    EVENT_PAYLOAD   VARIANT,
    EVENT_TIMESTAMP TIMESTAMP_NTZ,
    INGESTED_AT     TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-- ============================================================
-- 2. Named Pipe for Streaming Ingestion
-- NOTE: Requires Snowpipe Streaming (High-Performance Architecture) enabled.
-- If CREATE PIPE ... AS <table> fails, streaming SDK can still write
-- directly to the table without a pipe object in some configurations.
-- ============================================================

CREATE OR REPLACE PIPE HCP_EVENTS_RT_STREAMING AS HCP_EVENTS_RT;

-- ============================================================
-- 3. Grants (if using a dedicated streaming role)
-- ============================================================
-- Uncomment if you create a STREAMING_ROLE:
--
-- CREATE ROLE IF NOT EXISTS STREAMING_ROLE;
-- GRANT USAGE ON DATABASE DEMO TO ROLE STREAMING_ROLE;
-- GRANT USAGE ON SCHEMA DEMO.HEALTHCARE_DEMO TO ROLE STREAMING_ROLE;
-- GRANT INSERT ON TABLE DEMO.HEALTHCARE_DEMO.HCP_EVENTS_RT TO ROLE STREAMING_ROLE;
-- GRANT USAGE ON WAREHOUSE MY_WH TO ROLE STREAMING_ROLE;
-- GRANT ROLE STREAMING_ROLE TO USER <SERVICE_USER>;

-- ============================================================
-- 4. Verify
-- ============================================================

SHOW PIPES LIKE '%HCP_EVENTS%' IN SCHEMA DEMO.HEALTHCARE_DEMO;
DESC TABLE HCP_EVENTS_RT;
