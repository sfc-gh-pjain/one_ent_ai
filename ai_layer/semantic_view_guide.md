# Semantic Views: Understanding, Application, and Enterprise Value

## What is a Semantic View?

A Semantic View is a **first-class Snowflake database object** that defines a business-level data model over physical tables. It encodes:

- Which tables participate in a domain
- What the columns mean (dimensions vs. facts, with descriptions)
- How tables relate to each other (joins with cardinality)
- Computed business metrics (derived facts via SQL expressions)
- Verified queries (known-good question-to-SQL mappings)

Unlike a regular SQL view that transforms data, a semantic view transforms **understanding**. It tells AI systems and consumers what the data means, not just how to access it.

```
Regular View:   SELECT a, b, c FROM table WHERE x = 1    (transforms data)
Semantic View:  "REVENUE_AT_RISK means total exposure     (transforms meaning)
                 for accounts where SEGMENT = 'At Risk'"
```

## Anatomy of a Semantic View

```yaml
name: CRM_COMMERCIAL_INTELLIGENCE       # Object name in Snowflake

tables:                                   # Physical tables in this domain
  - name: CUSTOMER_360                    # Logical alias
    base_table: DEMO.CRM_DEMO.CUSTOMER_360
    primary_key: [ACCOUNT_ID]
    dimensions:                           # Categorical/grouping columns
      - name: SEGMENT
        description: "High Value, Growth, or At Risk"
    facts:                                # Measurable/aggregatable columns
      - name: HEALTH_SCORE
        description: "Composite 0-100"
      - name: REVENUE_AT_RISK             # DERIVED FACT (computed)
        expr: "CASE WHEN SEGMENT = 'At Risk' THEN TOTAL_PIPELINE + WON_REVENUE ELSE 0 END"

relationships:                            # How tables join
  - left_table: PIPELINE_FORECAST
    right_table: ACCOUNTS
    relationship_type: many_to_one
    join_on: ACCOUNT_ID = ACCOUNT_ID

verified_queries:                         # Known-good SQL for common questions
  - question: "Which accounts are at risk?"
    sql: "SELECT ... FROM CUSTOMER_360 WHERE SEGMENT = 'At Risk'"
```

### Key Components

| Component | Purpose | Example |
|-----------|---------|---------|
| **Tables** | Physical tables that participate in this domain | RX_METRICS_OUTPUT, DIM_DRUG |
| **Dimensions** | Columns you filter/group by | REGION, SPECIALTY, STAGE |
| **Facts** | Columns you measure/aggregate | METRIC_VALUE, AMOUNT, HEALTH_SCORE |
| **Derived Facts** | Business metrics computed from other columns | ENGAGEMENT_EFFECTIVENESS, DEAL_QUALITY_INDEX |
| **Relationships** | Join paths between tables with cardinality | RX_METRICS many-to-one DRUGS via DRUG_ID |
| **Verified Queries** | Pre-validated question/SQL pairs | "What is Rx volume by drug?" -> proven SQL |

## How It Connects to Our Demo

```
                    ┌─────────────────────────────────────────┐
                    │         SEMANTIC VIEWS (3)               │
                    │                                         │
                    │  PHARMA_COMMERCIAL_INTELLIGENCE         │
                    │  CRM_COMMERCIAL_INTELLIGENCE            │
                    │  FINANCE_SUMMARY                        │
                    └──────────────┬──────────────────────────┘
                                   │
                    ┌──────────────┼──────────────────────────┐
                    │              │                          │
                    ▼              ▼                          ▼
          ┌─────────────┐  ┌────────────┐          ┌─────────────────┐
          │ Cortex      │  │ Enterprise │          │ Streamlit       │
          │ Analyst     │  │ Agent      │          │ Dashboard       │
          │             │  │            │          │                 │
          │ Text-to-SQL │  │ Routes to  │          │ Analyst tab     │
          │ generation  │  │ correct    │          │ calls Analyst   │
          │ using the   │  │ domain via │          │ with the        │
          │ semantic    │  │ registry + │          │ semantic_view   │
          │ view model  │  │ search     │          │ parameter       │
          └─────────────┘  └────────────┘          └─────────────────┘
                    │              │                          │
                    └──────────────┼──────────────────────────┘
                                   │
                                   ▼
                          ┌────────────────┐
                          │   USER         │
                          │                │
                          │ "What is the   │
                          │  weighted      │
                          │  pipeline by   │
                          │  region?"      │
                          └────────────────┘
```

### The Flow

1. **User asks a question** (in Streamlit, via Agent, or directly to Analyst)
2. **Cortex Analyst** reads the semantic view definition to understand:
   - What tables exist and what they mean
   - How to join them correctly
   - What derived facts are available
   - What verified queries match this pattern
3. **SQL is generated** that correctly joins tables, applies the right aggregations, and uses the defined metrics
4. **Results returned** to the user with attribution to the domain

### Without a Semantic View

The same question ("What is revenue at risk?") would require:
- The user to know that REVENUE_AT_RISK is a conditional formula
- The user to know which table has SEGMENT, TOTAL_PIPELINE, WON_REVENUE
- The user to know the filter condition (SEGMENT = 'At Risk')
- The AI to guess all of the above from raw column names

## Our 3 Deployed Semantic Views

### DEMO.HEALTHCARE_DEMO.PHARMA_COMMERCIAL_INTELLIGENCE

