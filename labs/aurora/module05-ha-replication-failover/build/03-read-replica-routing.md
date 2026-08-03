# BUILD 03 - Read Replica Routing: Reader Endpoint, Custom Endpoints, Test Routing
## Estimated Time: 35 minutes

---

## What You Will Do

1. Test the reader endpoint load balancing with multiple connections
2. Measure Aurora replica lag
3. Create a custom endpoint for analytics workload isolation
4. Verify endpoint routing with DNS inspection
5. Test read-your-writes behavior

> **Cost warning:** This lab uses the cluster from BUILD 01-02. No additional resources except a custom endpoint.

---

## Before You Start

You need:
- The Aurora cluster from BUILD 01 (`devops-lab-cluster`) with at least 1 reader
- AWS CLI v2 configured
- psql and `dig` (or `nslookup`) installed

---

## Step 1 - List All Endpoints

**In your terminal:**

```bash
aws rds describe-db-cluster-endpoints \
  --db-cluster-identifier devops-lab-cluster \
  --query 'DBClusterEndpoints[*].{ID:DBClusterEndpointIdentifier,Type:EndpointType,Endpoint:Endpoint,Status:Status}' \
  --output table \
  --region us-east-1
```

Expected output (yours will differ):
```
------------------------------------------------------------------------------------
|                          DescribeDBClusterEndpoints                              |
+------------------------+---------------------------------------------------+-----+
| ID                     | Endpoint                                          | Type|
+------------------------+---------------------------------------------------+-----+
| devops-lab-cluster     | devops-lab-cluster.cluster-xxxx...               | WRITER|
| devops-lab-cluster-ro  | devops-lab-cluster.cluster-ro-xxxx...            | READER|
+------------------------+---------------------------------------------------+-----+
```

You have two endpoints: the writer endpoint and the reader endpoint.

---

## Step 2 - Inspect DNS with dig

**In your terminal:**

Check the writer endpoint:

```bash
dig +short devops-lab-cluster.cluster-xxxx.us-east-1.rds.amazonaws.com
```

Expected output (yours will differ):
```
10.0.1.23
```

One IP - the writer.

Check the reader endpoint:

```bash
dig +short devops-lab-cluster.cluster-ro-xxxx.us-east-1.rds.amazonaws.com
```

Expected output (yours will differ):
```
10.0.2.45
```

Run the reader dig multiple times to see round-robin:

```bash
for i in 1 2 3 4 5; do
  dig +short devops-lab-cluster.cluster-ro-xxxx.us-east-1.rds.amazonaws.com
done
```

Expected output (yours will differ):
```
10.0.2.45
10.0.2.45
10.0.2.45
10.0.2.45
10.0.2.45
```

If you only have one reader, you will see the same IP every time. DNS round-robin only shows multiple IPs when you have multiple readers.

---

## Step 3 - Add a Second Reader (If You Have Only One)

**In your terminal:**

```bash
aws rds create-db-instance \
  --db-instance-identifier devops-lab-reader-2 \
  --db-cluster-identifier devops-lab-cluster \
  --engine aurora-postgresql \
  --db-instance-class db.t3.medium \
  --availability-zone us-east-1c \
  --promotion-tier 1 \
  --region us-east-1
```

`--availability-zone us-east-1c` - third AZ for maximum resilience.
`--promotion-tier 1` - lower priority than reader-1 (tier 0).

Wait for the instance to become available (8-15 minutes).

---

## Step 4 - Test Reader Endpoint Load Balancing

**In your terminal:**

With two readers, the reader endpoint should rotate between them:

```bash
for i in 1 2 3 4 5 6; do
  psql -h devops-lab-cluster.cluster-ro-xxxx.us-east-1.rds.amazonaws.com \
       -U postgres -d postgres \
       -t -c "SELECT $i AS session, inet_server_addr() AS connected_to;"
done
```

Expected output (yours will differ):
```
 1 | 10.0.2.45
 2 | 10.0.3.67
 3 | 10.0.2.45
 4 | 10.0.3.67
 5 | 10.0.2.45
 6 | 10.0.3.67
```

The connections alternate between two different reader IPs. This is DNS round-robin load balancing.

---

## Step 5 - Measure Replica Lag

**In your terminal:**

Connect to the reader endpoint:

```bash
psql -h devops-lab-cluster.cluster-ro-xxxx.us-east-1.rds.amazonaws.com \
     -U postgres \
     -d postgres
```

**In psql:**

```sql
SELECT
    now() AS current_time,
    pg_last_xact_replay_timestamp() AS last_replayed,
    now() - pg_last_xact_replay_timestamp() AS lag,
    pg_is_in_recovery() AS is_replica;
```

`pg_last_xact_replay_timestamp()` - the timestamp of the last transaction replayed on this replica.

