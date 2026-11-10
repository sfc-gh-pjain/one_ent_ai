# Snowflake Horizon Catalog Demo
## Healthcare Data Governance & AI Distribution

---

### Slide 1: The Challenge

Healthcare organizations must balance **data accessibility** with **regulatory compliance** (HIPAA, state privacy laws). Traditional approaches force a choice between security and usability.

**Snowflake Horizon Catalog** eliminates this trade-off by embedding governance directly into the data platform — and makes that governance context available to AI services.

---

### Slide 2: Dataset & Medallion Architecture

| Table | Records | Layer | Classification |
|-------|---------|-------|---------------|
| PATIENTS | 10,000 | BRONZE | PHI |
| DOCTORS | 200 | BRONZE | PII |
| APPOINTMENTS | 50,000 | BRONZE | PHI |
| PRESCRIPTIONS | 30,000 | BRONZE | PHI |
| BILLING | 40,000 | BRONZE | FINANCIAL |
| INSURANCE_CLAIMS | 25,000 | BRONZE | FINANCIAL |
| STG_PATIENTS, STG_BILLING, STG_APPOINTMENTS | (views) | SILVER | Inherited |
| PATIENT_ANALYTICS (Dynamic Table) | 10,000 | GOLD | Aggregated |
| REVENUE_DASHBOARD, DEPARTMENT_METRICS | (secure views) | GOLD | Shareable |

**155,200 total records** across a bronze/silver/gold pipeline with full lineage tracking.

---

### Slide 3: Architecture

```
┌──────────────────────────────────────────────────────────────────────────────┐
│  GOVERNANCE LAYER                                                             │
│  Tags: PII_LEVEL | DATA_CLASSIFICATION | PIPELINE_LAYER | SOURCE_SYSTEM      │
│        LOAD_FREQUENCY | SLA_FRESHNESS_SECONDS | DATA_DOMAIN | RETENTION_DAYS │
│  Policies: Masking | Row Access | Aggregation | Join | Projection            │
│  Quality: NULL_COUNT | DUPLICATE_COUNT | INVALID_SSN | INVALID_PHONE         │
└──────────────────────────────────────────────────────────────────────────────┘
        │                          │                          │
        ▼                          ▼                          ▼
  ┌──────────┐              ┌──────────┐              ┌──────────┐
  │ PATIENTS │              │APPOINTMTS│              │ BILLING  │
  │ (BRONZE) │              │ (BRONZE) │              │ (BRONZE) │
  └────┬─────┘              └────┬─────┘              └────┬─────┘
       ▼                         ▼                         ▼
  ┌──────────┐              ┌──────────┐              ┌──────────┐
  │STG_PATS  │              │STG_APPTS │              │STG_BILL  │
  │ (SILVER) │              │ (SILVER) │              │ (SILVER) │
  └────┬─────┘              └────┬─────┘              └────┬─────┘
       └────────────────────────┬┘────────────────────────┘
                                ▼
                    ┌───────────────────────┐
                    │  PATIENT_ANALYTICS    │
                    │  (GOLD - Dynamic Tbl) │
                    └───────────┬───────────┘
                                │
              ┌─────────────────┼──────────────────┐
              ▼                 ▼                   ▼
     ┌────────────────┐ ┌─────────────┐  ┌──────────────────┐
     │REVENUE_DASHBOARD│ │DEPT_METRICS │  │METADATA_CATALOG  │
     │  (Secure View)  │ │(Secure View)│  │(Unified Context) │
     └───────┬─────────┘ └─────────────┘  └────────┬─────────┘
             │                                      │
             ▼                                      ▼
     ┌────────────────┐                  ┌──────────────────────┐
     │ SECURE SHARE   │                  │ CORTEX AI LAYER      │
     │+ Marketplace   │                  │ Agent + Search +     │
     └────────────────┘                  │ Analyst              │
                                         └──────────────────────┘
```

---

### Slide 4: Governance Policies (Defense in Depth)

