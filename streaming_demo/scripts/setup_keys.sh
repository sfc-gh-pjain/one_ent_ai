#!/bin/bash
set -eo pipefail
# ============================================================
# Generate RSA key pair for Snowpipe Streaming authentication
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KEYS_DIR="${SCRIPT_DIR}/../keys"

mkdir -p "$KEYS_DIR"

if [ -f "$KEYS_DIR/rsa_key.p8" ]; then
    echo "Key pair already exists at $KEYS_DIR/rsa_key.p8"
    echo "Delete it first if you want to regenerate."
    echo ""
else
    echo "Generating RSA 2048-bit key pair..."
    openssl genrsa 2048 | openssl pkcs8 -topk8 -inform PEM -out "$KEYS_DIR/rsa_key.p8" -nocrypt
    openssl rsa -in "$KEYS_DIR/rsa_key.p8" -pubout -out "$KEYS_DIR/rsa_key.pub"
    chmod 600 "$KEYS_DIR/rsa_key.p8"
    echo "  Private key: $KEYS_DIR/rsa_key.p8"
    echo "  Public key:  $KEYS_DIR/rsa_key.pub"
    echo ""
fi

# Extract public key content
PUB_KEY=$(grep -v "^-" "$KEYS_DIR/rsa_key.pub" | tr -d '\n')

echo "============================================"
echo "  Next Steps"
echo "============================================"
echo ""
echo "1. Assign the public key to your Snowflake user:"
echo ""
echo "   ALTER USER <SERVICE_USER> SET RSA_PUBLIC_KEY='${PUB_KEY}';"
echo ""
echo "2. Create/update profile.json:"

# Write profile template
PROFILE="$KEYS_DIR/profile.json"
if [ ! -f "$PROFILE" ]; then
    cat > "$PROFILE" << 'PROFILE_EOF'
{
    "account": "<ACCOUNT_LOCATOR>",
    "user": "<SERVICE_USER>",
    "private_key_path": "keys/rsa_key.p8",
    "role": "SYSADMIN"
}
PROFILE_EOF
    echo "   Written to: $PROFILE"
else
    echo "   Already exists: $PROFILE"
fi

echo ""
echo "3. Run the demo:"
echo "   ./scripts/run_demo.sh"
echo ""
