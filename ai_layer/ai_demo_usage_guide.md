# AI and Dashboard Demo Usage Guide

Ready-to-use prompts and walkthroughs for demoing the Streamlit apps, Cortex Analyst, Search, and Enterprise Agent.

---

## Quick Access

| Resource | Location |
|----------|----------|
| Pharma Intelligence App | Snowsight > Streamlit > `DEMO.HEALTHCARE_DEMO.PHARMA_INTELLIGENCE_APP` |
| Demo Story Dashboard | Snowsight > Streamlit > `DEMO.HEALTHCARE_DEMO.DEMO_STORY_DASHBOARD` |
| Enterprise Agent | Snowsight > Cortex Agents > `DEMO.HEALTHCARE_DEMO.ENTERPRISE_INTELLIGENCE_AGENT` |
| Pharma Agent | Snowsight > Cortex Agents > `DEMO.HEALTHCARE_DEMO.PHARMA_INTELLIGENCE_AGENT` |

---

## 1. Pharma Intelligence App (4 Tabs)

### Tab 1: Analyst (Text-to-SQL)

Uses semantic view: `DEMO.HEALTHCARE_DEMO.PHARMA_COMMERCIAL_INTELLIGENCE`

**Example Prompts:**

| Prompt | What It Demonstrates |
|--------|---------------------|
| "What is the total prescription volume by drug?" | Basic aggregation across joined tables (RX_METRICS + DIM_DRUG) |
| "Which territories have the most new patient starts?" | Filtering by METRIC_NAME + joining to DIM_TERRITORY |
| "Show me HCP tier distribution by specialty" | Grouping on multiple dimensions |
| "What are the top 5 drugs by annual revenue?" | Simple sort on a dimension table |
| "What is the average engagement duration by channel?" | Aggregation on the ENGAGEMENTS table |

**What to expect:** Generated SQL appears in an expandable section, followed by a data table. If the result has 2+ columns with a text + numeric pair, a bar chart renders automatically.

**Good follow-up:** "Now show me only oncology drugs" — demonstrates conversational refinement.

---

### Tab 2: HCP and Drug Search

Uses: `PHARMA_SEARCH_SERVICE` (Cortex Search over 10K HCP profiles)

**Example Prompts:**

| Prompt | What It Demonstrates |
|--------|---------------------|
| "Cardiology specialists in the Northeast" | Semantic search by specialty + region |
| "Top tier oncologists" | Natural language tier filtering |
| "Neurologists with high engagement" | Concept-level search (not exact column match) |
| "Primary care providers in Western territory" | Standardized specialty matching |
| "Immunology HCPs Tier 1" | Direct attribute matching |

**Filter options:** Use the "Filter by specialty" dropdown to narrow results.

**What to expect:** Table of matching HCP profiles with name, specialty, standardized specialty, territory, region, and tier.

---

### Tab 3: AI Enrichment

Shows pre-computed AI classifications on drug and engagement data.

**No prompts needed** — this tab displays results of `AI_CLASSIFY` and `AI_SENTIMENT` already applied to data. Point out:
- Therapeutic area classification (AI-assigned vs original)
- Engagement sentiment scores
- How this runs at scale on all 80K engagement records

---

### Tab 4: Agent

Provides direct links to the published agents in Snowsight CoWork.

**Test via Snowsight Preview tab** (navigate to the agent, click Preview):

| Prompt | What It Demonstrates |
|--------|---------------------|
| "What are the top 5 drugs by total prescription volume?" | Analyst tool calling semantic view |
| "Find me top tier oncologists in the Northeast" | Search tool over HCP profiles |
| "What is the engagement effectiveness for top-tier HCPs?" | Uses derived fact ENGAGEMENT_EFFECTIVENESS |
| "Show HCP tier distribution by specialty" | Routes to Analyst |

**What to expect:** The agent uses `pharma_analyst` (Cortex Analyst with `claude-haiku-4-5`) for data queries and `hcp_search` (Cortex Search) for finding HCPs. Responses include thinking steps, tool calls, and final answers with data.

