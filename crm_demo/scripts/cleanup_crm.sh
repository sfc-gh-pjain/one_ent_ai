#!/bin/bash
set -eo pipefail
# ============================================================
# Cleanup CRM Demo — Drop all Snowflake objects
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONNECTION="${SNOW_CONNECTION:-my_conn}"

# Activate conda env
CONDA_ENV="e2edemo"
if ! command -v conda >/dev/null 2>&1; then
    [ -f "$HOME/miniconda3/bin/conda" ] && export PATH="$HOME/miniconda3/bin:$PATH"
fi
if command -v conda >/dev/null 2>&1; then
    eval "$(conda shell.bash hook)"
    conda activate "$CONDA_ENV" 2>/dev/null || true
    export PATH="${CONDA_PREFIX:-$HOME/miniconda3/envs/$CONDA_ENV}/bin:$PATH"
fi

echo "--- CRM Demo Cleanup ---"

echo "  Dropping Code Bundle..."
snow sql -c "$CONNECTION" -q "DROP CODE BUNDLE IF EXISTS DEMO.CRM_DEMO.CB_CRM_SPARK" 2>&1 | grep -i "status\|drop" || true

echo "  Dropping tables..."
snow sql -c "$CONNECTION" -q "
DROP TABLE IF EXISTS DEMO.CRM_DEMO.CUSTOMER_360;
DROP TABLE IF EXISTS DEMO.CRM_DEMO.PIPELINE_FORECAST;
DROP TABLE IF EXISTS DEMO.CRM_DEMO.RAW_ACCOUNTS;
DROP TABLE IF EXISTS DEMO.CRM_DEMO.RAW_OPPORTUNITIES;
DROP TABLE IF EXISTS DEMO.CRM_DEMO.RAW_CASES;
" 2>&1 | grep -i "status\|drop" || true

echo "  Dropping stage..."
snow sql -c "$CONNECTION" -q "DROP STAGE IF EXISTS DEMO.CRM_DEMO.CRM_STAGE" 2>&1 | grep -i "status\|drop" || true

echo "  Dropping schema..."
snow sql -c "$CONNECTION" -q "DROP SCHEMA IF EXISTS DEMO.CRM_DEMO CASCADE" 2>&1 | grep -i "status\|drop" || true

echo "  CRM Demo cleanup complete."
