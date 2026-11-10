"""
Healthcare Data Quality & MDM Monitor
5-tab Streamlit dashboard for monitoring data quality, business rules,
freshness, lineage, and data catalog.
"""

import streamlit as st
import pandas as pd
from snowflake.snowpark.context import get_active_session

st.set_page_config(page_title="DQ & MDM Monitor", page_icon="🏥", layout="wide")

session = get_active_session()

st.title("Healthcare Data Quality & MDM Monitor")
st.caption("Real-time monitoring of data quality, business rules, and governance")

# --- Tabs ---
tab_dq, tab_br, tab_fresh, tab_lineage, tab_catalog = st.tabs([
    "DQ Scores", "Business Rules", "Freshness", "Lineage", "Data Catalog"
])

# ============================================================
# Tab 1: Data Quality Scores
# ============================================================
with tab_dq:
    st.header("Data Quality Scores")

    col1, col2 = st.columns([2, 1])

    with col1:
        st.subheader("DMF Results by Table")
        try:
            dq_results = session.sql("""
                SELECT
                    TABLE_NAME,
                    METRIC_NAME,
                    METRIC_DATABASE || '.' || METRIC_SCHEMA || '.' || METRIC_NAME AS FULL_METRIC_NAME,
                    ARGUMENT_NAMES,
                    VALUE AS METRIC_VALUE,
                    MEASUREMENT_TIME
                FROM SNOWFLAKE.LOCAL.DATA_QUALITY_MONITORING_RESULTS
                WHERE TABLE_SCHEMA = 'HEALTHCARE_DEMO'
                  AND TABLE_DATABASE = 'DEMO'
                ORDER BY MEASUREMENT_TIME DESC
                LIMIT 100
            """).to_pandas()

            if not dq_results.empty:
                st.dataframe(dq_results, use_container_width=True, hide_index=True)
            else:
                st.info("No DMF results yet. DMFs will run on next table change.")
        except Exception as e:
            st.warning(f"Cannot access DMF results: {e}")

    with col2:
        st.subheader("Quality Summary")
        try:
            summary = session.sql("""
                SELECT
                    TABLE_NAME,
                    COUNT(*) AS total_checks,
                    SUM(CASE WHEN VALUE = 0 THEN 1 ELSE 0 END) AS passing,
                    ROUND(SUM(CASE WHEN VALUE = 0 THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 1) AS pass_pct
                FROM SNOWFLAKE.LOCAL.DATA_QUALITY_MONITORING_RESULTS
                WHERE TABLE_SCHEMA = 'HEALTHCARE_DEMO'
                  AND TABLE_DATABASE = 'DEMO'
                  AND MEASUREMENT_TIME >= DATEADD('day', -7, CURRENT_TIMESTAMP())
                GROUP BY TABLE_NAME
                ORDER BY pass_pct ASC
            """).to_pandas()

            if not summary.empty:
                for _, row in summary.iterrows():
                    pct = row['PASS_PCT']
                    color = "green" if pct >= 95 else ("orange" if pct >= 80 else "red")
                    st.metric(
                        label=row['TABLE_NAME'],
                        value=f"{pct}%",
                        delta=f"{int(row['PASSING'])}/{int(row['TOTAL_CHECKS'])} passing"
                    )
            else:
                st.info("No results in last 7 days")
        except Exception as e:
            st.warning(f"Cannot compute summary: {e}")

    st.subheader("DQ Trend (Last 30 Days)")
    try:
        trend = session.sql("""
            SELECT
                DATE_TRUNC('day', MEASUREMENT_TIME) AS DAY,
                TABLE_NAME,
                ROUND(SUM(CASE WHEN VALUE = 0 THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 1) AS PASS_PCT
            FROM SNOWFLAKE.LOCAL.DATA_QUALITY_MONITORING_RESULTS
            WHERE TABLE_SCHEMA = 'HEALTHCARE_DEMO'
              AND TABLE_DATABASE = 'DEMO'
              AND MEASUREMENT_TIME >= DATEADD('day', -30, CURRENT_TIMESTAMP())
            GROUP BY DAY, TABLE_NAME
            ORDER BY DAY
        """).to_pandas()

        if not trend.empty:
            st.line_chart(trend.pivot(index='DAY', columns='TABLE_NAME', values='PASS_PCT'))
        else:
            st.info("Not enough data for trend chart yet")
    except Exception as e:
        st.warning(f"Cannot load trend data: {e}")

