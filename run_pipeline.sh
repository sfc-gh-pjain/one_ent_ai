#!/bin/bash
set -eo pipefail
# ============================================
# Run the SCOS Pipeline (assumes bootstrap already completed)
# Usage: conda activate e2edemo && ./run_pipeline.sh
#    or: ./run_pipeline.sh (auto-activates conda env)
# ============================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

CONNECTION="${CONNECTION:-my_conn}"
DATABASE="${DATABASE:-DEMO}"
SCHEMA="${SCHEMA:-HEALTHCARE_DEMO}"
WAREHOUSE="${WAREHOUSE:-MY_WH}"

# Activate conda env if not already active
CONDA_ENV="e2edemo"
if [[ "${CONDA_DEFAULT_ENV:-}" != "$CONDA_ENV" ]]; then
    # Ensure conda is in PATH
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
SNOW="snow"

echo "============================================"
echo "  Running Healthcare SCOS Pipeline"
echo "  CLI: $($SNOW --version)"
echo "  Target: $DATABASE.$SCHEMA"
echo "============================================"
echo ""

echo "=== Deploying Code Bundle ==="
$SNOW bundle create CB_HEALTHCARE_SPARK \
    --source scos_pipeline/src \
    --exclude "__pycache__" \
    --overwrite \
    -c "$CONNECTION" \
    --database "$DATABASE" --schema "$SCHEMA" --warehouse "$WAREHOUSE"
echo ""

echo "=== Job 1: Rx Metrics Load ==="
$SNOW bundle execute CB_HEALTHCARE_SPARK --entrypoint 01_rx_metrics_load.py \
    -c "$CONNECTION" --database "$DATABASE" --schema "$SCHEMA" --warehouse "$WAREHOUSE" \
    -- --ds 2026-05-26
echo ""

echo "=== Job 2: HCP Classification (UDTF) ==="
$SNOW bundle execute CB_HEALTHCARE_SPARK --entrypoint 02_hcp_classification.py \
    -c "$CONNECTION" --database "$DATABASE" --schema "$SCHEMA" --warehouse "$WAREHOUSE" \
    -- --ds 2026-05-26 --batch-size 50
echo ""

echo "=== Job 3: Engagement Merge ==="
$SNOW bundle execute CB_HEALTHCARE_SPARK --entrypoint 03_engagement_merge.py \
    -c "$CONNECTION" --database "$DATABASE" --schema "$SCHEMA" --warehouse "$WAREHOUSE"
echo ""

echo "=== Job 4: Validate ==="
$SNOW bundle execute CB_HEALTHCARE_SPARK --entrypoint 04_validate.py \
    -c "$CONNECTION" --database "$DATABASE" --schema "$SCHEMA" --warehouse "$WAREHOUSE"
echo ""

echo "=== Execution History ==="
$SNOW bundle history \
    -c "$CONNECTION" --database "$DATABASE" --schema "$SCHEMA" --result-limit 5
echo ""

echo "============================================"
echo "  PIPELINE COMPLETE — ALL JOBS PASSED"
echo "============================================"
