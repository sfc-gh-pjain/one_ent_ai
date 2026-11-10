-- ============================================================
-- Semantic Views: Deploy 3 domain semantic views
-- Uses SYSTEM$CREATE_SEMANTIC_VIEW_FROM_YAML
-- Deploy: snow sql -f ai_layer/sql/04_semantic_views.sql -c my_conn
-- ============================================================

-- 1. PHARMA COMMERCIAL INTELLIGENCE (Healthcare Domain)
CALL SYSTEM$CREATE_SEMANTIC_VIEW_FROM_YAML(
  'DEMO.HEALTHCARE_DEMO',
  $$
name: PHARMA_COMMERCIAL_INTELLIGENCE
description: |
  Commercial medicine analytics for a pharmaceutical company. Covers prescription volume
  metrics by drug and territory, HCP specialty classification and engagement tiering,
  and sales rep engagement attribution with drug/territory/region enrichment.

tables:
  - name: RX_METRICS
    base_table:
      database: DEMO
      schema: HEALTHCARE_DEMO
      table: RX_METRICS_OUTPUT
    dimensions:
      - name: DS
        expr: DS
        description: Date of the metric computation
        data_type: TEXT
      - name: METRIC_NAME
        expr: METRIC_NAME
        description: Type of metric (total_rx_volume, new_patient_starts)
        data_type: TEXT
      - name: DRUG_ID
        expr: DRUG_ID
        description: Drug identifier
        data_type: TEXT
      - name: TERRITORY_ID
        expr: TERRITORY_ID
        description: Territory identifier
        data_type: NUMBER
    facts:
      - name: METRIC_VALUE
        expr: METRIC_VALUE
        description: The metric value
        data_type: NUMBER
    time_dimensions:
      - name: ETL_TIMESTAMP
        expr: ETL_TIMESTAMP
        description: When the metric was last computed
        data_type: TIMESTAMP_NTZ

  - name: HCP_PROFILES
    base_table:
      database: DEMO
      schema: HEALTHCARE_DEMO
      table: HCP_TIERED_PROFILES
    dimensions:
      - name: HCP_ID
        expr: HCP_ID
        description: Unique HCP identifier
        data_type: TEXT
      - name: SPECIALTY
        expr: SPECIALTY
        description: Original specialty as reported
        data_type: TEXT
      - name: STANDARDIZED_SPECIALTY
        expr: STANDARDIZED_SPECIALTY
        description: Normalized specialty group
        data_type: TEXT
      - name: TIER
        expr: TIER
        description: Engagement tier
        data_type: TEXT
      - name: DECILE
        expr: DECILE
        description: Prescribing decile (1-10)
        data_type: NUMBER
    facts:
      - name: CONFIDENCE
        expr: CONFIDENCE
        description: Confidence score of the tier assignment
        data_type: NUMBER

  - name: ENGAGEMENTS
    base_table:
      database: DEMO
      schema: HEALTHCARE_DEMO
      table: ENGAGEMENT_FINAL
    dimensions:
      - name: ENGAGEMENT_ID
        expr: ENGAGEMENT_ID
        description: Unique engagement event identifier
        data_type: TEXT
      - name: HCP_ID
        expr: HCP_ID
        description: The HCP who was engaged
        data_type: TEXT
      - name: DRUG_NAME
        expr: DRUG_NAME
        description: Name of the drug discussed
        data_type: TEXT
      - name: THERAPEUTIC_AREA
        expr: THERAPEUTIC_AREA
        description: Therapeutic area of the drug
        data_type: TEXT
      - name: ENGAGEMENT_TYPE
        expr: ENGAGEMENT_TYPE
        description: Type of engagement activity
        data_type: TEXT
      - name: CHANNEL
        expr: CHANNEL
        description: Communication channel used
        data_type: TEXT
    facts:
      - name: DURATION_MINUTES
        expr: DURATION_MINUTES
        description: Duration of the engagement in minutes
        data_type: NUMBER
      - name: SAMPLES_DROPPED
        expr: SAMPLES_DROPPED
        description: Number of drug samples provided
        data_type: NUMBER
      - name: ENGAGEMENT_EFFECTIVENESS
        expr: "(DURATION_MINUTES * 0.4) + (SAMPLES_DROPPED * 10 * 0.3) + (CASE WHEN CHANNEL = 'In-Person' THEN 30 WHEN CHANNEL = 'Virtual' THEN 20 ELSE 10 END * 0.3)"
        description: Composite effectiveness score
        data_type: NUMBER
    time_dimensions:
      - name: ENGAGEMENT_DATE
        expr: ENGAGEMENT_DATE
        description: Date of the engagement
        data_type: DATE

  - name: DRUGS
    base_table:
      database: DEMO
      schema: HEALTHCARE_DEMO
      table: DIM_DRUG
    primary_key:
      columns:
        - DRUG_ID
    dimensions:
      - name: DRUG_ID
        expr: DRUG_ID
        description: Drug unique identifier
        data_type: TEXT
      - name: DRUG_NAME
        expr: DRUG_NAME
        description: Brand name of the drug
        data_type: TEXT
      - name: THERAPEUTIC_AREA
        expr: THERAPEUTIC_AREA
        description: Therapeutic area classification
        data_type: TEXT
      - name: IS_SPECIALTY
        expr: IS_SPECIALTY
        description: Whether this is a specialty drug
        data_type: BOOLEAN
    facts:
      - name: ANNUAL_REVENUE_MM
        expr: ANNUAL_REVENUE_MM
        description: Annual revenue in millions USD
        data_type: NUMBER

  - name: TERRITORIES
    base_table:
      database: DEMO
      schema: HEALTHCARE_DEMO
      table: DIM_TERRITORY
    primary_key:
      columns:
        - TERRITORY_ID
    dimensions:
      - name: TERRITORY_ID
        expr: TERRITORY_ID
        description: Territory unique identifier
        data_type: NUMBER
      - name: TERRITORY_NAME
        expr: TERRITORY_NAME
        description: Territory name
        data_type: TEXT
      - name: DISTRICT_NAME
        expr: DISTRICT_NAME
        description: District the territory belongs to
        data_type: TEXT
      - name: REGION_ID
        expr: REGION_ID
        description: Region identifier
        data_type: NUMBER

  - name: REGIONS
    base_table:
      database: DEMO
      schema: HEALTHCARE_DEMO
      table: DIM_REGION
    primary_key:
      columns:
        - REGION_ID
    dimensions:
      - name: REGION_ID
        expr: REGION_ID
        description: Region unique identifier
        data_type: NUMBER
      - name: REGION_NAME
        expr: REGION_NAME
        description: Region name
        data_type: TEXT

relationships:
  - name: rx_metrics_to_drugs
    left_table: RX_METRICS
    right_table: DRUGS
    join_type: left_outer
    relationship_type: many_to_one
    relationship_columns:
      - left_column: DRUG_ID
        right_column: DRUG_ID
  - name: rx_metrics_to_territories
    left_table: RX_METRICS
    right_table: TERRITORIES
    join_type: left_outer
    relationship_type: many_to_one
    relationship_columns:
      - left_column: TERRITORY_ID
        right_column: TERRITORY_ID
  - name: territories_to_regions
    left_table: TERRITORIES
    right_table: REGIONS
    join_type: left_outer
    relationship_type: many_to_one
    relationship_columns:
      - left_column: REGION_ID
        right_column: REGION_ID

verified_queries:
  - name: rx_volume_by_drug
    question: What is the total prescription volume by drug?
    sql: |
      SELECT d.DRUG_NAME, d.THERAPEUTIC_AREA, SUM(m.METRIC_VALUE) AS total_volume
      FROM DEMO.HEALTHCARE_DEMO.RX_METRICS_OUTPUT m
      LEFT JOIN DEMO.HEALTHCARE_DEMO.DIM_DRUG d ON m.DRUG_ID = d.DRUG_ID
      WHERE m.METRIC_NAME = 'total_rx_volume'
      GROUP BY d.DRUG_NAME, d.THERAPEUTIC_AREA
      ORDER BY total_volume DESC
  - name: hcp_tier_distribution
    question: How are HCPs distributed across tiers?
    sql: |
      SELECT TIER, STANDARDIZED_SPECIALTY, COUNT(*) AS hcp_count
      FROM DEMO.HEALTHCARE_DEMO.HCP_TIERED_PROFILES
      GROUP BY TIER, STANDARDIZED_SPECIALTY
      ORDER BY hcp_count DESC
$$,
  FALSE
);

