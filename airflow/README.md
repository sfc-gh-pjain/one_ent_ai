# Airflow Orchestration

Modular Airflow setup with 4 independent DAGs orchestrating all demo pipelines. Uses the Snowflake SQL REST API for async job submission and polling.

## Structure

```
airflow/
├── dags/
│   ├── healthcare_pipeline.py   # 4 Spark Code Bundle jobs
│   ├── crm_pipeline.py          # 3 Spark Code Bundle jobs
│   ├── dq_mdm_pipeline.py       # 4 MDM stored procedure calls
│   └── swap_pipeline.py         # Blue/green refresh (insert → clone → swap → verify)
├── plugins/
│   └── snowflake_executor.py    # Shared REST API helpers
└── .airflow/                    # Runtime home (gitignored)
```

## DAGs

| DAG ID | Steps | Trigger |
|--------|-------|---------|
| `healthcare_pipeline` | rx_metrics_load → hcp_classification → engagement_merge → validate | Manual |
| `crm_pipeline` | customer_360_enrich → pipeline_forecast → validate | Manual |
| `dq_mdm_pipeline` | hcp_dedup → rx_outlier_detection → engagement_validation → tier_validation | Manual |
| `swap_pipeline` | insert_new_source_data → refresh_star_schema → verify_swap | Manual |

All DAGs are `schedule=None` (manual trigger only) with `catchup=False`.

## Shared Plugin (`plugins/snowflake_executor.py`)

Two main functions used by all DAGs:

- **`submit_and_wait(entrypoint, bundle_name, ...)`** — Submits `EXECUTE CODE BUNDLE` via SQL API with `async=true`, then polls the statement handle every 15 seconds until completion (30-minute timeout).

- **`run_sql(sql, ...)`** — Executes arbitrary SQL statements (CALL, INSERT, ALTER, SELECT) via the same SQL API.

- **`get_config()`** — Reads connection details from Airflow Variables. Supports 3 auth modes:
  - `pat` — Programmatic Access Token (default)
  - `keypair` — Key-Pair JWT (recommended for production)
  - `oauth` — External OAuth (Okta)

## Quick Start

```bash
export SNOWFLAKE_PAT='your_token'
./start_airflow.sh
```

Then open http://localhost:8080 and trigger any DAG.

## Airflow Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `snowflake_account_url` | Account URL | `<ACCOUNT_LOCATOR>.snowflakecomputing.com` |
| `snowflake_auth_mode` | Auth method | `pat` / `keypair` / `oauth` |
| `snowflake_pat` | PAT token (if auth_mode=pat) | `eyJraWQ...` |
| `snowflake_service_user` | Service user (if keypair) | `SVC_PIPELINE` |
| `snowflake_private_key_path` | Key path (if keypair) | `/path/to/rsa_key.p8` |
| `snowflake_role` | Snowflake role | `SYSADMIN` |
| `snowflake_warehouse` | Warehouse | `MY_WH` |
| `snowflake_database` | Database | `DEMO` |
| `snowflake_schema` | Default schema | `HEALTHCARE_DEMO` |

## Design Decisions

| Decision | Rationale |
|----------|-----------|
| One DAG per demo folder | Independent triggers, clear ownership, no cross-DAG dependencies |
| Shared plugin (not provider) | Code Bundle async execution needs custom polling; SnowflakeOperator blocks workers |
| SQL REST API (not Code Bundle API) | `/api/v2/code-bundle-executions` returns 405; only SQL API works for `EXECUTE CODE BUNDLE` |
| Airflow Variables (not Connections) | Simpler for demo; production should use Connections + secrets backend |

## Production Considerations

For production deployments, see `service_user_setup.md`:
- Switch `snowflake_auth_mode` to `keypair`
- Store private key in a secrets backend (Vault, AWS Secrets Manager)
- Use the Snowflake Airflow Provider (`apache-airflow-providers-snowflake`) for connection management
- Consider Approach C (hybrid): Provider for auth + custom polling for async Code Bundles
