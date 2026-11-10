-- ============================================================================
-- BLUE/GREEN SWAP DEMO — SETUP (Run as ACCOUNTADMIN)
-- Creates database, schemas, star schema tables, sample data, RBAC
-- ============================================================================
-- Run this ONCE to set up the environment.
-- After this, run blue_green_swap_demo.sql to demo the swap.
-- ============================================================================

-- ============================================================================
-- SECTION 1: ENVIRONMENT SETUP
-- ============================================================================

USE ROLE SYSADMIN;
USE WAREHOUSE MY_WH;

CREATE OR REPLACE DATABASE SWAP_DEMO;

CREATE SCHEMA SWAP_DEMO.STAR_SCHEMA COMMENT = 'Source: ETL-curated star schema';
CREATE SCHEMA SWAP_DEMO.PROD        COMMENT = 'Target: Analyst-facing production';
CREATE SCHEMA SWAP_DEMO.STAGING     COMMENT = 'Temp: Clone landing zone before swap';

-- ============================================================================
-- SECTION 2: STAR SCHEMA TABLES + SAMPLE DATA (in STAR_SCHEMA)
-- ============================================================================

USE SCHEMA SWAP_DEMO.STAR_SCHEMA;

-- ---------- dim_customer ----------
CREATE OR REPLACE TABLE DIM_CUSTOMER (
    CUSTOMER_ID   INTEGER,
    CUSTOMER_NAME VARCHAR(100),
    SEGMENT       VARCHAR(30),
    REGION        VARCHAR(30),
    SIGNUP_DATE   DATE
);

INSERT INTO DIM_CUSTOMER
SELECT
    SEQ4()                                                         AS CUSTOMER_ID,
    'Customer_' || SEQ4()                                          AS CUSTOMER_NAME,
    CASE MOD(SEQ4(), 3)
        WHEN 0 THEN 'Enterprise'
        WHEN 1 THEN 'Mid-Market'
        ELSE 'SMB'
    END                                                            AS SEGMENT,
    CASE MOD(SEQ4(), 5)
        WHEN 0 THEN 'Northeast'
        WHEN 1 THEN 'Southeast'
        WHEN 2 THEN 'Midwest'
        WHEN 3 THEN 'West'
        ELSE 'International'
    END                                                            AS REGION,
    DATEADD('day', -UNIFORM(30, 1500, RANDOM()), CURRENT_DATE())   AS SIGNUP_DATE
FROM TABLE(GENERATOR(ROWCOUNT => 75));

-- ---------- dim_product ----------
CREATE OR REPLACE TABLE DIM_PRODUCT (
    PRODUCT_ID   INTEGER,
    PRODUCT_NAME VARCHAR(100),
    CATEGORY     VARCHAR(50),
    UNIT_PRICE   NUMBER(10,2),
    LAUNCH_DATE  DATE
);

INSERT INTO DIM_PRODUCT
SELECT
    SEQ4()                                                         AS PRODUCT_ID,
    'Product_' || SEQ4()                                           AS PRODUCT_NAME,
    CASE MOD(SEQ4(), 4)
        WHEN 0 THEN 'Electronics'
        WHEN 1 THEN 'Software'
        WHEN 2 THEN 'Services'
        ELSE 'Hardware'
    END                                                            AS CATEGORY,
    ROUND(UNIFORM(9.99, 999.99, RANDOM())::NUMBER(10,2), 2)        AS UNIT_PRICE,
    DATEADD('day', -UNIFORM(60, 1000, RANDOM()), CURRENT_DATE())   AS LAUNCH_DATE
FROM TABLE(GENERATOR(ROWCOUNT => 50));

-- ---------- fact_orders ----------
CREATE OR REPLACE TABLE FACT_ORDERS (
    ORDER_ID     INTEGER,
    CUSTOMER_ID  INTEGER,
    PRODUCT_ID   INTEGER,
    ORDER_DATE   DATE,
    QUANTITY     INTEGER,
    TOTAL_AMOUNT NUMBER(12,2),
    CHANNEL      VARCHAR(30)
);

