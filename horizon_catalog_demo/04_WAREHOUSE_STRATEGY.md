# Warehouse Sizing & Usage Strategy

## Snowflake Recommendations for Ingestion, Processing, and Consumption Workloads

---

## 1. Workload Isolation Strategy

Snowflake recommends **dedicated warehouses per workload type** rather than a single shared warehouse.

| Principle | Rationale |
|-----------|-----------|
| Separate warehouses per workload class | Avoid resource contention between ETL and BI |
| Independent scaling | Size each warehouse for its specific pattern |
| Cost attribution | Clear credit consumption per pipeline stage |
| SLA enforcement | Different auto-suspend/resume policies per workload |

### Recommended Warehouse Layout

```
INGEST_WH       → Bronze layer loads (COPY INTO, Snowpipe, streams)
TRANSFORM_WH    → Silver/Gold processing (DT refresh, MERGE, joins)
ANALYTICS_WH    → BI dashboards, ad-hoc queries, Cortex Agent
```

---

## 2. Sizing Recommendations by Workload

### Ingestion (Bronze Layer)

| Attribute | Recommendation |
|-----------|---------------|
| Workload pattern | Batch COPY INTO, Snowpipe, short burst loads |
| Warehouse type | Gen2 Standard |
| Size | SMALL to MEDIUM |
| Auto-suspend | 60 seconds (frequent short loads) |
| Multi-cluster | Not needed (low concurrency, sequential loads) |
| Key metric | Rows/second throughput |

**Why Gen2 for ingestion:** Gen2's DML improvements (DELETE, UPDATE, MERGE) directly benefit change-data-capture and incremental load patterns. The faster hardware reduces COPY INTO wall-clock time.

### Processing (Silver and Gold Layers)

| Attribute | Recommendation |
|-----------|---------------|
| Workload pattern | Dynamic Table refresh, MERGE, complex multi-table joins |
| Warehouse type | Gen2 Standard OR Adaptive |
| Size (Gen2) | MEDIUM to XLARGE |
| Size (Adaptive) | MAX_QUERY_PERFORMANCE_LEVEL = MEDIUM to LARGE |
| Auto-suspend | 300 seconds (longer queries, avoid thrashing) |
| Multi-cluster | 1-2 clusters (DT refresh is sequential per table) |
| Key metric | Query execution time, spill-to-disk ratio |

**Why this matters:** Silver-to-Gold transformations involve large aggregations and multi-way joins. Under-sizing causes remote disk spilling which dramatically increases execution time.

### Consumption (BI / Dashboards / AI)

| Attribute | Recommendation |
|-----------|---------------|
| Workload pattern | High concurrency, variable complexity, interactive response times |
| Warehouse type | Adaptive (preferred) or Gen2 Multi-cluster |
| Size (Gen2) | MEDIUM to LARGE with multi-cluster AUTO |
| Adaptive params | MAX_QUERY_PERFORMANCE_LEVEL = XLARGE, QUERY_THROUGHPUT_MULTIPLIER = 4 |
| Auto-suspend | 60 seconds (quick resume for interactive use) |
| Key metric | Queue time, P95 latency |

**Why Adaptive for consumption:** Dashboard workloads have unpredictable concurrency and variable query complexity. Adaptive Compute allocates the right resources per query without manual sizing decisions.

---

## 3. Gen2 vs Adaptive Comparison

| Dimension | Gen2 Standard | Adaptive |
|-----------|--------------|----------|
| **Compute model** | Fixed size (XS-4XL), customer-managed | System-determined per query |
| **Sizing** | Customer chooses | Snowflake selects resources up to MAX_QUERY_PERFORMANCE_LEVEL |
| **Concurrency** | Multi-cluster with explicit min/max | QUERY_THROUGHPUT_MULTIPLIER controls capacity |
| **DML performance** | Significant improvements over Gen1 | Includes Gen2 improvements + auto-optimization |
| **Idle cost** | Credits burn until auto-suspend | No idle charges (per-query billing) |
| **Best for** | Predictable workloads with known resource needs | Variable/mixed workloads, BI, multi-tenant |
| **Migration** | ALTER WAREHOUSE SET GENERATION = '2' | ALTER WAREHOUSE SET WAREHOUSE_TYPE = 'ADAPTIVE' |
| **Rollback** | ALTER SET GENERATION = '1' | ALTER SET WAREHOUSE_TYPE = STANDARD |
| **Max size** | X4LARGE (172.8 cr/hr on AWS) | X4LARGE performance level |
| **QAS** | Separate charge if enabled | Included in compute credits |

### When to Use Each

