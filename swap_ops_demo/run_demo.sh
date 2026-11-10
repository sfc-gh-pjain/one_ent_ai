#!/usr/bin/env bash
# ============================================================
# Deploy & Run: Blue/Green Zero-Copy Clone Swap Demo
# ============================================================
# Step 1: setup.sql (SYSADMIN) — creates DB, schemas, data, RBAC
# Step 2: blue_green_swap_demo.sql (SYSADMIN) — procedure + validation
# ============================================================
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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
echo " Blue/Green Swap Demo — Deploy & Run"
echo "======================================"
echo ""
echo "Connection: $CONNECTION"
echo ""

echo "▶ Step 1: Running setup.sql (creates DB, schemas, data, RBAC)..."
echo ""
snow sql -f "$SCRIPT_DIR/setup.sql" -c "$CONNECTION"

echo ""
echo "▶ Step 2: Running blue_green_swap_demo.sql (procedure + swap validation)..."
echo ""
snow sql -f "$SCRIPT_DIR/blue_green_swap_demo.sql" -c "$CONNECTION"

echo ""
echo "======================================"
echo " Demo Complete"
echo "======================================"
echo ""
echo "Objects created:"
echo "  Database:   SWAP_DEMO"
echo "  Schemas:    STAR_SCHEMA, STAGING, PROD"
echo "  Roles:      ETL_ROLE, ANALYST_ROLE"
echo "  Procedure:  SWAP_DEMO.STAR_SCHEMA.REFRESH_STAR_SCHEMA()"
echo ""
echo "To re-run the swap manually:"
echo "  snow sql -q \"CALL SWAP_DEMO.STAR_SCHEMA.REFRESH_STAR_SCHEMA();\" -c $CONNECTION"
echo ""
echo "To teardown:"
echo "  snow sql -q \"USE ROLE ACCOUNTADMIN; DROP DATABASE IF EXISTS SWAP_DEMO; DROP ROLE IF EXISTS ETL_ROLE; DROP ROLE IF EXISTS ANALYST_ROLE;\" -c $CONNECTION"