# ============================================================
# Tab 2: Business Rules (MDM Violations)
# ============================================================
with tab_br:
    st.header("Business Rules & MDM Violations")

    col1, col2, col3 = st.columns(3)

    try:
        violations = session.sql("""
            SELECT
                RULE_NAME,
                TABLE_NAME,
                SEVERITY,
                COUNT(*) AS VIOLATION_COUNT,
                MAX(DETECTED_AT) AS LATEST_DETECTION,
                SUM(CASE WHEN RESOLVED THEN 1 ELSE 0 END) AS RESOLVED_COUNT
            FROM DEMO.HEALTHCARE_DEMO.MDM_VIOLATION_LOG
            GROUP BY RULE_NAME, TABLE_NAME, SEVERITY
            ORDER BY VIOLATION_COUNT DESC
        """).to_pandas()

        if not violations.empty:
            total_v = violations['VIOLATION_COUNT'].sum()
            resolved = violations['RESOLVED_COUNT'].sum()
            critical = violations[violations['SEVERITY'] == 'CRITICAL']['VIOLATION_COUNT'].sum()

            col1.metric("Total Violations", int(total_v))
            col2.metric("Resolved", int(resolved))
            col3.metric("Critical", int(critical))

            st.subheader("Violations by Rule")
            st.dataframe(violations, use_container_width=True, hide_index=True)
        else:
            col1.metric("Total Violations", 0)
            col2.metric("Resolved", 0)
            col3.metric("Critical", 0)
            st.success("No violations detected")
    except Exception as e:
        st.warning(f"Cannot access violation log: {e}")

    st.divider()
    st.subheader("Task Execution History")
    try:
        task_hist = session.sql("""
            SELECT
                NAME,
                STATE,
                SCHEDULED_TIME,
                COMPLETED_TIME,
                DATEDIFF('second', SCHEDULED_TIME, COMPLETED_TIME) AS DURATION_SEC,
                ERROR_CODE,
                ERROR_MESSAGE
            FROM TABLE(INFORMATION_SCHEMA.TASK_HISTORY(
                SCHEDULED_TIME_RANGE_START => DATEADD('day', -7, CURRENT_TIMESTAMP()),
                RESULT_LIMIT => 50
            ))
            WHERE NAME LIKE '%MDM%'
            ORDER BY SCHEDULED_TIME DESC
        """).to_pandas()

        if not task_hist.empty:
            st.dataframe(task_hist, use_container_width=True, hide_index=True)
        else:
            st.info("No MDM task runs in the last 7 days")
    except Exception as e:
        st.warning(f"Cannot access task history: {e}")

    st.subheader("Recent Violation Details")
    try:
        recent = session.sql("""
            SELECT RULE_NAME, TABLE_NAME, RECORD_ID, VIOLATION_DETAIL, SEVERITY, DETECTED_AT
            FROM DEMO.HEALTHCARE_DEMO.MDM_VIOLATION_LOG
            WHERE RESOLVED = FALSE
            ORDER BY DETECTED_AT DESC
            LIMIT 20
        """).to_pandas()

        if not recent.empty:
            st.dataframe(recent, use_container_width=True, hide_index=True)
        else:
            st.success("No unresolved violations")
    except Exception as e:
        st.warning(f"Cannot load recent violations: {e}")