-- 2. CRM COMMERCIAL INTELLIGENCE (CRM/Sales Domain)
CALL SYSTEM$CREATE_SEMANTIC_VIEW_FROM_YAML(
  'DEMO.CRM_DEMO',
  $$
name: CRM_COMMERCIAL_INTELLIGENCE
description: |
  CRM analytics for Salesforce one-hop-reduction. Customer health scoring,
  pipeline forecasting, and account segmentation with derived metrics.

tables:
  - name: CUSTOMER_360
    base_table:
      database: DEMO
      schema: CRM_DEMO
      table: CUSTOMER_360
    primary_key:
      columns:
        - ACCOUNT_ID
    dimensions:
      - name: ACCOUNT_ID
        expr: ACCOUNT_ID
        description: Unique account identifier
        data_type: TEXT
      - name: ACCOUNT_NAME
        expr: ACCOUNT_NAME
        description: Company name
        data_type: TEXT
      - name: INDUSTRY
        expr: INDUSTRY
        description: Industry vertical
        data_type: TEXT
      - name: REGION
        expr: REGION
        description: Geographic region
        data_type: TEXT
      - name: SEGMENT
        expr: SEGMENT
        description: Account segment (High Value, Growth, At Risk)
        data_type: TEXT
    facts:
      - name: TOTAL_PIPELINE
        expr: TOTAL_PIPELINE
        description: Sum of open opportunity amounts
        data_type: NUMBER
      - name: WON_REVENUE
        expr: WON_REVENUE
        description: Sum of closed-won opportunity amounts
        data_type: NUMBER
      - name: WIN_RATE
        expr: WIN_RATE
        description: Ratio of closed-won to total opportunities
        data_type: NUMBER
      - name: OPEN_OPPS
        expr: OPEN_OPPS
        description: Count of open opportunities
        data_type: NUMBER
      - name: HEALTH_SCORE
        expr: HEALTH_SCORE
        description: Composite score 0-100
        data_type: NUMBER
      - name: REVENUE_AT_RISK
        expr: "CASE WHEN SEGMENT = 'At Risk' THEN TOTAL_PIPELINE + WON_REVENUE ELSE 0 END"
        description: Total revenue exposure for at-risk accounts
        data_type: NUMBER
      - name: EXPANSION_POTENTIAL
        expr: "TOTAL_PIPELINE * WIN_RATE * (1.0 + (HEALTH_SCORE / 100.0))"
        description: Weighted expansion opportunity
        data_type: NUMBER
    time_dimensions:
      - name: ETL_TIMESTAMP
        expr: ETL_TIMESTAMP
        description: When the enrichment was last computed
        data_type: TIMESTAMP_NTZ

  - name: PIPELINE_FORECAST
    base_table:
      database: DEMO
      schema: CRM_DEMO
      table: PIPELINE_FORECAST
    dimensions:
      - name: OPP_ID
        expr: OPP_ID
        description: Unique opportunity identifier
        data_type: TEXT
      - name: ACCOUNT_ID
        expr: ACCOUNT_ID
        description: Account this opportunity belongs to
        data_type: TEXT
      - name: ACCOUNT_NAME
        expr: ACCOUNT_NAME
        description: Account company name
        data_type: TEXT
      - name: REGION
        expr: REGION
        description: Geographic region
        data_type: TEXT
      - name: INDUSTRY
        expr: INDUSTRY
        description: Industry of the account
        data_type: TEXT
      - name: STAGE
        expr: STAGE
        description: Current opportunity stage
        data_type: TEXT
      - name: FORECAST_CATEGORY
        expr: FORECAST_CATEGORY
        description: Forecast bucket (Commit, Best Case, Pipeline)
        data_type: TEXT
    facts:
      - name: AMOUNT
        expr: AMOUNT
        description: Opportunity deal value
        data_type: NUMBER
      - name: WEIGHTED_PIPELINE
        expr: WEIGHTED_PIPELINE
        description: Amount times stage probability
        data_type: NUMBER
      - name: DAYS_TO_CLOSE
        expr: DAYS_TO_CLOSE
        description: Days until expected close date
        data_type: NUMBER
      - name: VELOCITY_SCORE
        expr: VELOCITY_SCORE
        description: Deal velocity 0-100
        data_type: NUMBER
      - name: DEAL_QUALITY_INDEX
        expr: "WEIGHTED_PIPELINE / NULLIF(GREATEST(DAYS_TO_CLOSE, 1), 0)"
        description: Weighted pipeline per day remaining
        data_type: NUMBER
    time_dimensions:
      - name: ETL_TIMESTAMP
        expr: ETL_TIMESTAMP
        description: When the forecast was computed
        data_type: TIMESTAMP_NTZ

  - name: ACCOUNTS
    base_table:
      database: DEMO
      schema: CRM_DEMO
      table: RAW_ACCOUNTS
    primary_key:
      columns:
        - ACCOUNT_ID
    dimensions:
      - name: ACCOUNT_ID
        expr: ACCOUNT_ID
        description: Unique account identifier
        data_type: TEXT
      - name: ACCOUNT_NAME
        expr: ACCOUNT_NAME
        description: Company name
        data_type: TEXT
      - name: INDUSTRY
        expr: INDUSTRY
        description: Industry vertical
        data_type: TEXT
      - name: REGION
        expr: REGION
        description: Geographic region
        data_type: TEXT
    facts:
      - name: EMPLOYEE_COUNT
        expr: EMPLOYEE_COUNT
        description: Number of employees
        data_type: NUMBER
      - name: ANNUAL_REVENUE
        expr: ANNUAL_REVENUE
        description: Annual revenue in millions
        data_type: NUMBER

relationships:
  - name: customer360_to_accounts
    left_table: CUSTOMER_360
    right_table: ACCOUNTS
    join_type: left_outer
    relationship_type: one_to_one
    relationship_columns:
      - left_column: ACCOUNT_ID
        right_column: ACCOUNT_ID
  - name: pipeline_to_accounts
    left_table: PIPELINE_FORECAST
    right_table: ACCOUNTS
    join_type: left_outer
    relationship_type: many_to_one
    relationship_columns:
      - left_column: ACCOUNT_ID
        right_column: ACCOUNT_ID

verified_queries:
  - name: at_risk_accounts
    question: Which accounts are at risk and what is their revenue exposure?
    sql: |
      SELECT ACCOUNT_NAME, INDUSTRY, REGION, HEALTH_SCORE, SEGMENT,
             TOTAL_PIPELINE + WON_REVENUE AS TOTAL_REVENUE_EXPOSURE
      FROM DEMO.CRM_DEMO.CUSTOMER_360
      WHERE SEGMENT = 'At Risk'
      ORDER BY TOTAL_PIPELINE + WON_REVENUE DESC
  - name: pipeline_by_region
    question: What is the weighted pipeline by region?
    sql: |
      SELECT REGION, COUNT(*) AS deal_count,
             SUM(AMOUNT) AS total_pipeline,
             SUM(WEIGHTED_PIPELINE) AS weighted_pipeline
      FROM DEMO.CRM_DEMO.PIPELINE_FORECAST
      GROUP BY REGION
      ORDER BY weighted_pipeline DESC
$$,
  FALSE
);

