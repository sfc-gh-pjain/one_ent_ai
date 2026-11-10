#!/bin/bash
set -eo pipefail
# Deploy Code Bundle to Snowflake
# Run this once initially, then again whenever src/ code changes.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="${SCRIPT_DIR}/../src"

CONNECTION="${CONNECTION:-my_conn}"
DATABASE="${DATABASE:-DEMO}"
SCHEMA="${SCHEMA:-HEALTHCARE_DEMO}"
WAREHOUSE="${WAREHOUSE:-MY_WH}"
BUNDLE_NAME="${BUNDLE_NAME:-CB_HEALTHCARE_SPARK}"

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

echo "Deploying Code Bundle: ${BUNDLE_NAME}"
echo "  Source: ${SRC_DIR}"
echo "  Target: ${DATABASE}.${SCHEMA}"

# Requires snow CLI dev version (3.20.0.dev0+)
# Install: uv tool install git+https://github.com/snowflakedb/snowflake-cli@code
snow bundle create "${BUNDLE_NAME}" \
    --source "${SRC_DIR}" \
    --exclude "__pycache__" \
    --overwrite \
    -c "${CONNECTION}" \
    --database "${DATABASE}" \
    --schema "${SCHEMA}" \
    --warehouse "${WAREHOUSE}"

echo "Done. Bundle '${BUNDLE_NAME}' is ready."
echo ""
echo "Also uploading to SSE stage for REST API (FROM stage) execution..."

# Create SSE stage if needed and upload files for anonymous execution
snow sql -c "${CONNECTION}" -q "
CREATE STAGE IF NOT EXISTS ${DATABASE}.${SCHEMA}.CB_SSE_STAGE ENCRYPTION = (TYPE = 'SNOWFLAKE_SSE');
"

for f in "${SRC_DIR}"/*.py "${SRC_DIR}"/code_bundle.yml; do
    [ -f "$f" ] && snow stage copy "$f" "@${DATABASE}.${SCHEMA}.CB_SSE_STAGE/" -c "${CONNECTION}" --overwrite
done

echo "Stage @${DATABASE}.${SCHEMA}.CB_SSE_STAGE updated."
