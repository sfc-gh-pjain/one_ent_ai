# Service User Setup & Authentication Guide

This guide covers how to set up a service account for programmatic access to Snowflake (REST API, Snow CLI, Airflow, Spark Connect) — especially for Organization Accounts using Okta SSO.

---

## Authentication Options Overview

| Method | Token Type Header | Interactive Login | Okta Org Compatible | Recommended For |
|--------|-------------------|-------------------|---------------------|-----------------|
| PAT | `PROGRAMMATIC_ACCESS_TOKEN` | Yes (to generate) | Bypasses SSO | Dev/demo environments |
| Key-Pair JWT | `KEYPAIR_JWT` | No | Yes | Production automation, Airflow, CI/CD |
| External OAuth (Okta) | `OAUTH` | Depends on flow | Native | User-context apps, delegated access |

---

## Option 1: PAT (Programmatic Access Token)

**How it works:** A user generates a long-lived token in Snowsight. The token acts as that user's credentials.

**Pros:** Simple to set up, no infrastructure needed.
**Cons:** User-bound (not true service identity), requires interactive generation, bypasses SSO policies.

### Setup

1. Log into Snowsight as the service user
2. Navigate to: User Menu > Programmatic Access Tokens > Generate
3. Copy the token

### Usage in REST API

```
Authorization: Bearer <pat_token>
X-Snowflake-Authorization-Token-Type: PROGRAMMATIC_ACCESS_TOKEN
```

### Usage in Snow CLI (`config.toml`)

```toml
[connections.svc]
account = "your_org-your_account"
user = "SVC_USER"
authenticator = "PROGRAMMATIC_ACCESS_TOKEN"
password = "<pat_token>"
role = "SYSADMIN"
warehouse = "MY_WH"
```

### Limitations

- Token is tied to the user who created it
- Max expiry varies by account settings
- Does not integrate with Okta SSO enforcement
- If the user is deactivated, token stops working

---

## Option 2: Key-Pair JWT (Recommended for Automation)

**How it works:** An RSA key pair is generated. The public key is registered with a Snowflake user. A JWT is generated locally using the private key and passed as a Bearer token.

**Pros:** No interactive login, works with org accounts, standard for service accounts, rotatable.
**Cons:** Requires key management, slightly more setup.

### Setup

#### Step 1: Generate RSA Key Pair

```bash
# Generate 2048-bit private key (no passphrase for automation)
openssl genrsa 2048 | openssl pkcs8 -topk8 -inform PEM -out rsa_key.p8 -nocrypt

# Extract public key
openssl rsa -in rsa_key.p8 -pubout -out rsa_key.pub

# Get the public key body (no header/footer) for Snowflake
grep -v "BEGIN\|END" rsa_key.pub | tr -d '\n'
```

#### Step 2: Create Service User in Snowflake

```sql
-- Run as ACCOUNTADMIN or USERADMIN
USE ROLE USERADMIN;

CREATE USER SVC_PIPELINE
    TYPE = SERVICE
    DEFAULT_ROLE = SYSADMIN
    DEFAULT_WAREHOUSE = MY_WH
    COMMENT = 'Service account for pipeline automation';

-- Assign the public key
ALTER USER SVC_PIPELINE SET RSA_PUBLIC_KEY = 'MIIBIjANBgkqh...your_key_here...';

-- Grant role
USE ROLE SECURITYADMIN;
GRANT ROLE SYSADMIN TO USER SVC_PIPELINE;
```

#### Step 3: Generate JWT for REST API Calls

```python
import jwt
import time
import hashlib
import base64
from cryptography.hazmat.primitives import serialization

def generate_jwt(account, user, private_key_path):
    """Generate a Snowflake-compatible JWT token."""
    # Account identifier: ORG-ACCOUNT in uppercase
    account_id = account.upper().replace(".", "-")
    qualified_user = f"{account_id}.{user.upper()}"

    # Load private key
    with open(private_key_path, "rb") as f:
        private_key = serialization.load_pem_private_key(f.read(), password=None)

    # Get public key fingerprint
    public_key_der = private_key.public_key().public_bytes(
        serialization.Encoding.DER,
        serialization.PublicFormat.SubjectPublicKeyInfo
    )
    sha256_hash = hashlib.sha256(public_key_der).digest()
    fingerprint = "SHA256:" + base64.b64encode(sha256_hash).decode("utf-8")

    now = int(time.time())
    payload = {
        "iss": f"{qualified_user}.{fingerprint}",
        "sub": qualified_user,
        "iat": now,
        "exp": now + 3600,  # 1 hour
    }

    return jwt.encode(payload, private_key, algorithm="RS256")


# Usage
token = generate_jwt("MY_ORG-MY_ACCOUNT", "SVC_PIPELINE", "rsa_key.p8")
```

