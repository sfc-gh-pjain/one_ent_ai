-- ============================================================================
-- BLUE/GREEN ZERO-COPY CLONE SWAP DEMO (Run as SYSADMIN)
-- Prerequisite: Run setup.sql first (as ACCOUNTADMIN)
-- ============================================================================
-- This script demonstrates the swap pattern:
--   1. Creates a stored procedure that clones source → staging → swaps with prod
--   2. Validates zero-downtime by querying before/after the swap
-- ============================================================================

USE ROLE SYSADMIN;
USE WAREHOUSE MY_WH;

-- ============================================================================
-- SECTION 5: STORED PROCEDURE — REFRESH_STAR_SCHEMA
-- ============================================================================

USE SCHEMA SWAP_DEMO.STAR_SCHEMA;

CREATE OR REPLACE PROCEDURE SWAP_DEMO.STAR_SCHEMA.REFRESH_STAR_SCHEMA()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
BEGIN
    -- Step 1: Clone each source table into STAGING (zero-copy, metadata-only)
    CREATE OR REPLACE TABLE SWAP_DEMO.STAGING.DIM_CUSTOMER CLONE SWAP_DEMO.STAR_SCHEMA.DIM_CUSTOMER;
    CREATE OR REPLACE TABLE SWAP_DEMO.STAGING.DIM_PRODUCT  CLONE SWAP_DEMO.STAR_SCHEMA.DIM_PRODUCT;
    CREATE OR REPLACE TABLE SWAP_DEMO.STAGING.FACT_ORDERS  CLONE SWAP_DEMO.STAR_SCHEMA.FACT_ORDERS;

    -- Step 2: Atomic swap — PROD tables now point to fresh data
    ALTER TABLE SWAP_DEMO.PROD.DIM_CUSTOMER SWAP WITH SWAP_DEMO.STAGING.DIM_CUSTOMER;
    ALTER TABLE SWAP_DEMO.PROD.DIM_PRODUCT  SWAP WITH SWAP_DEMO.STAGING.DIM_PRODUCT;
    ALTER TABLE SWAP_DEMO.PROD.FACT_ORDERS  SWAP WITH SWAP_DEMO.STAGING.FACT_ORDERS;

    -- Step 3: Drop leftover staging tables (they hold the OLD prod data)
    DROP TABLE IF EXISTS SWAP_DEMO.STAGING.DIM_CUSTOMER;
    DROP TABLE IF EXISTS SWAP_DEMO.STAGING.DIM_PRODUCT;
    DROP TABLE IF EXISTS SWAP_DEMO.STAGING.FACT_ORDERS;

    RETURN 'REFRESH_STAR_SCHEMA complete at ' || CURRENT_TIMESTAMP()::VARCHAR;
END;
$$;

-- ============================================================================
-- SECTION 6: VALIDATION — Prove Zero-Downtime Swap
-- ============================================================================

-- 6a. Baseline: Query PROD (current state)
USE SCHEMA SWAP_DEMO.PROD;

SELECT '--- BASELINE: PROD row counts ---' AS step;

SELECT 'dim_customer' AS tbl, COUNT(*) AS row_count FROM DIM_CUSTOMER
UNION ALL
SELECT 'dim_product', COUNT(*) FROM DIM_PRODUCT
UNION ALL
SELECT 'fact_orders', COUNT(*) FROM FACT_ORDERS;

-- 6b. Simulate source update: Insert new rows into STAR_SCHEMA
USE SCHEMA SWAP_DEMO.STAR_SCHEMA;

SELECT '--- SIMULATING SOURCE UPDATE: Adding 10 customers, 5 products, 25 orders ---' AS step;

INSERT INTO DIM_CUSTOMER
SELECT
    75 + SEQ4()                                                    AS CUSTOMER_ID,
    'NewCustomer_' || (75 + SEQ4())                                AS CUSTOMER_NAME,
    'Enterprise'                                                   AS SEGMENT,
    'West'                                                         AS REGION,
    CURRENT_DATE()                                                 AS SIGNUP_DATE
FROM TABLE(GENERATOR(ROWCOUNT => 10));

INSERT INTO DIM_PRODUCT
SELECT
    50 + SEQ4()                                                    AS PRODUCT_ID,
    'NewProduct_' || (50 + SEQ4())                                 AS PRODUCT_NAME,
    'AI/ML'                                                        AS CATEGORY,
    ROUND(UNIFORM(49.99, 499.99, RANDOM())::NUMBER(10,2), 2)       AS UNIT_PRICE,
    CURRENT_DATE()                                                 AS LAUNCH_DATE
FROM TABLE(GENERATOR(ROWCOUNT => 5));

INSERT INTO FACT_ORDERS
SELECT
    100 + SEQ4()                                                   AS ORDER_ID,
    UNIFORM(0, 84, RANDOM())                                       AS CUSTOMER_ID,
    UNIFORM(0, 54, RANDOM())                                       AS PRODUCT_ID,
    CURRENT_DATE()                                                 AS ORDER_DATE,
    UNIFORM(1, 10, RANDOM())                                       AS QUANTITY,
    ROUND(UNIFORM(50, 5000, RANDOM())::NUMBER(12,2), 2)            AS TOTAL_AMOUNT,
    'Online'                                                       AS CHANNEL
FROM TABLE(GENERATOR(ROWCOUNT => 25));

-- Verify source now has more rows
SELECT 'STAR_SCHEMA (after insert)' AS src,
       'dim_customer' AS tbl, COUNT(*) AS row_count FROM DIM_CUSTOMER
UNION ALL
SELECT 'STAR_SCHEMA (after insert)', 'dim_product', COUNT(*) FROM DIM_PRODUCT
UNION ALL
SELECT 'STAR_SCHEMA (after insert)', 'fact_orders', COUNT(*) FROM FACT_ORDERS;

-- 6c. Execute the swap procedure
SELECT '--- EXECUTING REFRESH (clone + swap) ---' AS step;
CALL SWAP_DEMO.STAR_SCHEMA.REFRESH_STAR_SCHEMA();

-- 6d. Verify: Query PROD again — should show fresh data instantly
USE SCHEMA SWAP_DEMO.PROD;

SELECT '--- AFTER SWAP: PROD row counts ---' AS step;

SELECT 'dim_customer' AS tbl, COUNT(*) AS row_count FROM DIM_CUSTOMER
UNION ALL
SELECT 'dim_product', COUNT(*) FROM DIM_PRODUCT
UNION ALL
SELECT 'fact_orders', COUNT(*) FROM FACT_ORDERS;

-- Prove data is accessible after swap
SELECT '--- VERIFICATION: PROD still queryable, showing latest orders ---' AS step;
SELECT TOP 5 * FROM FACT_ORDERS ORDER BY ORDER_DATE DESC;

-- ============================================================================
-- END OF DEMO
-- ============================================================================
-- Summary:
--   1. STAR_SCHEMA held 75 customers, 50 products, 100 orders
--   2. After source update: 85 customers, 55 products, 125 orders
--   3. CALL REFRESH_STAR_SCHEMA() cloned + swapped in < 1 second
--   4. PROD immediately reflects the new counts — zero downtime
--
-- To teardown: run cleanup.sql
-- ============================================================================