| Scenario | Recommendation |
|----------|---------------|
| Batch ETL with predictable data volumes | Gen2 (right-size once, runs efficiently) |
| DT refresh on schedule | Gen2 (consistent resource needs) |
| BI dashboards with 10-100 concurrent users | Adaptive (auto-scales to demand) |
| Cortex Agent / Analyst queries | Adaptive (unpredictable query complexity) |
| Snowpipe continuous ingestion | Gen2 SMALL (always-on, known throughput) |
| Ad-hoc data science exploration | Adaptive (varies from simple to complex) |

---

## 4. Is Adaptive Warehouse Recommended?

**Yes, for consumption workloads.** Adaptive is the recommended choice for:

- BI dashboard serving (Sigma, Tableau, Power BI connected via Snowflake)
- Cortex Agent and Cortex Analyst workloads
- Multi-tenant query patterns
- Any workload where concurrency and complexity vary unpredictably

**Not yet recommended for:**

- Snowpark-optimized workloads (not supported)
- Workloads requiring X5LARGE/X6LARGE equivalent (Adaptive caps at X4LARGE level)
- Accounts in regions where Adaptive is not yet available

### Adaptive Parameters for Common Patterns

| Workload | MAX_QUERY_PERFORMANCE_LEVEL | QUERY_THROUGHPUT_MULTIPLIER |
|----------|----------------------------|----------------------------|
| Latency-sensitive dashboards | XLARGE or higher | 4-8 |
| Mixed general-purpose | MEDIUM-LARGE | 2-4 |
| Low-complexity batch | SMALL-MEDIUM | 2 |

---

## 5. Credit Rates and Cost Considerations

### Gen1 vs Gen2 Credit Rates (per hour)

| Size | Gen1 (all clouds) | Gen2 AWS | Gen2 Azure | Gen2 GCP |
|------|-------------------|----------|------------|----------|
| XS | 1 | 1.35 | 1.25 | 1.35 |
| S | 2 | 2.7 | 2.5 | 2.7 |
| M | 4 | 5.4 | 5 | 5.4 |
| L | 8 | 10.8 | 10 | 10.8 |
| XL | 16 | 21.6 | 20 | 21.6 |
| 2XL | 32 | 43.2 | 40 | 43.2 |
| 3XL | 64 | 86.4 | 80 | 86.4 |
| 4XL | 128 | 172.8 | 160 | 172.8 |

