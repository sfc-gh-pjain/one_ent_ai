# Horizon Catalog Demo - Context

## Overview

End-to-end Snowflake Horizon Catalog demo using synthetic healthcare data (155K records). Demonstrates data governance, lineage, quality monitoring, object tagging, metadata layer, pipeline context, and AI integration across bronze/silver/gold medallion layers.

## Account Details

- **Account:** <ACCOUNT_LOCATOR>
- **User:** <SERVICE_USER> (has SYSADMIN, DEMO_ROLE)
- **Warehouse:** MY_WH
- **Database:** HORIZON_DEMO_DB
- **Schema:** HEALTHCARE
- **Working Directory:** `/Users/pjain/git/coco-work/horizon_catalog_demo`

## Deployment Flow

```
1. Run 01_setup_data.sql as ACCOUNTADMIN (creates DB, roles, tables, grants, ownership transfer)
2. Run ./deploy.sh my_conn (runs steps/ 02-08 as SYSADMIN)
3. Grant demo roles to user for masking demo:
   GRANT ROLE HORIZON_DEMO_ANALYST TO USER <SERVICE_USER>;
   GRANT ROLE HORIZON_DEMO_CLINICAL TO USER <SERVICE_USER>;
   GRANT ROLE HORIZON_DEMO_COMPLIANCE TO USER <SERVICE_USER>;
```

## File Structure

```
horizon_catalog_demo/
├── 01_service_user_setup_for_interation.md  # Auth guide (PAT, Key-Pair, OAuth)
├── 02_METADATA_DESIGN_AI_CONTEXT.md         # Metadata-to-AI design patterns
├── 04_WAREHOUSE_STRATEGY.md                 # Warehouse sizing for medallion workloads
├── DEMO_PRESENTATION.md                     # 8-slide markdown presentation
│
└── horizon_demo/
    ├── 01_setup_data.sql              # ACCOUNTADMIN: DB, roles, tables, grants
    ├── 07_cleanup.sql                 # DROP DATABASE + roles
    ├── deploy.sh                      # ./deploy.sh <connection_name> (9 steps)
    ├── steps/
    │   ├── 02_tagging.sql             # 8 tags (PII_LEVEL, DATA_CLASSIFICATION, etc.)
    │   ├── 03a_masking_projection.sql # Masking + projection policies (before DT)
    │   ├── 04_lineage.sql             # Views, Dynamic Table, Secure Views
    │   ├── 03b_row_join_agg.sql       # Row access, join, aggregation (after DT)
    │   ├── 05_data_quality.sql        # System + custom DMFs + bad data
    │   ├── 06a_share.sql              # Secure share
    │   ├── 06b_agent.sql              # Stage + Healthcare Agent
    │   ├── 07_metadata_layer.sql      # Pipeline log, layer tags, METADATA_CATALOG
    │   └── 08_ai_context.sql          # Cortex Search + Enhanced Agent
    ├── healthcare_analytics_model.yaml # Semantic model (patient analytics)
    ├── metadata_semantic_model.yaml    # Semantic model (pipeline metadata)
    ├── horizon_catalog_demo.ipynb      # SQL notebook (33 cells) for Snowsight
    ├── CONTEXT.md                      # This file
    ├── METADATA_AI_DESIGN.md           # Full metadata-to-AI design doc
    ├── WAREHOUSE_STRATEGY.md           # Warehouse sizing strategy
    ├── DEMO_PRESENTATION.html          # 8-slide HTML with SVG architecture
    └── DEMO_PRESENTATION.md            # 8-slide markdown version
```

## Objects Created

| Type | Objects |
|------|---------|
| Tables | PATIENTS (10K), DOCTORS (200), APPOINTMENTS (50K), PRESCRIPTIONS (30K), BILLING (40K), INSURANCE_CLAIMS (25K), PIPELINE_EXECUTION_LOG, METADATA_SEARCH_CORPUS |
| Dynamic Table | PATIENT_ANALYTICS |
| Views | STG_PATIENTS, STG_BILLING, STG_APPOINTMENTS, LINEAGE_CACHE, METADATA_CATALOG |
| Secure Views | REVENUE_DASHBOARD, DEPARTMENT_METRICS |
| Tags | PII_LEVEL, DATA_CLASSIFICATION, DATA_DOMAIN, RETENTION_DAYS, PIPELINE_LAYER, SOURCE_SYSTEM, LOAD_FREQUENCY, SLA_FRESHNESS_SECONDS |
| Masking Policy | PII_TAG_MASK (tag-based) |
| Row Access Policy | DEPARTMENT_ROW_POLICY |
| Aggregation Policy | MIN_GROUP_SIZE_POLICY |
| Join Policy | PATIENT_JOIN_POLICY |
| Projection Policy | PRESCRIPTION_PROJECTION_POLICY |
| DMFs | NULL_COUNT, DUPLICATE_COUNT, ROW_COUNT, INVALID_SSN_COUNT, INVALID_PHONE_COUNT |
| Share | HORIZON_DEMO_DB_HEALTHCARE_SHARE |
| Agents | HEALTHCARE_AGENT, HEALTHCARE_METADATA_AGENT |
| Search Service | METADATA_SEARCH |
| Stage | SEMANTIC_MODELS |

## Demo Roles

