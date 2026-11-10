#!/bin/bash
set -eo pipefail
# ============================================
# Bootstrap Script — Healthcare Demo (SCOS + AI)
# Fully self-contained: installs Miniconda if needed, creates
# conda env, installs all dependencies, deploys everything.
# Only requires: bash, curl, and a Snowflake PAT.
# ============================================
# export SNOWFLAKE_PAT='your_token'
# export CONNECTION='your_connection_name'  # optional, defaults to 'my_conn'
# ./bootstrap.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "============================================"
echo "  Healthcare Demo Bootstrap (SCOS + AI)"
echo "============================================"
echo ""

# ---- Configuration (edit these or export before running) ----
CONNECTION="${CONNECTION:-my_conn}"
DATABASE="${DATABASE:-DEMO}"
SCHEMA="${SCHEMA:-HEALTHCARE_DEMO}"
WAREHOUSE="${WAREHOUSE:-MY_WH}"
SNOWFLAKE_ACCOUNT_URL="${SNOWFLAKE_ACCOUNT_URL:-<ACCOUNT_LOCATOR>.snowflakecomputing.com}"
SNOWFLAKE_PAT="${SNOWFLAKE_PAT:-}"

if [ -z "$SNOWFLAKE_PAT" ]; then
    echo "ERROR: SNOWFLAKE_PAT environment variable is not set."
    echo "Generate a PAT in Snowsight: User Menu > Programmatic Access Tokens > Generate"
    echo "Then: export SNOWFLAKE_PAT='your_token_here'"
    exit 1
fi

echo "  Connection:  $CONNECTION"
echo "  Account URL: $SNOWFLAKE_ACCOUNT_URL"
echo "  Database:    $DATABASE.$SCHEMA"
echo "  Warehouse:   $WAREHOUSE"
echo ""

# ============================================
# Phase 0: Install Miniconda (if conda not found)
# ============================================

if ! command -v conda >/dev/null 2>&1; then
    echo "=== Phase 0: Installing Miniconda ==="
    MINICONDA_DIR="$HOME/miniconda3"

    if [ -f "$MINICONDA_DIR/bin/conda" ]; then
        echo "  Miniconda found at $MINICONDA_DIR but not in PATH, adding..."
        export PATH="$MINICONDA_DIR/bin:$PATH"
    else
        echo "  conda not found. Installing Miniconda..."

        # Detect platform
        OS="$(uname -s)"
        ARCH="$(uname -m)"
        case "$OS" in
            Linux)  PLATFORM="Linux" ;;
            Darwin) PLATFORM="MacOSX" ;;
            *)      echo "ERROR: Unsupported OS: $OS"; exit 1 ;;
        esac
        case "$ARCH" in
            x86_64)  ARCH="x86_64" ;;
            aarch64|arm64) ARCH="arm64" ;;
            *)       echo "ERROR: Unsupported architecture: $ARCH"; exit 1 ;;
        esac

        INSTALLER_URL="https://repo.anaconda.com/miniconda/Miniconda3-latest-${PLATFORM}-${ARCH}.sh"
        INSTALLER="/tmp/miniconda_installer.sh"

        echo "  Downloading: $INSTALLER_URL"
        curl -fsSL "$INSTALLER_URL" -o "$INSTALLER"
        echo "  Installing to $MINICONDA_DIR..."
        bash "$INSTALLER" -b -p "$MINICONDA_DIR"
        rm -f "$INSTALLER"

        export PATH="$MINICONDA_DIR/bin:$PATH"
        echo "  Miniconda installed successfully."
    fi
    echo ""
fi

# ============================================
# Phase 1: Conda Environment + Dev CLI
# ============================================
echo "=== Phase 1: Setting up conda environment ==="

CONDA_ENV="e2edemo"

eval "$(conda shell.bash hook)"

if conda info --envs 2>/dev/null | grep -q "^${CONDA_ENV} "; then
    echo "  Conda env '$CONDA_ENV' exists, activating..."
    conda activate "$CONDA_ENV"
