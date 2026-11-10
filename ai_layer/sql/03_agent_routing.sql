-- ============================================================
-- Agent Routing at Scale
-- Semantic model registry + Cortex Search router + multi-tool agent
-- ============================================================
-- Demonstrates the pattern for an agent spanning 10K+ tables:
--   1. Registry of domain semantic models (metadata searchable)
--   2. Cortex Search indexes the registry for tool routing
--   3. Enterprise agent uses search to find relevant domain, then queries it
-- ============================================================

USE ROLE SYSADMIN;
USE WAREHOUSE MY_WH;
USE SCHEMA DEMO.HEALTHCARE_DEMO;

-- ============================================================
-- 1. Semantic Model Registry
-- In production, this would contain 100s of domain entries
-- ============================================================

CREATE OR REPLACE TABLE SEMANTIC_MODEL_REGISTRY (
    MODEL_NAME VARCHAR(200),
    DOMAIN VARCHAR(100),
    SUBDOMAIN VARCHAR(100),
    DESCRIPTION VARCHAR(2000),
    TABLE_COUNT INTEGER,
    KEY_METRICS VARCHAR(1000),
    KEY_DIMENSIONS VARCHAR(1000),
    BUSINESS_QUESTIONS VARCHAR(2000),
    STAGE_PATH VARCHAR(500),
    OWNER_TEAM VARCHAR(100),
    LAST_UPDATED DATE,
    SEARCH_TEXT VARCHAR(4000)
);

INSERT INTO SEMANTIC_MODEL_REGISTRY VALUES
-- Real models (deployed)
('pharma_commercial_intelligence', 'Healthcare', 'Commercial Analytics',
 'Pharmaceutical commercial analytics covering prescription volume metrics, HCP specialty classification and engagement tiering, and sales rep engagement attribution with drug/territory/region enrichment.',
 7, 'METRIC_VALUE, CONFIDENCE, DURATION_MINUTES, SAMPLES_DROPPED, ANNUAL_REVENUE_MM, ENGAGEMENT_EFFECTIVENESS',
 'DRUG_NAME, SPECIALTY, TERRITORY_NAME, REGION_NAME, CHANNEL, ENGAGEMENT_TYPE, THERAPEUTIC_AREA',
 'What is the total prescription volume by drug? Which territories have the most new patient starts? How are HCPs distributed across tiers? What is engagement volume by channel?',
 '@DEMO.HEALTHCARE_DEMO.SEMANTIC_MODELS/pharma_commercial_intelligence.yaml -- Semantic View: DEMO.HEALTHCARE_DEMO.PHARMA_COMMERCIAL_INTELLIGENCE',
 'Commercial Analytics', '2026-08-20',
 'Healthcare pharmaceutical prescription volume HCP provider specialty tier engagement drug territory region channel sales rep detailing samples duration'),

('crm_commercial_intelligence', 'CRM', 'Customer Analytics',
 'CRM analytics for Salesforce one-hop-reduction. Customer health scoring, pipeline forecasting, opportunity management, and account segmentation with multi-step derived metrics.',
 5, 'HEALTH_SCORE, WIN_RATE, TOTAL_PIPELINE, WEIGHTED_PIPELINE, VELOCITY_SCORE, REVENUE_AT_RISK, EXPANSION_POTENTIAL',
 'SEGMENT, INDUSTRY, REGION, STAGE, FORECAST_CATEGORY, ACCOUNT_NAME',
 'Which accounts are at risk? What is the weighted pipeline by region? What is the forecast by category? Which industries have expansion potential?',
 '@DEMO.HEALTHCARE_DEMO.SEMANTIC_MODELS/crm_commercial_intelligence.yaml -- Semantic View: DEMO.CRM_DEMO.CRM_COMMERCIAL_INTELLIGENCE',
 'Revenue Operations', '2026-08-20',
 'CRM Salesforce customer account health score pipeline forecast opportunity win rate segment at risk expansion revenue sales'),

('finance_summary', 'Finance', 'FPA',
 'Financial analytics covering revenue recognition by product line and region, cost center budget tracking, forecast variance, and burn rate analysis.',
 3, 'ACTUAL_REVENUE, BUDGET_REVENUE, VARIANCE_TO_BUDGET, VARIANCE_PCT, FORECAST_ACCURACY, ACTUAL_SPEND, BURN_RATE_PCT',
 'PRODUCT_LINE, REGION, REVENUE_TYPE, COST_CENTER_NAME, EXPENSE_CATEGORY, PERIOD',
 'What is the revenue variance by product line? Which cost centers are over budget? What is forecast accuracy?',
 '@DEMO.HEALTHCARE_DEMO.SEMANTIC_MODELS/finance_summary.yaml -- Semantic View: DEMO.HEALTHCARE_DEMO.FINANCE_SUMMARY',
 'FPA', '2026-08-20',
 'Finance revenue budget variance forecast cost center spend burn rate product line FPA actual vs plan'),

