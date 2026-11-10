"""
Pharma Commercial Intelligence — Snowflake AI Demo
Streamlit app with multiple AI capabilities:
  - Tab 1: Cortex Analyst (natural language to SQL on Rx/engagement data)
  - Tab 2: Cortex Search (semantic HCP and drug search)
  - Tab 3: AI Functions (classify therapeutic area, sentiment on engagement notes)
  - Tab 4: Cortex Agent (combined search + analyst)
"""
import streamlit as st
import json
from snowflake.snowpark.context import get_active_session

st.set_page_config(page_title="Pharma Commercial Intelligence", page_icon="💊", layout="wide")

SEMANTIC_MODEL = "@DEMO.HEALTHCARE_DEMO.SEMANTIC_MODELS/pharma_commercial_intelligence.yaml"
SEMANTIC_VIEW = "DEMO.HEALTHCARE_DEMO.PHARMA_COMMERCIAL_INTELLIGENCE"
SEARCH_SERVICE = "DEMO.HEALTHCARE_DEMO.PHARMA_SEARCH_SERVICE"
AGENT_NAME = "DEMO.HEALTHCARE_DEMO.PHARMA_INTELLIGENCE_AGENT"

session = get_active_session()

st.title("Pharma Commercial Intelligence")
st.caption("Snowflake AI Demo — Cortex Analyst, Search, AI Functions, and Agent")

tab1, tab2, tab3, tab4 = st.tabs(["💬 Analyst (Text-to-SQL)", "🔍 HCP & Drug Search", "🤖 AI Enrichment", "🧠 Agent"])

# ============ TAB 1: CORTEX ANALYST ============
with tab1:
    st.header("Ask Questions About Commercial Data")
    st.markdown("Powered by **Cortex Analyst** — converts natural language to SQL using the semantic model.")

    suggestions = [
        "What is the total prescription volume by drug?",
        "Which territories have the most new patient starts?",
        "How are HCPs distributed across tiers?",
        "What is the engagement volume by channel?",
        "What are the top drugs by annual revenue?",
    ]
    col1, col2 = st.columns(2)
    with col1:
        for s in suggestions[:3]:
            if st.button(s, key=f"s1_{s[:20]}"):
                st.session_state["analyst_q"] = s
    with col2:
        for s in suggestions[3:]:
            if st.button(s, key=f"s2_{s[:20]}"):
                st.session_state["analyst_q"] = s

    analyst_input = st.text_input("Or type your own question:", key="analyst_input",
                                   value=st.session_state.pop("analyst_q", ""))

    if analyst_input:
        with st.spinner("Generating SQL..."):
            try:
                import _snowflake
                resp = _snowflake.send_snow_api_request(
                    "POST", "/api/v2/cortex/analyst/message", {}, {},
                    {
                        "messages": [{"role": "user", "content": [{"type": "text", "text": analyst_input}]}],
                        "semantic_view": SEMANTIC_VIEW,
                    }, {}, 30000,
                )
                resp_body = json.loads(resp["content"])
                sql = None
                for item in resp_body.get("message", {}).get("content", []):
                    if item.get("type") == "sql":
                        sql = item.get("statement", "")
                    elif item.get("type") == "text":
                        st.markdown(item.get("text", ""))

                if sql:
                    with st.expander("Generated SQL", expanded=False):
                        st.code(sql, language="sql")
                    df = session.sql(sql).to_pandas()
                    st.dataframe(df, use_container_width=True)
                    if len(df.columns) >= 2 and len(df) <= 30:
                        numeric_cols = df.select_dtypes(include=["number"]).columns.tolist()
                        text_cols = df.select_dtypes(include=["object"]).columns.tolist()
                        if numeric_cols and text_cols:
                            st.bar_chart(df.set_index(text_cols[0])[numeric_cols[0]])
            except Exception as e:
                st.error(f"Error: {e}")

# ============ TAB 2: CORTEX SEARCH ============
with tab2:
    st.header("Semantic HCP & Drug Search")
    st.markdown("Powered by **Cortex Search** — finds relevant HCPs and drugs using natural language.")

    search_query = st.text_input("Search for HCPs or drugs:",
                                  placeholder="e.g., oncologists prescribing immunotherapy in Northeast",
                                  key="search_input")

    col_filter1, col_filter2 = st.columns(2)
    with col_filter1:
        specialty_filter = st.selectbox("Filter by specialty:",
                                  ["All", "Oncology", "Immunology", "Cardiology", "Neurology",
                                   "Respiratory", "Endocrinology", "Dermatology", "Infectious Disease"])
    with col_filter2:
        limit = st.slider("Results:", 5, 25, 10)

    if search_query:
        with st.spinner("Searching..."):
            try:
                filter_clause = ""
                if specialty_filter != "All":
                    filter_clause = f', "filter": {{"@eq": {{"SPECIALTY": "{specialty_filter}"}}}}'

                search_json = f'{{"query": "{search_query}", "columns": ["HCP_NAME", "SPECIALTY", "STANDARDIZED_SPECIALTY", "TIER", "TERRITORY_NAME", "REGION_NAME"], "limit": {limit}{filter_clause}}}'

                results = session.sql(f"""
                    SELECT r.value:HCP_NAME::STRING AS hcp_name,
                           r.value:SPECIALTY::STRING AS specialty,
                           r.value:STANDARDIZED_SPECIALTY::STRING AS standardized_specialty,
                           r.value:TERRITORY_NAME::STRING AS territory,
                           r.value:REGION_NAME::STRING AS region,
                           r.value:TIER::STRING AS tier
                    FROM TABLE(FLATTEN(
                        PARSE_JSON(SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
                            '{SEARCH_SERVICE}', '{search_json}'
                        )):results
                    )) r
                """).to_pandas()

                st.dataframe(results, use_container_width=True)
                st.metric("Results found", len(results))
            except Exception as e:
                st.error(f"Search error: {e}")

