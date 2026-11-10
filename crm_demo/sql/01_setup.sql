-- ============================================================
-- CRM Demo: Schema + Table Setup
-- Salesforce One-Hop Reduction Pipeline
-- ============================================================
-- Simulates Salesforce CRM data landing via Iceberg/Glue,
-- enriched in Snowflake for direct Tableau analytics.
-- ============================================================

USE ROLE SYSADMIN;
USE WAREHOUSE MY_WH;

CREATE SCHEMA IF NOT EXISTS DEMO.CRM_DEMO;
USE SCHEMA DEMO.CRM_DEMO;

CREATE STAGE IF NOT EXISTS CRM_STAGE;

-- ============================================================
-- Raw Source Tables (simulating Salesforce CDC via Iceberg/Glue)
-- ============================================================

CREATE OR REPLACE TABLE RAW_ACCOUNTS (
    ACCOUNT_ID VARCHAR(36),
    ACCOUNT_NAME VARCHAR(200),
    INDUSTRY VARCHAR(100),
    REGION VARCHAR(50),
    EMPLOYEE_COUNT INTEGER,
    ANNUAL_REVENUE FLOAT,
    CREATED_DATE DATE
);

CREATE OR REPLACE TABLE RAW_OPPORTUNITIES (
    OPP_ID VARCHAR(36),
    ACCOUNT_ID VARCHAR(36),
    OPP_NAME VARCHAR(200),
    STAGE VARCHAR(50),
    AMOUNT FLOAT,
    CLOSE_DATE DATE,
    CREATED_DATE DATE,
    IS_CLOSED BOOLEAN,
    IS_WON BOOLEAN
);

CREATE OR REPLACE TABLE RAW_CASES (
    CASE_ID VARCHAR(36),
    ACCOUNT_ID VARCHAR(36),
    PRIORITY VARCHAR(20),
    STATUS VARCHAR(50),
    SUBJECT VARCHAR(300),
    CREATED_DATE DATE,
    CLOSED_DATE DATE,
    RESOLUTION_DAYS INTEGER
);

-- ============================================================
-- Enrichment Target Tables
-- ============================================================

CREATE OR REPLACE TABLE CUSTOMER_360 (
    ACCOUNT_ID VARCHAR(36),
    ACCOUNT_NAME VARCHAR(200),
    INDUSTRY VARCHAR(100),
    REGION VARCHAR(50),
    TOTAL_PIPELINE FLOAT,
    WON_REVENUE FLOAT,
    WIN_RATE FLOAT,
    OPEN_OPPS INTEGER,
    AVG_CASE_RESOLUTION_DAYS FLOAT,
    OPEN_CASES INTEGER,
    HEALTH_SCORE FLOAT,
    SEGMENT VARCHAR(50),
    ETL_TIMESTAMP TIMESTAMP_NTZ
);

CREATE OR REPLACE TABLE PIPELINE_FORECAST (
    OPP_ID VARCHAR(36),
    ACCOUNT_ID VARCHAR(36),
    ACCOUNT_NAME VARCHAR(200),
    REGION VARCHAR(50),
    INDUSTRY VARCHAR(100),
    STAGE VARCHAR(50),
    AMOUNT FLOAT,
    WEIGHTED_PIPELINE FLOAT,
    FORECAST_CATEGORY VARCHAR(50),
    DAYS_TO_CLOSE INTEGER,
    VELOCITY_SCORE FLOAT,
    ETL_TIMESTAMP TIMESTAMP_NTZ
);
