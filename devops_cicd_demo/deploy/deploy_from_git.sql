--!jinja

-- ============================================================
-- Master Deploy Script (EXECUTE IMMEDIATE FROM + Jinja2)
-- ============================================================
-- Deploys all SQL layers from the Snowflake Git Repository.
--
-- Usage:
--   ALTER GIT REPOSITORY DEMO.HEALTHCARE_DEMO.HEALTHCARE_DEMO_REPO FETCH;
--
--   EXECUTE IMMEDIATE FROM
--     @DEMO.HEALTHCARE_DEMO.HEALTHCARE_DEMO_REPO/branches/main/devops_cicd_demo/deploy/deploy_from_git.sql
--     USING (branch => 'main', env => 'prod');
--
-- Parameters:
--   branch  - Git branch name (e.g., 'main', 'experiment/new-hcp-tiering')
--   env     - Environment label (e.g., 'prod', 'experiment')
--
-- Preview without executing:
--   EXECUTE IMMEDIATE FROM ... USING (...) DRY_RUN = TRUE;
-- ============================================================

USE ROLE SYSADMIN;
USE WAREHOUSE MY_WH;
USE DATABASE DEMO;

-- ---- 1. Healthcare Pipeline Setup ----
EXECUTE IMMEDIATE FROM
  @DEMO.HEALTHCARE_DEMO.HEALTHCARE_DEMO_REPO/branches/{{branch}}/scos_pipeline/sql/01_setup.sql;

-- ---- 2. CRM Setup ----
EXECUTE IMMEDIATE FROM
  @DEMO.HEALTHCARE_DEMO.HEALTHCARE_DEMO_REPO/branches/{{branch}}/crm_demo/sql/01_setup.sql;

-- ---- 3. AI Layer ----
EXECUTE IMMEDIATE FROM
  @DEMO.HEALTHCARE_DEMO.HEALTHCARE_DEMO_REPO/branches/{{branch}}/ai_layer/sql/02_multi_domain_setup.sql;

EXECUTE IMMEDIATE FROM
  @DEMO.HEALTHCARE_DEMO.HEALTHCARE_DEMO_REPO/branches/{{branch}}/ai_layer/sql/03_agent_routing.sql;

EXECUTE IMMEDIATE FROM
  @DEMO.HEALTHCARE_DEMO.HEALTHCARE_DEMO_REPO/branches/{{branch}}/ai_layer/sql/04_semantic_views.sql;

-- ---- 4. Data Quality & MDM ----
EXECUTE IMMEDIATE FROM
  @DEMO.HEALTHCARE_DEMO.HEALTHCARE_DEMO_REPO/branches/{{branch}}/dq_mdm/sql/01_dmf_setup.sql;

EXECUTE IMMEDIATE FROM
  @DEMO.HEALTHCARE_DEMO.HEALTHCARE_DEMO_REPO/branches/{{branch}}/dq_mdm/sql/02_business_rules.sql;

EXECUTE IMMEDIATE FROM
  @DEMO.HEALTHCARE_DEMO.HEALTHCARE_DEMO_REPO/branches/{{branch}}/dq_mdm/sql/03_constraints.sql;

EXECUTE IMMEDIATE FROM
  @DEMO.HEALTHCARE_DEMO.HEALTHCARE_DEMO_REPO/branches/{{branch}}/dq_mdm/sql/04_governance.sql;

EXECUTE IMMEDIATE FROM
  @DEMO.HEALTHCARE_DEMO.HEALTHCARE_DEMO_REPO/branches/{{branch}}/dq_mdm/sql/05_ai_assisted_dq.sql;

EXECUTE IMMEDIATE FROM
  @DEMO.HEALTHCARE_DEMO.HEALTHCARE_DEMO_REPO/branches/{{branch}}/dq_mdm/sql/06_hybrid_governance.sql;

-- ---- 5. Blue/Green Swap Demo ----
EXECUTE IMMEDIATE FROM
  @DEMO.HEALTHCARE_DEMO.HEALTHCARE_DEMO_REPO/branches/{{branch}}/swap_ops_demo/setup.sql;

-- ---- 6. Streaming Setup ----
EXECUTE IMMEDIATE FROM
  @DEMO.HEALTHCARE_DEMO.HEALTHCARE_DEMO_REPO/branches/{{branch}}/streaming_demo/sql/01_setup.sql;

-- ---- 7. Horizon Governance ----
EXECUTE IMMEDIATE FROM
  @DEMO.HEALTHCARE_DEMO.HEALTHCARE_DEMO_REPO/branches/{{branch}}/horizon_catalog_demo/horizon_demo/01_setup_data.sql;

-- ---- 8. DevOps CI/CD Demo: Market Share Analysis ----
EXECUTE IMMEDIATE FROM
  @DEMO.HEALTHCARE_DEMO.HEALTHCARE_DEMO_REPO/branches/{{branch}}/devops_cicd_demo/code_bundle/sql/01_market_share_setup.sql;