# ============ TAB 3: AI FUNCTIONS ============
with tab3:
    st.header("AI-Powered Drug & HCP Enrichment")
    st.markdown("Powered by **Cortex AI Functions** — classify drugs, analyze engagement sentiment, and enrich data automatically.")

    st.subheader("Pre-computed AI Enrichment (sample drugs)")
    st.markdown("Using `CLASSIFY_TEXT` for therapeutic grouping and `SENTIMENT` on engagement notes.")

    try:
        enriched = session.sql("""
            SELECT THERAPEUTIC_AREA_PREDICTED, RISK_CATEGORY, COUNT(*) AS DRUG_COUNT,
                   ROUND(AVG(AVG_NOTE_SENTIMENT), 3) AS AVG_SENTIMENT
            FROM DEMO.HEALTHCARE_DEMO.AI_ENRICHED_DRUGS
            GROUP BY THERAPEUTIC_AREA_PREDICTED, RISK_CATEGORY
            ORDER BY DRUG_COUNT DESC
        """).to_pandas()
        st.dataframe(enriched, use_container_width=True)

        col1, col2 = st.columns(2)
        with col1:
            st.subheader("By Therapeutic Area")
            by_ta = session.sql("""
                SELECT THERAPEUTIC_AREA_PREDICTED, COUNT(*) AS COUNT,
                       ROUND(AVG(AVG_NOTE_SENTIMENT), 3) AS AVG_SENTIMENT
                FROM DEMO.HEALTHCARE_DEMO.AI_ENRICHED_DRUGS
                GROUP BY THERAPEUTIC_AREA_PREDICTED ORDER BY COUNT DESC
            """).to_pandas()
            st.bar_chart(by_ta.set_index("THERAPEUTIC_AREA_PREDICTED")["AVG_SENTIMENT"])
        with col2:
            st.subheader("By Risk Category")
            by_risk = session.sql("""
                SELECT RISK_CATEGORY, COUNT(*) AS COUNT,
                       ROUND(AVG(AVG_NOTE_SENTIMENT), 3) AS AVG_SENTIMENT
                FROM DEMO.HEALTHCARE_DEMO.AI_ENRICHED_DRUGS
                GROUP BY RISK_CATEGORY ORDER BY COUNT DESC
            """).to_pandas()
            st.bar_chart(by_risk.set_index("RISK_CATEGORY")["COUNT"])
    except Exception as e:
        st.error(f"Error loading enrichment data: {e}")

    st.divider()
    st.subheader("Live AI Classification")
    drug_input = st.text_input("Enter a drug name or indication to classify:",
                                placeholder="e.g., pembrolizumab for melanoma")
    if drug_input:
        with st.spinner("Classifying..."):
            result = session.sql(f"""
                SELECT
                    SNOWFLAKE.CORTEX.CLASSIFY_TEXT('{drug_input}',
                        ['Oncology', 'Immunology', 'Cardiology', 'Neurology', 'Respiratory',
                         'Endocrinology', 'Dermatology', 'Infectious Disease']):label::STRING AS therapeutic_area,
                    SNOWFLAKE.CORTEX.CLASSIFY_TEXT('{drug_input}',
                        ['High Risk - Specialty', 'Medium Risk - Branded', 'Low Risk - Generic']):label::STRING AS risk_category,
                    SNOWFLAKE.CORTEX.SENTIMENT('{drug_input}') AS sentiment
            """).to_pandas()
            c1, c2, c3 = st.columns(3)
            c1.metric("Therapeutic Area", result["THERAPEUTIC_AREA"].iloc[0])
            c2.metric("Risk Category", result["RISK_CATEGORY"].iloc[0])
            c3.metric("Sentiment", f"{result['SENTIMENT'].iloc[0]:.2f}")

# ============ TAB 4: CORTEX AGENT ============
with tab4:
    st.header("AI Agent — Commercial Intelligence Assistant")
    st.markdown("""
    Powered by **Cortex Agent** — combines Search + Analyst to answer complex questions
    that require both finding HCPs/drugs and analyzing commercial data.
    """)
    st.info(f"Agent: `{AGENT_NAME}` (Search + Analyst tools)")

    st.markdown("### Launch the Agent")
    st.markdown("[Open Pharma Intelligence Agent in Snowsight](https://app.snowflake.com/<ORG>/<ACCOUNT_NAME>/#/cortex-agent/DEMO.HEALTHCARE_DEMO.PHARMA_INTELLIGENCE_AGENT)")
    st.markdown("[Open Enterprise Intelligence Agent in Snowsight](https://app.snowflake.com/<ORG>/<ACCOUNT_NAME>/#/cortex-agent/DEMO.HEALTHCARE_DEMO.ENTERPRISE_INTELLIGENCE_AGENT)")

    st.divider()
    st.subheader("Example Prompts to Try")
    st.markdown("""
| Prompt | What It Does |
|--------|-------------|
| "Find oncologists in the Northeast and show their tiers" | Search + Analyst combined |
| "What is engagement effectiveness for top-tier HCPs?" | Uses derived fact ENGAGEMENT_EFFECTIVENESS |
| "How many HCPs are in each tier?" | Routes to Analyst |
| "Find cardiologists in Western territory" | Routes to Search |
| "What is the weighted pipeline by region?" | Enterprise Agent: routes to CRM domain |
| "What is budget variance for Oncology portfolio?" | Enterprise Agent: routes to Finance domain |
""")
