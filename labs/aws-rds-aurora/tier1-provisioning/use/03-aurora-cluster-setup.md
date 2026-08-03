# USE 03 - Aurora Cluster Setup
## Tier 1: Provisioning and Connectivity

**Estimated time:** 50 minutes
**Type:** Hands-on exercise with requirements
**Prerequisite:** Build 03 complete

---

## Overview

You will provision a production-like Aurora PostgreSQL cluster with 1 writer and 2 reader instances. Then you will test read/write splitting by using different endpoints and verify each replica is healthy.

This exercise simulates a real workload split: heavy analytics queries go to readers, write transactions go to the writer.

---

## Requirements

### Requirement 1 - Create the Aurora Cluster

Create an Aurora PostgreSQL cluster with these specifications:

| Setting | Value |
|---------|-------|
| Cluster identifier | `suta-use03-aurora` |
| Engine | Aurora PostgreSQL |
| Engine version | Latest available |
| Master username | `clusteradmin` |
| Initial database | `salesdb` |
| Instance class | `db.t3.medium` |
| Number of instances | 1 writer + 2 readers |
| Backup retention | 1 day |
| Public access | Yes |

Create the cluster and all three instances (writer: `suta-use03-writer`, readers: `suta-use03-reader-1`, `suta-use03-reader-2`).

Use any security group and subnet group from your previous labs, or create new ones.

Wait until all three instances show status `available`.

---

### Requirement 2 - Document All Endpoints

Once the cluster is available, find and write down all five endpoints:

| Endpoint Type | URL |
|--------------|-----|
| Cluster endpoint (writer) | |
| Reader endpoint (load-balanced) | |
| Writer instance endpoint | |
| Reader 1 instance endpoint | |
| Reader 2 instance endpoint | |

Use the CLI:

```bash
# Cluster endpoints
aws rds describe-db-clusters \
  --db-cluster-identifier suta-use03-aurora \
  --query "DBClusters[0].{Writer:Endpoint,Reader:ReaderEndpoint}" \
  --output table

# Instance endpoints
aws rds describe-db-instances \
  --filters "Name=db-cluster-id,Values=suta-use03-aurora" \
  --query "DBInstances[*].{ID:DBInstanceIdentifier,Endpoint:Endpoint.Address}" \
  --output table
```

---

### Requirement 3 - Verify Each Instance's Role

Connect to each of the five endpoints. For each one, run:

```sql
SELECT pg_is_in_recovery(), inet_server_addr();
```

Fill in this table:

| Endpoint | pg_is_in_recovery() | inet_server_addr() | Role |
|----------|--------------------|--------------------|------|
| Cluster endpoint | | | writer / reader |
| Reader endpoint | | | writer / reader |
| Writer instance | | | writer / reader |
| Reader 1 instance | | | writer / reader |
| Reader 2 instance | | | writer / reader |

Questions after filling in the table:

1. The reader endpoint sometimes connects you to reader-1 and sometimes reader-2. Why?

2. Can you tell which physical instance the reader endpoint is using for any given connection? What SQL function tells you the server address?

3. What happens if you try to write data through the reader endpoint?

---

### Requirement 4 - Create Test Data via the Writer

Connect to the cluster endpoint (writer) and create a realistic dataset:

```sql
CREATE TABLE sales_orders (
    order_id SERIAL PRIMARY KEY,
    customer_name TEXT NOT NULL,
    product TEXT NOT NULL,
    quantity INTEGER NOT NULL,
    unit_price NUMERIC(10,2) NOT NULL,
    order_date TIMESTAMPTZ DEFAULT NOW(),
    status TEXT DEFAULT 'pending'
);

INSERT INTO sales_orders (customer_name, product, quantity, unit_price, status)
SELECT
    'Customer ' || i,
    CASE (i % 4)
        WHEN 0 THEN 'Laptop'
        WHEN 1 THEN 'Mouse'
        WHEN 2 THEN 'Keyboard'
        ELSE 'Monitor'
    END,
    (i % 10) + 1,
    CASE (i % 4)
        WHEN 0 THEN 999.99
        WHEN 1 THEN 29.99
        WHEN 2 THEN 79.99
        ELSE 399.99
    END,
    CASE (i % 3)
        WHEN 0 THEN 'pending'
        WHEN 1 THEN 'shipped'
        ELSE 'delivered'
    END
FROM generate_series(1, 1000) AS s(i);

SELECT count(*) FROM sales_orders;
```

Expected output: `1000`

Exit psql:

```sql
\q
```

---

### Requirement 5 - Verify Replication on Both Readers

Connect to reader-1 instance endpoint and verify the data replicated:

```sql
SELECT count(*) FROM sales_orders;
SELECT status, count(*) FROM sales_orders GROUP BY status ORDER BY status;
```

Expected output for count: `1000`
Expected output for group by (approximate):
```
  status   | count
-----------+-------
 delivered |   334
 pending   |   333
 shipped   |   333
```

Connect to reader-2 instance endpoint and run the same queries. Confirm both readers have the same data.

---

### Requirement 6 - Measure Replication Lag

Connect to each reader and run:

```sql
SELECT now() - pg_last_xact_replay_timestamp() AS replication_lag;
```

Record the lag for each reader:

