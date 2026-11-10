#!/bin/bash
set -eo pipefail
# ============================================
# Start Airflow for Demo Pipelines
# One command: sets up, configures, and starts Airflow
# Usage: export SNOWFLAKE_PAT='your_token' && ./start_airflow.sh
# ============================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

SNOWFLAKE_PAT="${SNOWFLAKE_PAT:-}"
CONNECTION="${CONNECTION:-my_conn}"
DATABASE="${DATABASE:-DEMO}"
SCHEMA="${SCHEMA:-HEALTHCARE_DEMO}"
WAREHOUSE="${WAREHOUSE:-MY_WH}"

if [ -z "$SNOWFLAKE_PAT" ]; then
    echo "ERROR: SNOWFLAKE_PAT not set."
    echo "  export SNOWFLAKE_PAT='your_token'"
    exit 1
fi

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
        echo "ERROR: Conda env '$CONDA_ENV' not found. Run ./bootstrap.sh first."
        exit 1
    fi
fi
export PATH="$CONDA_PREFIX/bin:$PATH"

export AIRFLOW_HOME="${SCRIPT_DIR}/airflow/.airflow"
DAGS_DIR="${SCRIPT_DIR}/airflow/dags"
PLUGINS_DIR="${SCRIPT_DIR}/airflow/plugins"

echo "============================================"
echo "  Starting Airflow — Demo Pipelines"
echo "  AIRFLOW_HOME: $AIRFLOW_HOME"
echo "  DAGs:         $DAGS_DIR"
echo "  Plugins:      $PLUGINS_DIR"
echo "============================================"
echo ""
echo "  Available DAGs:"
echo "    - healthcare_pipeline (4 Spark jobs)"
echo "    - crm_pipeline (3 Spark jobs)"
echo "    - dq_mdm_pipeline (4 MDM rules)"
echo "    - swap_pipeline (blue/green refresh)"
echo ""

# Install if needed
if ! command -v airflow >/dev/null 2>&1; then
    echo "  Airflow not found, installing from requirements.txt..."
    pip install -r "$SCRIPT_DIR/requirements.txt" 2>&1 | tail -3
fi

# Initialize if first time
if [ ! -f "$AIRFLOW_HOME/airflow.cfg" ]; then
    echo "  Initializing Airflow database..."
    mkdir -p "$AIRFLOW_HOME"
    airflow db migrate 2>&1 | tail -3
fi

# Set DAGs folder and plugins, disable example DAGs
if [ -f "$AIRFLOW_HOME/airflow.cfg" ]; then
    sed -i.bak "s|dags_folder = .*|dags_folder = ${DAGS_DIR}|" "$AIRFLOW_HOME/airflow.cfg" 2>/dev/null || true
    sed -i.bak "s|plugins_folder = .*|plugins_folder = ${PLUGINS_DIR}|" "$AIRFLOW_HOME/airflow.cfg" 2>/dev/null || true
    sed -i.bak "s|load_examples = .*|load_examples = False|" "$AIRFLOW_HOME/airflow.cfg" 2>/dev/null || true
fi

# Set variables
echo "  Configuring Snowflake variables..."
airflow variables set snowflake_account_url '<ACCOUNT_LOCATOR>.snowflakecomputing.com' 2>/dev/null || true
airflow variables set snowflake_pat "$SNOWFLAKE_PAT" 2>/dev/null || true
airflow variables set snowflake_role 'SYSADMIN' 2>/dev/null || true
airflow variables set snowflake_warehouse "$WAREHOUSE" 2>/dev/null || true
airflow variables set snowflake_database "$DATABASE" 2>/dev/null || true
airflow variables set snowflake_schema "$SCHEMA" 2>/dev/null || true

echo "  Variables set."
echo ""
echo "  Starting Airflow standalone (background)..."
echo "  Log: $SCRIPT_DIR/airflow_out.log"
echo "  URL: http://localhost:8080"
echo "  User: admin"
echo "  Stop: pkill -f airflow"
echo ""
echo "--------------------------------------------"

airflow standalone > "$SCRIPT_DIR/airflow_out.log" 2>&1 &
echo "  Airflow PID: $!"
echo "  Waiting for startup..."
sleep 5

# Display password from generated file
PASS_FILE="$AIRFLOW_HOME/simple_auth_manager_passwords.json.generated"
if [ -f "$PASS_FILE" ]; then
    ADMIN_PASS=$(python3 -c "import json; print(json.load(open('$PASS_FILE'))['admin'])" 2>/dev/null)
    echo "  Password: $ADMIN_PASS"
else
    echo "  Password: check $PASS_FILE after startup completes"
fi
echo ""
echo "  Done. Open http://localhost:8080"
