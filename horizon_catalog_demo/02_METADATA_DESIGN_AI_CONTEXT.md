# Metadata, Lineage, and AI Context Integration

## Design Document for Snowflake Horizon Catalog + Cortex AI

---

## 1. Problem Statement

Healthcare data pipelines produce data across bronze, silver, and gold layers. Each layer generates metadata: load timestamps, row counts, quality checks, lineage paths, and classification tags. Today this metadata exists in Snowflake but is fragmented across system views (ACCOUNT_USAGE, INFORMATION_SCHEMA, GET_LINEAGE, DMF results).

**Goal:** Unify this metadata into a queryable surface that Snowflake AI services (Cortex Agent, Cortex Analyst, Cortex Search, Cortex Code) can consume to provide context-aware responses.

---

## 2. Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        MEDALLION ARCHITECTURE                            │
│                                                                          │
│  BRONZE (Raw)          SILVER (Cleaned)         GOLD (Analytics)         │
│  ┌──────────────┐     ┌──────────────┐        ┌──────────────────┐     │
│  │ PATIENTS     │────▶│ STG_PATIENTS │───┐    │ PATIENT_ANALYTICS│     │
│  │ APPOINTMENTS │────▶│ STG_APPOINT  │───┼───▶│ (Dynamic Table)  │     │
│  │ BILLING      │────▶│ STG_BILLING  │───┘    │                  │     │
│  │ PRESCRIPTIONS│     └──────────────┘        └────────┬─────────┘     │
│  │ DOCTORS      │                                      │               │
│  │ INS_CLAIMS   │                              ┌───────┴────────┐      │
│  └──────────────┘                              │ REVENUE_DASHBOARD│     │
│                                                │ DEPT_METRICS     │     │
│                                                └──────────────────┘     │
└─────────────────────────────────────────────────────────────────────────┘
         │                    │                          │
         ▼                    ▼                          ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                        METADATA STORE                                    │
│                                                                          │
│  Tags:           PIPELINE_LAYER, SOURCE_SYSTEM, LOAD_FREQUENCY,         │
│                  SLA_FRESHNESS_SECONDS, PII_LEVEL, DATA_CLASSIFICATION   │
│                                                                          │
│  Pipeline Log:   PIPELINE_EXECUTION_LOG (per-run metrics, WH details)   │
│                                                                          │
│  Lineage:        LINEAGE_CACHE (materialized GET_LINEAGE results)       │
│                                                                          │
│  Quality:        DMF results (NULL_COUNT, DUPLICATE_COUNT, custom)       │
│                                                                          │
│  Catalog View:   METADATA_CATALOG (unified join of all above)           │
└─────────────────────────────────────────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                        AI CONTEXT LAYER                                   │
│                                                                          │
│  Cortex Agent:     metadata_semantic_model.yaml (tool: cortex_analyst)  │
│                    + cortex_search over catalog                          │
│                                                                          │
│  Cortex Analyst:   Direct semantic model queries on metadata             │
│                                                                          │
│  Cortex Search:    Indexed on table descriptions, tags, column metadata  │
│                                                                          │
│  Cortex Code:      CONTEXT.md with object inventory, layer map, tags    │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 3. Medallion Layer Tagging Pattern

### Tags

| Tag | Purpose | Values |
|-----|---------|--------|
| `PIPELINE_LAYER` | Identifies medallion tier | BRONZE, SILVER, GOLD |
| `SOURCE_SYSTEM` | Originating system | EHR, BILLING_SYSTEM, CLAIMS_PORTAL |
| `LOAD_FREQUENCY` | How often data refreshes | REAL_TIME, HOURLY, DAILY, WEEKLY |
| `SLA_FRESHNESS_SECONDS` | Max acceptable staleness | Numeric (e.g., 3600, 86400) |

### Layer Assignment

