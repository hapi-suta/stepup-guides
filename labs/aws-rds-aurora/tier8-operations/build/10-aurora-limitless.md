# BUILD 10 - Aurora Limitless Database

**Time:** 50 minutes
**Goal:** Create an Aurora Limitless Database DB shard group, distribute tables across shards, run distributed queries, monitor shard utilization, and understand when horizontal sharding is the right scaling strategy.
**Prerequisites:** Aurora PostgreSQL cluster running version 16.4+ (Limitless requires 16.4 or later). AWS CLI v2. Familiarity with Aurora cluster architecture from Tier 1-4.

---

## What Is Aurora Limitless Database?

Aurora Limitless Database adds horizontal write scaling to Aurora PostgreSQL. Instead of scaling up to a bigger instance, you scale out by adding more compute nodes (shards) that share Aurora's distributed storage layer.

**The problem it solves:** A single Aurora writer instance has a ceiling - even on the largest instance class, there is a limit to the write throughput one PostgreSQL process can sustain. Limitless breaks that ceiling by distributing writes across multiple compute nodes.

**How it works:**
- You create a **DB shard group** attached to your Aurora cluster
- You designate tables as **sharded** (split across shards by a shard key) or **reference** (copied to all shards)
- Applications connect to a **Limitless endpoint** that routes queries to the correct shard(s)
- Reads and writes both scale horizontally

**When to use it:**
- Your write throughput has hit the ceiling of a single Aurora writer
- Your data model has a natural shard key (tenant_id, customer_id, region_id)
- You need to scale beyond what vertical scaling (bigger instance) can provide

**When NOT to use it:**
- Your workload is read-heavy (use read replicas instead)
- Your queries frequently join across different shard keys (cross-shard joins are expensive)
- Your total data fits comfortably on a single writer and you are not CPU/IOPS bound

---

## Step 1 - Verify Your Cluster Supports Limitless

Aurora Limitless requires:
- Aurora PostgreSQL 16.4 or later
- r-series instances (db.r6g.large or larger)
- The cluster must be in a supported region

Check your cluster:

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier [YOUR-CLUSTER-ID] \
  --query 'DBClusters[0].{Engine:Engine,Version:EngineVersion,Status:Status}' \
  --output table \
  --region [REGION]
```

Expected output (yours will differ):
```
---------------------------------------------------------
|                  DescribeDBClusters                   |
+----------+-------------------------------------------+
| Engine   | aurora-postgresql                          |
| Status   | available                                  |
| Version  | 16.6                                       |
+----------+-------------------------------------------+
```

If your version is below 16.4, upgrade first using a Blue/Green deployment (BUILD 05 in Tier 5).

---

## Step 2 - Create a DB Shard Group

A DB shard group is a set of compute nodes that handle your sharded workload. You specify the minimum and maximum capacity.

### Console

1. Go to **RDS > Databases**.
2. Click your Aurora cluster.
3. Click **Actions > Create shard group**.
4. Configure:
   - **Shard group identifier**: `my-shard-group`
   - **Maximum ACU capacity**: `128` (this is the upper limit across all shards)
   - **Minimum ACU capacity**: `24` (minimum is 24 ACU for Limitless)
5. Click **Create shard group**.

### CLI

```bash
aws rds create-db-shard-group \
  --db-shard-group-identifier my-shard-group \
  --db-cluster-identifier [YOUR-CLUSTER-ID] \
  --max-acu 128 \
  --min-acu 24 \
  --region [REGION]
