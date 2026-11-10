# Snowflake Horizon Catalog Demo
## Healthcare Data Governance & AI Distribution

---

### Slide 1: The Challenge

Healthcare organizations must balance **data accessibility** with **regulatory compliance** (HIPAA, state privacy laws). Traditional approaches force a choice between security and usability.

**Snowflake Horizon Catalog** eliminates this trade-off by embedding governance directly into the data platform.

---

### Slide 2: Dataset

| Table | Records | Contains |
|-------|---------|----------|
| PATIENTS | 10,000 | Demographics, SSN, contact info, department |
| DOCTORS | 200 | Staff info, specialties, licenses |
| APPOINTMENTS | 50,000 | Visit records, diagnoses, outcomes |
| PRESCRIPTIONS | 30,000 | Medications, dosages, controlled substances |
| BILLING | 40,000 | Charges, payments, insurance coverage |
| INSURANCE_CLAIMS | 25,000 | Claims, approvals, denials |

**155,200 total records** across 6 tables simulating a mid-size healthcare system.

---

### Slide 3: Architecture

```
                    ┌─────────────────────────────────────────────────┐
                    │              GOVERNANCE LAYER                    │
                    │                                                  │
                    │  Tags: PII_LEVEL | DATA_CLASSIFICATION          │
                    │        DATA_DOMAIN | RETENTION_DAYS              │
                    │                                                  │
                    │  Policies: Masking | Row Access | Aggregation    │
                    │            Join | Projection                     │
                    │                                                  │
                    │  Quality: NULL_COUNT | DUPLICATE_COUNT           │
                    │           INVALID_SSN | INVALID_PHONE            │
                    └─────────────────────────────────────────────────┘
                                         │
          ┌──────────────────────────────┼──────────────────────────────┐
          │                              │                              │
          ▼                              ▼                              ▼
   ┌─────────────┐              ┌─────────────┐              ┌─────────────┐
   │  PATIENTS   │              │ APPOINTMENTS│              │   BILLING   │
   │  (raw PHI)  │              │  (raw PHI)  │              │ (financial) │
   └──────┬──────┘              └──────┬──────┘              └──────┬──────┘
          │                            │                            │
          ▼                            ▼                            ▼
   ┌─────────────┐              ┌─────────────┐              ┌─────────────┐
   │STG_PATIENTS │              │STG_APPOINT- │              │ STG_BILLING │
   │   (view)    │              │MENTS (view) │              │   (view)    │
   └──────┬──────┘              └──────┬──────┘              └──────┬──────┘
          │                            │                            │
          └────────────────────────────┼────────────────────────────┘
                                       │
                                       ▼
                            ┌─────────────────────┐
                            │  PATIENT_ANALYTICS  │
                            │  (dynamic table)    │
                            └──────────┬──────────┘
                                       │
                         ┌─────────────┼─────────────┐
                         │                           │
                         ▼                           ▼
              ┌─────────────────┐         ┌─────────────────┐
              │REVENUE_DASHBOARD│         │DEPARTMENT_METRICS│
              │ (secure view)   │         │  (secure view)   │
              └────────┬────────┘         └─────────────────┘
                       │
                       ▼
              ┌─────────────────┐
              │  SECURE SHARE   │──────▶  Internal Marketplace
              │+ CORTEX AGENT   │──────▶  AI-Powered Analytics
              └─────────────────┘
```

---

### Slide 4: Governance Features

| Feature | Implementation | Why |
|---------|---------------|-----|
| **Object Tags** | PII_LEVEL (HIGH/MEDIUM/LOW), DATA_CLASSIFICATION (PHI/PII/FINANCIAL) | One tag drives multiple policies; compliance audit in one query |
| **Masking Policy** | Tag-based: reads PII_LEVEL to decide mask level per role | Single policy scales to all PII columns automatically |
| **Row Access Policy** | Department-scoped: clinical staff sees only their patients | Enforces need-to-know without application logic |
| **Aggregation Policy** | Min group size = 5 on billing data | Prevents re-identification from financial analytics |
| **Join Policy** | Analysts must join PATIENTS (no standalone SELECT) | Prevents bulk PII export |
| **Projection Policy** | Blocks medication_name for analyst role | Stops linking prescriptions to individuals |

---

### Slide 5: Lineage & Quality

**Lineage** (via `SNOWFLAKE.CORE.GET_LINEAGE`):
- Downstream: "If I change PATIENTS, what breaks?" → 4 dependent objects
- Upstream: "Where does REVENUE_DASHBOARD data come from?" → 3 source tables
- Column-level: "Does SSN leak downstream?" → Tracks through every hop

**Data Quality** (via DMFs):
- System DMFs: NULL_COUNT, DUPLICATE_COUNT, ROW_COUNT
- Custom DMFs: SSN format validation, phone format validation
- Results visible in Snowsight Data Governance tab
- Scheduled to run every hour automatically

---

### Slide 6: Sharing & Agentic AI

**Data Sharing:**
- Secure views enforce all policies even for consumers
- Zero-copy: no data movement, real-time access
- Share contains only aggregated, de-identified views

**Cortex Agent:**
- Backed by a semantic model (YAML) defining metrics and dimensions
- Answers natural language: "What is the no-show rate by department?"
- Distributable via internal marketplace listing
- Consumers get data AND the AI interface in one package

---

### Slide 7: Key Takeaways

1. **Tag once, protect everywhere** — One masking policy + tags = coverage across all PII columns
2. **Defense in depth** — 5 policy types work together (no single point of failure)
3. **Automated quality** — DMFs catch bad data without manual queries
4. **Built-in lineage** — No external tools needed for impact analysis
5. **AI + Governance** — Share governed data with an AI agent attached

**All governance is enforced at the platform level — no application code required.**
