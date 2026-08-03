# BUILD 05 - Aurora Endpoints: Explore All 4 Types
## Estimated Time: 30 minutes

---

## What You Will Do

1. Find and examine all four Aurora endpoint types
2. Use dig/nslookup to inspect DNS resolution
3. Create a custom endpoint for an analytics workload
4. Understand endpoint behavior during failover

---

## Before You Start

You need:
- The Aurora cluster from BUILD 04 with at least 2 reader instances
- AWS CLI v2 configured
- `dig` or `nslookup` installed (comes standard on macOS and Linux)
- psql available

---

## Step 1 - List All Endpoints for Your Cluster

### Console

1. Go to RDS -> Databases
2. Click your cluster `my-aurora-cluster`
3. Click the "Connectivity and security" tab
4. Look at the "Endpoints" section
5. You will see: cluster (writer) endpoint and reader endpoint

### CLI

```bash
aws rds describe-db-cluster-endpoints \
  --db-cluster-identifier my-aurora-cluster \
  --region us-east-1
```

Expected output (yours will differ):
```json
{
    "DBClusterEndpoints": [
        {
            "DBClusterEndpointIdentifier": "my-aurora-cluster",
            "DBClusterIdentifier": "my-aurora-cluster",
            "DBClusterEndpointResourceIdentifier": "cluster-xxxx",
            "Endpoint": "my-aurora-cluster.cluster-xxxx.us-east-1.rds.amazonaws.com",
            "Status": "available",
            "EndpointType": "WRITER",
            "CustomEndpointType": "ANY",
            "DBInstanceMembers": [],
            "ExcludedMembers": []
        },
        {
            "DBClusterEndpointIdentifier": "my-aurora-cluster-ro",
            "DBClusterIdentifier": "my-aurora-cluster",
            "Endpoint": "my-aurora-cluster.cluster-ro-xxxx.us-east-1.rds.amazonaws.com",
            "Status": "available",
            "EndpointType": "READER",
            "CustomEndpointType": "ANY",
            "DBInstanceMembers": [],
            "ExcludedMembers": []
        }
    ]
}
```

---

## Step 2 - Inspect the Writer Endpoint with dig

`dig` shows what DNS returns for a hostname. Aurora endpoints are DNS names that resolve to IP addresses.

```bash
dig my-aurora-cluster.cluster-xxxx.us-east-1.rds.amazonaws.com
```

`dig` - DNS lookup tool.

Expected output (yours will differ):
```
;; ANSWER SECTION:
my-aurora-cluster.cluster-xxxx.us-east-1.rds.amazonaws.com. 5 IN A 10.0.1.23
```

The TTL (time to live) is 5 seconds for Aurora endpoints. This means after a failover, DNS updates happen within 5 seconds for Aurora. Compare this to RDS Multi-AZ which has a 60-second TTL.

```bash
# If dig is not available, use nslookup
nslookup my-aurora-cluster.cluster-xxxx.us-east-1.rds.amazonaws.com
```

Expected output (yours will differ):
```
Server:         8.8.8.8
Address:        8.8.8.8#53

Non-authoritative answer:
Name:   my-aurora-cluster.cluster-xxxx.us-east-1.rds.amazonaws.com
Address: 10.0.1.23
```

---

## Step 3 - Inspect the Reader Endpoint

```bash
dig my-aurora-cluster.cluster-ro-xxxx.us-east-1.rds.amazonaws.com
```

Expected output (yours will differ):
```
;; ANSWER SECTION:
my-aurora-cluster.cluster-ro-xxxx.us-east-1.rds.amazonaws.com. 5 IN A 10.0.2.45
```

Run the same dig command several times:

```bash
for i in 1 2 3 4 5; do
  dig +short my-aurora-cluster.cluster-ro-xxxx.us-east-1.rds.amazonaws.com
done
```

Expected output (yours will differ):
```
10.0.2.45
10.0.3.67
10.0.2.45
10.0.3.67
10.0.2.45
```