```

`--max-acu 128`: The shard group can scale up to 128 Aurora Capacity Units total across all shards. Aurora adds/removes shards automatically within this range.
`--min-acu 24`: The minimum capacity. Limitless requires at least 24 ACU (roughly equivalent to 3 db.r6g.large instances).

Expected output (yours will differ):
```json
{
    "DBShardGroup": {
        "DBShardGroupIdentifier": "my-shard-group",
        "DBClusterIdentifier": "[YOUR-CLUSTER-ID]",
        "MaxACU": 128.0,
        "MinACU": 24.0,
        "Status": "creating",
        "Endpoint": "my-shard-group.limitless-xxxx.[REGION].rds.amazonaws.com"
    }
}
```

Note the **Endpoint** - this is the Limitless endpoint your application will connect to.

Wait for the shard group to become available (5-15 minutes):

```bash
aws rds describe-db-shard-groups \
  --db-shard-group-identifier my-shard-group \
  --region [REGION] \
  --query 'DBShardGroups[0].{Status:Status,Endpoint:Endpoint,MaxACU:MaxACU}' \
  --output table
```

Expected output (yours will differ):
```
-----------------------------------------------------------------------
|                      DescribeDBShardGroups                          |
+----------+----------------------------------------------------------+
| Endpoint | my-shard-group.limitless-xxxx.[REGION].rds.amazonaws.com |
| MaxACU   | 128.0                                                    |
| Status   | available                                                |
+----------+----------------------------------------------------------+
```

---

## Step 3 - Connect to the Limitless Endpoint

Connect using psql through the Limitless endpoint (not the regular cluster endpoint):

```bash
psql -h [LIMITLESS-ENDPOINT] -U postgres -d postgres
```

> **Important:** Always connect through the Limitless endpoint for sharded tables. The regular cluster endpoint does not route queries across shards. If you connect to the regular endpoint, sharded tables will appear empty or incomplete.

---

## Step 4 - Create Reference Tables

Reference tables are copied in full to every shard. Use them for small lookup tables that are frequently joined with sharded tables.

```sql
-- Set the table mode to reference
SET rds_aurora.limitless_create_table_mode = 'reference';

CREATE TABLE regions (
    region_id INT PRIMARY KEY,
    region_name TEXT NOT NULL,
    currency_code TEXT
);

INSERT INTO regions (region_id, region_name, currency_code) VALUES
    (1, 'North America', 'USD'),
    (2, 'Europe', 'EUR'),
    (3, 'Asia Pacific', 'JPY'),
    (4, 'Latin America', 'BRL');
```

`SET rds_aurora.limitless_create_table_mode = 'reference'` tells Aurora to replicate this table to all shards. Every shard has a complete copy, so joins between sharded tables and reference tables are always local (fast).

Verify the table is a reference table:

```sql
SELECT * FROM rds_aurora.limitless_table_info()
WHERE table_name = 'regions';
```

Expected output (yours will differ):
```
 table_schema | table_name | table_mode | shard_key
--------------+------------+------------+-----------
 public       | regions    | reference  |
(1 row)
```

---

## Step 5 - Create Sharded Tables

Sharded tables are split across shards by a shard key. Choose a shard key that:
1. Has high cardinality (many distinct values)
2. Is included in most queries as a filter
3. Distributes data evenly across shards

Good shard keys: `tenant_id`, `customer_id`, `account_id`
Bad shard keys: `status` (low cardinality), `created_at` (causes hot shards for recent data)

```sql
-- Set the table mode to sharded and specify the shard key
SET rds_aurora.limitless_create_table_mode = 'sharded';
SET rds_aurora.limitless_create_table_shard_key = '{"tenant_id"}';