Source: [Snowflake Credit Consumption Table](https://www.snowflake.com/legal-files/CreditConsumptionTable.pdf)

### Key Cost Insight

Gen2 costs ~35% more per hour (on AWS/GCP) than Gen1, but queries complete faster due to hardware and software improvements. **Net effect: similar cost for the same work, delivered faster.** Gen2 is a performance feature, not a cost-saving feature.

### Adaptive Billing Model

- **Per-query credits:** Each query is attributed credits based on resources consumed
- **No idle charges:** Unlike standard warehouses, no credits burn while waiting for queries
- **QAS included:** Query Acceleration Service is bundled into Adaptive credits
- **Cost monitoring:** Use `WAREHOUSE_METERING_HISTORY` for warehouse-level and `QUERY_METERING_HISTORY` for per-query attribution

### Auto-Suspend Strategy

| Workload | Auto-Suspend | Rationale |
|----------|-------------|-----------|
| Ingestion (batch) | 60s | Loads are bursty; quick suspend between batches |
| Ingestion (Snowpipe) | 0 (never) | Continuous micro-batches; suspend/resume thrashing wastes credits |
| Processing (DT) | 300s | DTs refresh on schedule; keep warm between refresh cycles |
| Consumption (BI) | 60s | Fast resume with Gen2 warmed cache; minimize idle cost |
| Consumption (Adaptive) | N/A | No idle cost; system manages lifecycle |

---

## 6. Performance Observations

### Gen2 DML Improvements

Snowflake's engineering blog documents significant DML performance gains on Gen2:
- DELETE, UPDATE, MERGE operations show substantial speed improvements
- Table scan operations benefit from faster hardware
- Source: https://www.snowflake.com/en/engineering-blog/dml-performance-snowflake-gen2-warehouses/

### Gen2 Resume Behavior

Gen2 uses a **warmed cache of servers** for resume:
- The system maintains a pool of pre-warmed servers based on usage patterns
- Resume time may differ from Gen1 (not necessarily faster or slower - depends on pattern)
- For latency-critical workloads, keep auto-suspend longer to avoid resume overhead

### Adaptive Performance Characteristics

- System selects optimal resources per query (no over/under provisioning)
- Eliminates queue-based latency spikes from fixed-size warehouses
- Throughput scales with QUERY_THROUGHPUT_MULTIPLIER (increase if seeing queuing)
- Performance level caps prevent runaway resource consumption

---

## 7. Application to This Demo

### Current Demo Warehouse Usage

The demo uses a single `MY_WH` (Medium, Gen2) warehouse for all workloads. In production, the recommended strategy would be:

| Pipeline Stage | Warehouse | Type | Size | Why |
|---------------|-----------|------|------|-----|
| Bronze ingestion (COPY INTO) | INGEST_WH | Gen2 | SMALL | Short bursts, DML-heavy |
| Silver staging (views) | N/A | N/A | N/A | Views don't consume compute at definition time |
| Gold DT refresh (PATIENT_ANALYTICS) | TRANSFORM_WH | Gen2 | MEDIUM | Predictable aggregation workload |
| BI queries (REVENUE_DASHBOARD) | ANALYTICS_WH | Adaptive | XLARGE level | Variable concurrency, interactive |
| Cortex Agent queries | ANALYTICS_WH | Adaptive | XLARGE level | Unpredictable complexity |

### Pipeline Execution Log Integration

The `PIPELINE_EXECUTION_LOG` table already captures `warehouse_name` and `warehouse_size` per run, enabling:
- Cost attribution per pipeline stage
- Performance correlation with warehouse size
- Historical analysis of warehouse utilization patterns
- AI-queryable via the metadata semantic model

### Sample Cost Attribution Query

```sql
SELECT
  layer_to AS target_layer,
  warehouse_name,
  warehouse_size,
  COUNT(*) AS runs,
  AVG(duration_seconds) AS avg_duration_sec,
  SUM(rows_written) AS total_rows
FROM PIPELINE_EXECUTION_LOG
GROUP BY layer_to, warehouse_name, warehouse_size
ORDER BY target_layer;
```

---

## 8. Recommendations Summary

| Decision | Recommendation |
|----------|---------------|
| New ingestion warehouse | Gen2 Standard, SMALL-MEDIUM, auto-suspend 60s |
| New transformation warehouse | Gen2 Standard, MEDIUM-XLARGE based on data volume |
| New BI/analytics warehouse | Adaptive, MQPL=XLARGE, QTM=4 |
| Existing Gen1 warehouse | Convert to Gen2 (zero-downtime ALTER) |
| High-concurrency BI on Gen2 | Migrate to Adaptive |
| Snowpark-optimized needs | Stay Gen1 (Gen2/Adaptive not supported) |
| Cost monitoring | Use PIPELINE_EXECUTION_LOG + WAREHOUSE_METERING_HISTORY |

### Migration Path

```
Gen1 Standard → Gen2 Standard (ALTER SET GENERATION = '2')
                     ↓
Gen2 Standard → Adaptive (ALTER SET WAREHOUSE_TYPE = 'ADAPTIVE')
```

Both conversions are live (no downtime) and reversible.

---

## 9. References

| Topic | URL |
|-------|-----|
| Warehouse overview | https://docs.snowflake.com/en/user-guide/warehouses-overview |
| Warehouse sizing considerations | https://docs.snowflake.com/en/user-guide/warehouses-considerations |
| Gen2 warehouses | https://docs.snowflake.com/en/user-guide/warehouses-gen2 |
| Gen2 region availability | https://docs.snowflake.com/en/user-guide/warehouses-gen2#region-availability |
| Gen2 DML performance blog | https://www.snowflake.com/en/engineering-blog/dml-performance-snowflake-gen2-warehouses/ |
| Adaptive warehouses | https://docs.snowflake.com/en/user-guide/warehouses-adaptive |
| Adaptive warehouse billing | https://docs.snowflake.com/en/user-guide/warehouses-adaptive#billing |
| Multi-cluster warehouses | https://docs.snowflake.com/en/user-guide/warehouses-multicluster |
| Resource monitors | https://docs.snowflake.com/en/user-guide/resource-monitors |
| Credit consumption table (PDF) | https://www.snowflake.com/legal-files/CreditConsumptionTable.pdf |
| WAREHOUSE_METERING_HISTORY view | https://docs.snowflake.com/en/sql-reference/account-usage/warehouse_metering_history |
| WAREHOUSE_LOAD_HISTORY view | https://docs.snowflake.com/en/sql-reference/account-usage/warehouse_load_history |
| CREATE WAREHOUSE syntax | https://docs.snowflake.com/en/sql-reference/sql/create-warehouse |
| ALTER WAREHOUSE syntax | https://docs.snowflake.com/en/sql-reference/sql/alter-warehouse |
| Auto-suspend and auto-resume | https://docs.snowflake.com/en/user-guide/warehouses-overview#auto-suspension-and-auto-resumption |
| Query Acceleration Service | https://docs.snowflake.com/en/user-guide/query-acceleration-service |
| Snowpark-optimized warehouses | https://docs.snowflake.com/en/user-guide/warehouses-snowpark-optimized |
