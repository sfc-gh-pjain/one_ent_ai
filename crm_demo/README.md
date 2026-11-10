# CRM Demo — Salesforce One-Hop Reduction

PySpark Code Bundle pipeline demonstrating the optimized analytics architecture where Tableau queries enriched CRM data directly from Snowflake, eliminating the round-trip through Salesforce.

## Architecture

```
BEFORE (4 hops for analytics):
  Salesforce → S3 (raw Iceberg) → Snowflake (enrich) → S3 (enriched) → Salesforce → Tableau

AFTER (2 hops — this demo):
  Salesforce → S3 (raw Iceberg) → Snowflake (enrich) → Tableau (direct query)
```

## Pipeline Jobs

| # | File | Pattern | Output Table |
|---|------|---------|--------------|
| 1 | `01_customer_360_enrich.py` | Multi-join + health scoring + MERGE | `CUSTOMER_360` |
| 2 | `02_pipeline_forecast.py` | Weighted pipeline + velocity + MERGE | `PIPELINE_FORECAST` |
| 3 | `03_validate.py` | 10 DQ assertion gates | Pass/Fail |

## Data

| Table | Rows | Description |
|-------|------|-------------|
| RAW_ACCOUNTS | 50 | Salesforce accounts (5 industries, 5 regions) |
| RAW_OPPORTUNITIES | 200 | Pipeline deals across 6 stages ($10K-$2M) |
| RAW_CASES | 150 | Support cases with priority + resolution tracking |
| CUSTOMER_360 | 50 | Enriched: health score, segment, win rate, pipeline |
| PIPELINE_FORECAST | ~157 | Open opps: weighted pipeline, velocity, forecast category |

## Health Score Formula

```
health_score = (win_rate * 40) + (pipeline_factor * 30) + (case_factor * 30)

Where:
  pipeline_factor = min(total_pipeline / 500000, 1.0)
  case_factor = max(1.0 - avg_resolution_days / 30, 0)

Segments:
  >= 70 → "High Value"
  >= 40 → "Growth"
  <  40 → "At Risk"
```

## Semantic Model

The CRM semantic model (`ai_layer/src/crm_commercial_intelligence.yaml`) adds multi-step derived facts:

- **REVENUE_AT_RISK** — Total exposure for at-risk accounts only
- **EXPANSION_POTENTIAL** — Pipeline * win_rate * (1 + health/100)
- **CASE_BURDEN_RATIO** — Open cases per open opportunity (friction signal)
- **DEAL_QUALITY_INDEX** — Weighted pipeline per day remaining

## Deploy

```bash
# One-click deploy
./crm_demo/scripts/deploy_crm.sh

# One-click teardown
./crm_demo/scripts/cleanup_crm.sh
```

## Airflow

The `crm_pipeline` DAG orchestrates the 3 jobs:
```
customer_360_enrich → pipeline_forecast → validate
```

Trigger via Airflow UI at http://localhost:8080 after running `./start_airflow.sh`.

## Key Talking Points

| Topic | Message |
|-------|---------|
| Why one hop matters | Every hop adds latency, cost, and staleness. Analytics shouldn't wait for a Salesforce round-trip. |
| Separation of concerns | Salesforce = CRM operations. Snowflake = analytics engine. Tableau = visualization. |
| Salesforce API limits | Eliminating the analytics read avoids governor limits and API call overhead. |
| Real-time vs batch | Direct Snowflake queries are real-time. The old path was batch-dependent. |
