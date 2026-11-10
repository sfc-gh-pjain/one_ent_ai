"""
Demo Story Dashboard — One Enterprise Platform with Snowflake
Streamlit-in-Snowflake app showcasing platform capabilities across the full demo.
Each tab tells a story with KPIs (executive) and expandable technical details (architect).
Version: 3
"""
import streamlit as st
import altair as alt
import pandas as pd
from snowflake.snowpark.context import get_active_session

st.set_page_config(page_title="One Enterprise Platform | Snowflake", layout="wide")

session = get_active_session()

# ============================================================
# HELPER FUNCTIONS
# ============================================================

def run_query(sql):
    """Execute SQL and return pandas DataFrame."""
    try:
        return session.sql(sql).to_pandas()
    except Exception as e:
        st.error(f"Query failed: {e}")
        return pd.DataFrame()


def metric_row(metrics):
    """Display a row of metric cards."""
    cols = st.columns(len(metrics))
    for col, (label, value, delta) in zip(cols, metrics):
        col.metric(label, value, delta)


def safe_count(sql):
    """Get a single count value safely."""
    try:
        result = session.sql(sql).collect()
        return result[0][0] if result else 0
    except:
        return 0


# ============================================================
# HEADER
# ============================================================

st.title("One Enterprise Platform with Snowflake")
st.caption("Healthcare + CRM + Finance | Data Transformation + Cortex AI + Horizon Governance")

# ============================================================
# TABS
# ============================================================

tab1, tab2, tab3, tab4, tab5, tab6, tab7 = st.tabs([
    "Platform Overview",
    "Data Transformation",
    "CRM Pipeline",
    "Data Quality",
    "Enterprise AI",
    "Horizon Governance",
    "Closing & Summary"
])

# ============================================================
# TAB 1: PLATFORM OVERVIEW
# ============================================================

with tab1:
    st.header("One Enterprise Platform")
    st.markdown("""
    **Problem Statement:** Enterprises run fragmented data stacks — separate tools for ingestion,
    transformation, AI, governance, and orchestration. This creates integration tax, security gaps,
    and slow time-to-insight.

    **What You Are Going to See:** Snowflake as a unified platform handling **all 7 layers** —
    from PySpark data transformation to Cortex AI agents to Horizon governance — in one account,
    one security model, one governance framework.
    """)

    # KPIs
    total_tables = safe_count("""
        SELECT COUNT(*) FROM DEMO.INFORMATION_SCHEMA.TABLES
        WHERE TABLE_SCHEMA IN ('HEALTHCARE_DEMO', 'CRM_DEMO') AND TABLE_TYPE = 'BASE TABLE'
    """)
    total_rows = safe_count("""
        SELECT SUM(ROW_COUNT) FROM DEMO.INFORMATION_SCHEMA.TABLES
        WHERE TABLE_SCHEMA IN ('HEALTHCARE_DEMO', 'CRM_DEMO') AND TABLE_TYPE = 'BASE TABLE'
    """)
    horizon_tables = safe_count("""
        SELECT COUNT(*) FROM HORIZON_DEMO_DB.INFORMATION_SCHEMA.TABLES
        WHERE TABLE_SCHEMA = 'HEALTHCARE' AND TABLE_TYPE = 'BASE TABLE'
    """)

    metric_row([
        ("Total Tables", str(total_tables + horizon_tables), None),
        ("Total Rows", f"{total_rows:,.0f}" if total_rows else "0", None),
        ("Databases", "3", None),
        ("Platform Layers", "7", None),
    ])

    st.divider()

    # Platform layers
    st.subheader("Platform Layers Demonstrated")
    layers = pd.DataFrame({
        "Layer": [
            "Data Transformation",
            "CRM Integration",
            "Data Quality & MDM",
            "Enterprise AI",
            "Horizon Governance",
            "Metadata Intelligence",
            "Orchestration",
        ],
        "Snowflake Capability": [
            "Snowpark Connect (PySpark on warehouse compute)",
            "Snowpark Connect + Semantic Views",
            "Streams, Tasks, DMFs, Cortex AI",
            "Cortex Agents + Semantic Views + Cortex Search",
            "Tags, Masking Policies, Row Access Policies",
            "Cortex Search over governance metadata",
            "Tasks, Streams, Airflow integration",
        ],
        "Key Outcome": [
            "Zero-infra Spark pipelines",
            "4 hops reduced to 2",
            "AI-generated DQ rules",
            "Natural language across 3 domains",
            "Tag-driven policy automation",
            "Search tags/policies/PII in natural language",
            "Event-driven + scheduled processing",
        ],
    })
    st.dataframe(layers, use_container_width=True)

    with st.expander("Architecture Overview"):
        st.code("""
Snowflake Account
|
|-- DEMO database
|   |-- HEALTHCARE_DEMO schema
|   |   |-- Snowpark Connect: 4 PySpark jobs (Rx metrics, HCP, Engagement, Validation)
|   |   |-- AI Layer: 3 Semantic Views + 2 Cortex Agents + Cortex Search
|   |   |-- DQ/MDM: DMFs, Streams, Tasks, AI-generated rules
|   |
|   |-- CRM_DEMO schema
|       |-- Snowpark Connect: 3 PySpark jobs (Customer 360, Pipeline Forecast)
|       |-- Semantic View: CRM_COMMERCIAL_INTELLIGENCE
|
|-- HORIZON_DEMO_DB database
|   |-- HEALTHCARE schema
|       |-- 8 Tags (DATA_CLASSIFICATION, PII_LEVEL, PIPELINE_LAYER, etc.)
|       |-- Masking Policies (PII_TAG_MASK)
|       |-- Row Access Policies (DEPARTMENT_ROW_POLICY)
|       |-- Cortex Search: METADATA_SEARCH + GOVERNANCE_SEARCH
|       |-- Streamlit: HORIZON_INTELLIGENCE_APP
|
|-- Orchestration: Airflow DAGs / Snowflake Tasks
        """, language="text")


