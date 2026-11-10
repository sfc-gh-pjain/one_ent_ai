# DevOps CI/CD Demo

Self-contained demonstration of Git integration, CI/CD pipelines, and A/B testing for Snowflake Code Bundles.

## What This Demonstrates

1. **Snowflake Git Repository Integration** -- GitHub repo mirrored as a read-only Snowflake stage
2. **EXECUTE IMMEDIATE FROM** -- deploy 27+ SQL files from the git repo stage with Jinja2 templating
3. **Two-Path Deployment** -- SQL objects via EXECUTE IMMEDIATE FROM, Code Bundles via dev Snow CLI
4. **GitHub Actions CI/CD** -- automated validate + deploy on push, dry-run on PR
5. **A/B Testing** -- experiment branches deployed as parallel Code Bundles
6. **New Code Bundle Job** -- `05_market_share_analysis.py` (drug market share by territory)

## Folder Structure

```
devops_cicd_demo/
├── README.md                               # This file
├── code_bundle/
│   ├── src/
│   │   ├── code_bundle.yml                 # Spark bundle config (warehouse, python, 1.29)
│   │   └── 05_market_share_analysis.py     # New PySpark job: market share by territory
│   └── sql/
│       └── 01_market_share_setup.sql       # CREATE TABLE MARKET_SHARE_ANALYSIS
├── deploy/
│   └── deploy_from_git.sql                 # Jinja2 master deploy (EXECUTE IMMEDIATE FROM)
├── github_actions/
│   └── deploy.yml                          # GitHub Actions workflow (also at .github/workflows/)
└── docs/
    ├── path1_sql_deployment.svg            # Architecture: SQL deployment path
    └── path2_code_bundle_deployment.svg    # Architecture: Code Bundle deployment path
```

## Quick Start

### Run the new Code Bundle job locally

```bash
# Package the new job into the existing healthcare bundle
cd scos_pipeline
snow bundle create CB_HEALTHCARE_SPARK --source src --overwrite -c my_conn

# Copy the new job file into the bundle source
cp ../devops_cicd_demo/code_bundle/src/05_market_share_analysis.py src/

# Re-package with the new job
snow bundle create CB_HEALTHCARE_SPARK --source src --overwrite -c my_conn

# Create the output table
snow sql -f ../devops_cicd_demo/code_bundle/sql/01_market_share_setup.sql -c my_conn

# Execute via SQL
snow sql -q "
  EXECUTE CODE BUNDLE CB_HEALTHCARE_SPARK
    ENTRYPOINT = '05_market_share_analysis.py'
    ARGUMENTS = ('--ds', CURRENT_DATE()::VARCHAR)
    EXECUTION_NAME = 'market_share_analysis';
" -c my_conn
```

### Deploy all SQL via Git Repository

```sql
-- One-time setup (see steps_for_git_integration.md for SECRET + API INTEGRATION)
ALTER GIT REPOSITORY DEMO.HEALTHCARE_DEMO.HEALTHCARE_DEMO_REPO FETCH;

-- Deploy all layers
EXECUTE IMMEDIATE FROM
  @DEMO.HEALTHCARE_DEMO.HEALTHCARE_DEMO_REPO/branches/main/devops_cicd_demo/deploy/deploy_from_git.sql
  USING (branch => 'main', env => 'prod');

-- Preview without executing
EXECUTE IMMEDIATE FROM
  @DEMO.HEALTHCARE_DEMO.HEALTHCARE_DEMO_REPO/branches/main/devops_cicd_demo/deploy/deploy_from_git.sql
  USING (branch => 'main', env => 'prod')
  DRY_RUN = TRUE;
```

### A/B Testing

```bash
# Create experiment branch
git checkout -b experiment/new-hcp-tiering
# ... modify code ...
git push -u origin experiment/new-hcp-tiering
```

```sql
ALTER GIT REPOSITORY DEMO.HEALTHCARE_DEMO.HEALTHCARE_DEMO_REPO FETCH;

-- Deploy experiment alongside production
EXECUTE IMMEDIATE FROM
  @DEMO.HEALTHCARE_DEMO.HEALTHCARE_DEMO_REPO/branches/experiment-new-hcp-tiering/devops_cicd_demo/deploy/deploy_from_git.sql
  USING (branch => 'experiment/new-hcp-tiering', env => 'experiment');
```

## Two-Path Deployment Model

| What | Create/Package | Execute/Run |
|------|---------------|-------------|
| SQL objects (tables, agents, views, policies) | N/A | `EXECUTE IMMEDIATE FROM @repo/...` |
| Code Bundles (PySpark) | `snow bundle create` (**dev CLI 3.20.0+**) | `EXECUTE CODE BUNDLE` (standard SQL) |

**Dev CLI install:** `uv tool install git+https://github.com/snowflakedb/snowflake-cli@code`

The standard `pip install snowflake-cli-labs` does NOT include `snow bundle`.

## Architecture Diagrams

- [Path 1: SQL Deployment](docs/path1_sql_deployment.svg)
- [Path 2: Code Bundle Deployment](docs/path2_code_bundle_deployment.svg)

## GitHub Actions CI/CD

The workflow at `.github/workflows/deploy.yml` provides:

| Trigger | Jobs |
|---------|------|
| Push to `main` | Validate SQL (sqlfluff) -> Deploy SQL (EXECUTE IMMEDIATE FROM) -> Package Code Bundles (snow bundle create) |
| Pull Request | Validate SQL -> Dry-run (DRY_RUN = TRUE, no execution) |

**Required secrets:** `SNOWFLAKE_PAT`, `SNOWFLAKE_ACCOUNT` in GitHub repo settings.

## Full Plan

See [steps_for_git_integration.md](../steps_for_git_integration.md) for the complete 7-step implementation plan with all SQL, YAML, and bash.
