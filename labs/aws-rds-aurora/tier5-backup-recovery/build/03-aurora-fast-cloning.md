# BUILD 03 - Aurora Fast Database Cloning
## Tier 5 - Backup, Recovery, and Lifecycle

**Time:** 35 minutes
**Goal:** Create an Aurora PostgreSQL clone using fast cloning (copy-on-write), understand the cost and behavior model, and compare clone vs restore vs snapshot restore.

**Important:** Fast cloning requires Aurora PostgreSQL, not standard RDS PostgreSQL. If you only have an RDS PostgreSQL instance, follow the console steps using the Aurora cluster you created in an earlier tier, or create a new Aurora cluster for this lab.

**Prerequisites:**
- An Aurora PostgreSQL cluster (not standard RDS PostgreSQL)
- AWS CLI configured with rds permissions
- The cluster must be in `available` state

---

## Step 1 - Set Your Variables

```bash
export SOURCE_CLUSTER="suta-t5-aurora-hfa"
export CLONE_CLUSTER="suta-t5-clone-hfa"
export CLONE_INSTANCE="suta-t5-clone-instance-hfa"
export AWS_REGION="us-east-1"
export DB_SUBNET_GROUP="your-subnet-group-name"
export VPC_SG_ID="sg-xxxxxxxxxxxxxxxxx"
```

Replace subnet group and security group with values from your environment.

---

## Step 2 - Verify Your Source Cluster Exists

Before cloning, confirm the cluster is available:

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier $SOURCE_CLUSTER \
  --region $AWS_REGION \
  --query 'DBClusters[0].{Status:Status,Engine:Engine,EngineVersion:EngineVersion,ClusterArn:DBClusterArn}' \
  --output table
```

Expected output (yours will differ):

```
-----------------------------------------------------------------------------------------------------------
|                                         DescribeDBClusters                                              |
+----------+------------------+------------------+----------------------------------------------------------+
|  Engine  |  EngineVersion   |  Status          |  ClusterArn                                            |
+----------+------------------+------------------+----------------------------------------------------------+
|  aurora-postgresql | 16.6  |  available       |  arn:aws:rds:us-east-1:123456789012:cluster:suta-t5-... |
+----------+------------------+------------------+----------------------------------------------------------+
```

The engine must show `aurora-postgresql`. If you see `postgres`, this is a standard RDS instance and fast cloning is not available.

---

## Step 3 - Add Test Data to the Source Cluster

Get the cluster writer endpoint:

```bash
export AURORA_HOST=$(aws rds describe-db-clusters \
  --db-cluster-identifier $SOURCE_CLUSTER \
  --region $AWS_REGION \
  --query 'DBClusters[0].Endpoint' \
  --output text)

echo $AURORA_HOST
```

Connect and create test data:

```bash
psql -h $AURORA_HOST -U postgres -d postgres
```

Inside psql:

```sql
CREATE TABLE products (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    price NUMERIC(10,2),
    category TEXT
);

INSERT INTO products (name, price, category)
SELECT
    'Product ' || i,
    (random() * 1000)::NUMERIC(10,2),
    (ARRAY['Electronics','Clothing','Food','Books'])[floor(random()*4+1)]
FROM generate_series(1, 10000) AS s(i);

SELECT COUNT(*) FROM products;
SELECT category, COUNT(*), AVG(price)::NUMERIC(10,2)
FROM products
GROUP BY category
ORDER BY category;
```

Expected output (yours will differ):

```
 count
-------
 10000

   category   | count |  avg
--------------+-------+--------
 Books        |  2543 | 498.72
 Clothing     |  2489 | 501.14
 Electronics  |  2471 | 499.03
 Food         |  2497 | 500.11
