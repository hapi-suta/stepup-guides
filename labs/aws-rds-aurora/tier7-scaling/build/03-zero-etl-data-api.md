# Tier 7 - Scaling, Integration, and Modern Patterns
## Guide 03: Zero-ETL Integration to Redshift and RDS Data API

**Objective:** Set up a Zero-ETL integration from Aurora PostgreSQL to Amazon Redshift for near-real-time analytics replication, then configure and use the RDS Data API for serverless query access.
**Time:** 45 minutes
**Prerequisites:** An Aurora PostgreSQL 16.6+ cluster. Basic understanding of Amazon Redshift. IAM permissions to create Redshift clusters and Zero-ETL integrations.
**Infrastructure:** You will create a Redshift Serverless namespace for the destination. Costs are minimal for short lab sessions.

---

## Part A: Zero-ETL Integration to Redshift

### A1. Understand the Architecture

Zero-ETL creates a managed pipeline: Aurora PostgreSQL (source) -> AWS internal replication mechanism -> Amazon Redshift (destination).

Changes made in Aurora appear in Redshift within seconds to minutes. You do not write extraction code, transformation code, or loading jobs. AWS manages the entire pipeline.

**Requirements checklist before you start:**
- Aurora PostgreSQL version 16.4 or later.
- Logical replication must be enabled on the Aurora cluster.
- Tables must have primary keys.
- The Aurora cluster and Redshift must be in the same AWS account and region.
- The Aurora cluster must have `aurora_enhanced_binlog` turned on (Aurora MySQL) or `wal_level=logical` (Aurora PostgreSQL).

For Aurora PostgreSQL, logical replication (`wal_level=logical`) is what enables Zero-ETL. Aurora PostgreSQL clusters with `rds.logical_replication=1` in the parameter group automatically have `wal_level=logical`.

### A2. Enable Logical Replication on the Source Aurora Cluster

Skip this step if you already enabled logical replication in Build 05.

**Console:**

1. Go to **RDS** > **Parameter groups** in the left sidebar.
2. Click **Create parameter group**.
3. Under **Parameter group family**, select `aurora-postgresql16`.
4. **Type**: DB Cluster Parameter Group.
5. **Group name**: `tier7-logical-replication`.
6. Click **Create**.
7. Click the new parameter group to open it.
8. Click **Edit parameters**.
9. Search for `rds.logical_replication`.
10. Set the value to `1`.
11. Click **Save changes**.
12. Go back to **Databases**, click your Aurora cluster, click **Modify**.
13. Under **Additional configuration** > **DB cluster parameter group**, select `tier7-logical-replication`.
14. Click **Continue** > **Apply immediately** > **Modify cluster**.
15. The cluster needs a reboot for the parameter to take effect. Go to **Actions** > **Reboot**.

**CLI:**

**Step 1.** Create the parameter group:

```bash
aws rds create-db-cluster-parameter-group \
  --db-cluster-parameter-group-name tier7-logical-replication \
  --db-parameter-group-family aurora-postgresql16 \
  --description "Enable logical replication for Zero-ETL" \
  --region [REGION]
```

**Step 2.** Set the parameter:

```bash
aws rds modify-db-cluster-parameter-group \
  --db-cluster-parameter-group-name tier7-logical-replication \
  --parameters "ParameterName=rds.logical_replication,ParameterValue=1,ApplyMethod=pending-reboot" \
  --region [REGION]
```

The `ApplyMethod=pending-reboot` flag means the change takes effect after the next reboot. Some parameters are `immediate` but `rds.logical_replication` requires a reboot.

**Step 3.** Apply the parameter group to your cluster:

```bash
aws rds modify-db-cluster \
  --db-cluster-identifier [YOUR-AURORA-CLUSTER] \
  --db-cluster-parameter-group-name tier7-logical-replication \
  --apply-immediately \
  --region [REGION]
```

**Step 4.** Reboot the writer instance:

