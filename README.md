# Snowflake End-to-End Data Platform Demo

A comprehensive demonstration of Snowflake's data engineering, AI, governance, and orchestration capabilities across multiple business domains.

## What's Included

| Layer | Folder | Description |
|-------|--------|-------------|
| Healthcare Pipeline | `scos_pipeline/` | PySpark Code Bundle jobs for Rx metrics, HCP tiering, engagement attribution |
| CRM Pipeline | `crm_demo/` | Salesforce one-hop-reduction: CUSTOMER_360 + PIPELINE_FORECAST |
| AI Layer | `ai_layer/` | Cortex Analyst, Search, Agent, Streamlit + multi-domain semantic models |
| Data Quality | `dq_mdm/` | DMFs, streams, tasks, AI-assisted DQ, hybrid governance |
| Blue/Green Swap | `swap_ops_demo/` | Zero-copy clone + atomic table swap |
| Streaming | `streaming_demo/` | Snowpipe Streaming SDK (real-time ingestion) |
| Orchestration | `airflow/` | 4 Airflow DAGs orchestrating all pipelines |
| Story Dashboard | `streamlit_dashboard/` | 7-tab Streamlit app summarizing all demos with live data |

## Demo Stories

### Healthcare Pipeline (`scos_pipeline/`)

**Problem:** Running PySpark transformations requires managing Spark clusters, EMR/Dataproc infrastructure, and data movement between storage and compute.

**Solution:** Snowflake Code Bundles execute PySpark directly on warehouse compute. Zero infrastructure — full Spark API with Snowflake-native DDL (MERGE, QUALIFY, TRANSIENT).

**What it shows:** 4 sequential jobs: Rx metrics aggregation (staging-validate-MERGE), HCP specialty classification (Python UDTF), 6-way engagement enrichment join, and data quality validation gates.

### CRM Pipeline (`crm_demo/`)

**Problem:** Traditional Salesforce analytics routes enriched data back through S3 and Salesforce before Tableau can visualize it — adding 2 extra hops of latency and cost.

**Solution:** Enrich CRM data in Snowflake and let Tableau query it directly. Eliminates the round-trip: 4 hops reduced to 2.

**What it shows:** 3 Code Bundle jobs produce CUSTOMER_360 (health scores, segmentation) and PIPELINE_FORECAST (weighted pipeline, velocity scoring). Multi-step derived facts demonstrate complex business rules in semantic models.

### AI Layer (`ai_layer/`)

**Problem:** Enterprises need text-to-SQL across 500+ tables spanning multiple domains, without building one massive monolithic model.

**Solution:** Federated semantic models (one per domain) + search-based agent routing. An enterprise agent uses Cortex Search to find the right domain, then queries the appropriate Cortex Analyst tool.

**What it shows:** 3 semantic models (Healthcare, CRM, Finance), a model registry with 9 simulated domains, MODEL_ROUTER_SEARCH for routing, and ENTERPRISE_INTELLIGENCE_AGENT spanning all domains.

### Data Quality (`dq_mdm/`)

**Problem:** Maintaining hundreds of DQ rules manually doesn't scale. Business users can't interpret technical violations. Trend detection requires constant monitoring.

**Solution:** Cortex AI generates DQ rule suggestions from schema metadata, explains violations in business language, and detects trends over time — reducing manual maintenance as schemas evolve.

**What it shows:** 6 custom DMFs, stream-triggered tasks, stored procedures for MDM (dedup, outlier detection), AI-generated rule suggestions, AI violation interpretation, and schema coverage assessment.

### Blue/Green Swap (`swap_ops_demo/`)

**Problem:** Traditional ETL refreshes (TRUNCATE + INSERT) expose a window where queries return empty or partial results — causing downtime for analysts and dashboards.

**Solution:** Zero-copy clone + atomic table swap. Clone source tables (metadata-only, instant), then swap pointers with production (sub-second). Zero downtime regardless of table size.

