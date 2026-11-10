# Blue/Green Zero-Copy Clone Swap Demo

## Overview

This demo implements the **blue/green deployment pattern** for data pipelines in Snowflake. The pattern ensures that production consumers (analysts, dashboards, downstream systems) experience **zero downtime** and **zero data inconsistency** during ETL refreshes — even when replacing entire tables in a star schema.

Traditional ETL approaches (TRUNCATE + INSERT, or DROP + RECREATE) expose a window where queries return empty or partial results. The blue/green swap pattern eliminates this by using Snowflake's metadata-only operations to atomically switch what "production" points to.

## Why This Pattern Matters

| Problem | How Swap Solves It |
|---------|--------------------|
| **Downtime during refresh** | SWAP WITH is atomic — consumers never see an empty or half-loaded table |
| **Data inconsistency across tables** | All tables swap in sequence (each swap is instant), maintaining referential integrity |
| **Storage cost of full copies** | Zero-copy clone shares underlying micro-partitions — no duplicate storage |
| **Grant management after table recreation** | SWAP preserves the target table's identity — grants, policies, and references stay intact |
| **Rollback capability** | Before dropping staging leftovers, the old PROD data exists in STAGING for instant rollback |

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          SWAP_DEMO Database                              │
├────────────────────┬───────────────────────┬────────────────────────────┤
│  STAR_SCHEMA       │  STAGING              │  PROD                      │
│  (ETL source)      │  (clone landing zone) │  (analyst-facing)          │
│                    │                       │                            │
│  dim_customer      │  dim_customer [clone] │  dim_customer ◄── Analysts │
│  dim_product       │  dim_product  [clone] │  dim_product  ◄── query    │
│  fact_orders       │  fact_orders  [clone] │  fact_orders  ◄── here     │
└────────────────────┴───────────────────────┴────────────────────────────┘

Refresh Flow:
─────────────
Step 1: CLONE source → staging     (metadata-only, ~1 second regardless of data size)
Step 2: SWAP staging ↔ prod        (atomic pointer exchange, ~milliseconds)
Step 3: DROP staging leftovers      (old prod data removed)
```

## How the Swap Works (Under the Hood)

Snowflake tables are metadata pointers to micro-partitions (immutable columnar files). The key operations:

1. **CLONE** (`CREATE TABLE ... CLONE ...`)
   - Creates a new metadata entry pointing to the same micro-partitions
   - Cost: O(metadata) — no data copied regardless of table size (1 KB or 1 TB)
   - The clone is independent: writes to either table create new micro-partitions

2. **SWAP WITH** (`ALTER TABLE A SWAP WITH B`)
   - Exchanges the metadata pointers between two tables
   - Table A now points to B's micro-partitions and vice versa
   - Grants, row access policies, masking policies stay with the table name (not the data)
   - Cost: O(1) — a single atomic metadata operation

3. **Result**: PROD table name keeps its identity (grants, references) but now points to fresh data.

## Context: When to Use This Pattern

**Use blue/green swap when:**
- Full table refreshes (daily/hourly dimension + fact rebuilds)
- Multi-table consistency is required (star schema, data mart)
- Downstream consumers cannot tolerate even brief downtime
- You need instant rollback capability
- Tables are large and TRUNCATE + INSERT would be slow

**Use incremental patterns instead when:**
- Only a small % of rows change (prefer MERGE/streams)
- Real-time/near-real-time latency is needed (prefer streams + tasks)
- Schema evolution happens frequently (swap requires identical schemas)

## Files

| File | Purpose | Run As |
|------|---------|--------|
| `setup.sql` | Creates database, schemas, star schema tables, sample data, RBAC (reference) | SYSADMIN |
| `blue_green_swap_demo.sql` | Creates stored procedure, runs validation (insert + swap + verify) | SYSADMIN |
| `cleanup.sql` | Drops SWAP_DEMO database and all objects | SYSADMIN |
| `run_demo.sh` | Runs setup.sql + blue_green_swap_demo.sql in sequence | Shell |
| `cleanup.sh` | Runs cleanup.sql | Shell |

## Quick Start

```bash
# Deploy and run the full demo
./run_demo.sh

# Teardown when done
./cleanup.sh
```

Or run SQL files individually:

```bash
snow sql -f setup.sql -c my_conn
snow sql -f blue_green_swap_demo.sql -c my_conn
snow sql -f cleanup.sql -c my_conn
```

## Schema Layout

| Schema | Purpose | Access |
|--------|---------|--------|
| `SWAP_DEMO.STAR_SCHEMA` | ETL-curated source tables | ETL_ROLE (SYSADMIN) |
| `SWAP_DEMO.STAGING` | Temporary clone landing zone | ETL_ROLE (SYSADMIN) |
| `SWAP_DEMO.PROD` | Analyst-facing production | ANALYST_ROLE (SELECT) |

## Star Schema

- **dim_customer** — 75 rows (customer_id, name, segment, region, signup_date)
- **dim_product** — 50 rows (product_id, product_name, category, unit_price, launch_date)
- **fact_orders** — 100 rows (order_id, customer_id, product_id, order_date, quantity, total_amount, channel)

## Validation Proof

The demo script demonstrates the full cycle:

1. **Query PROD** — sees 75 customers, 50 products, 100 orders
2. **Insert new rows into STAR_SCHEMA** — 10 customers, 5 products, 25 orders
3. **CALL REFRESH_STAR_SCHEMA()** — clone + swap executes in under 1 second
4. **Query PROD again** — now sees 85 customers, 55 products, 125 orders
5. **Grants verified** — SELECT still works, no re-grant required

## Cleanup

```bash
./cleanup.sh
```

Or manually:

```sql
USE ROLE SYSADMIN;
DROP DATABASE IF EXISTS SWAP_DEMO;
```