| Table | Layer | Rationale |
|-------|-------|-----------|
| PATIENTS, DOCTORS, APPOINTMENTS, PRESCRIPTIONS, BILLING, INSURANCE_CLAIMS | BRONZE | Raw ingested data, minimal transformation |
| STG_PATIENTS, STG_BILLING, STG_APPOINTMENTS | SILVER | Cleaned, typed, derived columns (age, outstanding_balance) |
| PATIENT_ANALYTICS, REVENUE_DASHBOARD, DEPARTMENT_METRICS | GOLD | Aggregated, joined, business-ready |

### Why Tags over a Lookup Table

- Tags are **native to Horizon Catalog** and appear in Snowsight governance UI
- Tags propagate through INFORMATION_SCHEMA views, accessible without special privileges
- Tag-based policies can reference layer (e.g., GOLD tables get stricter access)
- AI services can discover tags via `TAG_REFERENCES` without needing custom joins

---

## 4. Pipeline Execution Log

### Schema

```sql
CREATE TABLE PIPELINE_EXECUTION_LOG (
    execution_id      VARCHAR DEFAULT UUID_STRING(),
    pipeline_name     VARCHAR,
    source_table      VARCHAR,       -- FQN: DB.SCHEMA.TABLE
    target_table      VARCHAR,       -- FQN: DB.SCHEMA.TABLE
    layer_from        VARCHAR,       -- BRONZE / SILVER
    layer_to          VARCHAR,       -- SILVER / GOLD
    rows_read         NUMBER,
    rows_written      NUMBER,
    rows_rejected     NUMBER,
    warehouse_name    VARCHAR,       -- e.g., MY_WH
    warehouse_size    VARCHAR,       -- e.g., MEDIUM, LARGE
    execution_start   TIMESTAMP_NTZ,
    execution_end     TIMESTAMP_NTZ,
    status            VARCHAR,       -- SUCCESS / FAILED / PARTIAL
    error_message     VARCHAR,
    query_id          VARCHAR        -- links to QUERY_HISTORY for cost/duration
);
```

### How to Populate

**Option A: Task-based pipelines** - INSERT into log at task start/end:
```sql
-- At pipeline start
INSERT INTO PIPELINE_EXECUTION_LOG (pipeline_name, source_table, target_table, ...)
VALUES ('bronze_to_silver_patients', 'HORIZON_DEMO_DB.HEALTHCARE.PATIENTS', ...);

-- At pipeline end (update with results)
UPDATE PIPELINE_EXECUTION_LOG SET rows_written = :row_count, status = 'SUCCESS', ...
WHERE execution_id = :exec_id;
```

**Option B: Dynamic Table refresh metadata** - Query DT refresh history:
```sql
SELECT * FROM TABLE(INFORMATION_SCHEMA.DYNAMIC_TABLE_REFRESH_HISTORY(
  NAME => 'HORIZON_DEMO_DB.HEALTHCARE.PATIENT_ANALYTICS'));
```

**Option C: Query history correlation** - Join on query_id:
```sql
SELECT qh.query_id, qh.rows_produced, qh.total_elapsed_time, qh.warehouse_name, qh.warehouse_size
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY qh
WHERE qh.query_tag LIKE 'pipeline:%';
```

### Design Decision: Why a Custom Table

Snowflake's QUERY_HISTORY and DT refresh history exist but:
- They lack source-to-target mapping semantics
- They don't capture business context (layer_from, layer_to, pipeline_name)
- They have 45min-3hr latency in ACCOUNT_USAGE
- A custom log gives real-time, structured pipeline metadata queryable by AI

---

## 5. Lineage Integration

### Cached Lineage View