**What it shows:** REFRESH_STAR_SCHEMA procedure that clones 3 star schema tables, atomically swaps with PROD, and verifies zero-downtime.

### Streaming (`streaming_demo/`)

**Problem:** Real-time event ingestion typically requires Kafka, connectors, and complex infrastructure.

**Solution:** Snowpipe Streaming SDK with High-Performance Architecture — direct SDK-to-table ingestion at 50+ events/second with multi-channel partitioning and self-healing recovery.

**What it shows:** Named PIPE object, multi-channel producer (hash by HCP_ID, 4 partitions), VARIANT column for flexible JSON payloads, key-pair authentication.

### Hybrid Governance (`dq_mdm/sql/06_hybrid_governance.sql`)

**Problem:** Enterprises with data from SAP, Salesforce, and internal systems need unified governance regardless of data origin — but policies are often applied system-by-system.

**Solution:** Tag-based governance that follows the data. SOURCE_SYSTEM, INTEGRATION_PATTERN, COMPLIANCE_FRAMEWORK tags applied uniformly. Same masking policies work regardless of where the data came from.

**What it shows:** Provenance tags across both schemas (SAP dims, Salesforce CRM, internal transactions), cross-system inventory views, and compliance coverage reporting.

### Story Dashboard (`streamlit_dashboard/`)

**Problem:** Demo results scattered across multiple tables and schemas are hard to present as a cohesive story to executives and architects.

**Solution:** A single Streamlit-in-Snowflake app with 6 tabs — each telling the story of one demo layer with KPI cards (executive view) and expandable technical details (architect view).

**What it shows:** Live data visualizations from all demo tables, platform status grid, architecture diagrams, and the enterprise questions answered by each component.

## Quick Start

```bash
export SNOWFLAKE_PAT='your_token'
./deploy_all.sh             # Deploy ALL layers (calls bootstrap internally)
./streamlit_dashboard/deploy_streamlit_app.sh  # Deploy the story dashboard
./start_airflow.sh          # Start Airflow (4 DAGs at localhost:8080)
./teardown.sh               # Drop ALL Snowflake objects
```

## Prerequisites

- **bash** + **curl** (Miniconda is auto-installed if conda not found)
- Snowflake account with Code Bundles enabled
- A Programmatic Access Token (PAT) — see `service_user_setup.md` for alternatives (Key-Pair JWT, OAuth)

## Architecture

```
┌──────────────────────────────────────────────────────────────────────┐
│                        Snowflake Account                              │
│                                                                      │
│  ┌────────────────────────┐   ┌────────────────────────────────┐   │
│  │ SCOS Healthcare Pipeline│   │ CRM Pipeline (One-Hop)          │   │
│  │ CB_HEALTHCARE_SPARK     │   │ CB_CRM_SPARK                    │   │
│  │ 4 Spark jobs on WH      │   │ 3 Spark jobs on WH              │   │
│  └──────────┬─────────────┘   └──────────────┬─────────────────┘   │
│             │                                  │                     │
│             ▼                                  ▼                     │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │ AI Layer (Cortex)                                             │   │
│  │  • 3 Semantic Models (Healthcare, CRM, Finance)               │   │
│  │  • Enterprise Agent (search-based routing across domains)     │   │
│  │  • Cortex Search (HCP search + model router)                  │   │
│  │  • Streamlit Dashboard                                        │   │
│  └──────────────────────────────────────────────────────────────┘   │
│                              │                                       │
│  ┌───────────────────────────┼──────────────────────────────────┐   │
│  │ Governance & DQ           │                                   │   │
│  │  • DMFs (built-in + 6 custom)                                 │   │
│  │  • AI-assisted rule suggestions + violation interpretation    │   │
│  │  • Hybrid tags: SOURCE_SYSTEM, COMPLIANCE_FRAMEWORK           │   │
│  │  • Masking policies (NPI, HCP names, notes)                   │   │
│  └──────────────────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────────────────┘
         ▲
         │ SQL API (async + poll)
┌────────┴─────────────────────────────────────────────────────────────┐
│ Airflow (localhost:8080)                                              │
│  • healthcare_pipeline (4 Spark jobs)                                 │
│  • crm_pipeline (3 Spark jobs)                                        │
│  • dq_mdm_pipeline (4 MDM procedures)                                │
│  • swap_pipeline (blue/green refresh)                                 │
└──────────────────────────────────────────────────────────────────────┘
```

