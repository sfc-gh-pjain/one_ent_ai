#!/bin/bash
#===============================================================================
# HORIZON CATALOG DEMO - DEPLOY
#
# Runs steps 02-08 after 01_setup_data.sql has been executed as ACCOUNTADMIN.
# Each step is a separate snow sql call so failures are isolated.
#
# Usage: ./deploy.sh <connection_name>
# Example: ./deploy.sh my_conn
#===============================================================================
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONN="${1:-my_conn}"
FAILED=0

echo "============================================"
echo " Horizon Catalog Demo - Deploy"
echo " Connection: $CONN"
echo "============================================"
echo ""

run_step() {
    local step_num="$1"
    local step_name="$2"
    local sql_file="$3"
    local logfile="/tmp/horizon_deploy_${step_num//\//_}.log"

    echo "[$step_num] $step_name"
    echo "    File: $(basename "$sql_file")"

    if snow sql --connection "$CONN" -f "$sql_file" > "$logfile" 2>&1; then
        echo "    Status: OK"
    else
        echo "    Status: FAILED"
        tail -5 "$logfile" | sed 's/^/    /'
        FAILED=$((FAILED + 1))
    fi
    echo ""
}

run_query() {
    local step_num="$1"
    local step_name="$2"
    local sql="$3"
    local logfile="/tmp/horizon_deploy_${step_num//\//_}.log"

    echo "[$step_num] $step_name"
    if snow sql --connection "$CONN" --query "$sql" > "$logfile" 2>&1; then
        echo "    Status: OK"
    else
        echo "    Status: FAILED"
        tail -5 "$logfile" | sed 's/^/    /'
        FAILED=$((FAILED + 1))
    fi
    echo ""
}

# --- Step 1: Object Tagging ---
run_step "1/9" "Object Tagging" "$SCRIPT_DIR/steps/02_tagging.sql"

# --- Step 2: Masking & Projection Policies (safe before DT) ---
run_step "2/9" "Masking + Projection Policies" "$SCRIPT_DIR/steps/03a_masking_projection.sql"

# --- Step 3: Lineage Pipeline (views + DT + secure views) ---
run_step "3/9" "Lineage Pipeline" "$SCRIPT_DIR/steps/04_lineage.sql"

# --- Step 4: Row Access, Join, Aggregation Policies (after DT) ---
run_step "4/9" "Row Access + Join + Aggregation Policies" "$SCRIPT_DIR/steps/03b_row_join_agg.sql"

# --- Step 5: Data Quality (DMFs) ---
run_step "5/9" "Data Quality (DMFs)" "$SCRIPT_DIR/steps/05_data_quality.sql"

# --- Step 6: Sharing ---
run_step "6/9" "Secure Share" "$SCRIPT_DIR/steps/06a_share.sql"

# --- Step 7: Agent ---
run_step "7a/9" "Stage + Healthcare Agent" "$SCRIPT_DIR/steps/06b_agent.sql"
run_query "7b/9" "Upload healthcare semantic model" \
    "PUT 'file://$SCRIPT_DIR/healthcare_analytics_model.yaml' @HORIZON_DEMO_DB.HEALTHCARE.SEMANTIC_MODELS AUTO_COMPRESS=FALSE OVERWRITE=TRUE"

# --- Step 8: Metadata Layer ---
run_step "8/9" "Metadata Layer (tags, pipeline log, catalog)" "$SCRIPT_DIR/steps/07_metadata_layer.sql"

# --- Step 9: AI Context ---
run_query "9a/9" "Upload metadata semantic model" \
    "PUT 'file://$SCRIPT_DIR/metadata_semantic_model.yaml' @HORIZON_DEMO_DB.HEALTHCARE.SEMANTIC_MODELS AUTO_COMPRESS=FALSE OVERWRITE=TRUE"
run_step "9b/9" "AI Context (Search + Enhanced Agent)" "$SCRIPT_DIR/steps/08_ai_context.sql"

# --- Summary ---
echo "============================================"
if [ $FAILED -eq 0 ]; then
    echo " DEPLOY COMPLETE - All steps succeeded"
else
    echo " DEPLOY FINISHED - $FAILED step(s) failed"
    echo " Check /tmp/horizon_deploy_*.log for details"
fi
echo ""
echo " Open horizon_catalog_demo.ipynb in Snowsight"
echo "============================================"

exit $FAILED
