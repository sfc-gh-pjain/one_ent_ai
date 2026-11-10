#!/bin/bash
set -eo pipefail
# ============================================================
# TEARDOWN: Remove ALL demo objects from Snowflake
# Drops everything created by bootstrap.sh + sub-demos
# ============================================================
# Usage: ./teardown.sh
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONNECTION="${SNOW_CONNECTION:-my_conn}"

# Activate conda env
CONDA_ENV="e2edemo"
if ! command -v conda >/dev/null 2>&1; then
    [ -f "$HOME/miniconda3/bin/conda" ] && export PATH="$HOME/miniconda3/bin:$PATH"
fi
if command -v conda >/dev/null 2>&1; then
    if [[ "${CONDA_DEFAULT_ENV:-}" != "$CONDA_ENV" ]]; then
        if conda info --envs 2>/dev/null | grep -q "^${CONDA_ENV} "; then
            eval "$(conda shell.bash hook)"
            conda activate "$CONDA_ENV"
        fi
    fi
    export PATH="${CONDA_PREFIX:-$HOME/miniconda3/envs/$CONDA_ENV}/bin:$PATH"
fi

# Verify snow CLI
if ! command -v snow >/dev/null 2>&1; then
    echo "ERROR: snow CLI not found. Activate conda env 'e2edemo' or install Snow CLI."
    exit 1
fi

echo "======================================"
echo "  TEARDOWN: Healthcare Demo"
echo "  Removing ALL Snowflake objects"
echo "======================================"
echo ""
echo "  Connection: $CONNECTION"
echo ""
echo "  This will DROP:"
echo "    - All tables in DEMO.HEALTHCARE_DEMO"
echo "    - Cortex Search Service"
echo "    - Cortex Agent"
echo "    - Streamlit App"
echo "    - Code Bundle"
echo "    - Stages"
echo "    - SWAP_DEMO database (if exists)"
echo "    - CRM_DEMO schema (if exists)"
echo ""
read -p "  Are you sure? (y/N): " confirm
if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "  Cancelled."
    exit 0
fi
echo ""

echo ">>> Dropping Cortex Search Service..."
snow sql -c "$CONNECTION" -q "
DROP CORTEX SEARCH SERVICE IF EXISTS DEMO.HEALTHCARE_DEMO.PHARMA_SEARCH_SERVICE;
DROP CORTEX SEARCH SERVICE IF EXISTS DEMO.HEALTHCARE_DEMO.MODEL_ROUTER_SEARCH;
" 2>&1 | grep -i "status\|error\|drop" || true

echo ">>> Dropping Cortex Agent..."
snow sql -c "$CONNECTION" -q "
DROP AGENT IF EXISTS DEMO.HEALTHCARE_DEMO.PHARMA_INTELLIGENCE_AGENT;
DROP AGENT IF EXISTS DEMO.HEALTHCARE_DEMO.ENTERPRISE_INTELLIGENCE_AGENT;
" 2>&1 | grep -i "status\|error\|drop" || true

echo ">>> Dropping Semantic Views..."
snow sql -c "$CONNECTION" -q "
DROP SEMANTIC VIEW IF EXISTS DEMO.HEALTHCARE_DEMO.PHARMA_COMMERCIAL_INTELLIGENCE;
DROP SEMANTIC VIEW IF EXISTS DEMO.CRM_DEMO.CRM_COMMERCIAL_INTELLIGENCE;
DROP SEMANTIC VIEW IF EXISTS DEMO.HEALTHCARE_DEMO.FINANCE_SUMMARY;
" 2>&1 | grep -i "status\|error\|drop" || true

echo ">>> Dropping Streamlit App..."
snow sql -c "$CONNECTION" -q "
DROP STREAMLIT IF EXISTS DEMO.HEALTHCARE_DEMO.PHARMA_INTELLIGENCE_APP;
DROP STREAMLIT IF EXISTS DEMO.HEALTHCARE_DEMO.DQ_MONITOR;
" 2>&1 | grep -i "status\|error\|drop" || true

echo ">>> Dropping Pipes..."
snow sql -c "$CONNECTION" -q "
DROP PIPE IF EXISTS DEMO.HEALTHCARE_DEMO.HCP_EVENTS_RT_STREAMING;
" 2>&1 | grep -i "status\|error\|drop" || true