```bash
aws rds reboot-db-instance \
  --db-instance-identifier [YOUR-AURORA-WRITER-INSTANCE] \
  --region [REGION]
```

**Step 5.** Verify logical replication is active by connecting to the database:

```sql
SHOW wal_level;
```

Expected output:
```
 wal_level
-----------
 logical
(1 row)
```

### A3. Prepare Source Tables

Zero-ETL only replicates tables with primary keys. Create a sample schema:

```sql
CREATE TABLE orders (
  order_id    SERIAL PRIMARY KEY,
  customer_id INTEGER NOT NULL,
  product_sku VARCHAR(50) NOT NULL,
  quantity    INTEGER NOT NULL,
  unit_price  NUMERIC(10,2) NOT NULL,
  status      VARCHAR(20) DEFAULT 'pending',
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE customers (
  customer_id SERIAL PRIMARY KEY,
  email       VARCHAR(255) UNIQUE NOT NULL,
  country     VARCHAR(50),
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

INSERT INTO customers (email, country)
SELECT
  'customer_' || gs || '@example.com',
  CASE WHEN gs % 3 = 0 THEN 'US' WHEN gs % 3 = 1 THEN 'UK' ELSE 'CA' END
FROM generate_series(1, 1000) gs;

INSERT INTO orders (customer_id, product_sku, quantity, unit_price, status)
SELECT
  (RANDOM() * 999 + 1)::INTEGER,
  'SKU-' || (RANDOM() * 100)::INTEGER,
  (RANDOM() * 10 + 1)::INTEGER,
  (RANDOM() * 500 + 10)::NUMERIC(10,2),
  CASE WHEN RANDOM() > 0.5 THEN 'completed' ELSE 'pending' END
FROM generate_series(1, 5000);
```

### A4. Create a Redshift Serverless Namespace

**Console:**

1. Go to **Amazon Redshift** in the AWS Console.
2. Click **Redshift Serverless** in the left sidebar.
3. Click **Create workgroup**.
4. Set **Workgroup name**: `tier7-analytics`.
5. Set **Base capacity (RPU)**: 8 (minimum for cost control).
6. Under **Namespace**, click **Create a new namespace**.
7. Set **Namespace name**: `tier7-analytics-ns`.
8. Set an **Admin username** and **password**.
9. Under **Permissions**, attach the `AmazonRedshiftAllCommandsFullAccess` managed policy or a custom policy with Redshift access.
10. Click **Save configuration**.

**CLI:**

**Step 1.** Create the namespace:

```bash
aws redshift-serverless create-namespace \
  --namespace-name tier7-analytics-ns \
  --admin-username redshiftadmin \
  --admin-user-password [YOUR-PASSWORD] \
  --region [REGION]
```

**Step 2.** Create the workgroup:

```bash
aws redshift-serverless create-workgroup \
  --workgroup-name tier7-analytics \
  --namespace-name tier7-analytics-ns \
  --base-capacity 8 \
  --subnet-ids [SUBNET-ID-1] [SUBNET-ID-2] \
  --security-group-ids [SECURITY-GROUP-ID] \
  --region [REGION]
```

Wait for the workgroup to become available (5-10 minutes).

### A5. Create the Zero-ETL Integration

**Console:**

1. Go to **RDS** > **Zero-ETL integrations** in the left sidebar.
2. Click **Create Zero-ETL integration**.
3. Under **Source**: select your Aurora PostgreSQL cluster.
4. Under **Target**: select your Redshift Serverless workgroup (`tier7-analytics`).
5. Set **Integration name**: `aurora-to-redshift-lab`.
6. Under **Data filter** (optional): leave blank to replicate all tables.
7. Click **Create Zero-ETL integration**.

**CLI:**

```bash
aws rds create-integration \
  --integration-name aurora-to-redshift-lab \
  --source-arn arn:aws:rds:[REGION]:[ACCOUNT-ID]:cluster:[YOUR-AURORA-CLUSTER] \
  --target-arn arn:aws:redshift-serverless:[REGION]:[ACCOUNT-ID]:workgroup/tier7-analytics \
  --region [REGION]
```

