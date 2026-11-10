#!/bin/bash
set -eo pipefail
# ============================================================
# Deploy Demo Story Dashboard (Streamlit in Snowflake)
# Run AFTER deploy_all.sh — requires all demo objects to exist
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CONNECTION="${SNOW_CONNECTION:-my_conn}"
DATABASE="${DATABASE:-DEMO}"
WAREHOUSE="${WAREHOUSE:-MY_WH}"

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

echo "============================================"
echo "  Deploying Demo Story Dashboard"
echo "  (Streamlit in Snowflake)"
echo "============================================"
echo ""

# Ensure stage exists
echo "  Ensuring stage exists..."
snow sql -c "$CONNECTION" -q "
CREATE STAGE IF NOT EXISTS ${DATABASE}.HEALTHCARE_DEMO.STREAMLIT_STAGE ENCRYPTION = (TYPE = 'SNOWFLAKE_SSE');
" 2>&1 | grep -i "status\|created" || true

# Upload app
echo "  Uploading app.py..."
snow stage copy "$SCRIPT_DIR/app.py" \
    "@${DATABASE}.HEALTHCARE_DEMO.STREAMLIT_STAGE/dashboard/" \
    -c "$CONNECTION" --overwrite 2>&1 | grep -i "UPLOAD\|status" || true

# Create Streamlit object
echo "  Creating STREAMLIT object..."
snow sql -c "$CONNECTION" -q "
CREATE OR REPLACE STREAMLIT ${DATABASE}.HEALTHCARE_DEMO.DEMO_STORY_DASHBOARD
  ROOT_LOCATION = '@${DATABASE}.HEALTHCARE_DEMO.STREAMLIT_STAGE/dashboard'
  MAIN_FILE = 'app.py'
  QUERY_WAREHOUSE = '${WAREHOUSE}'
  COMMENT = 'Demo Story Dashboard - Platform capabilities overview with 6 tabs';
" 2>&1 | grep -i "status\|created\|success" || true

echo ""
echo "============================================"
echo "  DASHBOARD DEPLOYED"
echo "============================================"
echo ""
echo "  Open in Snowsight:"
echo "    Streamlit > DEMO_STORY_DASHBOARD"
echo ""
echo "  Or navigate to:"
echo "    https://app.snowflake.com/<ORG>/<ACCOUNT_NAME>/#/streamlit-apps/DEMO.HEALTHCARE_DEMO.DEMO_STORY_DASHBOARD"
echo ""