echo ">>> Suspending and Dropping Tasks..."
snow sql -c "$CONNECTION" -q "
ALTER TASK IF EXISTS DEMO.HEALTHCARE_DEMO.TASK_MDM_HCP_DEDUP SUSPEND;
ALTER TASK IF EXISTS DEMO.HEALTHCARE_DEMO.TASK_MDM_RX_OUTLIER_DETECTION SUSPEND;
ALTER TASK IF EXISTS DEMO.HEALTHCARE_DEMO.TASK_MDM_ENGAGEMENT_VALIDATION SUSPEND;
ALTER TASK IF EXISTS DEMO.HEALTHCARE_DEMO.TASK_MDM_TIER_VALIDATION SUSPEND;
DROP TASK IF EXISTS DEMO.HEALTHCARE_DEMO.TASK_MDM_HCP_DEDUP;
DROP TASK IF EXISTS DEMO.HEALTHCARE_DEMO.TASK_MDM_RX_OUTLIER_DETECTION;
DROP TASK IF EXISTS DEMO.HEALTHCARE_DEMO.TASK_MDM_ENGAGEMENT_VALIDATION;
DROP TASK IF EXISTS DEMO.HEALTHCARE_DEMO.TASK_MDM_TIER_VALIDATION;
" 2>&1 | grep -i "status\|error\|drop" || true

echo ">>> Dropping Streams..."
snow sql -c "$CONNECTION" -q "
DROP STREAM IF EXISTS DEMO.HEALTHCARE_DEMO.STREAM_RAW_PRESCRIPTIONS;
DROP STREAM IF EXISTS DEMO.HEALTHCARE_DEMO.STREAM_RAW_HCP_PROFILES;
DROP STREAM IF EXISTS DEMO.HEALTHCARE_DEMO.STREAM_RAW_HCP_ENGAGEMENTS;
" 2>&1 | grep -i "status\|error\|drop" || true

echo ">>> Dropping Code Bundle..."
snow sql -c "$CONNECTION" -q "
DROP CODE BUNDLE IF EXISTS DEMO.HEALTHCARE_DEMO.CB_HEALTHCARE_SPARK;
" 2>&1 | grep -i "status\|error\|drop" || true

echo ">>> Dropping all tables in HEALTHCARE_DEMO..."
snow sql -c "$CONNECTION" -q "
USE SCHEMA DEMO.HEALTHCARE_DEMO;
DROP TABLE IF EXISTS RAW_PRESCRIPTIONS;
DROP TABLE IF EXISTS RAW_HCP_PROFILES;
DROP TABLE IF EXISTS RAW_HCP_ENGAGEMENTS;
DROP TABLE IF EXISTS DIM_DRUG;
DROP TABLE IF EXISTS DIM_TERRITORY;
DROP TABLE IF EXISTS DIM_REGION;
DROP TABLE IF EXISTS DIM_THERAPEUTIC_AREA;
DROP TABLE IF EXISTS RX_METRICS_OUTPUT;
DROP TABLE IF EXISTS HCP_TIERED_PROFILES;
DROP TABLE IF EXISTS ENGAGEMENT_FINAL;
DROP TABLE IF EXISTS AI_ENRICHED_DRUGS;
DROP TABLE IF EXISTS HCP_GOLDEN_RECORD;
DROP TABLE IF EXISTS MDM_VIOLATION_LOG;
DROP TABLE IF EXISTS HCP_EVENTS_RT;
DROP TABLE IF EXISTS FINANCE_REVENUE_SUMMARY;
DROP TABLE IF EXISTS FINANCE_COST_CENTERS;
DROP TABLE IF EXISTS SEMANTIC_MODEL_REGISTRY;
DROP TABLE IF EXISTS DQ_AI_SUGGESTIONS;
" 2>&1 | grep -i "status\|error\|drop" || true

echo ">>> Dropping Views..."
snow sql -c "$CONNECTION" -q "
DROP VIEW IF EXISTS DEMO.HEALTHCARE_DEMO.HCP_SEARCH_V;
DROP VIEW IF EXISTS DEMO.HEALTHCARE_DEMO.DQ_VIOLATION_INSIGHTS;
DROP VIEW IF EXISTS DEMO.HEALTHCARE_DEMO.DQ_TREND_ANALYSIS;
DROP VIEW IF EXISTS DEMO.HEALTHCARE_DEMO.DQ_SCHEMA_COVERAGE;
DROP VIEW IF EXISTS DEMO.HEALTHCARE_DEMO.GOVERNANCE_INVENTORY;
DROP VIEW IF EXISTS DEMO.HEALTHCARE_DEMO.GOVERNANCE_SOURCE_SUMMARY;
DROP VIEW IF EXISTS DEMO.HEALTHCARE_DEMO.GOVERNANCE_COMPLIANCE_COVERAGE;
" 2>&1 | grep -i "status\|error\|drop" || true

