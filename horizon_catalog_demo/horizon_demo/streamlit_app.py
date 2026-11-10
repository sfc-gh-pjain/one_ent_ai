import streamlit as st
import json
import pandas as pd
import _snowflake
from snowflake.snowpark.context import get_active_session

session = get_active_session()

st.set_page_config(page_title="Horizon Healthcare Intelligence", layout="wide")

st.title("Horizon Healthcare Intelligence")
st.caption("Powered by Cortex Analyst + Cortex Search | HORIZON_DEMO_DB")

# --- Tabs ---
tab1, tab2, tab3, tab4, tab5 = st.tabs([
    "Healthcare Analytics",
    "Pipeline Metadata",
    "Table Discovery",
    "Governance Search",
    "Governance Details"
])


def call_cortex_analyst(semantic_model_path, question):
    """Call Cortex Analyst via REST API with a semantic model file."""
    request_body = {
        "messages": [{"role": "user", "content": [{"type": "text", "text": question}]}],
        "semantic_model_file": semantic_model_path
    }
    try:
        resp = _snowflake.send_snow_api_request(
            "POST",
            "/api/v2/cortex/analyst/message",
            {},
            {},
            request_body,
            {},
            30000
        )
        if resp and resp.get("status", 0) == 200:
            content = resp["content"]
            if isinstance(content, str):
                body = json.loads(content)
            else:
                body = content
            return body
        else:
            return {"error": f"Status {resp.get('status', 'unknown')}: {str(resp.get('content', ''))[:300]}"}
    except Exception as e:
        return {"error": str(e)}


def parse_analyst_response(response):
    """Parse Cortex Analyst response to extract SQL and text."""
    if "error" in response:
        return None, response["error"], None

    message = response.get("message", response)
    content = message.get("content", [])

    sql = None
    text_parts = []
    for item in content:
        if isinstance(item, dict):
            if item.get("type") == "sql":
                sql = item.get("statement", "")
            elif item.get("type") == "text":
                text_parts.append(item.get("text", ""))

    return sql, "\n".join(text_parts), None


def execute_sql_safely(sql):
    """Execute SQL and return pandas DataFrame."""
    try:
        df = session.sql(sql).to_pandas()
        return df, None
    except Exception as e:
        return None, str(e)


def call_cortex_search(query, service_name="HORIZON_DEMO_DB.HEALTHCARE.METADATA_SEARCH", limit=5):
    """Call Cortex Search service."""
    escaped_query = query.replace("'", "''").replace('"', '\\"')
    try:
        search_params = json.dumps({
            "query": query,
            "columns": ["TABLE_NAME", "PIPELINE_LAYER", "LAST_PIPELINE_STATUS", "SEARCH_TEXT"],
            "limit": limit
        }).replace("'", "''")
        result = session.sql(f"""
            SELECT TO_VARCHAR(
                SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
                    '{service_name}',
                    '{search_params}'
                )
            ) AS results
        """).collect()
        if result and result[0][0]:
            parsed = json.loads(result[0][0])
            return parsed.get("results", [])
        return []
    except Exception as e:
        # Fallback: direct table search
        try:
            escaped_like = query.replace("'", "''")
            result = session.sql(f"""
                SELECT TABLE_NAME, PIPELINE_LAYER, LAST_PIPELINE_STATUS, SEARCH_TEXT
                FROM HORIZON_DEMO_DB.HEALTHCARE.METADATA_SEARCH_CORPUS
                WHERE LOWER(SEARCH_TEXT) LIKE LOWER('%{escaped_like}%')
                LIMIT {limit}
            """).collect()
            return [{"TABLE_NAME": r[0], "PIPELINE_LAYER": r[1], "STATUS": r[2], "DESCRIPTION": r[3]} for r in result]
        except Exception as e2:
            return [{"error": str(e2)}]


