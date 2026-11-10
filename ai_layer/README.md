# AI Layer

Snowflake Cortex AI capabilities layered on the pipeline outputs. Includes multi-domain semantic models, an enterprise routing agent, Cortex Search, AI Functions, and a Streamlit dashboard.

## Components

| Component | File/Object | Purpose |
|-----------|-------------|---------|
| Healthcare Semantic View | `DEMO.HEALTHCARE_DEMO.PHARMA_COMMERCIAL_INTELLIGENCE` | Text-to-SQL for Rx metrics, HCP profiles, engagements |
| CRM Semantic View | `DEMO.CRM_DEMO.CRM_COMMERCIAL_INTELLIGENCE` | Customer 360, pipeline forecast with derived metrics |
| Finance Semantic View | `DEMO.HEALTHCARE_DEMO.FINANCE_SUMMARY` | Revenue variance, cost center budget tracking |
| Multi-Domain Setup | `sql/02_multi_domain_setup.sql` | Finance tables + data generation |
| Semantic Views | `sql/04_semantic_views.sql` | Deploy 3 native semantic views via SYSTEM$CREATE_SEMANTIC_VIEW_FROM_YAML |
| Cortex Search | `PHARMA_SEARCH_SERVICE` | Semantic HCP search (10K docs indexed) |
| Model Router | `MODEL_ROUTER_SEARCH` | Search across domain registry for routing |
| Domain Agent | `PHARMA_INTELLIGENCE_AGENT` | Healthcare-focused (Search + Analyst), model: claude-haiku-4-5 |
| Enterprise Agent | `ENTERPRISE_INTELLIGENCE_AGENT` | Multi-domain routing (Healthcare + CRM + Finance + Search) |
| Streamlit App | `PHARMA_INTELLIGENCE_APP` | 4-tab dashboard |

## Semantic Views with Complex Business Rules

Each semantic view (native Snowflake objects, not YAML files) demonstrates multi-step derived facts:

**Healthcare:**
- `METRIC_VALUE_NORMALIZED` — volume normalized against territory average
- `ENGAGEMENT_EFFECTIVENESS` — composite: duration (40%) + samples (30%) + channel value (30%)

**CRM:**
- `REVENUE_AT_RISK` — conditional exposure for at-risk accounts
- `EXPANSION_POTENTIAL` — pipeline * win_rate * (1 + health/100)
- `CASE_BURDEN_RATIO` — open cases per open opportunity
- `DEAL_QUALITY_INDEX` — weighted pipeline per day remaining

**Finance:**
- `VARIANCE_TO_BUDGET` / `VARIANCE_PCT` — actuals vs plan
- `FORECAST_ACCURACY` — 1 - |actual - forecast| / forecast
- `BURN_RATE_PCT` — spend / allocation * 100

## Agent Architecture

Agents use Cortex Agent with `claude-haiku-4-5` model and tools:

```
User question → Agent (LIVE version) → Tool Selection → Response
                                         ├─ pharma_analyst (semantic view + warehouse)
                                         ├─ crm_analyst (semantic view + warehouse)
                                         ├─ finance_analyst (semantic view + warehouse)
                                         └─ hcp_search (Cortex Search service)
```

The `ENTERPRISE_INTELLIGENCE_AGENT` has all 4 tools. The `PHARMA_INTELLIGENCE_AGENT` has pharma_analyst + hcp_search.

**Critical configuration:** Each `cortex_analyst_text_to_sql` tool MUST have `execution_environment.warehouse` specified.

## Deploy

Deployed as part of `bootstrap.sh` (Phase 5) and `deploy_all.sh` (Steps 1 + 5). To deploy individually:

```bash
# Create semantic views (native objects)
snow sql -f ai_layer/sql/04_semantic_views.sql -c my_conn

# Create finance tables
snow sql -f ai_layer/sql/02_multi_domain_setup.sql -c my_conn

# Create agents (uses CREATE AGENT, NOT CREATE OR REPLACE)
# See sql/03_agent_routing.sql or use the cortex-agent-jp skill
```

**Important:** Agents must be created with `CREATE AGENT` (not `CREATE OR REPLACE`) to get a LIVE version. See the `cortex-agent-jp` skill for the correct workflow.

## Testing

```bash
# Test agent via REST API (correct object-based endpoint)
curl -s -N -X POST "https://<ACCOUNT_LOCATOR>.snowflakecomputing.com/api/v2/databases/DEMO/schemas/HEALTHCARE_DEMO/agents/PHARMA_INTELLIGENCE_AGENT:run" \
  -H "Authorization: Bearer $SNOWFLAKE_PAT" \
  -H "Content-Type: application/json" \
  -H "X-Snowflake-Authorization-Token-Type: PROGRAMMATIC_ACCESS_TOKEN" \
  -d '{"messages": [{"role": "user", "content": [{"type": "text", "text": "What are the top 5 drugs by prescription volume?"}]}]}'
```

Or test in Snowsight: Navigate to Cortex Agents > PHARMA_INTELLIGENCE_AGENT > Preview tab.

```sql
-- Verify agent has LIVE version (required for it to work)
SHOW VERSIONS IN AGENT DEMO.HEALTHCARE_DEMO.PHARMA_INTELLIGENCE_AGENT;
-- Must show a row with '/versions/live/' in spec_file_path

-- Verify semantic views
SHOW SEMANTIC VIEWS IN DATABASE DEMO;

-- Verify search service is active
SHOW CORTEX SEARCH SERVICES IN SCHEMA DEMO.HEALTHCARE_DEMO;
```