# ============================================================
# TAB 2: DATA TRANSFORMATION (Healthcare Pipeline)
# ============================================================

with tab2:
    st.header("Healthcare Data Transformation Pipeline")
    st.markdown("""
    **Story:** PySpark transformations running on Snowflake warehouse compute via Snowpark Connect.
    Zero infrastructure to manage — full Spark API with Snowflake-native DDL (MERGE, QUALIFY, TRANSIENT).
    """)

    # KPIs
    rx_rows = safe_count("SELECT COUNT(*) FROM DEMO.HEALTHCARE_DEMO.RX_METRICS_OUTPUT")
    hcp_rows = safe_count("SELECT COUNT(*) FROM DEMO.HEALTHCARE_DEMO.HCP_TIERED_PROFILES")
    eng_rows = safe_count("SELECT COUNT(*) FROM DEMO.HEALTHCARE_DEMO.ENGAGEMENT_FINAL")

    metric_row([
        ("Rx Metrics", f"{rx_rows:,}", None),
        ("HCP Profiles", f"{hcp_rows:,}", None),
        ("Engagements", f"{eng_rows:,}", None),
        ("Pipeline Jobs", "4", None),
    ])

    st.divider()

    # Charts
    col1, col2 = st.columns(2)

    with col1:
        st.subheader("Rx Volume by Drug")
        rx_by_drug = run_query("""
            SELECT d.DRUG_NAME, SUM(m.METRIC_VALUE) AS TOTAL_VOLUME
            FROM DEMO.HEALTHCARE_DEMO.RX_METRICS_OUTPUT m
            LEFT JOIN DEMO.HEALTHCARE_DEMO.DIM_DRUG d ON m.DRUG_ID = d.DRUG_ID
            WHERE m.METRIC_NAME = 'total_rx_volume'
            GROUP BY d.DRUG_NAME
            ORDER BY TOTAL_VOLUME DESC
            LIMIT 10
        """)
        if not rx_by_drug.empty:
            chart = alt.Chart(rx_by_drug).mark_bar().encode(
                x=alt.X("TOTAL_VOLUME:Q", title="Total Volume"),
                y=alt.Y("DRUG_NAME:N", sort="-x", title="Drug"),
            ).properties(height=300)
            st.altair_chart(chart, use_container_width=True)

    with col2:
        st.subheader("HCP Tier Distribution")
        tier_dist = run_query("""
            SELECT TIER, COUNT(*) AS HCP_COUNT
            FROM DEMO.HEALTHCARE_DEMO.HCP_TIERED_PROFILES
            GROUP BY TIER ORDER BY TIER
        """)
        if not tier_dist.empty:
            chart = alt.Chart(tier_dist).mark_arc().encode(
                theta="HCP_COUNT:Q",
                color="TIER:N",
                tooltip=["TIER", "HCP_COUNT"],
            ).properties(height=300)
            st.altair_chart(chart, use_container_width=True)

    st.subheader("Engagement by Channel")
    eng_by_channel = run_query("""
        SELECT CHANNEL, ENGAGEMENT_TYPE, COUNT(*) AS CNT
        FROM DEMO.HEALTHCARE_DEMO.ENGAGEMENT_FINAL
        GROUP BY CHANNEL, ENGAGEMENT_TYPE
        ORDER BY CNT DESC
    """)
    if not eng_by_channel.empty:
        chart = alt.Chart(eng_by_channel).mark_bar().encode(
            x=alt.X("CHANNEL:N", title="Channel"),
            y=alt.Y("CNT:Q", title="Engagements"),
            color="ENGAGEMENT_TYPE:N",
        ).properties(height=300)
        st.altair_chart(chart, use_container_width=True)

    with st.expander("Technical Details"):
        st.markdown("""
        **Snowpark Connect (SCOS) Pattern:**
        ```python
        from pyspark.sql import SparkSession
        from snowflake.snowpark_connect.snowflake_session import SnowflakeSession

        spark = SparkSession.builder.getOrCreate()
        sf_session = SnowflakeSession(spark)  # For MERGE, QUALIFY, TRANSIENT
        ```

        **Pipeline Jobs:**
        | Job | Pattern | Output |
        |-----|---------|--------|
        | 01_rx_metrics_load.py | Staging + Validate + MERGE | RX_METRICS_OUTPUT |
        | 02_hcp_classification.py | Python UDTF | HCP_TIERED_PROFILES |
        | 03_engagement_merge.py | 6-way JOIN + MERGE | ENGAGEMENT_FINAL |
        | 04_validate.py | DQ assertion gates | Pass/Fail |

        **Key Point:** Same PySpark code, zero infrastructure. Warehouse compute scales automatically.
        """)