| Aspect | Details |
|--------|---------|
| **Domain** | Pharmaceutical commercial medicine |
| **Tables** | 6 (RX_METRICS, HCP_PROFILES, ENGAGEMENTS, DRUGS, TERRITORIES, REGIONS) |
| **Key Derived Fact** | `ENGAGEMENT_EFFECTIVENESS` = duration(40%) + samples(30%) + channel_value(30%) |
| **Relationships** | Rx -> Drug, Rx -> Territory -> Region |
| **Questions It Answers** | "What is Rx volume by drug?", "How are HCPs distributed by tier?", "Which channels are most effective?" |

### DEMO.CRM_DEMO.CRM_COMMERCIAL_INTELLIGENCE

| Aspect | Details |
|--------|---------|
| **Domain** | CRM / Sales operations |
| **Tables** | 3 (CUSTOMER_360, PIPELINE_FORECAST, ACCOUNTS) |
| **Key Derived Facts** | `REVENUE_AT_RISK`, `EXPANSION_POTENTIAL`, `DEAL_QUALITY_INDEX` |
| **Relationships** | Customer360 -> Accounts, Pipeline -> Accounts |
| **Questions It Answers** | "Which accounts are at risk?", "What is weighted pipeline by region?", "Which industries have expansion potential?" |

### DEMO.HEALTHCARE_DEMO.FINANCE_SUMMARY

| Aspect | Details |
|--------|---------|
| **Domain** | Financial planning and analysis |
| **Tables** | 2 (REVENUE_SUMMARY, COST_CENTERS) |
| **Key Derived Facts** | `VARIANCE_PCT`, `FORECAST_ACCURACY`, `BURN_RATE_PCT` |
| **Questions It Answers** | "What is revenue variance by product line?", "Which cost centers are over budget?" |

## Enterprise Relevance

### 1. Governance as Code

Semantic views are governed objects:
- **RBAC**: `GRANT SELECT ON SEMANTIC VIEW ... TO ROLE analyst_role`
- **Tags**: Can be tagged with SOURCE_SYSTEM, COMPLIANCE_FRAMEWORK
- **Lineage**: Appears in Snowflake lineage graphs — who uses this view, what tables feed it
- **Access History**: Every query against the semantic view is logged

This means your business definitions are governed with the same rigor as your data.

### 2. Discoverability

Semantic views appear in:
- `SHOW SEMANTIC VIEWS` (programmatic discovery)
- Snowsight catalog (visual browsing)
- Snowflake Horizon (data governance catalog)
- Cortex Search (if indexed)

Data consumers find business concepts, not raw table names.

### 3. Single Source of Truth for Business Logic

Without semantic views, the formula for REVENUE_AT_RISK lives in:
- A Tableau calculated field
- A dbt model
- A Python notebook
- A BI report definition
- Someone's head

With a semantic view, it lives in ONE place. Every consumer — Analyst, Agent, Streamlit, Tableau — uses the same definition.

### 4. Scale Pattern (Multi-Domain Federation)

For enterprises with thousands of tables:

```
┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│ Healthcare  │    │    CRM      │    │  Finance    │
│ Semantic    │    │  Semantic   │    │  Semantic   │
│ View        │    │  View       │    │  View       │
│ (6 tables)  │    │ (3 tables)  │    │ (2 tables)  │
└──────┬──────┘    └──────┬──────┘    └──────┬──────┘
       │                  │                  │
       └──────────────────┼──────────────────┘
                          │
                ┌─────────┴─────────┐
                │  ENTERPRISE       │
                │  INTELLIGENCE     │
                │  AGENT            │
                │                   │
                │  Routes questions │
                │  to correct       │
                │  domain           │
                └───────────────────┘
```

Each domain team owns their semantic view independently. The enterprise agent routes across all of them. Adding a new domain = adding one semantic view + one registry entry.

### 5. Shareable as a Data Product

Semantic views can be:
- Attached to Snowflake Marketplace listings
- Shared via data sharing (grants across accounts)
- Published as organizational data products

A YAML file on a stage cannot do any of these.

### 6. Validated at Deploy Time

When you create a semantic view, Snowflake validates:
- All referenced tables exist
- All columns in expressions exist
- Join columns match types
- Primary keys are declared for dimension tables in relationships

Errors are caught at creation time, not when a user asks a question and gets a cryptic failure.

## Semantic View vs Alternatives

| Capability | Semantic View | YAML on Stage | Regular View | BI Semantic Layer |
|---|---|---|---|---|
| **Object type** | Native DB object | File on stage | Native DB object | External tool |
| **RBAC** | Standard grants | Stage-level only | Standard grants | Tool-specific |
| **Catalog discovery** | Snowsight + Horizon | Hidden | Snowsight | Tool-specific |
| **Lineage tracking** | Yes | No | Yes | External |
| **Shareable (listings)** | Yes | No | Yes (data only) | No |
| **Validation at deploy** | Yes | No (runtime only) | Yes (SQL only) | Tool-specific |
| **Business descriptions** | Per column | Per column | No | Tool-specific |
| **Derived metrics** | expr: fields | expr: fields | SQL logic | Calculated fields |
| **Verified queries** | Built-in | Built-in | N/A | N/A |
| **AI-native** | Cortex Analyst + Agent | Cortex Analyst only | No | No |
| **Tagging/governance** | Tags, masking, audit | No | Tags, masking, audit | External |
| **Multi-domain routing** | Agent references view | Agent references stage path | Manual | Manual |

## Key Takeaway

A semantic view is the **executable business glossary** for your data platform. It is not documentation that sits next to your data — it IS the layer through which AI and consumers understand your data. When you define ENGAGEMENT_EFFECTIVENESS once in a semantic view, every question about engagement effectiveness — from any user, through any interface — uses the same validated formula.

For our demo, the three semantic views transform raw pipeline outputs into a governed, discoverable, AI-ready analytics layer that scales from 3 domains to 300 without changing the architecture.