INSERT INTO FACT_ORDERS
SELECT
    SEQ4()                                                         AS ORDER_ID,
    UNIFORM(0, 74, RANDOM())                                       AS CUSTOMER_ID,
    UNIFORM(0, 49, RANDOM())                                       AS PRODUCT_ID,
    DATEADD('day', -UNIFORM(1, 365, RANDOM()), CURRENT_DATE())     AS ORDER_DATE,
    UNIFORM(1, 20, RANDOM())                                       AS QUANTITY,
    ROUND(UNIFORM(1, 20, RANDOM()) * UNIFORM(9.99, 999.99, RANDOM())::NUMBER(12,2), 2) AS TOTAL_AMOUNT,
    CASE MOD(SEQ4(), 4)
        WHEN 0 THEN 'Online'
        WHEN 1 THEN 'In-Store'
        WHEN 2 THEN 'Partner'
        ELSE 'Direct Sales'
    END                                                            AS CHANNEL
FROM TABLE(GENERATOR(ROWCOUNT => 100));

-- Verify source data
SELECT 'dim_customer' AS tbl, COUNT(*) AS row_count FROM DIM_CUSTOMER
UNION ALL
SELECT 'dim_product', COUNT(*) FROM DIM_PRODUCT
UNION ALL
SELECT 'fact_orders', COUNT(*) FROM FACT_ORDERS;

-- ============================================================================
-- SECTION 3: INITIAL PROD POPULATION (zero-copy clone)
-- ============================================================================

CREATE OR REPLACE TABLE SWAP_DEMO.PROD.DIM_CUSTOMER CLONE SWAP_DEMO.STAR_SCHEMA.DIM_CUSTOMER;
CREATE OR REPLACE TABLE SWAP_DEMO.PROD.DIM_PRODUCT  CLONE SWAP_DEMO.STAR_SCHEMA.DIM_PRODUCT;
CREATE OR REPLACE TABLE SWAP_DEMO.PROD.FACT_ORDERS  CLONE SWAP_DEMO.STAR_SCHEMA.FACT_ORDERS;

-- ============================================================================
-- SECTION 4: RBAC SETUP (Reference — requires USERADMIN or ACCOUNTADMIN)
-- ============================================================================
-- In production, create dedicated roles:
--
--   USE ROLE USERADMIN;
--   CREATE ROLE ETL_ROLE     COMMENT = 'Owns pipeline, executes swap';
--   CREATE ROLE ANALYST_ROLE COMMENT = 'Read-only access to PROD';
--   GRANT ROLE ETL_ROLE     TO ROLE SYSADMIN;
--   GRANT ROLE ANALYST_ROLE TO ROLE SYSADMIN;
--
USE ROLE SYSADMIN;
GRANT USAGE ON DATABASE SWAP_DEMO TO ROLE ETL_ROLE;
GRANT USAGE ON SCHEMA SWAP_DEMO.STAR_SCHEMA TO ROLE ETL_ROLE;
GRANT USAGE ON SCHEMA SWAP_DEMO.STAGING TO ROLE ETL_ROLE;
GRANT USAGE ON SCHEMA SWAP_DEMO.PROD TO ROLE ETL_ROLE;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA SWAP_DEMO.STAR_SCHEMA TO ROLE ETL_ROLE;
GRANT CREATE TABLE ON SCHEMA SWAP_DEMO.STAGING TO ROLE ETL_ROLE;
GRANT CREATE TABLE ON SCHEMA SWAP_DEMO.PROD TO ROLE ETL_ROLE;
GRANT USAGE ON WAREHOUSE MY_WH TO ROLE ETL_ROLE;
--
GRANT USAGE ON DATABASE SWAP_DEMO TO ROLE ANALYST_ROLE;
GRANT USAGE ON SCHEMA SWAP_DEMO.PROD TO ROLE ANALYST_ROLE;
GRANT SELECT ON ALL TABLES IN SCHEMA SWAP_DEMO.PROD TO ROLE ANALYST_ROLE;
GRANT USAGE ON WAREHOUSE MY_WH TO ROLE ANALYST_ROLE;
GRANT SELECT ON FUTURE TABLES IN SCHEMA SWAP_DEMO.PROD TO ROLE ANALYST_ROLE;
--
-- This demo runs under SYSADMIN (which owns all objects) to demonstrate swap mechanics.

-- ============================================================================
-- SETUP COMPLETE
-- ============================================================================
-- Now run blue_green_swap_demo.sql to see the swap in action.
-- ============================================================================