The integration takes 10-20 minutes to complete the initial seed (full load) of existing data.

### A6. Monitor Integration Status

```bash
aws rds describe-integrations \
  --region [REGION] \
  --query 'Integrations[?IntegrationName==`aurora-to-redshift-lab`].{Name:IntegrationName,Status:Status,Errors:Errors}' \
  --output table
```

Expected output when ready:
```
-----------------------------------------------
|           DescribeIntegrations              |
+----------------------------+---------+-------+
|  Name                      |  Status |  ...  |
+----------------------------+---------+-------+
|  aurora-to-redshift-lab    |  active |       |
+----------------------------+---------+-------+
```

### A7. Query Data in Redshift

Connect to your Redshift workgroup using the Redshift query editor in the console or psql.

AWS creates a database in Redshift that mirrors the Aurora database name. The schema is automatically created.

```sql
-- In Redshift query editor
SELECT status, COUNT(*), SUM(unit_price * quantity) AS revenue
FROM orders
GROUP BY status
ORDER BY revenue DESC;
```

Now insert a new row in Aurora:

```sql
-- In your Aurora psql session
INSERT INTO orders (customer_id, product_sku, quantity, unit_price, status)
VALUES (1, 'SKU-NEW', 5, 99.99, 'pending');
```

Wait 30-60 seconds, then query Redshift again. The new row should appear.

---

## Part B: RDS Data API

The RDS Data API provides HTTP-based SQL access to Aurora Serverless databases. No persistent connection required.

### B1. Enable the Data API

The Data API only works with Aurora Serverless v2 (or v1) clusters.

**Console:**

1. Go to your Aurora Serverless cluster.
2. Click **Modify**.
3. Under **Additional configuration**, check **Enable RDS Data API**.
4. Apply immediately.

**CLI:**

```bash
aws rds modify-db-cluster \
  --db-cluster-identifier [YOUR-AURORA-SERVERLESS-CLUSTER] \
  --enable-http-endpoint \
  --apply-immediately \
  --region [REGION]
```

The `--enable-http-endpoint` flag turns on the Data API for the cluster.

Verify it is enabled:

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier [YOUR-AURORA-SERVERLESS-CLUSTER] \
  --region [REGION] \
  --query 'DBClusters[0].HttpEndpointEnabled'
```

Expected output:
```
true
```

### B2. Store Database Credentials in Secrets Manager

The Data API authenticates using a Secrets Manager secret. It does not accept inline credentials.

**Step 1.** Create the secret:

```bash
aws secretsmanager create-secret \
  --name tier7/aurora/dataapi \
  --secret-string '{
    "username": "postgres",
    "password": "[YOUR-PASSWORD]",
    "engine": "postgres",
    "host": "[CLUSTER-ENDPOINT]",
    "port": 5432,
    "dbname": "postgres"
  }' \
  --region [REGION]
```

Note the `SecretArn` from the output. You will use it for all Data API calls.

### B3. Execute a Query via Data API

**Step 1.** Get your cluster ARN:

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier [YOUR-AURORA-SERVERLESS-CLUSTER] \
  --region [REGION] \
  --query 'DBClusters[0].DBClusterArn' \
  --output text
```

**Step 2.** Run a query using the Data API:

```bash
aws rds-data execute-statement \
  --resource-arn [CLUSTER-ARN] \
  --secret-arn [SECRET-ARN] \
  --database postgres \
  --sql "SELECT status, COUNT(*) AS cnt FROM orders GROUP BY status" \
  --region [REGION]
```

The `--resource-arn` identifies the Aurora cluster. The `--secret-arn` points to your Secrets Manager secret. No connection string, no driver, no pool.

Expected output:
```json
{
    "records": [
        [{"stringValue": "completed"}, {"longValue": 2487}],
        [{"stringValue": "pending"},   {"longValue": 2513}]
    ],
    "numberOfRecordsUpdated": 0
}
```