#### Step 4: Use in REST API

```
Authorization: Bearer <jwt_token>
X-Snowflake-Authorization-Token-Type: KEYPAIR_JWT
```

#### Step 5: Use in Snow CLI

```toml
[connections.svc_keypair]
account = "your_org-your_account"
user = "SVC_PIPELINE"
authenticator = "SNOWFLAKE_JWT"
private_key_file = "/path/to/rsa_key.p8"
role = "SYSADMIN"
warehouse = "MY_WH"
database = "DEMO"
```

#### Step 6: Use in Airflow

There are three approaches for Airflow integration with Snowflake authentication:

##### Approach A: Custom REST API Plugin with Key-Pair JWT (Current Architecture)

This is what this project uses — a custom plugin (`airflow/plugins/snowflake_executor.py`) that calls the Snowflake SQL REST API directly. To switch from PAT to Key-Pair:

**Airflow Variables to set:**

```bash
airflow variables set snowflake_account_url 'your_org-your_account.snowflakecomputing.com'
airflow variables set snowflake_service_user 'SVC_PIPELINE'
airflow variables set snowflake_role 'SYSADMIN'
airflow variables set snowflake_warehouse 'MY_WH'
airflow variables set snowflake_database 'DEMO'
# Store the private key path (file must be accessible to Airflow worker)
airflow variables set snowflake_private_key_path '/opt/airflow/keys/rsa_key.p8'
# Auth mode toggle
airflow variables set snowflake_auth_mode 'keypair'  # or 'pat'
```

**Updated `airflow/plugins/snowflake_executor.py` — `get_config()` with multi-auth support:**

```python
import jwt
import time
import hashlib
import base64
from cryptography.hazmat.primitives import serialization
from airflow.models import Variable


def _generate_jwt_token(account, user, private_key_path):
    """Generate a Snowflake-compatible JWT from RSA private key."""
    # Account must be ORG-ACCOUNT format, uppercase
    account_id = account.split(".")[0].upper().replace("-", "-")
    qualified_user = f"{account_id}.{user.upper()}"

    with open(private_key_path, "rb") as f:
        private_key = serialization.load_pem_private_key(f.read(), password=None)

    # Compute public key fingerprint
    public_key_der = private_key.public_key().public_bytes(
        serialization.Encoding.DER,
        serialization.PublicFormat.SubjectPublicKeyInfo
    )
    sha256_hash = hashlib.sha256(public_key_der).digest()
    fingerprint = "SHA256:" + base64.b64encode(sha256_hash).decode("utf-8")

    now = int(time.time())
    payload = {
        "iss": f"{qualified_user}.{fingerprint}",
        "sub": qualified_user,
        "iat": now,
        "exp": now + 3600,
    }
    return jwt.encode(payload, private_key, algorithm="RS256")


def get_config():
    """Read Snowflake config from Airflow Variables with multi-auth support."""
    auth_mode = Variable.get("snowflake_auth_mode", default_var="pat")
    account_url = Variable.get("snowflake_account_url")

    config = {
        "account_url": account_url,
        "role": Variable.get("snowflake_role", default_var="SYSADMIN"),
        "warehouse": Variable.get("snowflake_warehouse", default_var="MY_WH"),
        "database": Variable.get("snowflake_database", default_var="DEMO"),
        "schema": Variable.get("snowflake_schema", default_var="HEALTHCARE_DEMO"),
    }

    if auth_mode == "keypair":
        user = Variable.get("snowflake_service_user")
        key_path = Variable.get("snowflake_private_key_path")
        # Extract account identifier from URL (org-account.snowflakecomputing.com)
        account = account_url.replace(".snowflakecomputing.com", "")
        config["token"] = _generate_jwt_token(account, user, key_path)
        config["token_type"] = "KEYPAIR_JWT"
    elif auth_mode == "oauth":
        config["token"] = Variable.get("snowflake_oauth_token")
        config["token_type"] = "OAUTH"
    else:  # pat (default)
        config["token"] = Variable.get("snowflake_pat")
        config["token_type"] = "PROGRAMMATIC_ACCESS_TOKEN"

    return config


def _get_headers(config):
    return {
        "Authorization": f"Bearer {config['token']}",
        "X-Snowflake-Authorization-Token-Type": config["token_type"],
        "Content-Type": "application/json",
        "Accept": "application/json",
        "User-Agent": "airflow-demo/1.0",
    }
```

**Key points:**
- JWT is regenerated on every task execution (tokens expire in 1 hour)
- Private key file must be readable by the Airflow worker process
- No secrets stored in Airflow Variables (only a file path reference)
- Toggle between auth modes by changing one Variable (`snowflake_auth_mode`)

##### Approach B: Snowflake Airflow Provider (apache-airflow-providers-snowflake)