# ============================================================
# TAB 3: CRM PIPELINE
# ============================================================

with tab3:
    st.header("CRM Pipeline: One-Hop Reduction")
    st.markdown("""
    **Story:** Salesforce CRM data enriched in Snowflake, queried directly by Tableau.
    Eliminates the round-trip back to Salesforce for analytics — cutting 4 hops to 2.
    """)

    # Architecture comparison
    col1, col2 = st.columns(2)
    with col1:
        st.markdown("**BEFORE (4 hops):**")
        st.code("Salesforce -> S3 -> Snowflake -> S3 -> Salesforce -> Tableau", language="text")
    with col2:
        st.markdown("**AFTER (2 hops):**")
        st.code("Salesforce -> S3 -> Snowflake -> Tableau (direct)", language="text")

    st.divider()

    # KPIs
    c360 = run_query("""
        SELECT
            COUNT(*) AS ACCOUNTS,
            SUM(TOTAL_PIPELINE) AS TOTAL_PIPELINE,
            SUM(CASE WHEN SEGMENT = 'At Risk' THEN 1 ELSE 0 END) AS AT_RISK,
            AVG(HEALTH_SCORE) AS AVG_HEALTH,
            AVG(WIN_RATE) AS AVG_WIN_RATE
        FROM DEMO.CRM_DEMO.CUSTOMER_360
    """)
    if not c360.empty:
        row = c360.iloc[0]
        metric_row([
            ("Accounts", str(int(row["ACCOUNTS"])), None),
            ("Total Pipeline", f"${row['TOTAL_PIPELINE']:,.0f}", None),
            ("At Risk", str(int(row["AT_RISK"])), None),
            ("Avg Health Score", f"{row['AVG_HEALTH']:.1f}", None),
            ("Avg Win Rate", f"{row['AVG_WIN_RATE']:.1%}", None),
        ])

    st.divider()

    # Charts
    col1, col2 = st.columns(2)

    with col1:
        st.subheader("Accounts by Segment")
        segment_data = run_query("""
            SELECT SEGMENT, COUNT(*) AS CNT, ROUND(AVG(HEALTH_SCORE), 1) AS AVG_SCORE
            FROM DEMO.CRM_DEMO.CUSTOMER_360
            GROUP BY SEGMENT
        """)
        if not segment_data.empty:
            chart = alt.Chart(segment_data).mark_arc(innerRadius=50).encode(
                theta="CNT:Q",
                color="SEGMENT:N",
                tooltip=["SEGMENT", "CNT", "AVG_SCORE"],
            ).properties(height=300)
            st.altair_chart(chart, use_container_width=True)

    with col2:
        st.subheader("Pipeline by Region")
        pipeline_region = run_query("""
            SELECT REGION, SUM(WEIGHTED_PIPELINE) AS WEIGHTED_PIPELINE, COUNT(*) AS DEALS
            FROM DEMO.CRM_DEMO.PIPELINE_FORECAST
            GROUP BY REGION ORDER BY WEIGHTED_PIPELINE DESC
        """)
        if not pipeline_region.empty:
            chart = alt.Chart(pipeline_region).mark_bar().encode(
                x=alt.X("REGION:N", title="Region"),
                y=alt.Y("WEIGHTED_PIPELINE:Q", title="Weighted Pipeline ($)"),
                tooltip=["REGION", "WEIGHTED_PIPELINE", "DEALS"],
            ).properties(height=300)
            st.altair_chart(chart, use_container_width=True)

    # At-risk accounts table
    st.subheader("Top At-Risk Accounts")
    at_risk = run_query("""
        SELECT ACCOUNT_NAME, INDUSTRY, REGION, HEALTH_SCORE,
               TOTAL_PIPELINE + WON_REVENUE AS REVENUE_EXPOSURE,
               OPEN_CASES
        FROM DEMO.CRM_DEMO.CUSTOMER_360
        WHERE SEGMENT = 'At Risk'
        ORDER BY TOTAL_PIPELINE + WON_REVENUE DESC
        LIMIT 10
    """)
    if not at_risk.empty:
        st.dataframe(at_risk, use_container_width=True)

    with st.expander("Technical Details"):
        st.markdown("""
        **Health Score Formula:**
        ```
        health_score = (win_rate * 40) + (pipeline_factor * 30) + (case_factor * 30)

        Segments: >= 70 -> High Value, >= 40 -> Growth, < 40 -> At Risk
        ```

        **Semantic View:** `DEMO.CRM_DEMO.CRM_COMMERCIAL_INTELLIGENCE`
        - Derived facts: REVENUE_AT_RISK, EXPANSION_POTENTIAL, DEAL_QUALITY_INDEX
        - 5 tables joined via semantic relationships
        """)