```sql
CREATE VIEW LINEAGE_CACHE AS
-- Downstream from all bronze tables
SELECT 'PATIENTS' AS anchor, l.*
FROM TABLE(SNOWFLAKE.CORE.GET_LINEAGE(
  'HORIZON_DEMO_DB.HEALTHCARE.PATIENTS', 'TABLE', 'DOWNSTREAM', 5)) l
UNION ALL
SELECT 'BILLING', l.*
FROM TABLE(SNOWFLAKE.CORE.GET_LINEAGE(
  'HORIZON_DEMO_DB.HEALTHCARE.BILLING', 'TABLE', 'DOWNSTREAM', 5)) l
UNION ALL
SELECT 'APPOINTMENTS', l.*
FROM TABLE(SNOWFLAKE.CORE.GET_LINEAGE(
  'HORIZON_DEMO_DB.HEALTHCARE.APPOINTMENTS', 'TABLE', 'DOWNSTREAM', 5)) l;
```

### Column-Level Lineage for PII Tracking

```sql
-- Track where SSN flows (critical for HIPAA)
SELECT SOURCE_OBJECT_NAME, SOURCE_COLUMN_NAME,
       TARGET_OBJECT_NAME, TARGET_COLUMN_NAME, DISTANCE
FROM TABLE(SNOWFLAKE.CORE.GET_LINEAGE(
  'HORIZON_DEMO_DB.HEALTHCARE.PATIENTS.SSN', 'COLUMN', 'DOWNSTREAM', 5));
```

### Lineage Metadata for AI

The LINEAGE_CACHE view enables AI to answer:
- "What tables feed REVENUE_DASHBOARD?" (upstream query)
- "If PATIENTS changes, what breaks?" (downstream impact)
- "Does SSN appear in any gold-layer table?" (PII leakage check)

---

## 6. Data Quality Integration

### DMF Results as AI Context

```sql
-- Unified quality view with layer context
CREATE VIEW DQ_SUMMARY AS
SELECT
  dq.TABLE_NAME,
  tag.TAG_VALUE AS pipeline_layer,
  dq.METRIC_NAME,
  dq.COLUMN_NAME,
  dq.VALUE AS violation_count,
  dq.MEASUREMENT_TIME,
  CASE WHEN dq.VALUE > 0 THEN 'VIOLATION' ELSE 'PASS' END AS quality_status
FROM SNOWFLAKE.LOCAL.DATA_QUALITY_MONITORING_RESULTS dq
LEFT JOIN TABLE(INFORMATION_SCHEMA.TAG_REFERENCES_ALL_COLUMNS(
  'HORIZON_DEMO_DB.HEALTHCARE.' || dq.TABLE_NAME, 'TABLE')) tag
  ON tag.TAG_NAME = 'PIPELINE_LAYER' AND tag.DOMAIN = 'TABLE'
WHERE dq.TABLE_DATABASE = 'HORIZON_DEMO_DB'
  AND dq.TABLE_SCHEMA = 'HEALTHCARE';
```

This enables AI queries like:
- "Are there any quality violations in the gold layer?"
- "When was the last successful quality check on PATIENTS?"
- "What columns have null violations?"

---

## 7. Unified Metadata Catalog

### METADATA_CATALOG View

Joins all metadata sources into one AI-queryable surface:

```sql
CREATE VIEW METADATA_CATALOG AS
SELECT
  t.TABLE_NAME,
  t.TABLE_TYPE,
  t.ROW_COUNT,
  t.CREATED,
  t.LAST_ALTERED,
  t.COMMENT,
  -- Tags
  layer_tag.TAG_VALUE AS pipeline_layer,
  class_tag.TAG_VALUE AS data_classification,
  domain_tag.TAG_VALUE AS data_domain,
  -- Pipeline
  p.last_load_time,
  p.last_load_status,
  p.avg_rows_per_load,
  p.warehouse_name,
  p.warehouse_size,
  -- Lineage
  l.upstream_count,
  l.downstream_count,
  -- Quality
  q.total_violations,
  q.last_check_time
FROM INFORMATION_SCHEMA.TABLES t
LEFT JOIN ... -- tag subqueries
LEFT JOIN ... -- pipeline aggregation
LEFT JOIN ... -- lineage counts
LEFT JOIN ... -- quality summary
WHERE t.TABLE_SCHEMA = 'HEALTHCARE';
```