Expected output (yours will differ):
```
        current_time         |       last_replayed         |    lag     | is_replica
-----------------------------+-----------------------------+------------+----------
 2026-06-09 14:30:00.000000  | 2026-06-09 14:29:59.950000 | 00:00:00.05| t
(1 row)
```

50 milliseconds of lag. Typical for Aurora. Compare this to RDS read replicas which often show 100-500ms of lag.

Exit psql:

```sql
\q
```

Check lag via CloudWatch:

**In your terminal:**

```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name AuroraReplicaLag \
  --dimensions Name=DBClusterIdentifier,Value=devops-lab-cluster \
  --start-time $(date -u -v-30M +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 60 \
  --statistics Maximum \
  --region us-east-1
```

`--metric-name AuroraReplicaLag` - Aurora-specific metric in milliseconds.

Expected output (yours will differ):
```json
{
    "Datapoints": [
        {
            "Timestamp": "2026-06-09T14:30:00Z",
            "Maximum": 52.3,
            "Unit": "Milliseconds"
        }
    ]
}
```

---

## Step 6 - Create a Custom Endpoint for Analytics

Custom endpoints let you route specific workloads to specific instances.

**Scenario:** You have a BI dashboard that runs heavy queries. You want it to use only `devops-lab-reader-2` so it does not interfere with your OLTP reads on reader-1.

**In your terminal:**

```bash
aws rds create-db-cluster-endpoint \
  --db-cluster-identifier devops-lab-cluster \
  --db-cluster-endpoint-identifier devops-lab-analytics \
  --endpoint-type READER \
  --static-members devops-lab-reader-2 \
  --region us-east-1
```

`--db-cluster-endpoint-identifier` - the name for your custom endpoint.
`--endpoint-type READER` - routes to reader instances only.
`--static-members` - explicitly list which instance(s) this endpoint includes.

Expected output (yours will differ):
```json
{
    "DBClusterEndpointIdentifier": "devops-lab-analytics",
    "Endpoint": "devops-lab-analytics.cluster-custom-xxxx.us-east-1.rds.amazonaws.com",
    "Status": "creating",
    "EndpointType": "CUSTOM"
}
```

Wait about 1 minute for the endpoint to become "available."

---

## Step 7 - Verify the Custom Endpoint

**In your terminal:**

Connect to the custom endpoint:

```bash
psql -h devops-lab-analytics.cluster-custom-xxxx.us-east-1.rds.amazonaws.com \
     -U postgres \
     -d postgres \
     -c "SELECT inet_server_addr() AS connected_to, pg_is_in_recovery() AS is_replica;"
```

Expected output (yours will differ):
```
 connected_to | is_replica
--------------+-----------
 10.0.3.67    | t
(1 row)
```

The IP should match devops-lab-reader-2. Connect multiple times - it should always return the same IP because you included only one instance.

Compare with the reader endpoint:

```bash
for i in 1 2 3 4; do
  psql -h devops-lab-cluster.cluster-ro-xxxx.us-east-1.rds.amazonaws.com \
       -U postgres -d postgres \
       -t -c "SELECT inet_server_addr();" 2>/dev/null
done
```

The reader endpoint rotates between both readers. The custom endpoint always goes to reader-2.

---

## Step 8 - Test Read-Your-Writes Behavior

This demonstrates a common problem with read replicas.

**In your terminal:**

Write a row to the writer and immediately read from the reader:

```bash
psql -h devops-lab-cluster.cluster-xxxx.us-east-1.rds.amazonaws.com \
     -U postgres -d postgres \
     -c "INSERT INTO failover_test (message) VALUES ('instant-read-test') RETURNING id;"
```

Note the returned `id`. Immediately query the reader:

```bash
psql -h devops-lab-cluster.cluster-ro-xxxx.us-east-1.rds.amazonaws.com \
     -U postgres -d postgres \
     -c "SELECT * FROM failover_test WHERE message = 'instant-read-test';"
```

With Aurora's near-zero lag, the row usually appears immediately. Under heavy write load, there might be a brief delay. This is the "read-your-own-writes" problem - your application writes to the writer but reads from a replica that may not have the data yet.

---

## Key Takeaways

1. The reader endpoint distributes connections across readers via DNS round-robin
2. Aurora replica lag is typically under 100 milliseconds
3. Custom endpoints route traffic to specific instances for workload isolation
4. Use `dig +short` to inspect which IP an endpoint resolves to
5. The read-your-writes problem exists even with near-zero lag - design your app accordingly
6. Custom endpoints with static members do not auto-adjust during failover

---

## Clean Up Custom Endpoint

```bash
aws rds delete-db-cluster-endpoint \
  --db-cluster-endpoint-identifier devops-lab-analytics \
  --region us-east-1
```

Keep the cluster running for BUILD 04.