---

## 2. Demo Story Dashboard (6 Tabs)

### Tab: Overview

**What it shows:** Platform-wide metrics — total records across all tables, pipeline status, schema object counts.

**Key callout:** "150K+ records across 4 domains, all on one platform."

### Tab: Healthcare

**What it shows:** Rx volume by drug, HCP tier distribution chart, engagement heatmap by channel/type.

**Key callout:** "This is the output of our PySpark Code Bundle pipeline — transformed on Snowflake warehouse compute."

### Tab: CRM

**What it shows:** Customer health score distribution, pipeline forecast by category, at-risk accounts.

**Key callout:** "Tableau would query this exact same data directly — no round-trip to Salesforce."

### Tab: Data Quality

**What it shows:** DMF results, violation counts by rule, golden record dedup stats.

**Key callout:** "These rules fire automatically when new data arrives via streams. AI suggests new rules as schemas evolve."

### Tab: Enterprise AI

**What it shows:** Semantic model registry, domain coverage, agent routing demonstration.

**Key callout:** "One agent spans 9 registered domains. Adding a new domain is one semantic view + one registry row."

### Tab: Governance

**What it shows:** Tag coverage across tables, compliance framework mapping, source system provenance.

**Key callout:** "Same governance applies whether data comes from SAP, Salesforce, or internal systems."

---

## 3. Enterprise Agent (Direct — Cross-Domain)

Object: `DEMO.HEALTHCARE_DEMO.ENTERPRISE_INTELLIGENCE_AGENT`

Access: Snowsight > Cortex Agents > ENTERPRISE_INTELLIGENCE_AGENT > Preview tab

Model: `claude-haiku-4-5` | Tools: `pharma_analyst`, `crm_analyst`, `finance_analyst`, `hcp_search`

**Cross-domain prompts that demonstrate routing:**

| Prompt | Routes To | Why It Is Impressive |
|--------|-----------|---------------------|
| "What are the top 5 drugs by total prescription volume?" | pharma_analyst | Agent routes to pharma semantic view |
| "What is the pipeline conversion rate by stage?" | crm_analyst | Routes to CRM domain |
| "What is the revenue forecast variance this quarter?" | finance_analyst | Routes to finance domain |
| "Find me Tier 1 oncologists in the Northeast" | hcp_search | Uses Cortex Search over HCP profiles |
| "Which sales reps have the highest win rates?" | crm_analyst | CRM pipeline analytics |
| "Show me cost center budget utilization" | finance_analyst | Uses BURN_RATE_PCT derived fact |

**Power demo sequence (show all domains in one conversation):**

1. "What are the top 5 drugs by prescription volume?" (pharma_analyst)
2. "Now show me pipeline conversion rates" (crm_analyst — domain switch)
3. "What about budget variance by product line?" (finance_analyst — third domain)
4. "Find me top tier oncologists" (hcp_search — search tool)

**What to expect:** The agent selects the appropriate tool based on the question. Responses include thinking steps, SQL generation via Cortex Analyst, and formatted results.

---

## 4. Cortex Analyst (Direct — via Snowsight)

Test semantic views directly in Snowsight without the Agent:

1. Navigate to: Snowsight > AI & ML > Cortex Analyst
2. Select the semantic view from the dropdown
3. Type a question in natural language

**Semantic Views Available:**

| Semantic View | Domain | Example Question |
|---|---|---|
| `DEMO.HEALTHCARE_DEMO.PHARMA_COMMERCIAL_INTELLIGENCE` | Pharma | "What is the total Rx volume by therapeutic area?" |
| `DEMO.CRM_DEMO.CRM_COMMERCIAL_INTELLIGENCE` | CRM | "What is the forecast breakdown by category?" |
| `DEMO.HEALTHCARE_DEMO.FINANCE_SUMMARY` | Finance | "Show budget variance by cost center" |

**Via REST API (programmatic):**