echo ">>> Dropping DMFs..."
snow sql -c "$CONNECTION" -q "
DROP FUNCTION IF EXISTS DEMO.HEALTHCARE_DEMO.DMF_VALID_RX_VOLUME(TABLE(FLOAT));
DROP FUNCTION IF EXISTS DEMO.HEALTHCARE_DEMO.DMF_VALID_HCP_TIER(TABLE(VARCHAR));
DROP FUNCTION IF EXISTS DEMO.HEALTHCARE_DEMO.DMF_VALID_HCP_DECILE(TABLE(INTEGER));
DROP FUNCTION IF EXISTS DEMO.HEALTHCARE_DEMO.DMF_NO_FUTURE_ENGAGEMENT_DATE(TABLE(DATE));
DROP FUNCTION IF EXISTS DEMO.HEALTHCARE_DEMO.DMF_RX_COMPLETENESS(TABLE(VARCHAR,INTEGER,FLOAT,VARCHAR));
DROP FUNCTION IF EXISTS DEMO.HEALTHCARE_DEMO.DMF_RX_ORPHAN_DRUGS(TABLE(VARCHAR));
" 2>&1 | grep -i "status\|error\|drop" || true

echo ">>> Dropping Masking Policies..."
snow sql -c "$CONNECTION" -q "
DROP MASKING POLICY IF EXISTS DEMO.HEALTHCARE_DEMO.MASK_NPI_NUMBER;
DROP MASKING POLICY IF EXISTS DEMO.HEALTHCARE_DEMO.MASK_HCP_NAME;
DROP MASKING POLICY IF EXISTS DEMO.HEALTHCARE_DEMO.MASK_NOTES;
" 2>&1 | grep -i "status\|error\|drop" || true

echo ">>> Dropping Tags..."
snow sql -c "$CONNECTION" -q "
DROP TAG IF EXISTS DEMO.HEALTHCARE_DEMO.SENSITIVITY_LEVEL;
DROP TAG IF EXISTS DEMO.HEALTHCARE_DEMO.DATA_DOMAIN;
DROP TAG IF EXISTS DEMO.HEALTHCARE_DEMO.DATA_QUALITY_STATUS;
DROP TAG IF EXISTS DEMO.HEALTHCARE_DEMO.DATA_OWNER;
DROP TAG IF EXISTS DEMO.HEALTHCARE_DEMO.SOURCE_SYSTEM;
DROP TAG IF EXISTS DEMO.HEALTHCARE_DEMO.INTEGRATION_PATTERN;
DROP TAG IF EXISTS DEMO.HEALTHCARE_DEMO.DATA_FRESHNESS_SLA;
DROP TAG IF EXISTS DEMO.HEALTHCARE_DEMO.COMPLIANCE_FRAMEWORK;
" 2>&1 | grep -i "status\|error\|drop" || true

echo ">>> Dropping Stages..."
snow sql -c "$CONNECTION" -q "
DROP STAGE IF EXISTS DEMO.HEALTHCARE_DEMO.DEMO_STAGE;
DROP STAGE IF EXISTS DEMO.HEALTHCARE_DEMO.SEMANTIC_MODELS;
DROP STAGE IF EXISTS DEMO.HEALTHCARE_DEMO.CB_SSE_STAGE;
DROP STAGE IF EXISTS DEMO.HEALTHCARE_DEMO.STREAMLIT_STAGE;
" 2>&1 | grep -i "status\|error\|drop" || true

echo ">>> Dropping Stored Procedures..."
snow sql -c "$CONNECTION" -q "
DROP PROCEDURE IF EXISTS DEMO.HEALTHCARE_DEMO.REFRESH_STAR_SCHEMA();
DROP PROCEDURE IF EXISTS DEMO.HEALTHCARE_DEMO.SP_MDM_HCP_DEDUP();
DROP PROCEDURE IF EXISTS DEMO.HEALTHCARE_DEMO.SP_MDM_ENGAGEMENT_VALIDATION();
" 2>&1 | grep -i "status\|error\|drop" || true

echo ">>> Dropping SWAP_DEMO database (if exists)..."
snow sql -c "$CONNECTION" -q "
DROP DATABASE IF EXISTS SWAP_DEMO;
" 2>&1 | grep -i "status\|error\|drop" || true

echo ">>> Dropping CRM_DEMO schema (if exists)..."
snow sql -c "$CONNECTION" -q "
DROP CODE BUNDLE IF EXISTS DEMO.CRM_DEMO.CB_CRM_SPARK;
DROP SCHEMA IF EXISTS DEMO.CRM_DEMO CASCADE;
" 2>&1 | grep -i "status\|error\|drop" || true

echo ">>> Dropping HEALTHCARE_DEMO schema..."
snow sql -c "$CONNECTION" -q "
DROP SCHEMA IF EXISTS DEMO.HEALTHCARE_DEMO CASCADE;
" 2>&1 | grep -i "status\|error\|drop" || true

echo ""
echo "======================================"
echo "  TEARDOWN COMPLETE"
echo "======================================"
echo ""
echo "  All Snowflake objects removed."
echo "  Local files (code, data) are still intact."
echo ""
echo "  To also remove the conda env:"
echo "    conda deactivate && conda env remove -n e2edemo"
echo ""
echo "  To re-deploy from scratch:"
echo "    export SNOWFLAKE_PAT='token' && ./bootstrap.sh"