The IP alternates between two addresses - DNS round-robin across your two readers.

---

## Step 4 - Inspect Instance Endpoints

Each instance in your cluster has its own endpoint. Get them:

```bash
aws rds describe-db-instances \
  --filters Name=db-cluster-id,Values=my-aurora-cluster \
  --query 'DBInstances[*].{Instance:DBInstanceIdentifier,Endpoint:Endpoint.Address}' \
  --output table \
  --region us-east-1
```

Expected output (yours will differ):
```
--------------------------------------------------------------------
|                    DescribeDBInstances                           |
+--------------------+---------------------------------------------+
| Instance           | Endpoint                                    |
+--------------------+---------------------------------------------+
| my-aurora-writer   | my-aurora-writer.xxxx.us-east-1.rds.amazonaws.com |
| my-aurora-reader-1 | my-aurora-reader-1.xxxx.us-east-1.rds.amazonaws.com |
| my-aurora-reader-2 | my-aurora-reader-2.xxxx.us-east-1.rds.amazonaws.com |
+--------------------+---------------------------------------------+
```

These instance endpoints always point to that specific instance, even after failover. Use them only for diagnostic work - not for application connections.

Connect to a specific reader via its instance endpoint:

```bash
psql -h my-aurora-reader-1.xxxx.us-east-1.rds.amazonaws.com \
     -U postgres \
     -d postgres \
     -c "SELECT inet_server_addr();"
```

Expected output:
```
 inet_server_addr
------------------
 10.0.2.45
(1 row)
```

---

## Step 5 - Create a Custom Endpoint

Custom endpoints let you route specific workloads to specific instances. This is useful when you have large analytics queries that should not compete with OLTP reads.

### Scenario

You have a BI tool (Tableau, Metabase, etc.) that runs heavy analytical queries. You want it to use only `my-aurora-reader-2` and not interfere with the application's reads on `my-aurora-reader-1`.

### Console

1. Go to RDS -> Databases -> your cluster
2. Click the "Endpoints" tab
3. Click "Create endpoint"
4. Fill in:
   - Endpoint identifier: `my-aurora-analytics`
   - Endpoint type: Reader
   - Choose instances: select `my-aurora-reader-2` only
5. Click "Create endpoint"

### CLI

```bash
aws rds create-db-cluster-endpoint \
  --db-cluster-identifier my-aurora-cluster \
  --db-cluster-endpoint-identifier my-aurora-analytics \
  --endpoint-type READER \
  --static-members my-aurora-reader-2 \
  --region us-east-1
```

`--db-cluster-endpoint-identifier` - the name for your custom endpoint.
`--endpoint-type READER` - this endpoint routes to reader instances only.
`--static-members` - explicitly list which instance(s) this endpoint includes.

Expected output (yours will differ):
```json
{
    "DBClusterEndpointIdentifier": "my-aurora-analytics",
    "DBClusterIdentifier": "my-aurora-cluster",
    "Endpoint": "my-aurora-analytics.cluster-custom-xxxx.us-east-1.rds.amazonaws.com",
    "Status": "creating",
    "EndpointType": "CUSTOM"
}
```

Wait about 1 minute for the endpoint to become "available."

---

## Step 6 - Verify the Custom Endpoint

Connect to the custom endpoint:

```bash
psql -h my-aurora-analytics.cluster-custom-xxxx.us-east-1.rds.amazonaws.com \
     -U postgres \
     -d postgres \
     -c "SELECT inet_server_addr();"
```

Expected output (yours will differ):
```
 inet_server_addr
------------------
 10.0.3.67
(1 row)
```

The IP should match `my-aurora-reader-2`'s IP. Connect multiple times - it should always return the same IP (because you only included one instance).

Compare with the reader endpoint - it should give you both readers:

```bash
for i in 1 2 3 4; do
  psql -h my-aurora-cluster.cluster-ro-xxxx.us-east-1.rds.amazonaws.com \
       -U postgres -d postgres \
       -c "SELECT inet_server_addr();" 2>/dev/null
done
```