else
    echo "  Creating conda env '$CONDA_ENV' (Python 3.11)..."
    conda create -n "$CONDA_ENV" python=3.11 -y -q
    conda activate "$CONDA_ENV"
fi

# Ensure conda env bin is first in PATH (overrides system /Applications/SnowflakeCLI.app)
export PATH="$CONDA_PREFIX/bin:$PATH"

# Install all dependencies if dev CLI not present
if ! snow bundle --help >/dev/null 2>&1; then
    echo "  Installing dependencies from requirements.txt..."
    pip install -r "$SCRIPT_DIR/requirements.txt" 2>&1 | tail -5
fi

SNOW="snow"

echo "  Snow CLI version: $($SNOW --version 2>/dev/null || echo 'install failed')"
echo ""

# ============================================
# Phase 2: Snowflake Schema + Data Setup
# ============================================
echo "=== Phase 2: Setting up Snowflake schema and data ==="

ROW_COUNT=$($SNOW sql -c "$CONNECTION" -q "SELECT COUNT(*) AS CNT FROM ${DATABASE}.${SCHEMA}.RAW_PRESCRIPTIONS" --format JSON 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)[0]['CNT'])" 2>/dev/null || echo "0")

if [ "$ROW_COUNT" -gt "0" ]; then
    echo "  Data already exists ($ROW_COUNT rows in RAW_PRESCRIPTIONS), skipping..."