| Role | Access Level |
|------|-------------|
| SYSADMIN | Full access (table owner, in policy allowlist) |
| HORIZON_DEMO_ADMIN | Full access to all data |
| HORIZON_DEMO_COMPLIANCE | Full access (audit purposes) |
| HORIZON_DEMO_CLINICAL | Partial SSN (last 4), full contact info, CARDIOLOGY patients only |
| HORIZON_DEMO_ANALYST | Fully masked PII, must join PATIENTS, can't project medication |

## Key Demo Queries

### Masking Policy Demo (compare across roles)

```sql
USE ROLE SYSADMIN;
SELECT patient_id, first_name, last_name, ssn, email, phone, department
FROM HORIZON_DEMO_DB.HEALTHCARE.PATIENTS LIMIT 5;
-- SSN: 123-45-6789 | email: john@email.com | all departments

USE ROLE HORIZON_DEMO_ANALYST;
SELECT patient_id, first_name, last_name, ssn, email, phone, department
FROM HORIZON_DEMO_DB.HEALTHCARE.PATIENTS LIMIT 5;
-- SSN: ***-**-**** | email: ******** | all departments (names visible)

USE ROLE HORIZON_DEMO_CLINICAL;
SELECT patient_id, first_name, last_name, ssn, email, phone, department
FROM HORIZON_DEMO_DB.HEALTHCARE.PATIENTS LIMIT 5;
-- SSN: ***-**-6789 | email: john@email.com | CARDIOLOGY only
```

### Lineage Demo

```sql
-- Downstream from PATIENTS (what depends on it?)
SELECT SOURCE_OBJECT_NAME, TARGET_OBJECT_NAME, DISTANCE
FROM TABLE(SNOWFLAKE.CORE.GET_LINEAGE('HORIZON_DEMO_DB.HEALTHCARE.PATIENTS', 'TABLE', 'DOWNSTREAM', 5))
ORDER BY DISTANCE;

-- Upstream from REVENUE_DASHBOARD (where does data come from?)
SELECT SOURCE_OBJECT_NAME, TARGET_OBJECT_NAME, DISTANCE
FROM TABLE(SNOWFLAKE.CORE.GET_LINEAGE('HORIZON_DEMO_DB.HEALTHCARE.REVENUE_DASHBOARD', 'TABLE', 'UPSTREAM', 5))
ORDER BY DISTANCE;
```

### Metadata Catalog Demo

```sql
-- Pipeline health by layer
SELECT TABLE_NAME, pipeline_layer, LAST_PIPELINE_STATUS, PIPELINE_SUCCESS_RATE_PCT, DOWNSTREAM_COUNT
FROM METADATA_CATALOG ORDER BY pipeline_layer, TABLE_NAME;

-- Pipeline execution log with warehouse details
SELECT pipeline_name, layer_from || ' -> ' || layer_to, warehouse_name, warehouse_size, duration_seconds, status
FROM PIPELINE_EXECUTION_LOG ORDER BY execution_start DESC;
```

### Data Quality Demo

```sql
-- Run custom DMFs for immediate results
SELECT INVALID_SSN_COUNT(SELECT SSN FROM PATIENTS) AS bad_ssns;        -- Expected: 2
SELECT INVALID_PHONE_COUNT(SELECT PHONE FROM PATIENTS) AS bad_phones;  -- Expected: 1
```

## Lineage Pipeline

```
BRONZE                    SILVER                     GOLD
PATIENTS ──────────► STG_PATIENTS ──────┐
                                        ├──► PATIENT_ANALYTICS (DT) ──► REVENUE_DASHBOARD
APPOINTMENTS ──────► STG_APPOINTMENTS ──┤                           └──► DEPARTMENT_METRICS
                                        │
BILLING ───────────► STG_BILLING ───────┘
```

## Known Issues / Lessons

1. **Policy ordering:** Row access, join, and aggregation policies block DT/view creation. Must create pipeline objects BEFORE applying these policies.
2. **Masking + DMFs:** SYSADMIN must be in the masking policy allowlist, otherwise DMFs see masked values.
3. **Ownership for DMFs:** Tables must be owned by the role attaching DMFs (OWNERSHIP required).
4. **Grants in 01_setup_data.sql:** Includes CREATE TAG, CREATE MASKING POLICY, CREATE DATA METRIC FUNCTION, CREATE AGENT, all APPLY privileges, and OWNERSHIP transfer.
5. **snow sql -f** stops on first error — hence split into individual step files in `steps/`.
6. **Agent DDL:** `CREATE AGENT <name> SPEC = $$ ... $$ COMMENT = '...'`. MODEL/LLM/TOOLS not valid.
7. **Semantic View DDL:** Not available on this account. Use stage-based YAML with Cortex Analyst.
8. **Notebook kernel:** Set to SQL (`language_info.name = "sql"`) for Snowsight compatibility.
9. **Deploy ordering:** Stage must be created before PUT (06b_agent.sql runs before YAML upload).

## Prompts Used to Build This Demo

1. "Create an end to end Snowflake demo to demonstrate Horizon catalog capabilities - Data Governance, Lineage, Data Quality, Object Tagging, Data Sharing and AI"
2. "Create a markdown file and HTML file to deliver the demo with SVG architecture in light color scheme, 5-7 slides"
3. "Create a simple deploy shell script to run all the SQL code"
4. "With reference to Metadata, Lineage, Horizon Catalog, and AI Context — how can pipeline metadata be linked to Snowflake AI and Cortex context?"
5. "What warehouse sizing and usage strategy does Snowflake recommend for ingestion, processing, and consumption workloads? Is Adaptive Warehouse recommended?"
6. "Update the presentation files to include metadata layer and AI context"
