# Data Quality & Master Data Management

Data quality monitoring, business rules enforcement, AI-assisted DQ maintenance, and hybrid governance for multi-source environments (SAP + Salesforce).

## Components

| File | Purpose |
|------|---------|
| `sql/01_dmf_setup.sql` | Built-in + 6 custom Data Metric Functions |
| `sql/02_business_rules.sql` | 3 streams, 4 tasks, 2 stored procedures for MDM |
| `sql/03_constraints.sql` | PK/FK/UNIQUE informational constraints |
| `sql/04_governance.sql` | Tags (SENSITIVITY_LEVEL, DATA_DOMAIN) + masking policies |
| `sql/05_ai_assisted_dq.sql` | AI-generated DQ rules, violation interpretation, trend detection |
| `sql/06_hybrid_governance.sql` | Source system provenance tags + cross-system inventory views |
| `streamlit/dq_monitor.py` | 5-tab monitoring dashboard |
| `scripts/deploy_dq.sh` | One-command deployment |

## AI-Assisted DQ Monitoring (`05_ai_assisted_dq.sql`)

Uses `SNOWFLAKE.CORTEX.COMPLETE` to automate DQ rule lifecycle:

1. **Rule Suggestion** — Analyzes column names/types and generates appropriate DQ checks as JSON
2. **Violation Interpretation** — Translates technical violations into business-friendly explanations
3. **Trend Detection** — Assesses whether violation patterns are growing, one-time, or steady-state
4. **Coverage Assessment** — Identifies unmonitored columns that should have DQ checks

### Objects Created

| Object | Type | Purpose |
|--------|------|---------|
| `DQ_AI_SUGGESTIONS` | Table | AI-generated rule recommendations per column |
| `DQ_VIOLATION_INSIGHTS` | View | Violations enriched with AI explanation + remediation |
| `DQ_TREND_ANALYSIS` | View | Violation trend assessment per rule |
| `DQ_SCHEMA_COVERAGE` | View | Identifies gaps in DQ monitoring coverage |

### Demo Narrative

> "Cortex AI can suggest DQ rules by analyzing your schema, explain violations in business language, and detect trends over time. This reduces the manual effort of maintaining hundreds of rules as schemas evolve."

## Hybrid Governance (`06_hybrid_governance.sql`)

Governs data from multiple source systems with unified policies:

### Tags

| Tag | Values | Purpose |
|-----|--------|---------|
| `SOURCE_SYSTEM` | SALESFORCE, SAP, INTERNAL, THIRD_PARTY | Data provenance |
| `INTEGRATION_PATTERN` | CDC_ICEBERG, BATCH_ETL, STREAMING, API_PULL | How data arrives |
| `DATA_FRESHNESS_SLA` | REAL_TIME, HOURLY, DAILY, WEEKLY | Expected freshness |
| `COMPLIANCE_FRAMEWORK` | HIPAA, SOX, GDPR, PCI_DSS, NONE | Regulatory governance |

### Tagging Strategy

| Table | Source System | Integration | Freshness | Compliance |
|-------|--------------|-------------|-----------|------------|
| DIM_DRUG | SAP | BATCH_ETL | DAILY | SOX |
| DIM_TERRITORY | SAP | BATCH_ETL | WEEKLY | - |
| RAW_PRESCRIPTIONS | INTERNAL | STREAMING | REAL_TIME | HIPAA |
| RAW_HCP_PROFILES | INTERNAL | BATCH_ETL | DAILY | HIPAA |
| RAW_ACCOUNTS (CRM) | SALESFORCE | CDC_ICEBERG | HOURLY | SOX |
| RAW_OPPORTUNITIES (CRM) | SALESFORCE | CDC_ICEBERG | HOURLY | SOX |

### Cross-System Views

- `GOVERNANCE_INVENTORY` — Single pane showing all tables with their source, integration, freshness, domain, quality status, owner, and compliance framework
- `GOVERNANCE_SOURCE_SUMMARY` — Table counts by source system
- `GOVERNANCE_COMPLIANCE_COVERAGE` — Which tables are under which regulatory framework

### Demo Narrative

> "Snowflake governs hybrid systems through tag-based policies that follow the data regardless of origin. Whether it comes from SAP, Salesforce, or internal systems, the same masking, access, and classification rules apply uniformly."

## MDM Business Rules

| Task | Trigger | Action |
|------|---------|--------|
| `TASK_MDM_HCP_DEDUP` | Stream on RAW_HCP_PROFILES | Golden record dedup via NPI, logs duplicates |
| `TASK_MDM_RX_OUTLIER_DETECTION` | Stream on RAW_PRESCRIPTIONS | Flags qty > 5x territory avg |
| `TASK_MDM_ENGAGEMENT_VALIDATION` | Stream on RAW_HCP_ENGAGEMENTS | Orphan drug + future date checks |
| `TASK_MDM_TIER_VALIDATION` | Scheduled | Invalid tier/decile detection |

## Deploy

```bash
# Full DQ/MDM layer
./dq_mdm/scripts/deploy_dq.sh

# Or individual files
snow sql -f dq_mdm/sql/05_ai_assisted_dq.sql -c my_conn
snow sql -f dq_mdm/sql/06_hybrid_governance.sql -c my_conn
```

**Note:** DMF attachment requires ACCOUNTADMIN to first grant:
```sql
GRANT EXECUTE DATA METRIC FUNCTION ON ACCOUNT TO ROLE SYSADMIN;
```