```bash
curl -X POST "https://<ACCOUNT_LOCATOR>.snowflakecomputing.com/api/v2/databases/DEMO/schemas/HEALTHCARE_DEMO/agents/PHARMA_INTELLIGENCE_AGENT:run" \
  -H "Authorization: Bearer $SNOWFLAKE_PAT" \
  -H "Content-Type: application/json" \
  -H "X-Snowflake-Authorization-Token-Type: PROGRAMMATIC_ACCESS_TOKEN" \
  -d '{"messages": [{"role": "user", "content": [{"type": "text", "text": "Top 5 drugs by Rx volume"}]}]}'
```

---

## 5. Tips for Live Demo

### Good Prompts (clear, domain-specific)

- "What is [metric] by [dimension]?" — always works well
- "Which [entities] have the highest/lowest [metric]?"
- "Show me [metric] for [filter condition]"
- "Compare [metric] across [dimension values]"

### Prompts to Avoid (may produce unclear results)

- Vague: "Tell me about the data" (no specific metric or dimension)
- Multi-hop: "What is the Rx volume for HCPs who are engaged in oncology drugs in the Northeast?" (too many joins)
- Time-series without dates: "Show me the trend" (no time dimension in most of our tables)

### Recovery Phrases (if something fails)

- "Let me rephrase that — what I mean is [simpler version]"
- "Let me try a more specific question..."
- If Agent routes wrong: "I meant this for the [Healthcare/CRM/Finance] domain — [rephrase with domain keywords]"

### Live Demo Checklist

- [ ] Verify Streamlit apps are accessible (may need `ALTER STREAMLIT ... SET COMMENT` to bust cache)
- [ ] Test one prompt per tab before the audience arrives
- [ ] Have the Enterprise Agent Preview tab open in a separate Snowsight tab
- [ ] Keep `SHOW SEMANTIC VIEWS IN DATABASE DEMO` ready to show governance angle
- [ ] Confirm `PHARMA_SEARCH_SERVICE` is ACTIVE (not suspended): `SHOW CORTEX SEARCH SERVICES IN SCHEMA DEMO.HEALTHCARE_DEMO`
- [ ] Have a SQL worksheet open with backup queries in case AI features are slow

---

## 6. Backup SQL Queries (If AI Features Are Unavailable)

Run these directly to show the same insights:

```sql
-- Top drugs by Rx volume
SELECT d.DRUG_NAME, d.THERAPEUTIC_AREA, SUM(m.METRIC_VALUE) AS total_volume
FROM DEMO.HEALTHCARE_DEMO.RX_METRICS_OUTPUT m
JOIN DEMO.HEALTHCARE_DEMO.DIM_DRUG d ON m.DRUG_ID = d.DRUG_ID
WHERE m.METRIC_NAME = 'total_rx_volume'
GROUP BY d.DRUG_NAME, d.THERAPEUTIC_AREA
ORDER BY total_volume DESC;

-- At-risk accounts with exposure
SELECT ACCOUNT_NAME, INDUSTRY, REGION, HEALTH_SCORE,
       TOTAL_PIPELINE + WON_REVENUE AS REVENUE_EXPOSURE
FROM DEMO.CRM_DEMO.CUSTOMER_360
WHERE SEGMENT = 'At Risk'
ORDER BY REVENUE_EXPOSURE DESC;

-- Budget variance by product line
SELECT PRODUCT_LINE, REGION,
       SUM(ACTUAL_REVENUE) - SUM(BUDGET_REVENUE) AS variance
FROM DEMO.HEALTHCARE_DEMO.FINANCE_REVENUE_SUMMARY
GROUP BY PRODUCT_LINE, REGION
ORDER BY variance DESC;

-- HCP tier distribution
SELECT TIER, COUNT(*) AS hcp_count
FROM DEMO.HEALTHCARE_DEMO.HCP_TIERED_PROFILES
GROUP BY TIER ORDER BY hcp_count DESC;
```