# ============================================================
# TAB 4: DATA QUALITY
# ============================================================

with tab4:
    st.header("AI-Assisted Data Quality")
    st.markdown("""
    **Story:** Cortex AI generates DQ rules from schema metadata, explains violations in
    business language, and detects trends — reducing manual maintenance as schemas evolve.
    """)

    # KPIs
    violations = safe_count("SELECT COUNT(*) FROM DEMO.HEALTHCARE_DEMO.MDM_VIOLATION_LOG")
    ai_suggestions = safe_count("SELECT COUNT(*) FROM DEMO.HEALTHCARE_DEMO.DQ_AI_SUGGESTIONS")
    golden = safe_count("SELECT COUNT(*) FROM DEMO.HEALTHCARE_DEMO.HCP_GOLDEN_RECORD")

    metric_row([
        ("Violations Detected", str(violations), None),
        ("AI Rule Suggestions", str(ai_suggestions), None),
        ("Golden Records", str(golden), None),
        ("Active Tasks", "4", None),
    ])

    st.divider()

    # Violations by rule
    col1, col2 = st.columns(2)

    with col1:
        st.subheader("Violations by Rule")
        v_by_rule = run_query("""
            SELECT RULE_NAME, COUNT(*) AS CNT
            FROM DEMO.HEALTHCARE_DEMO.MDM_VIOLATION_LOG
            GROUP BY RULE_NAME ORDER BY CNT DESC
        """)
        if not v_by_rule.empty:
            chart = alt.Chart(v_by_rule).mark_bar().encode(
                x=alt.X("CNT:Q", title="Count"),
                y=alt.Y("RULE_NAME:N", sort="-x", title="Rule"),
            ).properties(height=250)
            st.altair_chart(chart, use_container_width=True)
        else:
            st.info("No violations detected yet. Tasks run on schedule or stream trigger.")

    with col2:
        st.subheader("Violations by Severity")
        v_by_sev = run_query("""
            SELECT SEVERITY, COUNT(*) AS CNT
            FROM DEMO.HEALTHCARE_DEMO.MDM_VIOLATION_LOG
            GROUP BY SEVERITY
        """)
        if not v_by_sev.empty:
            chart = alt.Chart(v_by_sev).mark_arc().encode(
                theta="CNT:Q",
                color="SEVERITY:N",
                tooltip=["SEVERITY", "CNT"],
            ).properties(height=250)
            st.altair_chart(chart, use_container_width=True)
        else:
            st.info("No violations to show.")

    # AI Suggestions
    st.subheader("AI-Generated DQ Rule Suggestions")
    st.markdown("*Cortex AI analyzed column metadata and suggested these quality checks:*")
    suggestions = run_query("""
        SELECT TABLE_NAME, COLUMN_NAME, DATA_TYPE, LEFT(AI_SUGGESTED_RULES, 500) AS SUGGESTED_RULES
        FROM DEMO.HEALTHCARE_DEMO.DQ_AI_SUGGESTIONS
        LIMIT 6
    """)
    if not suggestions.empty:
        st.dataframe(suggestions, use_container_width=True)

    with st.expander("Technical Details"):
        st.markdown("""
        **AI DQ Pattern:**
        ```sql
        SNOWFLAKE.CORTEX.COMPLETE('mistral-large2',
            'Given column "' || COLUMN_NAME || '" with type ' || DATA_TYPE ||
            ' suggest 2 data quality rules...'
        )
        ```

        **MDM Architecture:**
        - Streams on source tables (CDC triggers)
        - Tasks call stored procedures (SP_MDM_HCP_DEDUP, SP_MDM_ENGAGEMENT_VALIDATION)
        - Central MDM_VIOLATION_LOG for all findings
        """)