-- Simulated models (not deployed — demonstrate registry scale)
('supply_chain_logistics', 'Operations', 'Supply Chain',
 'Supply chain and logistics analytics: inventory levels, lead times, supplier performance, distribution center throughput, and order fulfillment rates.',
 12, 'INVENTORY_LEVEL, LEAD_TIME_DAYS, FILL_RATE, ON_TIME_DELIVERY_PCT, THROUGHPUT_UNITS',
 'WAREHOUSE, SUPPLIER, SKU, PRODUCT_CATEGORY, DISTRIBUTION_CENTER, SHIPPING_MODE',
 'What are current inventory levels by warehouse? Which suppliers have the longest lead times? What is our on-time delivery rate?',
 '@DEMO.HEALTHCARE_DEMO.SEMANTIC_MODELS/supply_chain_logistics.yaml',
 'Supply Chain Ops', '2026-07-15',
 'Supply chain logistics inventory warehouse supplier lead time delivery fulfillment distribution shipping SKU'),

('hr_workforce', 'Human Resources', 'People Analytics',
 'Workforce analytics: headcount, attrition, compensation benchmarks, diversity metrics, hiring pipeline, and employee engagement scores.',
 8, 'HEADCOUNT, ATTRITION_RATE, AVG_COMPENSATION, DIVERSITY_INDEX, ENGAGEMENT_SCORE, TIME_TO_HIRE',
 'DEPARTMENT, LOCATION, JOB_LEVEL, GENDER, TENURE_BAND, HIRING_SOURCE',
 'What is our attrition rate by department? How does compensation compare to market? What is time-to-hire by role?',
 '@DEMO.HEALTHCARE_DEMO.SEMANTIC_MODELS/hr_workforce.yaml',
 'People Analytics', '2026-08-01',
 'HR human resources workforce headcount attrition compensation salary diversity hiring engagement employee department'),

('manufacturing_quality', 'Operations', 'Manufacturing',
 'Manufacturing quality and production analytics: batch yield, defect rates, equipment OEE, production scheduling, and quality audit results.',
 10, 'BATCH_YIELD_PCT, DEFECT_RATE_PPM, OEE_SCORE, CYCLE_TIME_HOURS, AUDIT_SCORE',
 'PRODUCTION_LINE, FACILITY, PRODUCT, SHIFT, EQUIPMENT_ID, QUALITY_GRADE',
 'What is our batch yield by production line? Which equipment has the lowest OEE? What are defect trends?',
 '@DEMO.HEALTHCARE_DEMO.SEMANTIC_MODELS/manufacturing_quality.yaml',
 'Manufacturing Excellence', '2026-07-28',
 'Manufacturing quality production batch yield defect OEE equipment facility line shift audit GMP'),

('clinical_trials', 'Healthcare', 'R and D',
 'Clinical trial analytics: enrollment rates, site performance, adverse events, protocol deviations, and milestone tracking across trial phases.',
 15, 'ENROLLMENT_RATE, SCREEN_FAIL_PCT, AE_COUNT, PROTOCOL_DEVIATIONS, MILESTONE_ADHERENCE',
 'TRIAL_ID, PHASE, THERAPEUTIC_AREA, SITE, COUNTRY, INVESTIGATOR, INDICATION',
 'What is enrollment rate by site? Which trials have the most protocol deviations? How are we tracking to milestones?',
 '@DEMO.HEALTHCARE_DEMO.SEMANTIC_MODELS/clinical_trials.yaml',
 'Clinical Operations', '2026-08-10',
 'Clinical trials R and D enrollment site investigator adverse events protocol deviation phase therapeutic area indication milestone'),

('marketing_campaigns', 'Marketing', 'Digital',
 'Marketing campaign analytics: digital spend, impression/click/conversion funnels, channel attribution, ROI by campaign, and audience segmentation.',
 6, 'IMPRESSIONS, CLICKS, CONVERSIONS, COST_PER_ACQUISITION, ROAS, ENGAGEMENT_RATE',
 'CAMPAIGN_NAME, CHANNEL, AUDIENCE_SEGMENT, CREATIVE_TYPE, PLATFORM, GEOGRAPHY',
 'What is our ROAS by channel? Which campaigns have the best conversion rate? What is cost per acquisition by segment?',
 '@DEMO.HEALTHCARE_DEMO.SEMANTIC_MODELS/marketing_campaigns.yaml',
 'Digital Marketing', '2026-08-05',
 'Marketing campaigns digital advertising spend impressions clicks conversions CPA ROAS channel attribution audience segment'),

