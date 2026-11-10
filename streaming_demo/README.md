# Snowpipe Streaming Demo

Real-time ingestion of HCP engagement events into Snowflake using the Snowpipe Streaming Python SDK (High-Performance Architecture).

## Overview

Simulates a pharmaceutical CRM (e.g., Veeva) pushing live sales rep engagement events into Snowflake with sub-second latency. Events include detail visits, digital interactions, sample drops, and conference attendance.

## Architecture

```
                    Snowpipe Streaming (High-Performance)
                    =====================================

 ┌────────────────────┐         ┌─────────────────────────────────────┐
 │  Event Producer    │         │          Snowflake                  │
 │  (stream_producer) │         │                                     │
 │                    │  SDK    │  PIPE: HCP_EVENTS_RT_STREAMING      │
 │  Generates events  │────────▶│         │                           │
 │  at 50/sec         │ channels│         ▼                           │
 │  (4 partitions)    │         │  TABLE: HCP_EVENTS_RT               │
 │                    │         │  (EVENT_ID, HCP_ID, REP_ID,         │
 └────────────────────┘         │   EVENT_TYPE, CHANNEL, DRUG_ID,     │
                                │   EVENT_PAYLOAD [VARIANT], ...)      │
                                └─────────────────────────────────────┘

 Key Features:
  - Multi-channel partitioning (hash by HCP_ID)
  - Self-healing channel recovery
  - VARIANT column for flexible JSON payloads
  - Offset tracking for exactly-once semantics
```

## Prerequisites

- Conda env `e2edemo` (created by bootstrap.sh)
- RSA key pair assigned to your Snowflake user (key-pair auth required by SDK)

## Quick Start

```bash
# 1. Generate RSA keys + profile.json
./scripts/setup_keys.sh

# 2. Assign public key to your Snowflake user (run in Snowsight):
#    ALTER USER <SERVICE_USER> SET RSA_PUBLIC_KEY='<key from step 1>';

# 3. Run the full demo (setup + stream 60s + verify)
./scripts/run_demo.sh
```

## Files

| File | Purpose |
|------|---------|
| `sql/01_setup.sql` | Creates HCP_EVENTS_RT table + named pipe |
| `sql/02_monitoring.sql` | Health check, throughput, latency queries |
| `src/streaming_service.py` | Reusable SDK wrapper (multi-channel, self-healing) |
| `src/stream_producer.py` | Event generator + streaming producer |
| `scripts/setup_keys.sh` | Generates RSA key pair + profile.json template |
| `scripts/run_demo.sh` | End-to-end: setup SQL, stream events, verify |
| `requirements.txt` | Python dependencies (snowpipe-streaming, cryptography) |

## Event Schema

| Column | Type | Description |
|--------|------|-------------|
| EVENT_ID | VARCHAR(36) | Unique event UUID |
| HCP_ID | VARCHAR(36) | Healthcare provider ID |
| REP_ID | VARCHAR(36) | Sales rep ID |
| EVENT_TYPE | VARCHAR(50) | DETAIL_VISIT, DIGITAL_ENGAGE, SAMPLE_DROP, CONFERENCE, etc. |
| CHANNEL | VARCHAR(30) | IN_PERSON, VIDEO, EMAIL, PHONE, CHAT |
| DRUG_ID | VARCHAR(36) | Drug discussed |
| TERRITORY_ID | INTEGER | Territory assignment |
| DURATION_SECONDS | INTEGER | Event duration |
| SENTIMENT_SCORE | FLOAT | -1.0 to 1.0 |
| EVENT_PAYLOAD | VARIANT | Full JSON payload (specialty, notes, geo, is_kol) |
| EVENT_TIMESTAMP | TIMESTAMP_NTZ | When event occurred |
| INGESTED_AT | TIMESTAMP_NTZ | When Snowflake received the row |

## Configuration

The producer accepts CLI arguments:

```
--profile       Path to profile.json (default: keys/profile.json)
--database      Target database (default: DEMO)
--schema        Target schema (default: HEALTHCARE_DEMO)
--table         Target table (default: HCP_EVENTS_RT)
--rate          Events per second (default: 50)
--duration      Seconds to run (default: 60)
--partitions    Number of channels (default: 4)
```

## Key Concepts Demonstrated

1. **High-Performance Architecture** — Uses PIPE objects (not direct table channels)
2. **Multi-channel partitioning** — Hash-based routing by HCP_ID for parallelism
3. **VARIANT ingestion** — Native dict/list stored as OBJECT/ARRAY (not JSON strings)
4. **Self-healing channels** — Auto-recovery on token expiry or channel invalidation
5. **Named pipe** — Explicit `HCP_EVENTS_RT_STREAMING` for visibility
6. **Offset tracking** — For exactly-once delivery guarantees

## Authentication

Snowpipe Streaming requires **key-pair authentication** (PAT is not supported). The `setup_keys.sh` script generates a 2048-bit RSA key pair and creates a `profile.json` template.

```json
{
    "account": "<ACCOUNT_LOCATOR>",
    "user": "<SERVICE_USER>",
    "private_key_path": "keys/rsa_key.p8",
    "role": "SYSADMIN"
}
```

## Monitoring

After streaming, run the monitoring queries:

```bash
snow sql -f sql/02_monitoring.sql -c my_conn
```

Key queries:
- Total events + time span
- Events per minute throughput
- Breakdown by event type and channel
- VARIANT payload verification (`TYPEOF` check)
- Ingestion latency (EVENT_TIMESTAMP vs INGESTED_AT)
- Channel/pipe health
