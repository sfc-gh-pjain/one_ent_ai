#!/bin/bash
set -eo pipefail
# ============================================================
# Deploy CRM Demo Pipeline
# Salesforce One-Hop Reduction (SCOS Code Bundle)
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CRM_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_DIR="$(cd "$CRM_DIR/.." && pwd)"

CONNECTION="${SNOW_CONNECTION:-my_conn}"
DATABASE="${DATABASE:-DEMO}"
SCHEMA="CRM_DEMO"
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

SNOW="snow"

echo "============================================"
echo "  CRM Demo Deploy (One-Hop Reduction)"
echo "============================================"
echo "  Connection: $CONNECTION"
echo "  Target:     $DATABASE.$SCHEMA"
echo ""

# ---- Phase 1: Schema + Tables ----
echo "--- Phase 1: Schema + Tables ---"
$SNOW sql -f "$CRM_DIR/sql/01_setup.sql" -c "$CONNECTION" --silent 2>&1 | tail -3
echo "  Schema and tables created."
echo ""

# ---- Phase 2: Generate + Load Data ----
echo "--- Phase 2: Generate + Load Data ---"

ROW_COUNT=$($SNOW sql -c "$CONNECTION" -q "SELECT COUNT(*) AS CNT FROM ${DATABASE}.${SCHEMA}.RAW_ACCOUNTS" --format JSON 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)[0]['CNT'])" 2>/dev/null || echo "0")

if [ "$ROW_COUNT" -gt "0" ]; then
    echo "  Data already exists ($ROW_COUNT accounts), skipping..."
else
    echo "  Generating synthetic CRM data..."
    python3 "$CRM_DIR/data_gen/generate_crm_data.py" --output-dir "$CRM_DIR/data"

    echo "  Uploading to stage..."
    for f in "$CRM_DIR/data"/*.csv; do
        $SNOW stage copy "$f" "@${DATABASE}.${SCHEMA}.CRM_STAGE/data/" -c "$CONNECTION" --overwrite 2>&1 | tail -1
    done

    echo "  Loading into tables..."
    $SNOW sql -c "$CONNECTION" -q "
    USE SCHEMA ${DATABASE}.${SCHEMA};
    COPY INTO RAW_ACCOUNTS FROM @CRM_STAGE/data/raw_accounts.csv FILE_FORMAT=(TYPE=CSV SKIP_HEADER=1 FIELD_OPTIONALLY_ENCLOSED_BY='\"' NULL_IF=('') EMPTY_FIELD_AS_NULL=TRUE) ON_ERROR='CONTINUE';
    COPY INTO RAW_OPPORTUNITIES FROM @CRM_STAGE/data/raw_opportunities.csv FILE_FORMAT=(TYPE=CSV SKIP_HEADER=1 FIELD_OPTIONALLY_ENCLOSED_BY='\"' NULL_IF=('') EMPTY_FIELD_AS_NULL=TRUE) ON_ERROR='CONTINUE';
    COPY INTO RAW_CASES FROM @CRM_STAGE/data/raw_cases.csv FILE_FORMAT=(TYPE=CSV SKIP_HEADER=1 FIELD_OPTIONALLY_ENCLOSED_BY='\"' NULL_IF=('') EMPTY_FIELD_AS_NULL=TRUE) ON_ERROR='CONTINUE';
    " 2>&1 | grep -i "LOADED\|rows_loaded\|status" | head -6
fi
echo ""

# ---- Phase 3: Deploy Code Bundle ----
echo "--- Phase 3: Deploy Code Bundle ---"
$SNOW bundle create CB_CRM_SPARK \
    --source "$CRM_DIR/src" \
    --exclude "__pycache__" \
    --overwrite \
    -c "$CONNECTION" \
    --database "$DATABASE" --schema "$SCHEMA" --warehouse "$WAREHOUSE"
echo ""

# ---- Phase 4: Execute Pipeline ----
echo "--- Phase 4: Execute Pipeline (3 jobs) ---"

echo "  Job 1: Customer 360 Enrichment..."
$SNOW bundle execute CB_CRM_SPARK --entrypoint 01_customer_360_enrich.py \
    -c "$CONNECTION" --database "$DATABASE" --schema "$SCHEMA" --warehouse "$WAREHOUSE"

echo "  Job 2: Pipeline Forecast..."
$SNOW bundle execute CB_CRM_SPARK --entrypoint 02_pipeline_forecast.py \
    -c "$CONNECTION" --database "$DATABASE" --schema "$SCHEMA" --warehouse "$WAREHOUSE"

echo "  Job 3: Validate..."
$SNOW bundle execute CB_CRM_SPARK --entrypoint 03_validate.py \
    -c "$CONNECTION" --database "$DATABASE" --schema "$SCHEMA" --warehouse "$WAREHOUSE"

echo ""
echo "============================================"
echo "  CRM DEMO DEPLOY COMPLETE"
echo "============================================"
echo ""
echo "  Tables:"
echo "    - CUSTOMER_360 (account health scores + segments)"
echo "    - PIPELINE_FORECAST (weighted pipeline + velocity)"
echo ""
echo "  Spark History:"
echo "    https://app.snowflake.com/<ORG>/<ACCOUNT_NAME>/#/compute/history/spark"
echo ""
