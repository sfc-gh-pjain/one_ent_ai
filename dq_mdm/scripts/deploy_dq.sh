#!/usr/bin/env bash
# ============================================================
# Deploy DQ, Business Rules, MDM & Governance
# Healthcare Commercial Analytics Pipeline
# ============================================================
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DQ_DIR="$(dirname "$SCRIPT_DIR")"
SQL_DIR="$DQ_DIR/sql"

# Connection name for Snow CLI
CONNECTION="${SNOW_CONNECTION:-my_conn}"

# Activate conda env
CONDA_ENV="e2edemo"
if [[ "${CONDA_DEFAULT_ENV:-}" != "$CONDA_ENV" ]]; then
    if ! command -v conda >/dev/null 2>&1; then
        [ -f "$HOME/miniconda3/bin/conda" ] && export PATH="$HOME/miniconda3/bin:$PATH"
    fi
    if conda info --envs 2>/dev/null | grep -q "^${CONDA_ENV} "; then
        eval "$(conda shell.bash hook)"
        conda activate "$CONDA_ENV"
    else
        echo "ERROR: Conda env '$CONDA_ENV' not found. Run bootstrap.sh first."
        exit 1
    fi
fi
export PATH="$CONDA_PREFIX/bin:$PATH"

echo "======================================"
echo " Healthcare DQ/MDM Deployment"
echo "======================================"
echo ""
echo "Connection: $CONNECTION"
echo "SQL Dir:    $SQL_DIR"
echo ""

# Function to run SQL file
run_sql() {
    local file="$1"
    local desc="$2"
    echo "▶ $desc..."
    echo "  File: $file"
    snow sql -f "$file" -c "$CONNECTION" --quiet 2>&1 | tail -5
    echo "  ✓ Done"
    echo ""
}

# Step 1: DMF Setup
run_sql "$SQL_DIR/01_dmf_setup.sql" "Setting up Data Metric Functions"

# Step 2: Business Rules (Streams + Tasks)
run_sql "$SQL_DIR/02_business_rules.sql" "Creating streams, tasks, and MDM rules"

# Step 3: Constraints
run_sql "$SQL_DIR/03_constraints.sql" "Adding primary/foreign key constraints"

# Step 4: Governance (Tags + Policies)
run_sql "$SQL_DIR/04_governance.sql" "Applying tags and masking policies"

# Step 5: Deploy Streamlit App
echo "▶ Deploying Streamlit DQ Monitor..."
STREAMLIT_DIR="$DQ_DIR/streamlit"

# Create Streamlit object via SQL
snow sql -c "$CONNECTION" -q "
    CREATE OR REPLACE STREAMLIT DEMO.HEALTHCARE_DEMO.DQ_MONITOR
        ROOT_LOCATION = '@DEMO.HEALTHCARE_DEMO.DEMO_STAGE/dq_monitor'
        MAIN_FILE = 'dq_monitor.py'
        QUERY_WAREHOUSE = 'MY_WH'
        TITLE = 'Healthcare DQ & MDM Monitor';
" --quiet 2>&1 | tail -3

# Upload the Streamlit file to stage
snow sql -c "$CONNECTION" -q "
    PUT file://$STREAMLIT_DIR/dq_monitor.py @DEMO.HEALTHCARE_DEMO.DEMO_STAGE/dq_monitor/
    AUTO_COMPRESS = FALSE OVERWRITE = TRUE;
" --quiet 2>&1 | tail -3
echo "  ✓ Streamlit app deployed"
echo ""

# Step 6: Verify
echo "======================================"
echo " Verification"
echo "======================================"
echo ""
echo "▶ Checking DMF attachments..."
snow sql -c "$CONNECTION" -q "
    SELECT TABLE_NAME, METRIC_NAME
    FROM TABLE(INFORMATION_SCHEMA.DATA_METRIC_FUNCTION_REFERENCES(
        REF_ENTITY_NAME => 'DEMO.HEALTHCARE_DEMO.RX_METRICS_OUTPUT',
        REF_ENTITY_DOMAIN => 'TABLE'
    ));
" --quiet 2>&1 | tail -10

echo ""
echo "▶ Checking tasks..."
snow sql -c "$CONNECTION" -q "
    SHOW TASKS LIKE '%MDM%' IN SCHEMA DEMO.HEALTHCARE_DEMO;
" --quiet 2>&1 | tail -10

echo ""
echo "======================================"
echo " Deployment Complete!"
echo "======================================"
echo ""
echo "Streamlit URL: Open Snowsight → Streamlit → DQ_MONITOR"
echo ""
echo "Next steps:"
echo "  1. Wait for DMFs to run (triggered on next table change)"
echo "  2. Run pipeline to trigger streams → tasks → violations"
echo "  3. View results in Streamlit dashboard"