CREATE TABLE orders (
    order_id BIGSERIAL,
    tenant_id INT NOT NULL,
    product_name TEXT,
    amount NUMERIC(12,2),
    status TEXT DEFAULT 'pending',
    created_at TIMESTAMPTZ DEFAULT now(),
    PRIMARY KEY (tenant_id, order_id)
);
```

`SET rds_aurora.limitless_create_table_shard_key = '{"tenant_id"}'` designates `tenant_id` as the column that determines which shard each row lives on.

> **Important:** The shard key must be part of the primary key. This is why the PRIMARY KEY is `(tenant_id, order_id)` and not just `(order_id)`. Aurora uses the shard key to route queries and enforce uniqueness within each shard.

Create another sharded table with the same shard key:

```sql
CREATE TABLE order_items (
    item_id BIGSERIAL,
    tenant_id INT NOT NULL,
    order_id BIGINT NOT NULL,
    product_sku TEXT,
    quantity INT,
    unit_price NUMERIC(12,2),
    PRIMARY KEY (tenant_id, item_id)
);
```

Tables with the same shard key are **co-located** - rows with the same `tenant_id` live on the same shard. This makes joins between co-located tables fast (no cross-shard communication needed).

Verify the sharded tables:

```sql
SELECT * FROM rds_aurora.limitless_table_info()
ORDER BY table_name;
```

Expected output (yours will differ):
```
 table_schema | table_name  | table_mode | shard_key
--------------+-------------+------------+------------
 public       | order_items | sharded    | {tenant_id}
 public       | orders      | sharded    | {tenant_id}
 public       | regions     | reference  |
(3 rows)
```

---

## Step 6 - Insert Data and Run Distributed Queries

Insert test data across multiple tenants:

```sql
INSERT INTO orders (tenant_id, product_name, amount, status)
SELECT
    (random() * 100 + 1)::INT,
    'Product-' || (random() * 50)::INT,
    (random() * 500 + 10)::NUMERIC(12,2),
    CASE (random() * 3)::INT
        WHEN 0 THEN 'pending'
        WHEN 1 THEN 'completed'
        ELSE 'shipped'
    END
FROM generate_series(1, 100000);
```

**Query with shard key (fast - single shard):**

```sql
EXPLAIN (ANALYZE)
SELECT count(*), status
FROM orders
WHERE tenant_id = 42
GROUP BY status;
```

When the query includes the shard key in the WHERE clause, Aurora routes it to a single shard. Look for `Single Shard` or `Direct Query` in the EXPLAIN output.

**Query without shard key (slower - all shards):**

```sql
EXPLAIN (ANALYZE)
SELECT count(*), status
FROM orders
GROUP BY status;
```

Without the shard key, Aurora must query ALL shards and merge the results. This is called a **scatter-gather** query. It works but is slower than a single-shard query.

**Co-located join (fast):**

```sql
SELECT o.tenant_id, o.order_id, o.amount, oi.product_sku, oi.quantity
FROM orders o
JOIN order_items oi ON o.tenant_id = oi.tenant_id AND o.order_id = oi.order_id
WHERE o.tenant_id = 42
LIMIT 10;
```

Because both tables use `tenant_id` as the shard key, rows for tenant 42 are on the same shard. The join happens locally.

**Join with reference table (fast):**

```sql
SELECT o.tenant_id, o.amount, r.region_name
FROM orders o
JOIN regions r ON o.tenant_id % 4 + 1 = r.region_id
WHERE o.tenant_id = 42;
```

Reference tables are on every shard, so joining with them is always local.

---

## Step 7 - Monitor Shard Utilization

### Console

1. Go to **RDS > Databases**.
2. Click your Aurora cluster.
3. Click the **Shard groups** tab.
4. You see each shard group with:
   - Current ACU utilization
   - Number of active shards
   - Connection count per shard

### CLI

Check shard group status:

```bash
aws rds describe-db-shard-groups \
  --db-shard-group-identifier my-shard-group \
  --region [REGION]
