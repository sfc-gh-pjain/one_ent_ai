-- ============================================================
-- AI-Assisted Data Quality Monitoring
-- Uses Cortex AI to suggest rules, interpret violations, detect trends
-- ============================================================
-- Demonstrates how AI built into Snowflake facilitates long-term
-- DQ monitoring development and maintenance.
-- ============================================================

USE ROLE SYSADMIN;
USE WAREHOUSE MY_WH;
USE SCHEMA DEMO.HEALTHCARE_DEMO;

-- ============================================================
-- 1. AI-Generated DQ Rule Suggestions
-- Analyzes table columns and suggests appropriate quality checks
-- ============================================================

CREATE OR REPLACE TABLE DQ_AI_SUGGESTIONS AS
SELECT
    TABLE_NAME,
    COLUMN_NAME,
    DATA_TYPE,
    SNOWFLAKE.CORTEX.COMPLETE('mistral-large2',
        'You are a data quality engineer. Given a column named "' || COLUMN_NAME ||
        '" with data type ' || DATA_TYPE ||
        ' in a pharmaceutical commercial analytics table called "' || TABLE_NAME ||
        '", suggest exactly 2 data quality rules. ' ||
        'Return ONLY a JSON array with objects containing: rule_name (short snake_case), ' ||
        'sql_condition (a WHERE clause that finds BAD rows), severity (CRITICAL or WARNING). ' ||
        'Example: [{"rule_name":"null_check","sql_condition":"column IS NULL","severity":"CRITICAL"}]'
    ) AS AI_SUGGESTED_RULES,
    CURRENT_TIMESTAMP() AS GENERATED_AT
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'HEALTHCARE_DEMO'
  AND TABLE_NAME IN ('RAW_PRESCRIPTIONS', 'RAW_HCP_PROFILES', 'RAW_HCP_ENGAGEMENTS')
  AND COLUMN_NAME IN ('RX_ID', 'DRUG_ID', 'HCP_ID', 'QUANTITY', 'NPI_NUMBER',
                       'ENGAGEMENT_DATE', 'SENTIMENT_SCORE', 'TERRITORY_ID');

-- ============================================================
-- 2. AI Violation Interpretation
-- Explains violations in business language and suggests remediation
-- ============================================================

CREATE OR REPLACE VIEW DQ_VIOLATION_INSIGHTS AS
SELECT
    VIOLATION_ID,
    RULE_NAME,
    TABLE_NAME,
    RECORD_ID,
    VIOLATION_DETAIL,
    SEVERITY,
    DETECTED_AT,
    SNOWFLAKE.CORTEX.COMPLETE('mistral-large2',
        'Explain this data quality violation in ONE sentence for a business analyst ' ||
        '(no technical jargon): Rule: ' || RULE_NAME ||
        ', Detail: ' || VIOLATION_DETAIL
    ) AS AI_EXPLANATION,
    SNOWFLAKE.CORTEX.COMPLETE('mistral-large2',
        'Suggest ONE specific remediation action for this data quality issue: ' ||
        RULE_NAME || ' - ' || VIOLATION_DETAIL ||
        '. Reply with a single actionable sentence starting with a verb.'
    ) AS AI_REMEDIATION
FROM MDM_VIOLATION_LOG
WHERE RESOLVED = FALSE;

-- ============================================================
-- 3. AI-Driven Violation Trend Analysis
-- Detects patterns and anomalies in violation frequency
-- ============================================================

CREATE OR REPLACE VIEW DQ_TREND_ANALYSIS AS
SELECT
    RULE_NAME,
    TABLE_NAME,
    COUNT(*) AS violation_count,
    COUNT(CASE WHEN SEVERITY = 'CRITICAL' THEN 1 END) AS critical_count,
    MIN(DETECTED_AT) AS first_seen,
    MAX(DETECTED_AT) AS last_seen,
    DATEDIFF('hour', MIN(DETECTED_AT), MAX(DETECTED_AT)) AS span_hours,
    SNOWFLAKE.CORTEX.COMPLETE('mistral-large2',
        'I have ' || COUNT(*) || ' data quality violations for rule "' || RULE_NAME ||
        '" on table ' || TABLE_NAME ||
        ', with ' || COUNT(CASE WHEN SEVERITY = 'CRITICAL' THEN 1 END) || ' critical. ' ||
        'First detected: ' || MIN(DETECTED_AT)::VARCHAR ||
        ', last detected: ' || MAX(DETECTED_AT)::VARCHAR ||
        '. In 1-2 sentences: Is this a growing trend, a one-time event, or steady state? ' ||
        'Should we escalate?'
    ) AS AI_TREND_ASSESSMENT
FROM MDM_VIOLATION_LOG
GROUP BY RULE_NAME, TABLE_NAME;

-- ============================================================
-- 4. AI Schema Evolution Impact Assessment
-- Helps maintain DQ rules when schemas change
-- ============================================================

CREATE OR REPLACE VIEW DQ_SCHEMA_COVERAGE AS
SELECT
    c.TABLE_NAME,
    c.COLUMN_NAME,
    c.DATA_TYPE,
    c.IS_NULLABLE,
    CASE
        WHEN c.IS_NULLABLE = 'YES' AND c.DATA_TYPE IN ('NUMBER', 'FLOAT')
        THEN 'Consider: null check + range validation'
        WHEN c.DATA_TYPE = 'VARCHAR' AND c.CHARACTER_MAXIMUM_LENGTH < 50
        THEN 'Consider: format validation + allowed values'
        WHEN c.DATA_TYPE = 'DATE'
        THEN 'Consider: future date check + freshness'
        ELSE 'Review needed'
    END AS SUGGESTED_COVERAGE
FROM INFORMATION_SCHEMA.COLUMNS c
WHERE c.TABLE_SCHEMA = 'HEALTHCARE_DEMO'
  AND c.TABLE_NAME IN ('RX_METRICS_OUTPUT', 'HCP_TIERED_PROFILES', 'ENGAGEMENT_FINAL',
                        'RAW_PRESCRIPTIONS', 'RAW_HCP_PROFILES', 'RAW_HCP_ENGAGEMENTS')
ORDER BY c.TABLE_NAME, c.ORDINAL_POSITION;

-- ============================================================
-- 5. Verify
-- ============================================================

SELECT 'DQ_AI_SUGGESTIONS' AS object_name, COUNT(*) AS row_count FROM DQ_AI_SUGGESTIONS
UNION ALL
SELECT 'MDM_VIOLATION_LOG', COUNT(*) FROM MDM_VIOLATION_LOG;
