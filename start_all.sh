#!/bin/bash
# start_all.sh — Start everything: Snowflake Tasks + DTs + Airflow
# Run as: ./start_all.sh
# Requires: conda env 'e2edemo' active or will activate it

set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AIRFLOW_HOME="$SCRIPT_DIR/airflow"

echo "============================================"
echo "  STARTING ALL DEMO SERVICES"
echo "============================================"

# --- Activate conda env if needed ---
if [[ "$CONDA_DEFAULT_ENV" != "e2edemo" ]]; then
  echo "Activating conda env 'e2edemo'..."
  eval "$(conda shell.bash hook)"
  conda activate e2edemo 2>/dev/null || { echo "Error: conda env 'e2edemo' not found. Run ./bootstrap.sh first."; exit 1; }
fi

# --- 1. Resume Healthcare Demo Tasks ---
echo ""
echo "[1/3] Resuming HEALTHCARE_DEMO tasks..."
snow sql --silent -c my_conn -q "
ALTER TASK IF EXISTS DEMO.HEALTHCARE_DEMO.TASK_MDM_HCP_DEDUP RESUME;
ALTER TASK IF EXISTS DEMO.HEALTHCARE_DEMO.TASK_MDM_RX_OUTLIER_DETECTION RESUME;
ALTER TASK IF EXISTS DEMO.HEALTHCARE_DEMO.TASK_MDM_ENGAGEMENT_VALIDATION RESUME;
ALTER TASK IF EXISTS DEMO.HEALTHCARE_DEMO.TASK_MDM_TIER_VALIDATION RESUME;
" 2>/dev/null && echo "  Healthcare tasks resumed." || echo "  Warning: some tasks may have failed to resume."

# --- 2. Resume Dynamic Tables (SYSADMIN-owned) ---
echo ""
echo "[2/3] Resuming Dynamic Tables..."
snow sql --silent -c my_conn -q "
ALTER DYNAMIC TABLE IF EXISTS DEMO.STATION_METRICS.FACT_STATION_METRICS RESUME;
ALTER DYNAMIC TABLE IF EXISTS DEMO.STATION_METRICS.SILVER_STATION_EVENTS RESUME;
ALTER DYNAMIC TABLE IF EXISTS DEMO.EMAIL_DEMO.EMAIL_LIVE RESUME;
ALTER DYNAMIC TABLE IF EXISTS DEMO.EMAIL_DEMO.STG_EMAIL_DT RESUME;
" 2>/dev/null && echo "  SYSADMIN-owned DTs resumed." || echo "  Warning: some DTs may have failed."

# --- 3. Start Airflow ---
echo ""
echo "[3/3] Starting Airflow..."
if pgrep -f "airflow" > /dev/null 2>&1; then
  echo "  Airflow already running."
else
  export AIRFLOW_HOME="$AIRFLOW_HOME"

  # Set Airflow Variables if not already set
  if ! airflow variables get snowflake_pat > /dev/null 2>&1; then
    echo "  Setting Airflow variables from environment..."
    if [ -n "$SNOWFLAKE_PAT" ]; then
      airflow variables set snowflake_account_url "https://<ACCOUNT_LOCATOR>.snowflakecomputing.com" 2>/dev/null
      airflow variables set snowflake_pat "$SNOWFLAKE_PAT" 2>/dev/null
      airflow variables set snowflake_role "SYSADMIN" 2>/dev/null
      airflow variables set snowflake_warehouse "MY_WH" 2>/dev/null
      airflow variables set snowflake_database "DEMO" 2>/dev/null
      airflow variables set snowflake_schema "HEALTHCARE_DEMO" 2>/dev/null
    else
      echo "  Warning: SNOWFLAKE_PAT not set. Airflow DAGs will fail without it."
      echo "  Run: export SNOWFLAKE_PAT='your_token' before starting."
    fi
  fi

  # Start Airflow in background
  AIRFLOW__CORE__LOAD_EXAMPLES=False \
  AIRFLOW__CORE__DAGS_FOLDER="$AIRFLOW_HOME/dags" \
  airflow standalone > "$AIRFLOW_HOME/airflow.log" 2>&1 &
  AIRFLOW_PID=$!

  echo "  Airflow starting (PID: $AIRFLOW_PID)..."
  echo "  Waiting for startup..."
  sleep 10

  # Get password
  if [ -f "$AIRFLOW_HOME/simple_auth_manager_passwords.json.generated" ]; then
    ADMIN_PASS=$(python3 -c "import json; print(json.load(open('$AIRFLOW_HOME/simple_auth_manager_passwords.json.generated'))['admin'])" 2>/dev/null)
    echo "  Airflow UI: http://localhost:8080"
    echo "  Username: admin"
    echo "  Password: $ADMIN_PASS"
  else
    echo "  Airflow starting... check $AIRFLOW_HOME/airflow.log for password."
  fi
fi

echo ""
echo "============================================"
echo "  ALL STARTED"
echo "============================================"
echo ""
echo "  Airflow UI:    http://localhost:8080"
echo "  Dashboard:     Snowsight > Streamlit > DEMO_STORY_DASHBOARD"
echo "  DAGs:          healthcare_pipeline, crm_pipeline, dq_mdm_pipeline, swap_pipeline"
echo ""
echo "  To trigger a DAG:"
echo "    export AIRFLOW_HOME=$AIRFLOW_HOME"
echo "    airflow dags trigger healthcare_pipeline"
echo ""