## Enterprise Questions Answered

This demo directly addresses five common enterprise questions:

| Question | Demo Component |
|----------|----------------|
| How do semantic views handle complex business rules? | Multi-step `expr:` in all 3 semantic models (health score, effectiveness, variance) |
| How can AI facilitate DQ monitoring long-term? | `dq_mdm/sql/05_ai_assisted_dq.sql` — AI suggests rules, explains violations, detects trends |
| Scalability of semantic views across 500+ tables? | 3 federated domain models + registry pattern (`ai_layer/sql/03_agent_routing.sql`) |
| Strategy for 10K+ tables in one agent? | Search-based routing: MODEL_ROUTER_SEARCH + ENTERPRISE_INTELLIGENCE_AGENT |
| Governance for hybrid systems (SAP + Salesforce)? | `dq_mdm/sql/06_hybrid_governance.sql` — source provenance tags + cross-system views |

## Snowflake Objects Created

| Object | Type | Schema |
|--------|------|--------|
| `CB_HEALTHCARE_SPARK` | Code Bundle | HEALTHCARE_DEMO |
| `CB_CRM_SPARK` | Code Bundle | CRM_DEMO |
| `PHARMA_SEARCH_SERVICE` | Cortex Search | HEALTHCARE_DEMO |
| `MODEL_ROUTER_SEARCH` | Cortex Search | HEALTHCARE_DEMO |
| `PHARMA_INTELLIGENCE_AGENT` | Agent | HEALTHCARE_DEMO |
| `ENTERPRISE_INTELLIGENCE_AGENT` | Agent | HEALTHCARE_DEMO |
| `PHARMA_INTELLIGENCE_APP` | Streamlit | HEALTHCARE_DEMO |
| `DEMO_SUMMARY_DASHBOARD` | Streamlit | HEALTHCARE_DEMO |
| `CUSTOMER_360` | Table | CRM_DEMO |
| `PIPELINE_FORECAST` | Table | CRM_DEMO |
| `SEMANTIC_MODEL_REGISTRY` | Table | HEALTHCARE_DEMO |
| 4 Tasks | Tasks | HEALTHCARE_DEMO |
| `SWAP_DEMO` | Database | (separate) |

## Demo Assets

### Cortex Agents (3)

| Agent | Database.Schema | Purpose |
|-------|----------------|---------|
| `PHARMA_INTELLIGENCE_AGENT` | DEMO.HEALTHCARE_DEMO | Healthcare analytics via Pharma semantic view + search |
| `ENTERPRISE_INTELLIGENCE_AGENT` | DEMO.HEALTHCARE_DEMO | Multi-domain routing across Healthcare, CRM, Finance |
| `HEALTHCARE_METADATA_AGENT` | HORIZON_DEMO_DB.HEALTHCARE | Metadata/governance queries via metadata semantic model |

### Semantic Views (3)

| View | Domain | Key Metrics |
|------|--------|-------------|
| `PHARMA_COMMERCIAL_INTELLIGENCE` | Healthcare | Rx volume, HCP effectiveness, engagement ROI |
| `CRM_COMMERCIAL_INTELLIGENCE` | CRM | Health scores, pipeline velocity, segmentation |
| `FINANCE_SUMMARY` | Finance | Budget variance, department spend |

### Cortex Search Services (4)