('regulatory_compliance', 'Legal', 'Compliance',
 'Regulatory compliance tracking: submission timelines, inspection findings, CAPA status, labeling changes, and post-market surveillance.',
 9, 'OPEN_SUBMISSIONS, INSPECTION_FINDINGS, CAPA_CLOSURE_RATE, DAYS_TO_APPROVAL, ADVERSE_EVENT_REPORTS',
 'REGULATORY_BODY, MARKET, SUBMISSION_TYPE, FINDING_CATEGORY, CAPA_STATUS, PRODUCT',
 'How many open regulatory submissions do we have? What is our CAPA closure rate? Are there inspection findings trends?',
 '@DEMO.HEALTHCARE_DEMO.SEMANTIC_MODELS/regulatory_compliance.yaml',
 'Regulatory Affairs', '2026-07-20',
 'Regulatory compliance FDA EMA submission inspection CAPA findings labeling post-market surveillance adverse event');

-- ============================================================
-- 2. Cortex Search over Registry (model router)
-- ============================================================

CREATE OR REPLACE CORTEX SEARCH SERVICE MODEL_ROUTER_SEARCH
  ON SEARCH_TEXT
  ATTRIBUTES MODEL_NAME, DOMAIN, SUBDOMAIN, DESCRIPTION, KEY_METRICS, KEY_DIMENSIONS, STAGE_PATH, OWNER_TEAM
  WAREHOUSE = MY_WH
  TARGET_LAG = '1 hour'
  AS (SELECT SEARCH_TEXT, MODEL_NAME, DOMAIN, SUBDOMAIN, DESCRIPTION,
             KEY_METRICS, KEY_DIMENSIONS, STAGE_PATH, OWNER_TEAM
      FROM SEMANTIC_MODEL_REGISTRY);

-- ============================================================
-- 3. Enterprise Multi-Domain Agent
-- Routes questions to the appropriate domain analyst
-- ============================================================

CREATE OR REPLACE AGENT ENTERPRISE_INTELLIGENCE_AGENT
SPEC = 'tools:
  - tool_spec:
      type: cortex_search
      name: domain_router
      description: "Search across all analytics domains to find the right data source for a question. Use this first to identify which domain can answer the user''s question."
    tool_resources:
      cortex_search_service: DEMO.HEALTHCARE_DEMO.MODEL_ROUTER_SEARCH
  - tool_spec:
      type: cortex_analyst
      name: pharma_analytics
      description: "Healthcare/pharmaceutical analytics: prescription volume, HCP profiles, engagement metrics, drug performance, territory analysis"
    tool_resources:
      semantic_view: DEMO.HEALTHCARE_DEMO.PHARMA_COMMERCIAL_INTELLIGENCE
  - tool_spec:
      type: cortex_analyst
      name: crm_analytics
      description: "CRM/Salesforce analytics: customer health scores, pipeline forecast, opportunity management, account segmentation, win rates"
    tool_resources:
      semantic_view: DEMO.CRM_DEMO.CRM_COMMERCIAL_INTELLIGENCE
  - tool_spec:
      type: cortex_analyst
      name: finance_analytics
      description: "Finance/FPA analytics: revenue vs budget, cost center spend, forecast accuracy, variance analysis"
    tool_resources:
      semantic_view: DEMO.HEALTHCARE_DEMO.FINANCE_SUMMARY
  - tool_spec:
      type: cortex_search
      name: hcp_search
      description: "Find specific healthcare providers by name, specialty, tier, or territory"
    tool_resources:
      cortex_search_service: DEMO.HEALTHCARE_DEMO.PHARMA_SEARCH_SERVICE
model: mistral-large2
system_prompt: "You are an enterprise intelligence assistant spanning multiple business domains (Healthcare, CRM, Finance, and more). When a user asks a question: 1) Use the domain_router to identify which analytics domain is most relevant, 2) Use the appropriate analyst tool to query the data, 3) Provide a concise, data-driven answer. If unsure which domain, search first. Always cite the data source domain in your response."';

-- ============================================================
-- 4. Verify
-- ============================================================

SELECT DOMAIN, COUNT(*) AS model_count, SUM(TABLE_COUNT) AS total_tables
FROM SEMANTIC_MODEL_REGISTRY
GROUP BY DOMAIN
ORDER BY total_tables DESC;