If you prefer using the official Snowflake provider instead of raw REST API:

```bash
pip install apache-airflow-providers-snowflake
```

**Create an Airflow Connection (UI or CLI):**

```bash
airflow connections add snowflake_default \
    --conn-type snowflake \
    --conn-login SVC_PIPELINE \
    --conn-host your_org-your_account.snowflakecomputing.com \
    --conn-schema HEALTHCARE_DEMO \
    --conn-extra '{
        "account": "your_org-your_account",
        "warehouse": "MY_WH",
        "database": "DEMO",
        "role": "SYSADMIN",
        "authenticator": "snowflake_jwt",
        "private_key_file": "/opt/airflow/keys/rsa_key.p8"
    }'
```

**Usage in DAG with SnowflakeOperator:**

```python
from airflow.providers.snowflake.operators.snowflake import SnowflakeOperator

execute_bundle = SnowflakeOperator(
    task_id="run_rx_metrics",
    snowflake_conn_id="snowflake_default",
    sql="""
        EXECUTE CODE BUNDLE CB_HEALTHCARE_SPARK
        ENTRYPOINT = '01_rx_metrics_load.py'
        ARGUMENTS = ('--ds', '{{ ds }}')
    """,
)
```

**Pros:** Standard Airflow pattern, connection management in UI, built-in retries.
**Cons:** SnowflakeOperator is synchronous (blocks the worker). For long-running Code Bundle jobs, you may still need the async submit+poll pattern from the custom plugin.

##### Approach C: Hybrid — Provider Connection + Custom Polling

Best of both worlds: use the Snowflake provider for connection/auth management, but keep async polling for Code Bundle jobs:

```python
from airflow.providers.snowflake.hooks.snowflake import SnowflakeHook

def submit_and_wait_via_hook(entrypoint, bundle_name, **kwargs):
    """Use SnowflakeHook for auth, custom polling for async execution."""
    hook = SnowflakeHook(snowflake_conn_id="snowflake_default")
    conn = hook.get_conn()
    cursor = conn.cursor()

    sql = f"EXECUTE CODE BUNDLE {bundle_name} ENTRYPOINT = '{entrypoint}'"
    cursor.execute_async(sql)
    query_id = cursor.sfqid

    # Poll until done
    while conn.is_still_running(conn.get_query_status(query_id)):
        time.sleep(15)

    status = conn.get_query_status_throw_if_error(query_id)
    logger.info(f"Job {query_id} completed with status: {status}")
    return query_id
```

##### Comparison Table

| Approach | Auth Management | Async Support | Code Bundles | Complexity |
|----------|----------------|---------------|--------------|------------|
| A: Custom REST plugin | Airflow Variables | Yes (built-in polling) | Yes | Medium |
| B: Snowflake Provider | Airflow Connections (UI) | No (blocks worker) | Partial | Low |
| C: Hybrid (Provider + custom) | Airflow Connections (UI) | Yes (execute_async) | Yes | Medium |

**Recommendation:** For this demo, Approach A (custom REST plugin) works best because Code Bundle execution is async and can take 5-15 minutes. For production, Approach C gives you proper connection management with async execution.

##### Securing the Private Key in Airflow

For production deployments:

```bash
# Option 1: Mount as a Kubernetes secret (if running on K8s)
# The key is injected as a volume mount at /opt/airflow/keys/

# Option 2: Use Airflow's built-in Secrets Backend
# Store the private key content (not path) in a secrets manager
airflow connections add snowflake_default \
    --conn-extra '{"private_key_content": "{{ vault_secret }}"}'

# Option 3: Use environment variable for key content
# Set AIRFLOW_CONN_SNOWFLAKE_DEFAULT as a connection URI with key embedded

# Option 4: For local dev, file permission is sufficient
chmod 600 /path/to/rsa_key.p8
```

### Key Rotation

```sql
-- Set a second key (allows zero-downtime rotation)
ALTER USER SVC_PIPELINE SET RSA_PUBLIC_KEY_2 = 'MIIBIjANBgkqh...new_key...';

-- After confirming new key works, remove old one
ALTER USER SVC_PIPELINE UNSET RSA_PUBLIC_KEY;

-- Promote key 2 to key 1
ALTER USER SVC_PIPELINE SET RSA_PUBLIC_KEY = 'MIIBIjANBgkqh...new_key...';
ALTER USER SVC_PIPELINE UNSET RSA_PUBLIC_KEY_2;
```

---

## Option 3: External OAuth (Okta)

**How it works:** Snowflake trusts Okta as an authorization server. Users (or service apps) get an OAuth access token from Okta and pass it directly to Snowflake.

**Pros:** Native Okta integration, SSO-consistent, supports both user and machine-to-machine flows.
**Cons:** Requires Okta admin setup, Security Integration configuration, token refresh handling.

