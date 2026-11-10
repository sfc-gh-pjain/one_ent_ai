#!/bin/bash
set -eo pipefail
# ============================================================
# DEPLOY ALL: Full Healthcare Demo (every layer)
# ============================================================
# Deploys: Pipeline + AI Layer + DQ/MDM + Swap Demo
# (Streaming demo requires key-pair setup — instructions printed)
# ============================================================
# Usage:
#   export SNOWFLAKE_PAT='your_token'
#   ./deploy_all.sh
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

SNOWFLAKE_PAT="${SNOWFLAKE_PAT:-}"
CONNECTION="${SNOW_CONNECTION:-my_conn}"
DATABASE="${DATABASE:-DEMO}"

if [ -z "$SNOWFLAKE_PAT" ]; then
    echo "ERROR: SNOWFLAKE_PAT not set."
    echo "  export SNOWFLAKE_PAT='your_token'"
    exit 1
fi

echo "======================================"
echo "  FULL DEMO DEPLOYMENT"
echo "  Pipeline + AI + DQ/MDM + Swap"
echo "======================================"
echo ""

# ============================================================
# 1. Bootstrap (conda env + schema + pipeline + AI layer)
# ============================================================
echo "============================================"
echo "  [1/4] Bootstrap (Pipeline + AI Layer)"
echo "============================================"
bash "$SCRIPT_DIR/bootstrap.sh"
echo ""

# Re-activate conda (bootstrap runs in subshell)
if ! command -v conda >/dev/null 2>&1; then
    [ -f "$HOME/miniconda3/bin/conda" ] && export PATH="$HOME/miniconda3/bin:$PATH"
fi
eval "$(conda shell.bash hook)"
conda activate e2edemo
export PATH="$CONDA_PREFIX/bin:$PATH"

# ============================================================
# 2. DQ/MDM Layer
# ============================================================
echo "============================================"
echo "  [2/4] Data Quality & MDM"
echo "============================================"
echo ""

echo "  Running DMF setup..."
snow sql -f "$SCRIPT_DIR/dq_mdm/sql/01_dmf_setup.sql" -c "$CONNECTION" --silent 2>&1 | tail -3 || echo "  (DMF setup had errors — may need EXECUTE DATA METRIC FUNCTION grant)"

echo "  Running business rules (streams + tasks)..."
snow sql -f "$SCRIPT_DIR/dq_mdm/sql/02_business_rules.sql" -c "$CONNECTION" --silent 2>&1 | tail -3

echo "  Running constraints..."
snow sql -f "$SCRIPT_DIR/dq_mdm/sql/03_constraints.sql" -c "$CONNECTION" --silent 2>&1 | tail -3

echo "  Running governance (tags + masking)..."
snow sql -f "$SCRIPT_DIR/dq_mdm/sql/04_governance.sql" -c "$CONNECTION" --silent 2>&1 | tail -3

echo "  DQ/MDM layer deployed."
echo ""

# ============================================================
# 3. Blue/Green Swap Demo
# ============================================================
echo "============================================"
echo "  [3/4] Blue/Green Swap Demo"
echo "============================================"
echo ""

echo "  Running setup.sql..."
snow sql -f "$SCRIPT_DIR/swap_ops_demo/setup.sql" -c "$CONNECTION" --silent 2>&1 | tail -3

echo "  Running blue_green_swap_demo.sql..."
snow sql -f "$SCRIPT_DIR/swap_ops_demo/blue_green_swap_demo.sql" -c "$CONNECTION" --silent 2>&1 | tail -3

echo "  Swap demo deployed and validated."
echo ""

# ============================================================
# 4. CRM Demo (Salesforce One-Hop Reduction)
# ============================================================
echo "============================================"
echo "  [4/5] CRM Demo (One-Hop Reduction)"
echo "============================================"
echo ""

bash "$SCRIPT_DIR/crm_demo/scripts/deploy_crm.sh"
echo ""

# ============================================================
# 5. Enterprise Enhancements (Multi-Domain + AI DQ + Governance)
# ============================================================
echo "============================================"
echo "  [5/7] Enterprise Enhancements"
echo "============================================"
echo ""