```

Exit:

```sql
\q
```

---

## Step 4 - Create the Fast Clone

Note the time before starting. You will see how fast this is compared to a restore.

```bash
date
```

### Console

1. Open **RDS > Databases**.
2. Click your Aurora cluster name.
3. Click **Actions > Create clone**.
4. Under **DB cluster identifier**, enter: `suta-t5-clone-hfa`.
5. Set **DB instance class** to `db.t3.medium` (same as source or smaller).
6. Set **VPC** and **Subnet group** to match your source.
7. Set **VPC security group** to match your source.
8. Click **Create clone**.

### CLI

Create the cluster clone:

```bash
aws rds restore-db-cluster-to-point-in-time \
  --db-cluster-identifier $CLONE_CLUSTER \
  --source-db-cluster-identifier $SOURCE_CLUSTER \
  --restore-type copy-on-write \
  --use-latest-restorable-time \
  --db-subnet-group-name $DB_SUBNET_GROUP \
  --vpc-security-group-ids $VPC_SG_ID \
  --region $AWS_REGION
```

`--restore-type copy-on-write` is the flag that tells Aurora to use fast cloning instead of a full data copy.
`--use-latest-restorable-time` clones from right now (the most recent state).

Expected output (yours will differ):

```json
{
    "DBCluster": {
        "DBClusterIdentifier": "suta-t5-clone-hfa",
        "Status": "creating",
        "Engine": "aurora-postgresql"
    }
}
```

Now add a DB instance to the clone cluster (a cluster without instances cannot be connected to):

```bash
aws rds create-db-instance \
  --db-instance-identifier $CLONE_INSTANCE \
  --db-cluster-identifier $CLONE_CLUSTER \
  --db-instance-class db.t3.medium \
  --engine aurora-postgresql \
  --region $AWS_REGION
```

`--db-cluster-identifier` associates this instance with the clone cluster.
`--engine aurora-postgresql` must match the cluster engine exactly.

Wait for the clone cluster to become available:

```bash
aws rds wait db-cluster-available \
  --db-cluster-identifier $CLONE_CLUSTER \
  --region $AWS_REGION
```

Then wait for the instance:

```bash
aws rds wait db-instance-available \
  --db-instance-identifier $CLONE_INSTANCE \
  --region $AWS_REGION
```

Check the time when done:

```bash
date
```

> **Concept:** Fast cloning for a 10,000-row database typically completes in under 5 minutes, mostly due to instance startup time. The actual data clone portion takes seconds regardless of database size, because no data is physically copied - both clusters point to the same storage pages.

---

## Step 5 - Connect to the Clone and Verify Data

Get the clone writer endpoint:

```bash
export CLONE_HOST=$(aws rds describe-db-clusters \
  --db-cluster-identifier $CLONE_CLUSTER \
  --region $AWS_REGION \
  --query 'DBClusters[0].Endpoint' \
  --output text)

echo $CLONE_HOST
```

Connect to the clone:

```bash
psql -h $CLONE_HOST -U postgres -d postgres
```

Verify the products table is there with all 10,000 rows:

```sql
SELECT COUNT(*) FROM products;

SELECT category, COUNT(*), AVG(price)::NUMERIC(10,2)
FROM products
GROUP BY category
ORDER BY category;
```

Expected output (should match source exactly):

```
 count
-------
 10000

   category   | count |  avg
--------------+-------+--------
 Books        |  2543 | 498.72
 Clothing     |  2489 | 501.14
 Electronics  |  2471 | 499.03
 Food         |  2497 | 500.11
```

The data matches the source. The clone is a complete copy.

---

## Step 6 - Demonstrate Copy-on-Write Behavior

This step shows what happens when you modify the clone. Changes stay isolated to the clone - the source is unaffected.

Still connected to the clone, run a destructive schema change (safe because it is a clone):

```sql
-- Simulate a schema migration test
ALTER TABLE products ADD COLUMN is_featured BOOLEAN DEFAULT false;

UPDATE products SET is_featured = true WHERE price > 900;

SELECT is_featured, COUNT(*) FROM products GROUP BY is_featured;
```

Expected output (yours will differ):

```
 is_featured | count
-------------+-------
 f           |  8987
 t           |  1013
```

Exit the clone:

```sql
\q
```

Now connect to the SOURCE cluster and verify it was NOT affected:

```bash
psql -h $AURORA_HOST -U postgres -d postgres
```

```sql
-- The source should NOT have the is_featured column
\d products
```

Expected output (source is unchanged):

```
             Table "public.products"
  Column  |     Type      | Nullable |      Default