# ===== TAB 1: Healthcare Analytics =====
with tab1:
    st.subheader("Healthcare Patient Analytics")
    st.markdown("Ask questions about patient demographics, visits, revenue, and department metrics.")

    col1, col2 = st.columns([3, 1])
    with col2:
        st.markdown("**Example questions:**")
        examples_health = [
            "What is the average revenue per patient by department?",
            "What is the no-show rate by department?",
            "Show total revenue by insurance provider",
            "Which department has the highest average patient age?",
            "What is the completed visit rate by gender?",
        ]
        for ex in examples_health:
            if st.button(ex, key=f"h_{ex[:20]}"):
                st.session_state["health_q"] = ex

    with col1:
        health_question = st.text_input(
            "Ask a healthcare analytics question:",
            value=st.session_state.get("health_q", ""),
            key="health_input"
        )

        if st.button("Ask", key="health_ask") and health_question:
            with st.spinner("Querying healthcare semantic model..."):
                resp = call_cortex_analyst(
                    "@HORIZON_DEMO_DB.HEALTHCARE.SEMANTIC_MODELS/healthcare_analytics_model.yaml",
                    health_question
                )
                sql, text, _ = parse_analyst_response(resp)

                if text:
                    st.markdown(text)
                if sql:
                    with st.expander("Generated SQL", expanded=False):
                        st.code(sql, language="sql")
                    df, err = execute_sql_safely(sql)
                    if df is not None:
                        st.dataframe(df, use_container_width=True)
                        if len(df.columns) >= 2 and df.dtypes.iloc[-1] in ['int64', 'float64']:
                            st.bar_chart(df.set_index(df.columns[0]))
                    else:
                        st.error(f"Error executing SQL: {err}")


# ===== TAB 2: Pipeline Metadata =====
with tab2:
    st.subheader("Pipeline Metadata Intelligence")
    st.markdown("Ask questions about pipeline health, execution history, warehouse usage, and data freshness.")

    col1, col2 = st.columns([3, 1])
    with col2:
        st.markdown("**Example questions:**")
        examples_meta = [
            "What is the pipeline success rate for each layer?",
            "Which pipelines failed in the last 3 days?",
            "What warehouse and size is used for gold layer pipelines?",
            "Show average duration by pipeline layer",
            "How many rows were rejected across all pipelines?",
        ]
        for ex in examples_meta:
            if st.button(ex, key=f"m_{ex[:20]}"):
                st.session_state["meta_q"] = ex

    with col1:
        meta_question = st.text_input(
            "Ask a pipeline metadata question:",
            value=st.session_state.get("meta_q", ""),
            key="meta_input"
        )

        if st.button("Ask", key="meta_ask") and meta_question:
            with st.spinner("Querying metadata semantic model..."):
                resp = call_cortex_analyst(
                    "@HORIZON_DEMO_DB.HEALTHCARE.SEMANTIC_MODELS/metadata_semantic_model.yaml",
                    meta_question
                )
                sql, text, _ = parse_analyst_response(resp)

                if text:
                    st.markdown(text)
                if sql:
                    with st.expander("Generated SQL", expanded=False):
                        st.code(sql, language="sql")
                    df, err = execute_sql_safely(sql)
                    if df is not None:
                        st.dataframe(df, use_container_width=True)
                    else:
                        st.error(f"Error executing SQL: {err}")


# ===== TAB 3: Table Discovery =====
with tab3:
    st.subheader("Table Discovery (Cortex Search)")
    st.markdown("Search across the metadata catalog to find tables by name, layer, or description.")

    col1, col2 = st.columns([3, 1])
    with col2:
        st.markdown("**Example searches:**")
        examples_search = [
            "patient billing",
            "gold layer tables",
            "pipeline status failed",
            "revenue dashboard",
            "appointments data",
        ]
        for ex in examples_search:
            if st.button(ex, key=f"s_{ex[:20]}"):
                st.session_state["search_q"] = ex

    with col1:
        search_query = st.text_input(
            "Search for tables:",
            value=st.session_state.get("search_q", ""),
            key="search_input"
        )

        if st.button("Search", key="search_go") and search_query:
            with st.spinner("Searching metadata catalog..."):
                results = call_cortex_search(search_query)
                if results and not (len(results) == 1 and "error" in results[0]):
                    for i, r in enumerate(results):
                        with st.container():
                            st.markdown(f"**{i+1}. {r.get('TABLE_NAME', 'Unknown')}**")
                            st.markdown(f"Layer: `{r.get('PIPELINE_LAYER', 'N/A')}` | Status: `{r.get('LAST_PIPELINE_STATUS', r.get('STATUS', 'N/A'))}`")
                            if r.get('DESCRIPTION') or r.get('SEARCH_TEXT') or r.get('search_text'):
                                st.caption(r.get('DESCRIPTION', r.get('SEARCH_TEXT', r.get('search_text', '')))[:200])
                            st.divider()
                else:
                    st.warning("No results found. Try different search terms.")