# ============================================================
# Tab 3: Freshness
# ============================================================
with tab_fresh:
    st.header("Data Freshness & SLA Monitoring")

    sla_hours = st.slider("SLA Threshold (hours)", 1, 72, 24)

    try:
        freshness_data = session.sql(f"""
            SELECT
                'RX_METRICS_OUTPUT' AS TABLE_NAME,
                MAX(ETL_TIMESTAMP) AS LAST_REFRESH,
                DATEDIFF('hour', MAX(ETL_TIMESTAMP), CURRENT_TIMESTAMP()) AS HOURS_STALE
            FROM DEMO.HEALTHCARE_DEMO.RX_METRICS_OUTPUT
            UNION ALL
            SELECT
                'HCP_TIERED_PROFILES',
                MAX(ETL_UPDATE_DATETIME_UTC),
                DATEDIFF('hour', MAX(ETL_UPDATE_DATETIME_UTC), CURRENT_TIMESTAMP())
            FROM DEMO.HEALTHCARE_DEMO.HCP_TIERED_PROFILES
            UNION ALL
            SELECT
                'ENGAGEMENT_FINAL',
                MAX(ENGAGEMENT_DATE)::TIMESTAMP_NTZ,
                DATEDIFF('hour', MAX(ENGAGEMENT_DATE)::TIMESTAMP_NTZ, CURRENT_TIMESTAMP())
            FROM DEMO.HEALTHCARE_DEMO.ENGAGEMENT_FINAL
            UNION ALL
            SELECT
                'HCP_GOLDEN_RECORD',
                MAX(UPDATED_AT),
                DATEDIFF('hour', MAX(UPDATED_AT), CURRENT_TIMESTAMP())
            FROM DEMO.HEALTHCARE_DEMO.HCP_GOLDEN_RECORD
        """).to_pandas()

        if not freshness_data.empty:
            for _, row in freshness_data.iterrows():
                hours = row['HOURS_STALE'] if row['HOURS_STALE'] is not None else 9999
                status = "normal" if hours <= sla_hours else "inverse"
                icon = "✅" if hours <= sla_hours else "🚨"
                st.metric(
                    label=f"{icon} {row['TABLE_NAME']}",
                    value=f"{int(hours)} hours ago" if hours < 9999 else "No data",
                    delta="Within SLA" if hours <= sla_hours else f"BREACHED ({int(hours - sla_hours)}h over)",
                    delta_color=status
                )
        else:
            st.info("No data in target tables")
    except Exception as e:
        st.warning(f"Cannot compute freshness: {e}")

    st.divider()
    st.subheader("Stream Status")
    try:
        streams = session.sql("""
            SHOW STREAMS IN SCHEMA DEMO.HEALTHCARE_DEMO
        """).to_pandas()
        if not streams.empty:
            display_cols = ['name', 'stale', 'stale_after']
            available = [c for c in display_cols if c in streams.columns]
            st.dataframe(streams[available] if available else streams, use_container_width=True, hide_index=True)
        else:
            st.info("No streams found")
    except Exception as e:
        st.warning(f"Cannot show streams: {e}")

# ============================================================
# Tab 4: Lineage
# ============================================================
with tab_lineage:
    st.header("Data Lineage & Dependencies")

    st.subheader("Object Dependencies")
    try:
        deps = session.sql("""
            SELECT
                REFERENCING_OBJECT_NAME AS DOWNSTREAM_OBJECT,
                REFERENCING_OBJECT_DOMAIN AS DOWNSTREAM_TYPE,
                REFERENCED_OBJECT_NAME AS UPSTREAM_OBJECT,
                REFERENCED_OBJECT_DOMAIN AS UPSTREAM_TYPE
            FROM SNOWFLAKE.ACCOUNT_USAGE.OBJECT_DEPENDENCIES
            WHERE REFERENCED_SCHEMA_NAME = 'HEALTHCARE_DEMO'
               OR REFERENCING_SCHEMA_NAME = 'HEALTHCARE_DEMO'
            ORDER BY DOWNSTREAM_OBJECT
        """).to_pandas()

        if not deps.empty:
            st.dataframe(deps, use_container_width=True, hide_index=True)

            st.subheader("Dependency Graph (Text)")
            upstream_map = deps.groupby('DOWNSTREAM_OBJECT')['UPSTREAM_OBJECT'].apply(list).to_dict()
            for obj, sources in upstream_map.items():
                st.text(f"  {', '.join(sources)} → {obj}")
        else:
            st.info("No dependency data available (may require ACCOUNT_USAGE access)")
    except Exception as e:
        st.warning(f"Cannot access lineage data: {e}")

    st.divider()
    st.subheader("Pipeline Flow")
    st.markdown("""
    ```
    RAW_PRESCRIPTIONS ──→ [01_rx_metrics_load] ──→ RX_METRICS_OUTPUT
    RAW_HCP_PROFILES  ──→ [02_hcp_classification] ──→ HCP_TIERED_PROFILES
    RAW_HCP_ENGAGEMENTS + DIM_* ──→ [03_engagement_merge] ──→ ENGAGEMENT_FINAL
    RAW_HCP_PROFILES ──→ [TASK_MDM_HCP_DEDUP] ──→ HCP_GOLDEN_RECORD
    ```
    """)

