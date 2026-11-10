-- ============================================================
-- Multi-Domain Semantic View Setup
-- Creates finance tables + deploys all 3 semantic models
-- ============================================================
-- Demonstrates federated semantic views across domains:
--   Domain 1: Healthcare (pharma_commercial_intelligence)
--   Domain 2: CRM (crm_commercial_intelligence)
--   Domain 3: Finance (finance_summary)
-- ============================================================

USE ROLE SYSADMIN;
USE WAREHOUSE MY_WH;
USE SCHEMA DEMO.HEALTHCARE_DEMO;

-- ============================================================
-- 1. Finance Domain Tables (simulated)
-- ============================================================

CREATE OR REPLACE TABLE FINANCE_REVENUE_SUMMARY (
    PERIOD VARCHAR(7),
    PRODUCT_LINE VARCHAR(100),
    REGION VARCHAR(50),
    REVENUE_TYPE VARCHAR(50),
    ACTUAL_REVENUE FLOAT,
    BUDGET_REVENUE FLOAT,
    FORECAST_REVENUE FLOAT
);

INSERT INTO FINANCE_REVENUE_SUMMARY
SELECT
    '2026-' || LPAD(MOD(SEQ4(), 6) + 1, 2, '0') AS PERIOD,
    CASE MOD(SEQ4(), 5)
        WHEN 0 THEN 'Oncology Portfolio'
        WHEN 1 THEN 'Immunology Portfolio'
        WHEN 2 THEN 'Cardiology Portfolio'
        WHEN 3 THEN 'Primary Care Portfolio'
        ELSE 'Specialty Biologics'
    END AS PRODUCT_LINE,
    CASE MOD(SEQ4(), 4)
        WHEN 0 THEN 'North America'
        WHEN 1 THEN 'Europe'
        WHEN 2 THEN 'Asia Pacific'
        ELSE 'Latin America'
    END AS REGION,
    CASE MOD(SEQ4(), 4)
        WHEN 0 THEN 'Product Sales'
        WHEN 1 THEN 'Licensing'
        WHEN 2 THEN 'Royalties'
        ELSE 'Services'
    END AS REVENUE_TYPE,
    ROUND(UNIFORM(50, 500, RANDOM())::FLOAT, 1) AS ACTUAL_REVENUE,
    ROUND(UNIFORM(60, 480, RANDOM())::FLOAT, 1) AS BUDGET_REVENUE,
    ROUND(UNIFORM(55, 490, RANDOM())::FLOAT, 1) AS FORECAST_REVENUE
FROM TABLE(GENERATOR(ROWCOUNT => 120));

CREATE OR REPLACE TABLE FINANCE_COST_CENTERS (
    COST_CENTER_ID VARCHAR(10),
    COST_CENTER_NAME VARCHAR(100),
    EXPENSE_CATEGORY VARCHAR(50),
    PERIOD VARCHAR(7),
    ACTUAL_SPEND FLOAT,
    BUDGET_ALLOCATION FLOAT
);

INSERT INTO FINANCE_COST_CENTERS
SELECT
    'CC-' || LPAD(SEQ4()::VARCHAR, 4, '0') AS COST_CENTER_ID,
    CASE MOD(SEQ4(), 5)
        WHEN 0 THEN 'Research and Development Oncology'
        WHEN 1 THEN 'Commercial Operations'
        WHEN 2 THEN 'Medical Affairs'
        WHEN 3 THEN 'Manufacturing'
        ELSE 'General and Admin'
    END AS COST_CENTER_NAME,
    CASE MOD(SEQ4(), 5)
        WHEN 0 THEN 'Personnel'
        WHEN 1 THEN 'Clinical Trials'
        WHEN 2 THEN 'Marketing'
        WHEN 3 THEN 'Technology'
        ELSE 'Facilities'
    END AS EXPENSE_CATEGORY,
    '2026-' || LPAD(MOD(SEQ4(), 6) + 1, 2, '0') AS PERIOD,
    ROUND(UNIFORM(5, 80, RANDOM())::FLOAT, 1) AS ACTUAL_SPEND,
    ROUND(UNIFORM(10, 75, RANDOM())::FLOAT, 1) AS BUDGET_ALLOCATION
FROM TABLE(GENERATOR(ROWCOUNT => 90));

-- ============================================================
-- 2. Verify Data
-- ============================================================

SELECT 'FINANCE_REVENUE_SUMMARY' AS TBL, COUNT(*) AS CNT FROM FINANCE_REVENUE_SUMMARY
UNION ALL
SELECT 'FINANCE_COST_CENTERS', COUNT(*) FROM FINANCE_COST_CENTERS;