# ===== TAB 4: Governance Search =====
with tab4:
    st.subheader("Governance Search")
    st.markdown("Search governance metadata using natural language — find tables by classification, PII level, policies, or tags.")

    col1, col2 = st.columns([3, 1])
    with col2:
        st.markdown("**Example searches:**")
        examples_gov = [
            "tables with PHI data",
            "high PII sensitive columns",
            "masking policy applied",
            "financial data classification",
            "gold layer analytics tables",
            "tables from EHR source system",
        ]
        for ex in examples_gov:
            if st.button(ex, key=f"g_{ex[:20]}"):
                st.session_state["gov_q"] = ex

    with col1:
        gov_query = st.text_input(
            "Search governance metadata:",
            value=st.session_state.get("gov_q", ""),
            key="gov_input",
            placeholder="e.g., which tables have masking policies?"
        )

        if st.button("Search", key="gov_search") and gov_query:
            with st.spinner("Searching governance catalog..."):
                escaped_query = gov_query.replace("'", "''").replace('"', '\\"')
                search_params = json.dumps({
                    "query": gov_query,
                    "columns": ["TABLE_NAME", "TAGS", "PII_COLUMNS", "ACTIVE_POLICIES", "SEARCH_TEXT"],
                    "limit": 10
                }).replace("'", "''")
                try:
                    result = session.sql(f"""
                        SELECT TO_VARCHAR(
                            SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
                                'HORIZON_DEMO_DB.HEALTHCARE.GOVERNANCE_SEARCH',
                                '{search_params}'
                            )
                        ) AS results
                    """).collect()
                    if result and result[0][0]:
                        parsed = json.loads(result[0][0])
                        results = parsed.get("results", [])
                        if results:
                            for i, r in enumerate(results):
                                with st.container():
                                    st.markdown(f"### {i+1}. {r.get('TABLE_NAME', 'Unknown')}")
                                    
                                    c1, c2 = st.columns(2)
                                    with c1:
                                        st.markdown("**Tags:**")
                                        tags = r.get('TAGS', 'None')
                                        if tags and tags != 'No tags':
                                            for tag in tags.split(', '):
                                                parts = tag.split('=')
                                                if len(parts) == 2:
                                                    st.markdown(f"- `{parts[0]}` = **{parts[1]}**")
                                        else:
                                            st.caption("No tags assigned")
                                    
                                    with c2:
                                        st.markdown("**PII Columns:**")
                                        pii = r.get('PII_COLUMNS', 'None')
                                        if pii and pii != 'None':
                                            for col in pii.split(', '):
                                                if 'HIGH' in col:
                                                    st.markdown(f"- :red[{col}]")
                                                elif 'MEDIUM' in col:
                                                    st.markdown(f"- :orange[{col}]")
                                                else:
                                                    st.markdown(f"- {col}")
                                        else:
                                            st.caption("No PII columns")
                                    
                                    policies = r.get('ACTIVE_POLICIES', 'None')
                                    if policies and policies != 'None':
                                        st.markdown("**Active Policies:**")
                                        for pol in policies.split('; '):
                                            st.markdown(f"- `{pol}`")
                                    
                                    st.divider()
                        else:
                            st.warning("No results found. Try different search terms.")
                    else:
                        st.warning("No results returned.")
                except Exception as e:
                    st.error(f"Search error: {e}")