| Policy | Applied To | What It Does | Role Behavior |
|--------|-----------|--------------|---------------|
| **Masking** | SSN, Email, Phone, Address | Tag-based dynamic masking | SYSADMIN=clear, Clinical=partial SSN, Analyst=fully masked |
| **Row Access** | PATIENTS.DEPARTMENT | Filters rows by department | Clinical sees only CARDIOLOGY |
| **Aggregation** | BILLING table | Min group size = 5 | Prevents re-identification |
| **Join** | PATIENTS table | Must JOIN (no standalone SELECT) | Analysts cannot bulk-export PII |
| **Projection** | PRESCRIPTIONS.MEDICATION_NAME | Blocks column projection | Analysts cannot see medication names |

**Key design:** One masking policy reads `PII_LEVEL` tag via `SYSTEM$GET_TAG_ON_CURRENT_COLUMN()` — scales to all PII columns automatically.

---

### Slide 5: Lineage & Data Quality

**Lineage** (via `SNOWFLAKE.CORE.GET_LINEAGE`):
- Downstream: "If I change PATIENTS, what breaks?" — 4 dependent objects across 3 hops
- Upstream: "Where does REVENUE_DASHBOARD data from?" — 3 source tables traced back
- Column-level: "Does SSN leak into GOLD layer?" — tracked through every hop
- Cached in `LINEAGE_CACHE` view for AI consumption

**Data Quality** (via DMFs):
- System DMFs: NULL_COUNT, DUPLICATE_COUNT, ROW_COUNT (7 attached)
- Custom DMFs: INVALID_SSN_COUNT, INVALID_PHONE_COUNT
- Bad data injected for demo (2 invalid SSNs, 1 invalid phone, 2 duplicate emails)
- Results visible in Snowsight > Data > Governance > Quality tab

---

### Slide 6: Metadata Layer & Pipeline Context

| Component | What It Captures |
|-----------|-----------------|
| **PIPELINE_LAYER tag** | BRONZE / SILVER / GOLD per table |
| **SOURCE_SYSTEM tag** | EHR, BILLING_SYSTEM, CLAIMS_PORTAL |
| **PIPELINE_EXECUTION_LOG** | Source-to-target mapping, rows read/written/rejected, warehouse name & size, duration, status |
| **LINEAGE_CACHE** | Pre-computed downstream lineage from all bronze tables |
| **METADATA_CATALOG** | Unified view joining tags + pipeline log + lineage + quality |

**Pipeline Execution Log captures per run:**
- `pipeline_name`, `source_table` → `target_table`
- `layer_from` → `layer_to` (BRONZE→SILVER, SILVER→GOLD)
- `rows_read`, `rows_written`, `rows_rejected`
- `warehouse_name`, `warehouse_size`
- `duration_seconds`, `status`, `query_id`

---

### Slide 7: AI Context Integration

| AI Service | How It Consumes Metadata | Example Query |
|------------|------------------------|---------------|
| **Cortex Agent** | Multi-tool: healthcare model + metadata model + search | "Is billing data fresh and what feeds the revenue dashboard?" |
| **Cortex Analyst** | Semantic model over PIPELINE_EXECUTION_LOG + METADATA_CATALOG | "What is the pipeline success rate by layer?" |
| **Cortex Search** | Indexed on table descriptions, layer, classification tags | "Find tables with patient billing data" |
| **Cortex Code** | CONTEXT.md with layer map, tag inventory, naming conventions | Generates SQL aware of layer boundaries and policies |

**Enhanced Agent (HEALTHCARE_METADATA_AGENT):**
- Tool 1: Healthcare analytics semantic model (business questions)
- Tool 2: Metadata semantic model (pipeline/ops questions)
- Tool 3: Cortex Search (table discovery)

---

### Slide 8: Key Takeaways

1. **Tag once, protect everywhere** — One masking policy + PII_LEVEL tag = automatic coverage
2. **Defense in depth** — 5 policy types (masking, row access, aggregation, join, projection)
3. **Medallion layer tags** — PIPELINE_LAYER classifies every object as BRONZE/SILVER/GOLD
4. **Pipeline metadata** — Every run logged with source, target, warehouse, row counts, status
5. **Built-in lineage** — No external tools; column-level tracking across all hops
6. **Automated quality** — System + custom DMFs catch bad data continuously
7. **AI-ready metadata** — Unified catalog feeds Cortex Agent, Analyst, Search, and Code

**All governance and metadata is platform-native. No external tools, no application code, fully AI-queryable.**
