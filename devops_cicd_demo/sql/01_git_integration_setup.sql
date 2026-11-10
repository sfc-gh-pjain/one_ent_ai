-- ============================================================
-- Snowflake Git Repository Integration Setup
-- ============================================================
-- Connects this GitHub repo to Snowflake as a read-only stage.
-- After setup, all files are accessible at:
--   @DEMO.HEALTHCARE_DEMO.HEALTHCARE_DEMO_REPO/branches/main/...
--
-- Prerequisites:
--   1. GitHub PAT with 'repo' scope (https://github.com/settings/tokens)
--   2. ACCOUNTADMIN role access (for API integration)
--
-- Usage:
--   Replace <your_github_pat_here> with your GitHub PAT, then run all statements.
-- ============================================================

-- ============================================================
-- Step 1: Create Secret (SYSADMIN)
-- ============================================================
USE ROLE SYSADMIN;
USE DATABASE DEMO;
USE SCHEMA HEALTHCARE_DEMO;

CREATE OR REPLACE SECRET GITHUB_SECRET
  TYPE = PASSWORD
  USERNAME = 'sfc-gh-pjain'
  PASSWORD = '<your_github_pat_here>';

-- ============================================================
-- Step 2: Create API Integration (ACCOUNTADMIN)
-- ============================================================
USE ROLE ACCOUNTADMIN;

CREATE OR REPLACE API INTEGRATION GITHUB_API_INTEGRATION
  API_PROVIDER = git_https_api
  API_ALLOWED_PREFIXES = ('https://github.com/sfc-gh-pjain/')
  ALLOWED_AUTHENTICATION_SECRETS = (DEMO.HEALTHCARE_DEMO.GITHUB_SECRET)
  ENABLED = TRUE;

GRANT USAGE ON INTEGRATION GITHUB_API_INTEGRATION TO ROLE SYSADMIN;

-- ============================================================
-- Step 3: Create Git Repository (SYSADMIN)
-- ============================================================
USE ROLE SYSADMIN;

CREATE OR REPLACE GIT REPOSITORY DEMO.HEALTHCARE_DEMO.HEALTHCARE_DEMO_REPO
  API_INTEGRATION = GITHUB_API_INTEGRATION
  GIT_CREDENTIALS = DEMO.HEALTHCARE_DEMO.GITHUB_SECRET
  ORIGIN = 'https://github.com/sfc-gh-pjain/snow_scos_e2e_healthcare_demo.git';

-- ============================================================
-- Step 4: Fetch and Verify
-- ============================================================
ALTER GIT REPOSITORY DEMO.HEALTHCARE_DEMO.HEALTHCARE_DEMO_REPO FETCH;

SHOW GIT BRANCHES IN DEMO.HEALTHCARE_DEMO.HEALTHCARE_DEMO_REPO;

-- Browse the devops_cicd_demo folder from the git repo stage
LS @DEMO.HEALTHCARE_DEMO.HEALTHCARE_DEMO_REPO/branches/main/devops_cicd_demo/;

-- ============================================================
-- Step 5: Test EXECUTE IMMEDIATE FROM
-- ============================================================
-- Deploy the market share setup SQL directly from the git repo:
EXECUTE IMMEDIATE FROM
  @DEMO.HEALTHCARE_DEMO.HEALTHCARE_DEMO_REPO/branches/main/devops_cicd_demo/code_bundle/sql/01_market_share_setup.sql;

-- Deploy ALL SQL layers from git (Jinja2 parameterized):
-- EXECUTE IMMEDIATE FROM
--   @DEMO.HEALTHCARE_DEMO.HEALTHCARE_DEMO_REPO/branches/main/devops_cicd_demo/deploy/deploy_from_git.sql
--   USING (branch => 'main', env => 'prod');

-- Preview without executing:
-- EXECUTE IMMEDIATE FROM
--   @DEMO.HEALTHCARE_DEMO.HEALTHCARE_DEMO_REPO/branches/main/devops_cicd_demo/deploy/deploy_from_git.sql
--   USING (branch => 'main', env => 'prod')
--   DRY_RUN = TRUE;