# ===== TAB 5: Governance Details =====
with tab5:
    st.subheader("Data Governance Dashboard")
    st.markdown("Explore tags, data classification, masking policies, and compliance metadata across all tables.")

    gov_tab1, gov_tab2, gov_tab3 = st.tabs(["Table Tags", "PII & Sensitivity", "Policies"])

    with gov_tab1:
        st.markdown("#### Table-Level Tags")
        try:
            tag_df = session.sql("""
                SELECT OBJECT_NAME AS TABLE_NAME, TAG_NAME, TAG_VALUE
                FROM SNOWFLAKE.ACCOUNT_USAGE.TAG_REFERENCES
                WHERE TAG_DATABASE = 'HORIZON_DEMO_DB' AND TAG_SCHEMA = 'HEALTHCARE'
                  AND OBJECT_DATABASE = 'HORIZON_DEMO_DB'
                  AND COLUMN_NAME IS NULL
                  AND DOMAIN = 'TABLE'
                ORDER BY OBJECT_NAME, TAG_NAME
            """).to_pandas()
            if not tag_df.empty:
                # Pivot for a nice view
                pivot_df = tag_df.pivot_table(index='TABLE_NAME', columns='TAG_NAME', values='TAG_VALUE', aggfunc='first').reset_index()
                st.dataframe(pivot_df, use_container_width=True, height=400)

                # Filter by tag
                col1, col2 = st.columns(2)
                with col1:
                    selected_tag = st.selectbox("Filter by tag:", sorted(tag_df['TAG_NAME'].unique()))
                with col2:
                    tag_values = sorted(tag_df[tag_df['TAG_NAME'] == selected_tag]['TAG_VALUE'].dropna().unique())
                    selected_value = st.selectbox("Filter by value:", ["All"] + list(tag_values))

                filtered = tag_df[tag_df['TAG_NAME'] == selected_tag]
                if selected_value != "All":
                    filtered = filtered[filtered['TAG_VALUE'] == selected_value]
                st.dataframe(filtered, use_container_width=True)
            else:
                st.info("No table-level tags found.")
        except Exception as e:
            st.error(f"Error loading tags: {e}")

    with gov_tab2:
        st.markdown("#### Column-Level PII Classification")
        try:
            pii_df = session.sql("""
                SELECT OBJECT_NAME AS TABLE_NAME, COLUMN_NAME, TAG_VALUE AS PII_LEVEL
                FROM SNOWFLAKE.ACCOUNT_USAGE.TAG_REFERENCES
                WHERE TAG_DATABASE = 'HORIZON_DEMO_DB' AND TAG_SCHEMA = 'HEALTHCARE'
                  AND TAG_NAME = 'PII_LEVEL'
                  AND COLUMN_NAME IS NOT NULL
                ORDER BY 
                  CASE TAG_VALUE WHEN 'HIGH' THEN 1 WHEN 'MEDIUM' THEN 2 WHEN 'LOW' THEN 3 ELSE 4 END,
                  OBJECT_NAME, COLUMN_NAME
            """).to_pandas()
            if not pii_df.empty:
                # Summary metrics
                c1, c2, c3 = st.columns(3)
                high_count = len(pii_df[pii_df['PII_LEVEL'] == 'HIGH'])
                med_count = len(pii_df[pii_df['PII_LEVEL'] == 'MEDIUM'])
                low_count = len(pii_df[pii_df['PII_LEVEL'] == 'LOW'])
                c1.metric("HIGH PII Columns", high_count)
                c2.metric("MEDIUM PII Columns", med_count)
                c3.metric("LOW PII Columns", low_count)

                st.dataframe(pii_df, use_container_width=True)
            else:
                st.info("No PII column tags found.")

            st.markdown("#### Data Classification by Table")
            class_df = session.sql("""
                SELECT OBJECT_NAME AS TABLE_NAME, TAG_VALUE AS CLASSIFICATION
                FROM SNOWFLAKE.ACCOUNT_USAGE.TAG_REFERENCES
                WHERE TAG_DATABASE = 'HORIZON_DEMO_DB' AND TAG_SCHEMA = 'HEALTHCARE'
                  AND TAG_NAME = 'DATA_CLASSIFICATION'
                  AND COLUMN_NAME IS NULL
                  AND DOMAIN = 'TABLE'
                ORDER BY OBJECT_NAME
            """).to_pandas()
            if not class_df.empty:
                st.dataframe(class_df, use_container_width=True)
        except Exception as e:
            st.error(f"Error loading PII data: {e}")

    with gov_tab3:
        st.markdown("#### Active Policies")
        st.markdown("**Masking Policies:**")
        try:
            mask_df = session.sql("""
                SELECT POLICY_NAME, REF_ENTITY_NAME AS TABLE_NAME, REF_COLUMN_NAME AS COLUMN_NAME
                FROM SNOWFLAKE.ACCOUNT_USAGE.POLICY_REFERENCES
                WHERE POLICY_DB = 'HORIZON_DEMO_DB' AND POLICY_SCHEMA = 'HEALTHCARE'
                  AND POLICY_KIND = 'MASKING_POLICY'
                ORDER BY REF_ENTITY_NAME, REF_COLUMN_NAME
            """).to_pandas()
            if not mask_df.empty:
                st.dataframe(mask_df, use_container_width=True)
            else:
                st.info("No masking policy references found in ACCOUNT_USAGE (may take up to 2 hours to appear).")
        except Exception as e:
            st.warning(f"Could not load masking policies: {e}")

        st.markdown("**Row Access Policies:**")
        try:
            rap_df = session.sql("""
                SELECT POLICY_NAME, REF_ENTITY_NAME AS TABLE_NAME
                FROM SNOWFLAKE.ACCOUNT_USAGE.POLICY_REFERENCES
                WHERE POLICY_DB = 'HORIZON_DEMO_DB' AND POLICY_SCHEMA = 'HEALTHCARE'
                  AND POLICY_KIND = 'ROW_ACCESS_POLICY'
                ORDER BY REF_ENTITY_NAME
            """).to_pandas()
            if not rap_df.empty:
                st.dataframe(rap_df, use_container_width=True)
            else:
                st.info("No row access policy references found in ACCOUNT_USAGE.")
        except Exception as e:
            st.warning(f"Could not load row access policies: {e}")

        st.markdown("---")
        st.markdown("#### Live Masking Demo")
        st.markdown("See how masking works by comparing views with different roles:")
        st.code("""-- Run in a SQL worksheet:
USE ROLE SYSADMIN;
SELECT patient_id, first_name, ssn, email, phone
FROM HORIZON_DEMO_DB.HEALTHCARE.PATIENTS LIMIT 5;

-- Now switch to analyst role (masked view):
USE ROLE HORIZON_DEMO_ANALYST;
SELECT patient_id, first_name, ssn, email, phone
FROM HORIZON_DEMO_DB.HEALTHCARE.PATIENTS LIMIT 5;""", language="sql")


# --- Sidebar info ---
with st.sidebar:
    st.markdown("### About")
    st.markdown("""
    This app demonstrates **Snowflake Horizon Catalog** AI capabilities:

    - **Healthcare Analytics** — Cortex Analyst over patient/visit/revenue data
    - **Pipeline Metadata** — Cortex Analyst over execution logs and freshness
    - **Table Discovery** — Cortex Search over the metadata catalog

    **Database:** `HORIZON_DEMO_DB`
    **Schema:** `HEALTHCARE`
    **Records:** 155K across 6 tables
    """)

    st.markdown("---")
    st.markdown("### Governance Demo")
    st.markdown("""
    Run these in a SQL worksheet to show masking:
    ```sql
    USE ROLE SYSADMIN;
    SELECT patient_id, ssn, email
    FROM PATIENTS LIMIT 5;

    USE ROLE HORIZON_DEMO_ANALYST;
    SELECT patient_id, ssn, email
    FROM PATIENTS LIMIT 5;
    ```
    """)