---

## 8. AI Service Integration Patterns

### 8.1 Cortex Agent

**Pattern:** Multi-tool agent with healthcare analytics AND metadata awareness.

```yaml
# Agent spec with two tools
tools:
  - tool_spec:
      type: cortex_analyst
      semantic_model_file: "@.../healthcare_analytics_model.yaml"
  - tool_spec:
      type: cortex_analyst
      semantic_model_file: "@.../metadata_semantic_model.yaml"
  - tool_spec:
      type: cortex_search
      search_service: HORIZON_DEMO_DB.HEALTHCARE.METADATA_SEARCH
```

**What it enables:**
- "What is the no-show rate by department?" (healthcare tool)
- "Is the billing data fresh?" (metadata tool)
- "Find me all PHI tables" (search tool)
- "What feeds the revenue dashboard and is it healthy?" (metadata + lineage)

### 8.2 Cortex Analyst

**Pattern:** Semantic model over metadata tables with pre-defined metrics.

Key metrics in the metadata semantic model:
- `pipeline_success_rate`: % of successful pipeline runs
- `avg_load_duration_seconds`: pipeline performance
- `total_violations`: data quality health
- `freshness_seconds`: staleness per table
- `tables_by_layer`: count of tables per medallion tier

### 8.3 Cortex Search

**Pattern:** Index table/column descriptions and tags for natural language discovery.

```sql
CREATE CORTEX SEARCH SERVICE METADATA_SEARCH
  ON (search_text)
  WAREHOUSE = MY_WH
  TARGET_LAG = '1 hour'
  AS (
    SELECT
      TABLE_NAME || ': ' || COALESCE(COMMENT, '') || ' | Layer: ' ||
      pipeline_layer || ' | Classification: ' || data_classification
      AS search_text,
      TABLE_NAME,
      pipeline_layer,
      data_classification
    FROM METADATA_CATALOG
  );
```

### 8.4 Cortex Code (CoCo)

**Pattern:** CONTEXT.md provides static context that CoCo reads at session start.

The existing `CONTEXT.md` already documents the schema. Extending it with:
- Layer-to-table mapping
- Tag inventory
- Pipeline dependencies
- Naming conventions (STG_ = silver, _ANALYTICS = gold)

This helps CoCo generate correct SQL that respects layer boundaries and policy constraints.

---

## 9. Source-to-Target Mapping

### Captured in PIPELINE_EXECUTION_LOG

Every pipeline run records:
- `source_table` -> `target_table` (the mapping)
- `layer_from` -> `layer_to` (the transition)
- `rows_read` vs `rows_written` (transformation impact)
- `query_id` (link to QUERY_HISTORY for cost attribution)

### Queryable by AI

```
User: "Show me the source-to-target mapping for the gold layer"
Agent: Queries PIPELINE_EXECUTION_LOG WHERE layer_to = 'GOLD'
Result: STG_PATIENTS + STG_BILLING + STG_APPOINTMENTS -> PATIENT_ANALYTICS
```

---

## 10. Implementation Notes

1. **Pipeline log is populated by sample data** in the demo (simulating real runs). In production, tasks would INSERT on each execution.
2. **LINEAGE_CACHE is a view** (not materialized) since GET_LINEAGE is fast and always current. For large estates, consider a scheduled task to materialize.
3. **DQ_SUMMARY depends on DMF schedule** - results appear after the hourly DMF run. For demo, use manual DMF execution to show immediate results.
4. **Cortex Search requires a warehouse** and TARGET_LAG for refresh. Uses the same pattern as Dynamic Tables.
5. **Agent with multiple tools** - the agent selects the right tool based on the question. Healthcare questions route to the analytics model; metadata questions route to the metadata model.