```

Monitor ACU utilization via CloudWatch:

```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name ServerlessDatabaseCapacity \
  --dimensions Name=DBShardGroupIdentifier,Value=my-shard-group \
  --start-time $(date -u -v-30M +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u --date='30 minutes ago' +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 60 \
  --statistics Average \
  --region [REGION]
```

---

## Step 8 - Modify Shard Group Capacity

If your workload grows, increase the maximum ACU:

```bash
aws rds modify-db-shard-group \
  --db-shard-group-identifier my-shard-group \
  --max-acu 256 \
  --region [REGION]
```

This is an online operation - no downtime. Aurora adds more shards automatically as needed within the new range.

To reduce capacity during off-peak:

```bash
aws rds modify-db-shard-group \
  --db-shard-group-identifier my-shard-group \
  --max-acu 64 \
  --region [REGION]
```

---

## Step 9 - Understand Limitless Limitations

Not everything works with sharded tables. Know these limits before designing your schema:

| Feature | Supported | Notes |
|---------|-----------|-------|
| Primary key | Yes | Must include the shard key |
| Foreign keys (same shard key) | Yes | Co-located tables only |
| Foreign keys (cross-shard) | No | Use application-level enforcement |
| Sequences (SERIAL/BIGSERIAL) | Yes | Globally unique across shards |
| Triggers | Limited | BEFORE triggers only, no cross-shard |
| Stored procedures | Yes | But cannot span multiple shards in a single transaction |
| Full-text search | Yes | Per-shard only |
| pgvector | Yes | Per-shard similarity search |
| Extensions | Most | Check AWS docs for specific extensions |
| Cross-shard transactions | Yes | 2-phase commit, higher latency |

**Key design rules:**
1. Always include the shard key in your WHERE clauses
2. Co-locate related tables by using the same shard key
3. Keep frequently-joined lookup tables as reference tables
4. Avoid cross-shard transactions when possible (they use 2PC and add latency)
5. Design your shard key for even distribution - avoid hotspots

---

## Step 10 - Cost Considerations

Aurora Limitless pricing:
- **ACU-hour pricing**: Same per-ACU rate as Serverless v2 (~$0.12/ACU-hour)
- **Minimum 24 ACU**: Even at idle, you pay for 24 ACU ($2.88/hour = ~$2,102/month)
- **Storage**: Standard Aurora storage pricing (same as non-Limitless)
- **Data transfer**: Cross-shard queries incur internal data transfer (minimal cost but adds up at scale)

**Break-even analysis:**

```
Limitless (24 ACU minimum):  24 * $0.12/hr * 730 hrs = $2,102/month
db.r6g.4xlarge (single):     $2.076/hr * 730 hrs     = $1,515/month
db.r6g.8xlarge (single):     $4.152/hr * 730 hrs     = $3,031/month
```

Limitless makes financial sense when a single db.r6g.4xlarge is not enough and you would otherwise need a db.r6g.8xlarge or larger. The scaling flexibility of adding ACU on demand can offset the higher minimum cost.

---

## Cleanup

Delete the shard group first, then clean up the tables:

```bash
aws rds delete-db-shard-group \
  --db-shard-group-identifier my-shard-group \
  --region [REGION]
```

Wait for deletion:

```bash
aws rds describe-db-shard-groups \
  --db-shard-group-identifier my-shard-group \
  --region [REGION] 2>&1 | head -3
```

Expected output when deleted:
```
An error occurred (DBShardGroupNotFoundFault) when calling the DescribeDBShardGroups operation.
```

If you created tables through the Limitless endpoint, drop them:

```sql
DROP TABLE IF EXISTS order_items;
DROP TABLE IF EXISTS orders;
DROP TABLE IF EXISTS regions;
```

---

## Summary

You have:
- Created a DB shard group and connected through the Limitless endpoint
- Created reference tables (replicated to all shards) and sharded tables (distributed by shard key)
- Run single-shard queries (fast) and scatter-gather queries (slower)
- Performed co-located joins between tables sharing the same shard key
- Monitored shard utilization via CloudWatch
- Understood the cost implications and design constraints

**Key things to remember:**
- Limitless is for write scaling - if reads are your bottleneck, use read replicas instead
- Choose your shard key carefully - it determines data distribution and query routing
- Co-locate related tables with the same shard key for fast joins
- Minimum 24 ACU means Limitless is not cheap - use it when you genuinely need horizontal write scaling
- Always connect through the Limitless endpoint, not the regular cluster endpoint