# ============================================================
# TAB 5: ENTERPRISE AI
# ============================================================

with tab5:
    st.header("Enterprise AI: Cortex Agents + Semantic Views")
    st.markdown("""
    **Story:** Natural language analytics across 3 business domains using Cortex Agents.
    Each domain owns a Semantic View — the agent routes questions to the right domain
    via Cortex Search, then generates SQL using Cortex Analyst.
    """)

    # KPIs
    metric_row([
        ("Semantic Views", "3", None),
        ("Cortex Agents", "2", None),
        ("Cortex Search Services", "3", None),
        ("Domains Covered", "Healthcare, CRM, Finance", None),
    ])

    st.divider()

    # Agents
    st.subheader("Deployed Agents")
    agents_df = pd.DataFrame({
        "Agent": [
            "PHARMA_INTELLIGENCE_AGENT",
            "ENTERPRISE_INTELLIGENCE_AGENT",
        ],
        "Schema": ["DEMO.HEALTHCARE_DEMO", "DEMO.HEALTHCARE_DEMO"],
        "Model": ["claude-haiku-4-5", "claude-haiku-4-5"],
        "Tools": [
            "pharma_analyst (Semantic View) + hcp_search (Cortex Search)",
            "pharma_analyst + crm_analyst + finance_analyst + domain_router",
        ],
        "Use Case": [
            "Single-domain pharma analytics",
            "Multi-domain routing across Healthcare, CRM, Finance",
        ],
    })
    st.dataframe(agents_df, use_container_width=True)

    st.divider()

    # Semantic Views
    st.subheader("Semantic Views (Text-to-SQL)")
    sv_df = pd.DataFrame({
        "Semantic View": [
            "PHARMA_COMMERCIAL_INTELLIGENCE",
            "CRM_COMMERCIAL_INTELLIGENCE",
            "FINANCE_SUMMARY",
        ],
        "Database.Schema": [
            "DEMO.HEALTHCARE_DEMO",
            "DEMO.CRM_DEMO",
            "DEMO.HEALTHCARE_DEMO",
        ],
        "Tables": ["5", "5", "3"],
        "Key Metrics": [
            "Rx volume, HCP tier, engagement ROI",
            "Pipeline forecast, health score, win rate",
            "Revenue by cost center, budget variance",
        ],
    })
    st.dataframe(sv_df, use_container_width=True)

    st.divider()

    # Demo prompts
    st.subheader("Try These Prompts")
    st.markdown("""
    **Pharma Agent** (in CoWork or Snowsight Preview):
    - "Which drugs have the highest prescription volume?"
    - "Show me HCP engagement ROI by channel"
    - "What is the market share trend for Lisinopril?"

    **Enterprise Agent** (multi-domain routing):
    - "What is our CRM pipeline by region?" → routes to CRM
    - "Show revenue by cost center" → routes to Finance
    - "Top prescribed drugs by volume" → routes to Healthcare
    """)

    # Routing pattern
    st.subheader("Agent Routing Pattern")
    st.code("""
User: "What is our pipeline by region?"
  |
  v
ENTERPRISE_INTELLIGENCE_AGENT (claude-haiku-4-5)
  |
  v  domain_router (Cortex Search) -> identifies "CRM" domain
  |
  v  crm_analyst (cortex_analyst_text_to_sql)
  |     -> Semantic View: CRM_COMMERCIAL_INTELLIGENCE
  |
  v
SQL: SELECT REGION, SUM(WEIGHTED_PIPELINE) FROM PIPELINE_FORECAST GROUP BY REGION
    """, language="text")

    with st.expander("Technical Details"):
        st.markdown("""
        **Agent Creation (must use CREATE AGENT, not CREATE OR REPLACE):**
        ```sql
        CREATE AGENT DEMO.HEALTHCARE_DEMO.ENTERPRISE_INTELLIGENCE_AGENT
        FROM SPECIFICATION $$
        tools:
          - tool_spec:
              type: cortex_search
              name: domain_router
          - tool_spec:
              type: cortex_analyst_text_to_sql
              name: pharma_analyst
          - tool_spec:
              type: cortex_analyst_text_to_sql
              name: crm_analyst
          - tool_spec:
              type: cortex_analyst_text_to_sql
              name: finance_analyst
        tool_resources:
          cortex_search:
            domain_router:
              service_name: DEMO.HEALTHCARE_DEMO.MODEL_ROUTER_SEARCH
          cortex_analyst_text_to_sql:
            pharma_analyst:
              semantic_view: DEMO.HEALTHCARE_DEMO.PHARMA_COMMERCIAL_INTELLIGENCE
            crm_analyst:
              semantic_view: DEMO.CRM_DEMO.CRM_COMMERCIAL_INTELLIGENCE
            finance_analyst:
              semantic_view: DEMO.HEALTHCARE_DEMO.FINANCE_SUMMARY
          execution_environment:
            type: warehouse
            warehouse: MY_WH
        $$
        COMMENT = 'Enterprise multi-domain agent';
        ```

        **Critical Lessons:**
        - `CREATE AGENT` (no REPLACE) creates a LIVE version
        - `execution_environment` is mandatory for `cortex_analyst_text_to_sql`
        - Allowed models: `auto`, `claude-haiku-4-5`, `claude-opus-4-5` through `claude-opus-4-8`
        - Object REST endpoint: `POST /api/v2/databases/{db}/schemas/{schema}/agents/{name}:run`
        """)


