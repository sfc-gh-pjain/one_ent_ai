-- ============================================================================
-- CLEANUP / TEARDOWN — Blue/Green Swap Demo
-- ============================================================================
-- Run this to destroy all demo objects created by setup.sql
-- ============================================================================

USE ROLE SYSADMIN;
USE WAREHOUSE MY_WH;

DROP DATABASE IF EXISTS SWAP_DEMO;

-- Role cleanup (requires USERADMIN or ACCOUNTADMIN if roles were created)
-- DROP ROLE IF EXISTS ETL_ROLE;
-- DROP ROLE IF EXISTS ANALYST_ROLE;

SELECT 'SWAP_DEMO teardown complete' AS status;