Expected output (yours will differ):
```
 10.0.2.45
 10.0.3.67
 10.0.2.45
 10.0.3.67
```

Both readers appear in rotation.

---

## Step 7 - Understand Endpoint Behavior During Failover

This is important knowledge for building resilient applications.

### Writer Endpoint Behavior

During failover:
- The writer endpoint DNS record is updated within 5 seconds
- Applications that respect short TTL will reconnect to the new writer
- Applications that cache DNS longer will fail until they refresh

Best practice for applications: set your DNS TTL/cache to 5 seconds or less. In Java, add `-Dnetworkaddress.cache.ttl=1` to JVM options.

### Reader Endpoint Behavior

During failover:
- If a reader is promoted to writer, it is removed from the reader pool
- The reader endpoint automatically adjusts
- A cluster with 2 readers goes to 1 reader during failover (until the old writer becomes a reader)
- Applications reading from the reader endpoint may see connection failures for ~5 seconds

### Custom Endpoint Behavior

If the instance your custom endpoint points to is involved in a failover:
- The custom endpoint may become unavailable temporarily
- Static member custom endpoints do not automatically swap to a different instance

Example:

```
Before failover:
  Custom endpoint -> my-aurora-reader-2 (tier 1, backup candidate)

Writer fails:
  my-aurora-reader-1 (tier 0) is promoted to writer

After failover:
  Custom endpoint -> my-aurora-reader-2 (still a reader - OK)
  Custom endpoint still works because reader-2 was not involved

But if writer fails AND reader-1 fails simultaneously:
  my-aurora-reader-2 promoted to writer
  Custom endpoint -> my-aurora-reader-2 (now a writer, but endpoint type is READER)
  Custom endpoint becomes unavailable until reader-2 is re-added as a reader
```

For this reason, use the reader endpoint for most read traffic. Custom endpoints are best for fixed, large readers where you know the failover behavior.

---

## Step 8 - View All Endpoints Summary

```bash
aws rds describe-db-cluster-endpoints \
  --db-cluster-identifier my-aurora-cluster \
  --query 'DBClusterEndpoints[*].{ID:DBClusterEndpointIdentifier,Type:EndpointType,Endpoint:Endpoint,Status:Status}' \
  --output table \
  --region us-east-1
```

Expected output (yours will differ):
```
----------------------------------------------------------------------------------------------------
|                              DescribeDBClusterEndpoints                                          |
+------------------------+-------------------------------------------------------+--------+-------+
| ID                     | Endpoint                                              | Status | Type  |
+------------------------+-------------------------------------------------------+--------+-------+
| my-aurora-analytics    | my-aurora-analytics.cluster-custom-xxxx...           | avail. | CUSTOM|
| my-aurora-cluster      | my-aurora-cluster.cluster-xxxx...                    | avail. | WRITER|
| my-aurora-cluster-ro   | my-aurora-cluster.cluster-ro-xxxx...                 | avail. | READER|
+------------------------+-------------------------------------------------------+--------+-------+
```

---

## Key Takeaways

1. Writer endpoint = always points to the current writer (updates within 5 seconds of failover)
2. Reader endpoint = DNS round-robin across all readers (fallback to writer if no readers exist)
3. Instance endpoint = points to one specific instance (use for diagnostics only)
4. Custom endpoint = you define which instances; use for analytics or tiered workloads
5. Aurora DNS TTL is 5 seconds - much shorter than RDS (60 sec). Design apps to respect this.
6. Custom endpoints with static members do not auto-heal during failover - plan accordingly

---

## Clean Up Custom Endpoint

```bash
aws rds delete-db-cluster-endpoint \
  --db-cluster-endpoint-identifier my-aurora-analytics \
  --region us-east-1
```

Keep the cluster running for BUILD 06 if you want a base cluster (though BUILD 06 creates a new global database).
