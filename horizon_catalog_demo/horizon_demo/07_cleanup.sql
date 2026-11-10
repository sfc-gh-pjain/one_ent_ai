/*=============================================================================
  SNOWFLAKE HORIZON CATALOG DEMO - CLEANUP SCRIPT
  
  Run this to remove all demo objects when done.
=============================================================================*/

USE ROLE SYSADMIN;

-- Drop agent
DROP AGENT IF EXISTS HORIZON_DEMO_DB.HEALTHCARE.HEALTHCARE_AGENT;

-- Drop share
DROP SHARE IF EXISTS HORIZON_DEMO_DB_HEALTHCARE_SHARE;

-- Drop database (removes all schemas, tables, views, policies, tags)
DROP DATABASE IF EXISTS HORIZON_DEMO_DB;

-- Drop demo roles (requires USERADMIN or ACCOUNTADMIN)
-- USE ROLE USERADMIN;
-- DROP ROLE IF EXISTS HORIZON_DEMO_ADMIN;
-- DROP ROLE IF EXISTS HORIZON_DEMO_CLINICAL;
-- DROP ROLE IF EXISTS HORIZON_DEMO_ANALYST;
-- DROP ROLE IF EXISTS HORIZON_DEMO_COMPLIANCE;