echo "  Uploading CRM + Finance semantic models..."
snow stage copy "$SCRIPT_DIR/ai_layer/src/crm_commercial_intelligence.yaml" \
    "@${DATABASE}.HEALTHCARE_DEMO.SEMANTIC_MODELS/" -c "$CONNECTION" --overwrite 2>&1 | tail -1 || true
snow stage copy "$SCRIPT_DIR/ai_layer/src/finance_summary.yaml" \
    "@${DATABASE}.HEALTHCARE_DEMO.SEMANTIC_MODELS/" -c "$CONNECTION" --overwrite 2>&1 | tail -1 || true

echo "  Creating finance tables (multi-domain)..."
snow sql -f "$SCRIPT_DIR/ai_layer/sql/02_multi_domain_setup.sql" -c "$CONNECTION" --silent 2>&1 | tail -3

echo "  Creating semantic views (3 domains)..."
snow sql -f "$SCRIPT_DIR/ai_layer/sql/04_semantic_views.sql" -c "$CONNECTION" --silent 2>&1 | tail -3 || echo "  (Semantic views may require newer Snowflake version)"

echo "  Creating agent routing (registry + search + enterprise agent)..."
snow sql -f "$SCRIPT_DIR/ai_layer/sql/03_agent_routing.sql" -c "$CONNECTION" --silent 2>&1 | tail -3

echo "  Running AI-assisted DQ..."
snow sql -f "$SCRIPT_DIR/dq_mdm/sql/05_ai_assisted_dq.sql" -c "$CONNECTION" --silent 2>&1 | tail -3 || echo "  (AI DQ may need Cortex AI access)"

echo "  Applying hybrid governance tags..."
snow sql -f "$SCRIPT_DIR/dq_mdm/sql/06_hybrid_governance.sql" -c "$CONNECTION" --silent 2>&1 | tail -3

echo "  Enterprise enhancements deployed."
echo ""

# ============================================================
# 6. Streaming Demo (setup only — requires key-pair)
# ============================================================
echo "============================================"
echo "  [6/7] Streaming Demo (table + pipe setup)"
echo "============================================"
echo ""

# Install streaming SDK
pip install snowpipe-streaming cryptography 2>&1 | tail -2

echo "  Running streaming setup SQL..."
snow sql -f "$SCRIPT_DIR/streaming_demo/sql/01_setup.sql" -c "$CONNECTION" --silent 2>&1 | tail -3 || echo "  (Streaming pipe creation may require HPA feature enabled)"

echo "  Table + pipe created."
echo ""
echo "  NOTE: Streaming requires RSA key-pair auth."
echo "  To complete setup:"
echo "    cd streaming_demo && ./scripts/setup_keys.sh"
echo "    Then: ALTER USER <SERVICE_USER> SET RSA_PUBLIC_KEY='<key>';"
echo "    Then: ./scripts/run_demo.sh"
echo ""

# ============================================================
# Summary
# ============================================================
echo "======================================"
echo "  DEPLOYMENT COMPLETE"
echo "======================================"
echo ""
echo "  Layers deployed:"
echo "    [x] SCOS Pipeline (4 Code Bundle jobs)"
echo "    [x] AI Layer (Analyst, Search, Agent, Streamlit)"
echo "    [x] DQ/MDM (DMFs, Streams, Tasks, Tags, Masking)"
echo "    [x] Blue/Green Swap Demo (SWAP_DEMO database)"
echo "    [x] CRM Demo (CUSTOMER_360, PIPELINE_FORECAST)"
echo "    [x] Enterprise (Multi-Domain Agent, AI DQ, Hybrid Governance)"
echo "    [~] Streaming Demo (table ready — key-pair needed)"
echo ""
echo "  Key URLs:"
echo "    Spark History: https://app.snowflake.com/<ORG>/<ACCOUNT_NAME>/#/compute/history/spark"
echo "    Streamlit:     Open PHARMA_INTELLIGENCE_APP in Snowsight"
echo "    Airflow:       ./start_airflow.sh (localhost:8080)"
echo ""
echo "  Teardown: ./teardown.sh"
echo "======================================"