Results are returned as JSON arrays of typed values. Your application code parses these.

**Step 3.** Run a parameterized INSERT:

```bash
aws rds-data execute-statement \
  --resource-arn [CLUSTER-ARN] \
  --secret-arn [SECRET-ARN] \
  --database postgres \
  --sql "INSERT INTO orders (customer_id, product_sku, quantity, unit_price, status) VALUES (:cid, :sku, :qty, :price, :status)" \
  --parameters '[
    {"name": "cid",    "value": {"longValue": 42}},
    {"name": "sku",    "value": {"stringValue": "SKU-API-TEST"}},
    {"name": "qty",    "value": {"longValue": 3}},
    {"name": "price",  "value": {"doubleValue": 49.99}},
    {"name": "status", "value": {"stringValue": "pending"}}
  ]' \
  --region [REGION]
```

The `--parameters` flag takes a JSON array of named parameters. Each parameter has a `name` (matching the `:name` placeholder in the SQL) and a typed `value`. This is how you use parameterized queries with the Data API - never string-concatenate values into the SQL.

### B4. Run a Transaction via Data API

The Data API supports multi-statement transactions using begin/commit transaction calls.

**Step 1.** Begin a transaction:

```bash
aws rds-data begin-transaction \
  --resource-arn [CLUSTER-ARN] \
  --secret-arn [SECRET-ARN] \
  --database postgres \
  --region [REGION]
```

Note the `transactionId` from the output.

**Step 2.** Execute statements within the transaction:

```bash
aws rds-data execute-statement \
  --resource-arn [CLUSTER-ARN] \
  --secret-arn [SECRET-ARN] \
  --database postgres \
  --transaction-id [TRANSACTION-ID] \
  --sql "UPDATE orders SET status = 'shipped' WHERE order_id = 1" \
  --region [REGION]
```

**Step 3.** Commit the transaction:

```bash
aws rds-data commit-transaction \
  --resource-arn [CLUSTER-ARN] \
  --secret-arn [SECRET-ARN] \
  --transaction-id [TRANSACTION-ID] \
  --region [REGION]
```

### B5. Data API vs Direct Connection - Decision Guide

| Factor | Data API | Direct Connection |
|--------|----------|-------------------|
| Best for | Lambda, API Gateway, serverless | Traditional apps, ORMs |
| Connection pool | Not needed | Required (use RDS Proxy or PgBouncer) |
| Query latency | 20-100ms overhead per call | Sub-millisecond connection overhead |
| Max query timeout | 45 seconds | Session-level setting |
| Long transactions | Not suitable | Fully supported |
| Binary data | Limited support | Full support |
| VPC requirement | Optional | Yes |
| Authentication | IAM + Secrets Manager | Database credentials |
| SDK support | AWS SDKs | psycopg2, pg, JDBC, etc. |

**Rule:** Use Data API for Lambda functions and API-driven access patterns where persistent connections are impractical. Use direct connections for all application workloads that can maintain a connection pool.

---

## Summary

What you did in this lab:

- Enabled logical replication on an Aurora PostgreSQL cluster.
- Created source tables with primary keys and seed data.
- Created a Redshift Serverless workgroup as the analytics destination.
- Created a Zero-ETL integration and observed near-real-time replication.
- Enabled the RDS Data API on an Aurora Serverless cluster.
- Stored credentials in Secrets Manager.
- Ran parameterized queries, INSERTs, and transactions through the HTTP-based Data API.
- Compared Data API vs direct connection trade-offs.

**Key things to remember:**
- Zero-ETL requires primary keys on all replicated tables. Tables without primary keys are silently skipped.
- Zero-ETL replication lag is typically seconds to minutes - not instant.
- The Data API has a 45-second query timeout. Do not use it for long-running operations.
- Always use parameterized queries with the Data API - never concatenate user input into SQL strings.
