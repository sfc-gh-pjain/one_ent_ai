USE ROLE SYSADMIN;
USE DATABASE HORIZON_DEMO_DB;
USE SCHEMA HEALTHCARE;
USE WAREHOUSE MY_WH;

CREATE OR REPLACE STAGE SEMANTIC_MODELS;

CREATE OR REPLACE AGENT HEALTHCARE_AGENT
  SPEC = $$
tools:
  - tool_spec:
      type: cortex_analyst
      semantic_model_file: "@HORIZON_DEMO_DB.HEALTHCARE.SEMANTIC_MODELS/healthcare_analytics_model.yaml"
$$
  COMMENT = 'AI agent for healthcare analytics';
