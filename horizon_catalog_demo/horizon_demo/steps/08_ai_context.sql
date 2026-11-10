USE ROLE SYSADMIN;
USE DATABASE HORIZON_DEMO_DB;
USE SCHEMA HEALTHCARE;
USE WAREHOUSE MY_WH;

-- ============================================================================
-- STEP 8: AI CONTEXT LAYER
-- Cortex Search service over metadata + enhanced multi-tool agent
-- ============================================================================

-- ============================================================================
-- 8.1 SEARCH BASE TABLE (Cortex Search requires a base table, not a view)
-- ============================================================================

CREATE OR REPLACE TABLE METADATA_SEARCH_CORPUS AS
SELECT
    TABLE_NAME,
    TABLE_TYPE,
    ROW_COUNT,
    PIPELINE_LAYER,
    LAST_PIPELINE_STATUS,
    WAREHOUSE_NAME,
    WAREHOUSE_SIZE,
    PIPELINE_SUCCESS_RATE_PCT,
    DOWNSTREAM_COUNT,
    STALENESS_SECONDS,
    TABLE_NAME || ' is a ' || COALESCE(PIPELINE_LAYER, 'unknown') || '-layer ' ||
    LOWER(TABLE_TYPE) || ' with ' || COALESCE(ROW_COUNT::VARCHAR, '0') || ' rows. ' ||
    'Last pipeline status: ' || COALESCE(LAST_PIPELINE_STATUS, 'N/A') || '. ' ||
    'Downstream dependents: ' || COALESCE(DOWNSTREAM_COUNT::VARCHAR, '0') || '. ' ||
    'Warehouse: ' || COALESCE(WAREHOUSE_NAME, 'N/A') || ' (' || COALESCE(WAREHOUSE_SIZE, 'N/A') || ').'
    AS search_text
FROM METADATA_CATALOG;

-- ============================================================================
-- 8.2 CORTEX SEARCH SERVICE
-- Enables natural language discovery of tables and metadata
-- ============================================================================

CREATE OR REPLACE CORTEX SEARCH SERVICE METADATA_SEARCH
  ON search_text
  ATTRIBUTES TABLE_NAME, PIPELINE_LAYER, LAST_PIPELINE_STATUS
  WAREHOUSE = MY_WH
  TARGET_LAG = '1 hour'
  AS (
    SELECT search_text, TABLE_NAME, PIPELINE_LAYER, LAST_PIPELINE_STATUS
    FROM METADATA_SEARCH_CORPUS
  );

-- ============================================================================
-- 8.3 UPLOAD METADATA SEMANTIC MODEL
-- ============================================================================

CREATE OR REPLACE STAGE SEMANTIC_MODELS;
-- PUT handled by deploy.sh: uploads metadata_semantic_model.yaml

-- ============================================================================
-- 8.4 ENHANCED CORTEX AGENT (healthcare + metadata tools)
-- ============================================================================

CREATE OR REPLACE AGENT HEALTHCARE_METADATA_AGENT
  SPEC = $$
tools:
  - tool_spec:
      type: cortex_analyst
      semantic_model_file: "@HORIZON_DEMO_DB.HEALTHCARE.SEMANTIC_MODELS/healthcare_analytics_model.yaml"
  - tool_spec:
      type: cortex_analyst
      semantic_model_file: "@HORIZON_DEMO_DB.HEALTHCARE.SEMANTIC_MODELS/metadata_semantic_model.yaml"
  - tool_spec:
      type: cortex_search
      search_service: HORIZON_DEMO_DB.HEALTHCARE.METADATA_SEARCH
$$
  COMMENT = 'Multi-tool agent: healthcare analytics + pipeline metadata + table discovery';

-- ============================================================================
-- 8.5 SAMPLE QUERIES FOR THE AGENT
-- (Uncomment and run to test the agent)
-- ============================================================================

-- Healthcare analytics questions (routes to healthcare semantic model):
-- SELECT SNOWFLAKE.CORTEX.AGENT('HORIZON_DEMO_DB.HEALTHCARE.HEALTHCARE_METADATA_AGENT',
--   'What is the average revenue per patient by department?');

-- Pipeline metadata questions (routes to metadata semantic model):
-- SELECT SNOWFLAKE.CORTEX.AGENT('HORIZON_DEMO_DB.HEALTHCARE.HEALTHCARE_METADATA_AGENT',
--   'What is the pipeline success rate for each layer?');

-- SELECT SNOWFLAKE.CORTEX.AGENT('HORIZON_DEMO_DB.HEALTHCARE.HEALTHCARE_METADATA_AGENT',
--   'Which pipelines failed in the last 3 days?');

-- SELECT SNOWFLAKE.CORTEX.AGENT('HORIZON_DEMO_DB.HEALTHCARE.HEALTHCARE_METADATA_AGENT',
--   'What warehouse and size is used for the gold layer pipelines?');

-- Discovery questions (routes to Cortex Search):
-- SELECT SNOWFLAKE.CORTEX.AGENT('HORIZON_DEMO_DB.HEALTHCARE.HEALTHCARE_METADATA_AGENT',
--   'Find tables related to patient billing');

-- Combined questions (agent orchestrates multiple tools):
-- SELECT SNOWFLAKE.CORTEX.AGENT('HORIZON_DEMO_DB.HEALTHCARE.HEALTHCARE_METADATA_AGENT',
--   'Is the billing data fresh and what feeds the revenue dashboard?');

-- ============================================================================
-- VERIFICATION
-- ============================================================================

-- Verify search service
SHOW CORTEX SEARCH SERVICES IN SCHEMA HORIZON_DEMO_DB.HEALTHCARE;

-- Verify agent
DESCRIBE AGENT HORIZON_DEMO_DB.HEALTHCARE.HEALTHCARE_METADATA_AGENT;