| Reader | Replication Lag |
|--------|----------------|
| reader-1 | |
| reader-2 | |

Questions:

1. Is the lag above or below 1 second? What does Aurora's architecture contribute to this low lag?

2. In standard RDS with a read replica, what would the typical lag be compared to Aurora?

3. If a reader is lagging 5 minutes behind the writer, what kind of problem might cause that?

---

### Requirement 7 - Simulate Read/Write Splitting in a Script

Create a Python script at `/tmp/aurora_split.py` that demonstrates read/write splitting:

```python
import psycopg2
import os

WRITER_ENDPOINT = os.environ["AURORA_WRITER"]
READER_ENDPOINT = os.environ["AURORA_READER"]
PASSWORD = os.environ["AURORA_PASS"]

CONN_ARGS = {
    "dbname": "salesdb",
    "user": "clusteradmin",
    "password": PASSWORD,
    "port": 5432,
    "sslmode": "require",
}

def get_writer_conn():
    return psycopg2.connect(host=WRITER_ENDPOINT, **CONN_ARGS)

def get_reader_conn():
    return psycopg2.connect(host=READER_ENDPOINT, **CONN_ARGS)

# Write operation - uses writer
writer = get_writer_conn()
wcur = writer.cursor()
wcur.execute(
    "INSERT INTO sales_orders (customer_name, product, quantity, unit_price) "
    "VALUES (%s, %s, %s, %s) RETURNING order_id",
    ("Python Script", "SSD", 2, 149.99)
)
new_id = wcur.fetchone()[0]
writer.commit()
print(f"Wrote new order_id={new_id} via writer endpoint")
wcur.close()
writer.close()

# Read operation - uses reader
reader = get_reader_conn()
rcur = reader.cursor()
rcur.execute(
    "SELECT order_id, customer_name, product, unit_price "
    "FROM sales_orders ORDER BY order_id DESC LIMIT 5"
)
rows = rcur.fetchall()
print("Most recent 5 orders (via reader endpoint):")
for row in rows:
    print(f"  order_id={row[0]}, customer={row[1]}, product={row[2]}, price={row[3]}")
rcur.close()
reader.close()
```

Run it:

```bash
export AURORA_WRITER="suta-use03-aurora.cluster-abc123.us-east-1.rds.amazonaws.com"
export AURORA_READER="suta-use03-aurora.cluster-ro-abc123.us-east-1.rds.amazonaws.com"
export AURORA_PASS="your_password"
python3 /tmp/aurora_split.py
```

Expected output:
```
Wrote new order_id=1001 via writer endpoint
Most recent 5 orders (via reader endpoint):
  order_id=1001, customer=Python Script, product=SSD, price=149.99
  order_id=1000, customer=Customer 1000, product=Monitor, price=399.99
  ...
```

Note: the newly written row appears on the reader almost instantly because of Aurora's storage-level replication.

---

### Requirement 8 - Check Cluster Member Status

Use the CLI to confirm all three instances are in the cluster and show their roles:

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier suta-use03-aurora \
  --query "DBClusters[0].DBClusterMembers[*].{Instance:DBInstanceIdentifier,IsWriter:IsClusterWriter,Tier:PromotionTier}" \
  --output table
```

Questions based on the output:

1. Which instance is the cluster writer?

2. What is the PromotionTier for each reader? What does this control?

3. If the writer fails, which reader gets promoted? (Hint: look at the PromotionTier values.)

---

### Requirement 9 - Change a Reader's Promotion Tier

Set `suta-use03-reader-1` as the preferred failover target by giving it PromotionTier 1 and `suta-use03-reader-2` PromotionTier 2.

```bash
aws rds modify-db-instance \
  --db-instance-identifier suta-use03-reader-1 \
  --promotion-tier 1

aws rds modify-db-instance \
  --db-instance-identifier suta-use03-reader-2 \
  --promotion-tier 2
```

Verify the change:

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier suta-use03-aurora \
  --query "DBClusters[0].DBClusterMembers[*].{Instance:DBInstanceIdentifier,IsWriter:IsClusterWriter,Tier:PromotionTier}" \
  --output table
```

---

## Cleanup

Delete all instances then the cluster. Delete in order.

```bash
aws rds delete-db-instance \
  --db-instance-identifier suta-use03-reader-2 \
  --skip-final-snapshot

aws rds delete-db-instance \
  --db-instance-identifier suta-use03-reader-1 \
  --skip-final-snapshot

aws rds delete-db-instance \
  --db-instance-identifier suta-use03-writer \
  --skip-final-snapshot

aws rds wait db-instance-deleted \
  --db-instance-identifier suta-use03-reader-2

aws rds wait db-instance-deleted \
  --db-instance-identifier suta-use03-reader-1

aws rds wait db-instance-deleted \
  --db-instance-identifier suta-use03-writer

aws rds delete-db-cluster \
  --db-cluster-identifier suta-use03-aurora \
  --skip-final-snapshot
```

---

## Key Takeaways

- Aurora always uses the cluster endpoint for writes and the reader endpoint for reads
- `pg_is_in_recovery()` tells you the role of any instance: `f` = writer, `t` = reader
- Aurora replication is near-instant due to storage-level architecture
- PromotionTier controls which reader becomes writer during failover
- Use separate connections for reads and writes - this is called "read/write splitting"