# ============================================================
# TAB 6: HORIZON GOVERNANCE
# ============================================================

with tab6:
    st.header("Horizon Governance — One Platform")
    st.markdown("""
    **Story:** Data governance that follows data from source to consumption — tags, classification,
    masking, row access, and metadata intelligence all managed in one platform.
    The same policies apply whether data comes from EHR, billing systems, or claims portals.
    """)

    # KPIs
    tag_count = safe_count("""
        SELECT COUNT(DISTINCT TAG_NAME) FROM SNOWFLAKE.ACCOUNT_USAGE.TAG_REFERENCES
        WHERE TAG_DATABASE = 'HORIZON_DEMO_DB' AND TAG_SCHEMA = 'HEALTHCARE'
    """)
    tagged_tables = safe_count("""
        SELECT COUNT(DISTINCT OBJECT_NAME) FROM SNOWFLAKE.ACCOUNT_USAGE.TAG_REFERENCES
        WHERE TAG_DATABASE = 'HORIZON_DEMO_DB' AND TAG_SCHEMA = 'HEALTHCARE'
        AND DOMAIN = 'TABLE' AND COLUMN_NAME IS NULL
    """)
    pii_columns = safe_count("""
        SELECT COUNT(*) FROM SNOWFLAKE.ACCOUNT_USAGE.TAG_REFERENCES
        WHERE TAG_DATABASE = 'HORIZON_DEMO_DB' AND TAG_SCHEMA = 'HEALTHCARE'
        AND TAG_NAME = 'PII_LEVEL' AND COLUMN_NAME IS NOT NULL
    """)

    metric_row([
        ("Tag Types", str(tag_count), None),
        ("Tables Tagged", str(tagged_tables), None),
        ("PII Columns Classified", str(pii_columns), None),
        ("Active Policies", "4", None),
    ])

    st.divider()

    # Governance features
    st.subheader("Governance Features Deployed")
    gov_features = pd.DataFrame({
        "Feature": [
            "Object Tagging",
            "Data Classification",
            "Column-Level PII",
            "Dynamic Masking",
            "Row Access Policy",
            "Projection Policy",
            "Aggregation Policy",
            "Join Policy",
        ],
        "Implementation": [
            "8 tag types: PIPELINE_LAYER, DATA_CLASSIFICATION, PII_LEVEL, DATA_DOMAIN, SOURCE_SYSTEM, LOAD_FREQUENCY, RETENTION_DAYS, SLA_FRESHNESS_SECONDS",
            "PHI, PII, FINANCIAL, OPERATIONAL, PUBLIC",
            "HIGH (SSN), MEDIUM (email, phone, DOB, address), LOW (names)",
            "PII_TAG_MASK: masks SSN, email, phone, address for non-privileged roles",
            "DEPARTMENT_ROW_POLICY: restricts patient rows by department assignment",
            "PRESCRIPTION_PROJECTION_POLICY: hides drug dosage columns",
            "MIN_GROUP_SIZE_POLICY: prevents small-group re-identification on BILLING",
            "PATIENT_JOIN_POLICY: restricts PATIENTS joins to approved tables",
        ],
        "Tables Affected": [
            "All 12 tables",
            "PATIENTS, APPOINTMENTS, PRESCRIPTIONS, BILLING, DOCTORS, INSURANCE_CLAIMS",
            "PATIENTS (7 columns)",
            "PATIENTS (SSN, email, phone, address)",
            "PATIENTS",
            "PRESCRIPTIONS",
            "BILLING",
            "PATIENTS",
        ],
    })
    st.dataframe(gov_features, use_container_width=True)

    st.divider()

    # Tag distribution
    st.subheader("Tags by Table")
    tag_data = run_query("""
        SELECT OBJECT_NAME AS TABLE_NAME, TAG_NAME, TAG_VALUE
        FROM SNOWFLAKE.ACCOUNT_USAGE.TAG_REFERENCES
        WHERE TAG_DATABASE = 'HORIZON_DEMO_DB' AND TAG_SCHEMA = 'HEALTHCARE'
          AND OBJECT_DATABASE = 'HORIZON_DEMO_DB'
          AND COLUMN_NAME IS NULL AND DOMAIN = 'TABLE'
        ORDER BY OBJECT_NAME, TAG_NAME
    """)
    if not tag_data.empty:
        pivot = tag_data.pivot_table(index='TABLE_NAME', columns='TAG_NAME', values='TAG_VALUE', aggfunc='first').reset_index()
        st.dataframe(pivot, use_container_width=True)
    else:
        st.info("Tag data may take up to 2 hours to appear in ACCOUNT_USAGE.")

    st.divider()

    # Metadata Intelligence
    st.subheader("AI-Powered Governance Search")
    st.markdown("""
    Two Cortex Search services enable natural language discovery over governance metadata:

    | Service | Purpose | Example Query |
    |---------|---------|---------------|
    | `METADATA_SEARCH` | Find tables by pipeline metadata | "gold layer tables", "patient billing" |
    | `GOVERNANCE_SEARCH` | Find tables by tags, PII, policies | "tables with PHI data", "masking policy applied" |

    **Live Demo:** Open the **Horizon Intelligence App** (Streamlit) to interact with both services.
    """)

    with st.expander("Technical Details"):
        st.markdown("""
        **Masking Demo (show role-based access):**
        ```sql
        -- Full access (SYSADMIN):
        USE ROLE SYSADMIN;
        SELECT patient_id, first_name, ssn, email, phone
        FROM HORIZON_DEMO_DB.HEALTHCARE.PATIENTS LIMIT 5;

        -- Masked view (HORIZON_DEMO_ANALYST):
        USE ROLE HORIZON_DEMO_ANALYST;
        SELECT patient_id, first_name, ssn, email, phone
        FROM HORIZON_DEMO_DB.HEALTHCARE.PATIENTS LIMIT 5;
        -- SSN -> ***-**-XXXX, email -> ***@***, phone -> ***-***-XXXX
        ```

        **Tag-Based Policy Pattern:**
        ```sql
        -- Policies follow tags, not individual tables
        -- Add a new table? Just tag it — policies apply automatically.
        ALTER TABLE NEW_TABLE SET TAG
            DATA_CLASSIFICATION = 'PHI',
            PII_LEVEL = 'HIGH';
        -- PII_TAG_MASK activates on tagged columns automatically
        ```

        **Cortex Search over Governance:**
        ```sql
        CREATE CORTEX SEARCH SERVICE GOVERNANCE_SEARCH
          ON SEARCH_TEXT
          ATTRIBUTES TABLE_NAME, TAGS, PII_COLUMNS, ACTIVE_POLICIES
          WAREHOUSE = MY_WH
          TARGET_LAG = '1 hour'
          AS (SELECT ... FROM GOVERNANCE_SEARCH_CORPUS);
        ```
        """)