| Service | Corpus | Use Case |
|---------|--------|----------|
| `PHARMA_SEARCH_SERVICE` | HCP profiles + Rx data | Natural language HCP lookup |
| `MODEL_ROUTER_SEARCH` | Semantic model registry (9 domains) | Agent routing to correct domain |
| `METADATA_SEARCH` | Table/column metadata catalog | Table discovery and lineage |
| `GOVERNANCE_SEARCH` | Tags, PII classifications, policies | Governance metadata search |

### Streamlit Apps (3)

| App | Location | Tabs |
|-----|----------|------|
| `PHARMA_INTELLIGENCE_APP` | DEMO.HEALTHCARE_DEMO | Cortex Analyst + Search |
| `DEMO_SUMMARY_DASHBOARD` | DEMO.HEALTHCARE_DEMO | 7 tabs: Platform, Transform, CRM, DQ, AI, Governance, Summary |
| `HORIZON_INTELLIGENCE_APP` | HORIZON_DEMO_DB.HEALTHCARE | Analyst + Search + Governance Search + Governance Details |

### HTML Artifacts (4)

| File | Purpose |
|------|---------|
| `demo_presentation.html` | 13-slide deck "One Enterprise Platform with Snowflake" |
| `demo_inventory.html` | Printable cheat sheet with all prompts, URLs, SQL |
| `Snowflake_Semantic_n_Context_Layer_Architecture.html` | Architecture doc with 4-layer SVG diagram |
| `ai_layer/ai_demo_usage_guide.html` | AI layer usage guide with agent prompts |

### Airflow DAGs (4)

| DAG | Tasks | Pipeline |
|-----|-------|----------|
| `healthcare_pipeline` | 4 Spark jobs | Rx metrics, HCP tiering, engagement, DQ gates |
| `crm_pipeline` | 3 Spark jobs | Customer 360, pipeline forecast, segmentation |
| `dq_mdm_pipeline` | 4 procedures | Tier validation, dedup, outlier, MDM enrich |
| `swap_pipeline` | 3 steps | Clone, swap, verify (blue/green) |

### Horizon Governance (HORIZON_DEMO_DB)

- 10+ object tags (PII_TYPE, DATA_CLASSIFICATION, SOURCE_SYSTEM, etc.)
- 3 masking policies (NPI, HCP names, clinical notes)
- 2 row access policies (role-based, region-based)
- Governance Search corpus table with auto-populated tag/policy inventory

## Airflow

```bash
export SNOWFLAKE_PAT='your_token'
./start_airflow.sh
```

- **URL:** http://localhost:8080
- **Username:** `admin`
- **Password:** Auto-generated (check `airflow/.airflow/simple_auth_manager_passwords.json.generated`)
- **DAGs:** `healthcare_pipeline`, `crm_pipeline`, `dq_mdm_pipeline`, `swap_pipeline`
- **Stop:** `Ctrl+C`

## Authentication

Three options documented in `service_user_setup.md`:
- **PAT** — simplest for dev/demo (current default)
- **Key-Pair JWT** — recommended for production (no interactive login)
- **External OAuth (Okta)** — for org accounts with SSO enforcement

## Documentation

| File | Purpose |
|------|---------|
| `CONTEXT.md` | Full technical context (tables, schemas, patterns, config) |
| `service_user_setup.md` | Authentication setup guide (PAT, JWT, OAuth, Airflow integration) |
| `demo_run.md` | Step-by-step demo delivery guide |
| `scos_pipeline/README.md` | Healthcare pipeline details |
| `crm_demo/README.md` | CRM pipeline details |
| `ai_layer/README.md` | AI layer details |
| `dq_mdm/README.md` | Data quality details |
| `airflow/README.md` | Orchestration details |
| `swap_ops_demo/README.md` | Blue/green swap pattern |
| `streaming_demo/README.md` | Snowpipe Streaming SDK |
| `streamlit_dashboard/` | Story dashboard (deploy script + app.py) |
