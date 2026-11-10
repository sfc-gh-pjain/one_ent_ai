-- ============================================================
-- Snowpipe Streaming Monitoring Queries
-- Run these after the producer to verify ingestion and health
-- ============================================================

USE ROLE SYSADMIN;
USE WAREHOUSE MY_WH;
USE SCHEMA DEMO.HEALTHCARE_DEMO;

-- ============================================================
-- 1. Row count and time range
-- ============================================================

SELECT
    COUNT(*) AS total_events,
    MIN(EVENT_TIMESTAMP) AS earliest_event,
    MAX(EVENT_TIMESTAMP) AS latest_event,
    DATEDIFF('second', MIN(EVENT_TIMESTAMP), MAX(EVENT_TIMESTAMP)) AS span_seconds,
    COUNT(DISTINCT HCP_ID) AS unique_hcps,
    COUNT(DISTINCT REP_ID) AS unique_reps,
    COUNT(DISTINCT EVENT_TYPE) AS event_types
FROM HCP_EVENTS_RT;

-- ============================================================
-- 2. Events per minute (throughput)
-- ============================================================

SELECT
    DATE_TRUNC('minute', EVENT_TIMESTAMP) AS minute,
    COUNT(*) AS events_per_min,
    COUNT(DISTINCT HCP_ID) AS unique_hcps
FROM HCP_EVENTS_RT
WHERE EVENT_TIMESTAMP > DATEADD('hour', -1, CURRENT_TIMESTAMP())
GROUP BY minute
ORDER BY minute;

-- ============================================================
-- 3. Breakdown by event type
-- ============================================================

SELECT
    EVENT_TYPE,
    COUNT(*) AS event_count,
    AVG(DURATION_SECONDS) AS avg_duration_sec,
    AVG(SENTIMENT_SCORE) AS avg_sentiment
FROM HCP_EVENTS_RT
GROUP BY EVENT_TYPE
ORDER BY event_count DESC;

-- ============================================================
-- 4. Breakdown by channel
-- ============================================================

SELECT
    CHANNEL,
    COUNT(*) AS event_count,
    COUNT(DISTINCT HCP_ID) AS unique_hcps
FROM HCP_EVENTS_RT
GROUP BY CHANNEL
ORDER BY event_count DESC;

-- ============================================================
-- 5. Top HCPs by engagement volume
-- ============================================================

SELECT
    HCP_ID,
    COUNT(*) AS total_engagements,
    COUNT(DISTINCT EVENT_TYPE) AS engagement_types,
    AVG(SENTIMENT_SCORE) AS avg_sentiment,
    MAX(EVENT_TIMESTAMP) AS last_engagement
FROM HCP_EVENTS_RT
GROUP BY HCP_ID
ORDER BY total_engagements DESC
LIMIT 10;

-- ============================================================
-- 6. VARIANT payload verification
-- ============================================================

SELECT
    EVENT_ID,
    EVENT_PAYLOAD:specialty::STRING AS specialty,
    EVENT_PAYLOAD:is_kol::BOOLEAN AS is_kol,
    EVENT_PAYLOAD:notes::STRING AS notes,
    EVENT_PAYLOAD:geo.lat::FLOAT AS latitude,
    TYPEOF(EVENT_PAYLOAD) AS payload_type
FROM HCP_EVENTS_RT
LIMIT 5;

-- ============================================================
-- 7. Channel health (pipe status)
-- ============================================================

SHOW PIPES LIKE '%HCP_EVENTS%' IN SCHEMA DEMO.HEALTHCARE_DEMO;
SHOW CHANNELS IN TABLE DEMO.HEALTHCARE_DEMO.HCP_EVENTS_RT;

-- ============================================================
-- 8. Ingestion latency (event time vs ingested time)
-- ============================================================

SELECT
    AVG(DATEDIFF('millisecond', EVENT_TIMESTAMP, INGESTED_AT)) AS avg_latency_ms,
    MAX(DATEDIFF('millisecond', EVENT_TIMESTAMP, INGESTED_AT)) AS max_latency_ms,
    MIN(DATEDIFF('millisecond', EVENT_TIMESTAMP, INGESTED_AT)) AS min_latency_ms
FROM HCP_EVENTS_RT
WHERE EVENT_TIMESTAMP > DATEADD('minute', -5, CURRENT_TIMESTAMP());

-- ============================================================
-- 9. Recent events (latest 10)
-- ============================================================

SELECT EVENT_ID, HCP_ID, REP_ID, EVENT_TYPE, CHANNEL, DRUG_ID, SENTIMENT_SCORE, EVENT_TIMESTAMP
FROM HCP_EVENTS_RT
ORDER BY EVENT_TIMESTAMP DESC
LIMIT 10;