# ============================================================
# Tab 5: Data Catalog
# ============================================================
with tab_catalog:
    st.header("Data Catalog & Governance")

    st.subheader("Tagged Objects — Sensitivity")
    try:
        tags = session.sql("""
            SELECT
                OBJECT_NAME,
                COLUMN_NAME,
                TAG_NAME,
                TAG_VALUE
            FROM TABLE(INFORMATION_SCHEMA.TAG_REFERENCES_ALL_COLUMNS(
                'DEMO.HEALTHCARE_DEMO.RAW_HCP_PROFILES', 'TABLE'
            ))
            UNION ALL
            SELECT
                OBJECT_NAME,
                COLUMN_NAME,
                TAG_NAME,
                TAG_VALUE
            FROM TABLE(INFORMATION_SCHEMA.TAG_REFERENCES_ALL_COLUMNS(
                'DEMO.HEALTHCARE_DEMO.HCP_GOLDEN_RECORD', 'TABLE'
            ))
            UNION ALL
            SELECT
                OBJECT_NAME,
                COLUMN_NAME,
                TAG_NAME,
                TAG_VALUE
            FROM TABLE(INFORMATION_SCHEMA.TAG_REFERENCES_ALL_COLUMNS(
                'DEMO.HEALTHCARE_DEMO.RAW_HCP_ENGAGEMENTS', 'TABLE'
            ))
            ORDER BY TAG_NAME, OBJECT_NAME
        """).to_pandas()

        if not tags.empty:
            phi_cols = tags[tags['TAG_VALUE'] == 'PHI']
            pii_cols = tags[tags['TAG_VALUE'] == 'PII']

            col1, col2, col3 = st.columns(3)
            col1.metric("PHI Columns", len(phi_cols))
            col2.metric("PII Columns", len(pii_cols))
            col3.metric("Total Tagged", len(tags))

            st.dataframe(tags, use_container_width=True, hide_index=True)
        else:
            st.info("No tags found. Run 04_governance.sql to apply tags.")
    except Exception as e:
        st.warning(f"Cannot access tag references: {e}")

    st.divider()
    st.subheader("Masking Policies")
    try:
        policies = session.sql("""
            SHOW MASKING POLICIES IN SCHEMA DEMO.HEALTHCARE_DEMO
        """).to_pandas()
        if not policies.empty:
            st.dataframe(policies[['name', 'kind', 'created_on']] if 'name' in policies.columns else policies,
                        use_container_width=True, hide_index=True)
        else:
            st.info("No masking policies found")
    except Exception as e:
        st.warning(f"Cannot show masking policies: {e}")

    st.divider()
    st.subheader("Table Inventory")
    try:
        tables = session.sql("""
            SELECT
                TABLE_NAME,
                ROW_COUNT,
                BYTES / (1024*1024) AS SIZE_MB,
                LAST_ALTERED
            FROM DEMO.INFORMATION_SCHEMA.TABLES
            WHERE TABLE_SCHEMA = 'HEALTHCARE_DEMO'
              AND TABLE_TYPE = 'BASE TABLE'
            ORDER BY TABLE_NAME
        """).to_pandas()

        if not tables.empty:
            st.dataframe(tables, use_container_width=True, hide_index=True)
    except Exception as e:
        st.warning(f"Cannot load table inventory: {e}")