### Setup

#### Step 1: Configure Okta Authorization Server

In Okta Admin Console:
1. Create a new Authorization Server (or use the default `https://your-org.okta.com/oauth2/default`)
2. Add a scope: `session:role:SYSADMIN` (one scope per Snowflake role)
3. Create a client app:
   - For service accounts: use **Client Credentials** grant type
   - For user-context: use **Authorization Code** grant type
4. Note the `client_id`, `client_secret`, and authorization server URL

#### Step 2: Create Security Integration in Snowflake

```sql
USE ROLE ACCOUNTADMIN;

CREATE OR REPLACE SECURITY INTEGRATION OKTA_OAUTH
    TYPE = EXTERNAL_OAUTH
    ENABLED = TRUE
    EXTERNAL_OAUTH_TYPE = OKTA
    EXTERNAL_OAUTH_ISSUER = 'https://your-org.okta.com/oauth2/default'
    EXTERNAL_OAUTH_TOKEN_USER_MAPPING_CLAIM = 'sub'
    EXTERNAL_OAUTH_SNOWFLAKE_USER_MAPPING_ATTRIBUTE = 'LOGIN_NAME'
    EXTERNAL_OAUTH_JWS_KEYS_URL = 'https://your-org.okta.com/oauth2/default/v1/keys'
    EXTERNAL_OAUTH_AUDIENCE_LIST = ('https://your_account.snowflakecomputing.com')
    EXTERNAL_OAUTH_SCOPE_MAPPING_ATTRIBUTE = 'scp'
    EXTERNAL_OAUTH_ANY_ROLE_MODE = 'ENABLE';
```

#### Step 3: Get Token from Okta (Client Credentials Flow)

```bash
# Machine-to-machine token request
curl -X POST https://your-org.okta.com/oauth2/default/v1/token \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials" \
  -d "client_id=YOUR_CLIENT_ID" \
  -d "client_secret=YOUR_CLIENT_SECRET" \
  -d "scope=session:role:SYSADMIN"
```

Response:
```json
{
  "access_token": "eyJraWQiOi...",
  "token_type": "Bearer",
  "expires_in": 3600
}
```

#### Step 4: Use in REST API

```
Authorization: Bearer <okta_access_token>
X-Snowflake-Authorization-Token-Type: OAUTH
```

#### Step 5: Use in Snow CLI

```toml
[connections.svc_oauth]
account = "your_org-your_account"
user = "SVC_PIPELINE"
authenticator = "oauth"
token = "<okta_access_token>"
role = "SYSADMIN"
warehouse = "MY_WH"
```

Note: Snow CLI doesn't natively refresh OAuth tokens — you'd need a wrapper script.

### Okta User Mapping

The Okta `sub` claim must match a Snowflake `LOGIN_NAME`:

```sql
-- Create user that maps to Okta subject
CREATE USER SVC_PIPELINE
    LOGIN_NAME = 'svc_pipeline@your-org.com'
    DEFAULT_ROLE = SYSADMIN;
```

---

## Recommendation

| Environment | Use This |
|-------------|----------|
| **Local development / demos** | PAT (simplest, already working) |
| **Production Airflow / CI/CD** | Key-Pair JWT on a TYPE=SERVICE user |
| **User-facing apps (Tableau, custom)** | External OAuth with Okta |
| **Org account with strict SSO policy** | Key-Pair for service accounts + OAuth for humans |

### Why Key-Pair for Automation

1. **No interactive login** — critical for headless automation (Airflow, GitHub Actions)
2. **Not affected by SSO policies** — service users (TYPE=SERVICE) are exempt from SAML requirements
3. **Rotatable** — dual-key support allows zero-downtime rotation
4. **Audit-friendly** — each service account has its own identity in QUERY_HISTORY
5. **Org-account safe** — works across all account types regardless of SSO configuration

### Migration Path (PAT to Key-Pair)

1. Generate RSA key pair
2. Create TYPE=SERVICE user or update existing user with public key
3. Update `config.toml` to use `authenticator = SNOWFLAKE_JWT`
4. Update Airflow plugin to generate JWT instead of reading PAT
5. Test, then remove PAT-based variables

---

## References

- [Snowflake REST API Authentication](https://docs.snowflake.com/en/developer-guide/snowflake-rest-api/authentication)
- [Key-Pair Authentication](https://docs.snowflake.com/en/user-guide/key-pair-auth)
- [External OAuth with Okta](https://docs.snowflake.com/en/user-guide/oauth-ext-okta)
- [Service Users (TYPE=SERVICE)](https://docs.snowflake.com/en/sql-reference/sql/create-user)
- [Spark Connect Authentication](https://docs.snowflake.com/en/developer-guide/snowflake-rest-api/spark-connect/spark-connect-introduction)
