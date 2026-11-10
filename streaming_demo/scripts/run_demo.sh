#!/bin/bash
set -eo pipefail
# ============================================================
# Run Snowpipe Streaming Demo
# Streams HCP engagement events into Snowflake in real-time
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEMO_DIR="$(dirname "$SCRIPT_DIR")"
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
echo " Snowpipe Streaming Demo"
echo " Real-time HCP Engagement Events"
echo "======================================"
echo ""

# Install streaming SDK if needed
if ! python -c "import snowflake.ingest.streaming" 2>/dev/null; then
    echo "Installing snowpipe-streaming SDK..."
    pip install -r "$DEMO_DIR/requirements.txt" 2>&1 | tail -3
    echo ""
fi

# Step 1: Run setup SQL
echo ">>> Step 1: Creating table + pipe..."
snow sql -f "$DEMO_DIR/sql/01_setup.sql" -c "$CONNECTION" --quiet 2>&1 | tail -5
echo ""

# Step 2: Check for keys
if [ ! -f "$DEMO_DIR/keys/rsa_key.p8" ]; then
    echo "ERROR: RSA key pair not found."
    echo "Run: ./scripts/setup_keys.sh"
    echo "Then assign the public key to your Snowflake user."
    exit 1
fi

if [ ! -f "$DEMO_DIR/keys/profile.json" ]; then
    echo "ERROR: keys/profile.json not found."
    echo "Run: ./scripts/setup_keys.sh"
    exit 1
fi

# Step 3: Run the producer
echo ">>> Step 2: Streaming events (60 seconds at 50 events/sec)..."
echo ""
cd "$DEMO_DIR/src"
python stream_producer.py \
    --profile "$DEMO_DIR/keys/profile.json" \
    --database DEMO \
    --schema HEALTHCARE_DEMO \
    --table HCP_EVENTS_RT \
    --rate 50 \
    --duration 60 \
    --partitions 4

echo ""

# Step 4: Verify
echo ">>> Step 3: Verifying ingestion..."
snow sql -c "$CONNECTION" -q "
SELECT COUNT(*) AS total_events,
       MIN(EVENT_TIMESTAMP) AS earliest,
       MAX(EVENT_TIMESTAMP) AS latest,
       COUNT(DISTINCT HCP_ID) AS unique_hcps,
       COUNT(DISTINCT EVENT_TYPE) AS event_types
FROM DEMO.HEALTHCARE_DEMO.HCP_EVENTS_RT;
"

echo ""
echo "======================================"
echo " Streaming Demo Complete"
echo "======================================"
echo ""
echo "Run monitoring queries:"
echo "  snow sql -f $DEMO_DIR/sql/02_monitoring.sql -c $CONNECTION"