# ============================================================
# TAB 7: CLOSING & SUMMARY
# ============================================================

with tab7:
    st.header("Closing — Enterprise Value")
    st.markdown("""
    ### What We Demonstrated

    A single Snowflake account delivering **7 platform capabilities** that traditionally require
    7 separate tools, 7 security models, and 7 integration layers.
    """)

    st.divider()

    # Value summary
    st.subheader("Business Outcomes")
    outcomes = pd.DataFrame({
        "Capability": [
            "Data Transformation",
            "CRM Integration",
            "Data Quality",
            "Enterprise AI",
            "Governance",
            "Metadata Intelligence",
            "Orchestration",
        ],
        "Traditional Approach": [
            "Databricks/EMR + S3 + Spark clusters",
            "MuleSoft + S3 + ETL tool + round-trip",
            "Great Expectations + custom code + manual rules",
            "LangChain + vector DB + custom RAG",
            "Collibra/Atlan + LDAP + custom scripts",
            "Alation + crawlers + manual tagging",
            "Airflow + custom DAGs + monitoring",
        ],
        "Snowflake Approach": [
            "Snowpark Connect on warehouse compute",
            "Direct query from Tableau (2 hops)",
            "Cortex AI generates rules from metadata",
            "Cortex Agents + Semantic Views (zero code)",
            "Native tags + policies (tag-driven automation)",
            "Cortex Search over governance corpus",
            "Tasks + Streams (serverless, event-driven)",
        ],
        "Reduction": [
            "Eliminates cluster management",
            "4 hops → 2 hops",
            "Manual → AI-generated",
            "Custom RAG → native agent",
            "3rd party catalog → native",
            "External crawler → native search",
            "External scheduler → native tasks",
        ],
    })
    st.dataframe(outcomes, use_container_width=True)

    st.divider()

    # Key messages
    st.subheader("Key Messages")
    st.markdown("""
    1. **One Platform, One Security Model** — No data leaves Snowflake. Same RBAC, same policies,
       same audit trail for pipelines, AI, and governance.

    2. **AI is Native** — Cortex Agents understand your data model (Semantic Views), not just raw tables.
       No vector DB, no embedding pipeline, no custom RAG infrastructure.

    3. **Governance Scales with Data** — Tag-driven policies mean new tables inherit protection automatically.
       Classification and masking don't require per-table configuration.

    4. **Zero Infrastructure** — PySpark on warehouse compute, serverless tasks, auto-scaling search services.
       No clusters to size, no containers to manage, no infrastructure to patch.

    5. **Natural Language Across Domains** — One agent routes across Healthcare, CRM, and Finance.
       Business users ask questions in English; the platform handles the rest.
    """)

    st.divider()

    # Demo assets
    st.subheader("Demo Assets & Access")
    assets = pd.DataFrame({
        "Asset": [
            "Demo Story Dashboard (this app)",
            "Pharma Intelligence App",
            "Horizon Intelligence App",
            "All Demo Walkthrough (HTML)",
            "AI Demo Usage Guide",
        ],
        "Location": [
            "DEMO.HEALTHCARE_DEMO.DEMO_STORY_DASHBOARD",
            "DEMO.HEALTHCARE_DEMO.PHARMA_INTELLIGENCE_APP",
            "HORIZON_DEMO_DB.HEALTHCARE.HORIZON_INTELLIGENCE_APP",
            "all_demo_walkthrough.html (local)",
            "ai_layer/ai_demo_usage_guide.html (local)",
        ],
        "Purpose": [
            "Executive summary with live metrics",
            "Pharma-specific agent + analytics",
            "Governance search + metadata + tags",
            "Full presenter guide with talk tracks",
            "AI layer deep-dive with prompts",
        ],
    })
    st.dataframe(assets, use_container_width=True)

    st.divider()

    st.subheader("Next Steps")
    st.markdown("""
    - **Expand domains:** Add Supply Chain, Clinical Trials semantic views
    - **Real-time governance:** Stream-triggered policy enforcement
    - **Cross-account sharing:** Publish governed data products via Internal Marketplace
    - **Production deployment:** CI/CD with `snow` CLI, scheduled agent evaluation
    """)


# ============================================================
# FOOTER
# ============================================================

st.divider()
st.caption("One Enterprise Platform with Snowflake | Account: <ACCOUNT_LOCATOR> | Built with Cortex Code")