else
    echo "  Running schema setup..."
    $SNOW sql -f scos_pipeline/sql/01_setup.sql -c "$CONNECTION"

    echo "  Generating synthetic data..."
    python3 scos_pipeline/data_gen/generate_data.py --output-dir scos_pipeline/data

    echo "  Uploading to stage..."
    for f in scos_pipeline/data/*.csv; do
        $SNOW stage copy "$f" "@${DATABASE}.${SCHEMA}.DEMO_STAGE/data/" -c "$CONNECTION" --overwrite
    done

    echo "  Loading into tables..."
    $SNOW sql -c "$CONNECTION" -q "
    USE SCHEMA ${DATABASE}.${SCHEMA};
    COPY INTO DIM_DRUG FROM @DEMO_STAGE/data/dim_drug.csv FILE_FORMAT=(TYPE=CSV SKIP_HEADER=1 FIELD_OPTIONALLY_ENCLOSED_BY='\"' NULL_IF=('') EMPTY_FIELD_AS_NULL=TRUE) ON_ERROR='CONTINUE';
    COPY INTO DIM_TERRITORY FROM @DEMO_STAGE/data/dim_territory.csv FILE_FORMAT=(TYPE=CSV SKIP_HEADER=1 FIELD_OPTIONALLY_ENCLOSED_BY='\"' NULL_IF=('') EMPTY_FIELD_AS_NULL=TRUE) ON_ERROR='CONTINUE';
    COPY INTO DIM_REGION FROM @DEMO_STAGE/data/dim_region.csv FILE_FORMAT=(TYPE=CSV SKIP_HEADER=1 FIELD_OPTIONALLY_ENCLOSED_BY='\"' NULL_IF=('') EMPTY_FIELD_AS_NULL=TRUE) ON_ERROR='CONTINUE';
    COPY INTO DIM_THERAPEUTIC_AREA FROM @DEMO_STAGE/data/dim_therapeutic_area.csv FILE_FORMAT=(TYPE=CSV SKIP_HEADER=1 FIELD_OPTIONALLY_ENCLOSED_BY='\"' NULL_IF=('') EMPTY_FIELD_AS_NULL=TRUE) ON_ERROR='CONTINUE';
    COPY INTO RAW_HCP_PROFILES FROM @DEMO_STAGE/data/raw_hcp_profiles.csv FILE_FORMAT=(TYPE=CSV SKIP_HEADER=1 FIELD_OPTIONALLY_ENCLOSED_BY='\"' NULL_IF=('') EMPTY_FIELD_AS_NULL=TRUE) ON_ERROR='CONTINUE';
    COPY INTO RAW_PRESCRIPTIONS FROM @DEMO_STAGE/data/raw_prescriptions.csv FILE_FORMAT=(TYPE=CSV SKIP_HEADER=1 FIELD_OPTIONALLY_ENCLOSED_BY='\"' NULL_IF=('') EMPTY_FIELD_AS_NULL=TRUE) ON_ERROR='CONTINUE';
    COPY INTO RAW_HCP_ENGAGEMENTS FROM @DEMO_STAGE/data/raw_hcp_engagements.csv FILE_FORMAT=(TYPE=CSV SKIP_HEADER=1 FIELD_OPTIONALLY_ENCLOSED_BY='\"' NULL_IF=('') EMPTY_FIELD_AS_NULL=TRUE) ON_ERROR='CONTINUE';
    "
fi
echo ""

# ============================================
# Phase 3: Deploy Code Bundle (SCOS Pipeline)
# ============================================
echo "=== Phase 3: Deploying SCOS Spark Code Bundle ==="

$SNOW bundle create CB_HEALTHCARE_SPARK \
    --source scos_pipeline/src \
    --exclude "__pycache__" \
    --overwrite \
    -c "$CONNECTION" \
    --database "$DATABASE" --schema "$SCHEMA" --warehouse "$WAREHOUSE"

echo ""

# ============================================
# Phase 4: Run the SCOS Pipeline
# ============================================
echo "=== Phase 4: Executing SCOS pipeline (4 jobs) ==="

echo "  Job 1: Rx Metrics Load..."
$SNOW bundle execute CB_HEALTHCARE_SPARK --entrypoint 01_rx_metrics_load.py \
    -c "$CONNECTION" --database "$DATABASE" --schema "$SCHEMA" --warehouse "$WAREHOUSE" \
    -- --ds 2026-05-26

echo "  Job 2: HCP Classification (UDTF)..."
$SNOW bundle execute CB_HEALTHCARE_SPARK --entrypoint 02_hcp_classification.py \
    -c "$CONNECTION" --database "$DATABASE" --schema "$SCHEMA" --warehouse "$WAREHOUSE" \
    -- --ds 2026-05-26 --batch-size 50

echo "  Job 3: Engagement Merge..."
$SNOW bundle execute CB_HEALTHCARE_SPARK --entrypoint 03_engagement_merge.py \
    -c "$CONNECTION" --database "$DATABASE" --schema "$SCHEMA" --warehouse "$WAREHOUSE"

echo "  Job 4: Validate..."
$SNOW bundle execute CB_HEALTHCARE_SPARK --entrypoint 04_validate.py \
    -c "$CONNECTION" --database "$DATABASE" --schema "$SCHEMA" --warehouse "$WAREHOUSE"

echo "  All pipeline jobs passed."
echo ""

# ============================================
# Phase 5: Deploy AI Layer
# ============================================
echo "=== Phase 5: Deploying Snowflake AI layer ==="

# Create stages
$SNOW sql -c "$CONNECTION" -q "
CREATE STAGE IF NOT EXISTS ${DATABASE}.${SCHEMA}.SEMANTIC_MODELS ENCRYPTION = (TYPE = 'SNOWFLAKE_SSE');
CREATE STAGE IF NOT EXISTS ${DATABASE}.${SCHEMA}.CB_SSE_STAGE ENCRYPTION = (TYPE = 'SNOWFLAKE_SSE');
CREATE STAGE IF NOT EXISTS ${DATABASE}.${SCHEMA}.STREAMLIT_STAGE ENCRYPTION = (TYPE = 'SNOWFLAKE_SSE');
"

# Upload semantic model
echo "  Uploading semantic model..."
$SNOW stage copy ai_layer/src/pharma_commercial_intelligence.yaml \
    "@${DATABASE}.${SCHEMA}.SEMANTIC_MODELS/" -c "$CONNECTION" --overwrite

# Upload SCOS files to SSE stage
echo "  Uploading pipeline code to SSE stage..."
for f in scos_pipeline/src/*.py scos_pipeline/src/code_bundle.yml; do
    $SNOW stage copy "$f" "@${DATABASE}.${SCHEMA}.CB_SSE_STAGE/" -c "$CONNECTION" --overwrite
done

# Create Cortex Search view + service
echo "  Creating Cortex Search service..."
$SNOW sql -c "$CONNECTION" -q "
USE SCHEMA ${DATABASE}.${SCHEMA};

CREATE OR REPLACE VIEW HCP_SEARCH_V AS
SELECT
    h.HCP_ID,
    hp.HCP_NAME,
    h.SPECIALTY,
    h.STANDARDIZED_SPECIALTY,
    h.TIER,
    h.DECILE,
    t.TERRITORY_NAME,
    r.REGION_NAME,
    hp.HCP_NAME || ' - ' || h.SPECIALTY || ' (' || h.STANDARDIZED_SPECIALTY || '). ' ||
    'Tier: ' || h.TIER || '. Territory: ' || COALESCE(t.TERRITORY_NAME, 'Unknown') ||
    ', Region: ' || COALESCE(r.REGION_NAME, 'Unknown') AS SEARCH_TEXT
FROM HCP_TIERED_PROFILES h
LEFT JOIN RAW_HCP_PROFILES hp ON h.HCP_ID = hp.HCP_ID
LEFT JOIN DIM_TERRITORY t ON hp.TERRITORY_ID = t.TERRITORY_ID
LEFT JOIN DIM_REGION r ON t.REGION_ID = r.REGION_ID;

CREATE OR REPLACE CORTEX SEARCH SERVICE PHARMA_SEARCH_SERVICE
  ON SEARCH_TEXT
  ATTRIBUTES HCP_NAME, SPECIALTY, STANDARDIZED_SPECIALTY, TIER, TERRITORY_NAME, REGION_NAME
  WAREHOUSE = ${WAREHOUSE}
  TARGET_LAG = '1 hour'
  AS (SELECT SEARCH_TEXT, HCP_ID, HCP_NAME, SPECIALTY, STANDARDIZED_SPECIALTY, TIER, TERRITORY_NAME, REGION_NAME
      FROM HCP_SEARCH_V);
"

# Create AI-enriched table
echo "  Creating AI-enriched drugs table..."
$SNOW sql -c "$CONNECTION" -q "
USE SCHEMA ${DATABASE}.${SCHEMA};

CREATE OR REPLACE TABLE AI_ENRICHED_DRUGS AS
SELECT
  d.DRUG_ID,
  d.DRUG_NAME,
  d.GENERIC_NAME,
  d.THERAPEUTIC_AREA,
  d.INDICATION,
  d.DOSAGE_FORM,
  d.ANNUAL_REVENUE_MM,
  SNOWFLAKE.CORTEX.CLASSIFY_TEXT(
    d.DRUG_NAME || ' - ' || d.INDICATION,
    ['Oncology', 'Immunology', 'Cardiology', 'Neurology', 'Respiratory', 'Endocrinology', 'Dermatology', 'Infectious Disease']
  ):label::STRING AS THERAPEUTIC_AREA_PREDICTED,
  SNOWFLAKE.CORTEX.CLASSIFY_TEXT(
    d.DOSAGE_FORM || ' ' || d.INDICATION || ' revenue ' || d.ANNUAL_REVENUE_MM || 'M',
    ['High Risk - Specialty', 'Medium Risk - Branded', 'Low Risk - Generic']
  ):label::STRING AS RISK_CATEGORY,
  COALESCE(eng_sent.avg_sentiment, 0) AS AVG_NOTE_SENTIMENT
FROM DIM_DRUG d
LEFT JOIN (
    SELECT DRUG_ID, AVG(SENTIMENT_SCORE) AS avg_sentiment
    FROM RAW_HCP_ENGAGEMENTS
    GROUP BY DRUG_ID
) eng_sent ON d.DRUG_ID = eng_sent.DRUG_ID;
"

# Create Cortex Agent
echo "  Creating Cortex Agent..."
$SNOW sql -c "$CONNECTION" -q "
USE SCHEMA ${DATABASE}.${SCHEMA};

CREATE OR REPLACE AGENT PHARMA_INTELLIGENCE_AGENT
SPEC = 'tools:
  - tool_spec:
      type: cortex_search
      name: hcp_search
    tool_resources:
      cortex_search_service: ${DATABASE}.${SCHEMA}.PHARMA_SEARCH_SERVICE
  - tool_spec:
      type: cortex_analyst
      name: rx_analytics
    tool_resources:
      semantic_model_file: \"@${DATABASE}.${SCHEMA}.SEMANTIC_MODELS/pharma_commercial_intelligence.yaml\"
model: claude-3-5-sonnet
system_prompt: \"You are a pharmaceutical commercial intelligence assistant. Help users find HCPs, understand prescription trends, analyze engagement effectiveness, and optimize territory performance. Be concise and data-driven.\"';
"

# Deploy Streamlit app
echo "  Deploying Streamlit app..."
$SNOW stage copy ai_layer/streamlit/app.py \
    "@${DATABASE}.${SCHEMA}.STREAMLIT_STAGE/" -c "$CONNECTION" --overwrite

$SNOW sql -c "$CONNECTION" -q "
CREATE OR REPLACE STREAMLIT ${DATABASE}.${SCHEMA}.PHARMA_INTELLIGENCE_APP
  ROOT_LOCATION = '@${DATABASE}.${SCHEMA}.STREAMLIT_STAGE'
  MAIN_FILE = 'app.py'
  QUERY_WAREHOUSE = '${WAREHOUSE}'
  COMMENT = 'Pharma Commercial Intelligence - Cortex Analyst + Search + AI Functions + Agent';
"

echo ""

# ============================================
# Phase 6: Airflow Setup
# ============================================
echo "=== Phase 6: Airflow Setup ==="
echo ""
echo "  Airflow is installed in the 'e2edemo' conda env."
echo "  To start orchestration, run:"
echo ""
echo "    ./start_airflow.sh"
echo ""
echo "  Or manually:"
echo "    export AIRFLOW_HOME=$(pwd)/airflow/.airflow"
echo "    airflow db migrate"
echo "    airflow variables set snowflake_account_url '$SNOWFLAKE_ACCOUNT_URL'"
echo "    airflow variables set snowflake_pat '\$SNOWFLAKE_PAT'"
echo "    airflow variables set snowflake_role 'SYSADMIN'"
echo "    airflow variables set snowflake_warehouse '$WAREHOUSE'"
echo "    airflow variables set snowflake_database '$DATABASE'"
echo "    airflow variables set snowflake_schema '$SCHEMA'"
echo "    airflow standalone"
echo ""
echo "  Available DAGs:"
echo "    - healthcare_pipeline"
echo "    - crm_pipeline"
echo "    - dq_mdm_pipeline"
echo "    - swap_pipeline"
echo ""

# ============================================
# Summary
# ============================================
echo "============================================"
echo "  BOOTSTRAP COMPLETE"
echo "============================================"
echo ""
echo "  SCOS Pipeline:"
echo "    - Code Bundle: CB_HEALTHCARE_SPARK (4 jobs passed)"
echo "    - Tables: RX_METRICS_OUTPUT, HCP_TIERED_PROFILES, ENGAGEMENT_FINAL"
echo "    - Airflow DAG: healthcare_spark_pipeline (scos_pipeline/dags/)"
echo ""
echo "  AI Layer:"
echo "    - Cortex Analyst: @${DATABASE}.${SCHEMA}.SEMANTIC_MODELS/pharma_commercial_intelligence.yaml"
echo "    - Cortex Search: ${DATABASE}.${SCHEMA}.PHARMA_SEARCH_SERVICE"
echo "    - AI Enrichment: ${DATABASE}.${SCHEMA}.AI_ENRICHED_DRUGS"
echo "    - Cortex Agent: ${DATABASE}.${SCHEMA}.PHARMA_INTELLIGENCE_AGENT"
echo "    - Streamlit App: ${DATABASE}.${SCHEMA}.PHARMA_INTELLIGENCE_APP"
echo ""
echo "  Spark History UI:"
echo "    https://app.snowflake.com/<ORG>/<ACCOUNT_NAME>/#/compute/history/spark"
echo ""
echo "============================================"
