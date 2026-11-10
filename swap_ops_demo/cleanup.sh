#!/usr/bin/env bash
# ============================================================
# Cleanup: Blue/Green Zero-Copy Clone Swap Demo
# Drops all objects created by setup.sql
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
echo " Blue/Green Swap Demo — Cleanup"
echo "======================================"
echo ""
echo "Connection: $CONNECTION"
echo ""

echo "▶ Running cleanup.sql..."
snow sql -f "$SCRIPT_DIR/cleanup.sql" -c "$CONNECTION"

echo ""
echo "  Done. All SWAP_DEMO objects removed."