----------+---------------+----------+-------------------
 id       | integer       | not null | nextval(...)
 name     | text          | not null |
 price    | numeric(10,2) |          |
 category | text          |          |
```

The `is_featured` column does not exist on the source. The clone is completely isolated.

Exit:

```sql
\q
```

> **Concept:** Copy-on-write means: when the clone modifies a storage page, Aurora creates a new physical copy of just that page for the clone. The original page is still shared with the source cluster. Only modified pages become separate. This is why the initial clone is near-instant and the ongoing storage cost is proportional to how much data changes, not the full database size.

---

## Step 7 - Compare Clone vs Restore vs Snapshot Restore

This comparison uses real numbers from typical AWS environments.

```
METHOD COMPARISON FOR A 500 GB AURORA POSTGRESQL CLUSTER
==========================================================

                FAST CLONE        RESTORE FROM     SNAPSHOT RESTORE
                (Aurora only)     SNAPSHOT         (standard restore)

Time to ready   2-5 minutes       45-90 minutes    45-90 minutes
               (instance          (full data copy  (full data copy
                startup only)      + startup)       + startup)

Initial storage Near zero          Full 500 GB      Full 500 GB
cost            (shared pages)     copied           copied

Ongoing cost    Only changed       Full 500 GB      Full 500 GB
                pages stored       storage          storage
                separately

Cross-region?   No (same region    Yes              Yes
                and account only)

Cross-account?  No                 Yes (shared      Yes
                                   snapshot needed)

Best for        Dev/test           DR recovery      Archive/audit
                Schema migrations  Specific point   Long-term copies
                Data exploration   in time

Modifies        No                 No               No
original?
```

---

## Step 8 - Real-World Use Case: Testing Schema Changes

This is the primary reason to use fast cloning in production environments.

The workflow:

```
1. Clone production
   [Prod Cluster] ---fast clone---> [Clone Cluster]  (seconds to minutes)

2. Run schema migration on clone
   [Clone Cluster]: ALTER TABLE orders ADD COLUMN tax_rate NUMERIC(5,4);
   [Clone Cluster]: UPDATE orders SET tax_rate = 0.0875 WHERE state = 'CA';
   [Clone Cluster]: CREATE INDEX idx_orders_tax_rate ON orders(tax_rate);

3. Measure impact
   - How long did the migration take?
   - Did table bloat increase significantly?
   - Did any queries slow down?
   - Are all application queries still working?

4. Validate results on clone
   [Clone Cluster]: Run full application test suite against clone

5. Apply to production with confidence
   [Prod Cluster]: Apply the same migration (you know what to expect)

6. Delete clone
   [Clone Cluster]: Deleted (stop paying for storage)
```

---

## Step 9 - Cleanup

Delete the clone instance first (must delete instances before cluster):

```bash
aws rds delete-db-instance \
  --db-instance-identifier $CLONE_INSTANCE \
  --skip-final-snapshot \
  --region $AWS_REGION
```

Wait for instance deletion:

```bash
aws rds wait db-instance-deleted \
  --db-instance-identifier $CLONE_INSTANCE \
  --region $AWS_REGION
```

Then delete the clone cluster:

```bash
aws rds delete-db-cluster \
  --db-cluster-identifier $CLONE_CLUSTER \
  --skip-final-snapshot \
  --region $AWS_REGION
```

Verify the clone cluster is gone:

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier $CLONE_CLUSTER \
  --region $AWS_REGION 2>&1 | head -3
```

Expected output:

```
An error occurred (DBClusterNotFoundFault) when calling the DescribeDBClusters operation:
DBCluster suta-t5-clone-hfa not found.
```

---

## Summary

You can now:
- Create an Aurora fast clone using copy-on-write storage
- Verify that the clone contains the exact same data as the source
- Modify the clone without affecting the source
- Explain when to use clone vs restore vs snapshot restore
- Apply this pattern for safe schema migration testing

**Next:** BUILD 04 - Engine Version Upgrades
