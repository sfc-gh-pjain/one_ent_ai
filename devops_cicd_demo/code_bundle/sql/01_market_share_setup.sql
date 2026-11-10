-- ============================================================
-- Market Share Analysis — Table Setup
-- ============================================================
-- Run once to create the target table for Job 5.
-- This file can be deployed via:
--   EXECUTE IMMEDIATE FROM @repo/branches/main/devops_cicd_demo/code_bundle/sql/01_market_share_setup.sql
-- ============================================================

USE ROLE SYSADMIN;
USE WAREHOUSE MY_WH;
USE SCHEMA DEMO.HEALTHCARE_DEMO;

CREATE TABLE IF NOT EXISTS MARKET_SHARE_ANALYSIS (
    DS                VARCHAR      NOT NULL COMMENT 'Date partition',
    THERAPEUTIC_AREA  VARCHAR      NOT NULL COMMENT 'Drug therapeutic area',
    TERRITORY_NAME    VARCHAR      NOT NULL COMMENT 'Sales territory',
    DRUG_NAME         VARCHAR      NOT NULL COMMENT 'Drug brand name',
    RX_VOLUME         NUMBER               COMMENT 'Total prescriptions for drug/territory',
    TERRITORY_TOTAL   NUMBER               COMMENT 'Total prescriptions in territory',
    MARKET_SHARE_PCT  NUMBER(10,2)         COMMENT 'Drug share of territory volume (%)',
    RANK_IN_TERRITORY NUMBER               COMMENT 'Rank by volume within territory',
    ANALYSIS_DATE     TIMESTAMP_NTZ        COMMENT 'When this analysis was computed'
)
COMMENT = 'Drug market share by therapeutic area and territory (Code Bundle Job 5)';