-- 3. FINANCE SUMMARY (Finance Domain)
CALL SYSTEM$CREATE_SEMANTIC_VIEW_FROM_YAML(
  'DEMO.HEALTHCARE_DEMO',
  $$
name: FINANCE_SUMMARY
description: |
  Financial analytics covering revenue recognition, cost center budgets, and forecast
  variance. Supports multi-domain federation and agent routing.

tables:
  - name: REVENUE_SUMMARY
    base_table:
      database: DEMO
      schema: HEALTHCARE_DEMO
      table: FINANCE_REVENUE_SUMMARY
    dimensions:
      - name: PERIOD
        expr: PERIOD
        description: Fiscal period (YYYY-MM format)
        data_type: TEXT
      - name: PRODUCT_LINE
        expr: PRODUCT_LINE
        description: Revenue product line
        data_type: TEXT
      - name: REGION
        expr: REGION
        description: Revenue region
        data_type: TEXT
      - name: REVENUE_TYPE
        expr: REVENUE_TYPE
        description: Type of revenue
        data_type: TEXT
    facts:
      - name: ACTUAL_REVENUE
        expr: ACTUAL_REVENUE
        description: Actual recognized revenue (millions)
        data_type: NUMBER
      - name: BUDGET_REVENUE
        expr: BUDGET_REVENUE
        description: Budgeted revenue target (millions)
        data_type: NUMBER
      - name: FORECAST_REVENUE
        expr: FORECAST_REVENUE
        description: Latest forecast (millions)
        data_type: NUMBER
      - name: VARIANCE_TO_BUDGET
        expr: "ACTUAL_REVENUE - BUDGET_REVENUE"
        description: Revenue variance vs budget
        data_type: NUMBER
      - name: VARIANCE_PCT
        expr: "(ACTUAL_REVENUE - BUDGET_REVENUE) / NULLIF(BUDGET_REVENUE, 0) * 100"
        description: Percentage variance to budget
        data_type: NUMBER
      - name: FORECAST_ACCURACY
        expr: "1.0 - ABS(ACTUAL_REVENUE - FORECAST_REVENUE) / NULLIF(FORECAST_REVENUE, 0)"
        description: Forecast accuracy ratio (1.0 = perfect)
        data_type: NUMBER

  - name: COST_CENTERS
    base_table:
      database: DEMO
      schema: HEALTHCARE_DEMO
      table: FINANCE_COST_CENTERS
    dimensions:
      - name: COST_CENTER_ID
        expr: COST_CENTER_ID
        description: Unique cost center identifier
        data_type: TEXT
      - name: COST_CENTER_NAME
        expr: COST_CENTER_NAME
        description: Cost center name
        data_type: TEXT
      - name: EXPENSE_CATEGORY
        expr: EXPENSE_CATEGORY
        description: Category of expense
        data_type: TEXT
      - name: PERIOD
        expr: PERIOD
        description: Fiscal period
        data_type: TEXT
    facts:
      - name: ACTUAL_SPEND
        expr: ACTUAL_SPEND
        description: Actual spending (millions)
        data_type: NUMBER
      - name: BUDGET_ALLOCATION
        expr: BUDGET_ALLOCATION
        description: Budget allocated (millions)
        data_type: NUMBER
      - name: BUDGET_REMAINING
        expr: "BUDGET_ALLOCATION - ACTUAL_SPEND"
        description: Remaining budget
        data_type: NUMBER
      - name: BURN_RATE_PCT
        expr: "ACTUAL_SPEND / NULLIF(BUDGET_ALLOCATION, 0) * 100"
        description: Percentage of budget consumed
        data_type: NUMBER

verified_queries:
  - name: revenue_variance
    question: What is the revenue variance by product line?
    sql: |
      SELECT PRODUCT_LINE, REGION,
             SUM(ACTUAL_REVENUE) AS total_actual,
             SUM(BUDGET_REVENUE) AS total_budget,
             SUM(ACTUAL_REVENUE) - SUM(BUDGET_REVENUE) AS variance
      FROM DEMO.HEALTHCARE_DEMO.FINANCE_REVENUE_SUMMARY
      GROUP BY PRODUCT_LINE, REGION
      ORDER BY variance DESC
  - name: cost_center_burn
    question: Which cost centers are over budget?
    sql: |
      SELECT COST_CENTER_NAME, EXPENSE_CATEGORY,
             SUM(ACTUAL_SPEND) AS total_spend,
             SUM(BUDGET_ALLOCATION) AS total_budget,
             SUM(ACTUAL_SPEND) - SUM(BUDGET_ALLOCATION) AS overage
      FROM DEMO.HEALTHCARE_DEMO.FINANCE_COST_CENTERS
      WHERE ACTUAL_SPEND > BUDGET_ALLOCATION
      GROUP BY COST_CENTER_NAME, EXPENSE_CATEGORY
      ORDER BY overage DESC
$$,
  FALSE
);
