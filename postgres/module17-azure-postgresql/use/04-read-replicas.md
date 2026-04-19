# USE 04 - Read Replicas

## Objective

Create a read replica, monitor replication lag, promote a replica to a standalone server, and create a cross-region replica.

---

## Exercise

### Task 1 - Check Replication Prerequisites

Your source server must be General Purpose or Memory Optimized tier. Check the current tier.

```bash
az postgres flexible-server show \
  --resource-group suta-pg-lab-rg \
  --name suta-pg-lab-server \
  --query "{Name:name, Tier:sku.tier, SKU:sku.name}" \
  --output table
```

Expected output (yours will differ):

```
Name                 Tier            SKU
-------------------  --------------  ----------------
suta-pg-lab-server   GeneralPurpose  Standard_D2ds_v4
```

If the tier is `Burstable`, upgrade first (see BUILD 02, Step 2).

---

### Task 2 - Create a Read Replica

Create a read replica in the same region. The `--source-server` flag specifies the primary server. The replica inherits the SKU and storage configuration.

```bash
az postgres flexible-server replica create \
  --resource-group suta-pg-lab-rg \
  --replica-name suta-pg-lab-replica1 \
  --source-server suta-pg-lab-server
```

Expected output (yours will differ):

```json
{
  "id": "/subscriptions/.../flexibleServers/suta-pg-lab-replica1",
  "location": "eastus",
  "name": "suta-pg-lab-replica1",
  "replicationRole": "AsyncReplica",
  "sourceServerResourceId": "/subscriptions/.../flexibleServers/suta-pg-lab-server",
  "state": "Ready"
}
```

This takes 5-10 minutes. The `replicationRole` is `AsyncReplica` - read replicas use asynchronous replication (unlike HA standby which uses synchronous).

---

### Task 3 - List All Replicas

View all replicas for your server.

```bash
az postgres flexible-server replica list \
  --resource-group suta-pg-lab-rg \
  --name suta-pg-lab-server \
  --query "[].{Name:name, Role:replicationRole, State:state, Location:location}" \
  --output table
```

Expected output (yours will differ):

```
Name                    Role          State  Location
----------------------  ------------  -----  --------
suta-pg-lab-replica1    AsyncReplica  Ready  eastus
```

---

### Task 4 - Check Replication Lag

Connect to the replica and check the replication lag.

First, add a firewall rule to the replica. Replace `[YOUR_IP]` with your public IP.

```bash
az postgres flexible-server firewall-rule create \
  --resource-group suta-pg-lab-rg \
  --name suta-pg-lab-replica1 \
  --rule-name my-ip \
  --start-ip-address [YOUR_IP] \
  --end-ip-address [YOUR_IP]
```

Connect to the replica.

```bash
psql "host=suta-pg-lab-replica1.postgres.database.azure.com port=5432 dbname=postgres user=pgadmin sslmode=require"
```

Check replication status.

```sql
SELECT now() - pg_last_xact_replay_timestamp() AS replication_lag;
```

Expected output (yours will differ):

```
 replication_lag
-----------------
 00:00:00.123456
```

A lag under 1 second is typical for same-region replicas under normal load.

Check if the replica is in recovery mode (it should be).

```sql
SELECT pg_is_in_recovery();
```

Expected output:

```
 pg_is_in_recovery
-------------------
 t
```

The `t` (true) confirms this is a replica receiving WAL from the primary.

Exit psql.

```sql
\q
```

---

### Task 5 - Verify Read-Only on Replica

Connect to the replica and try to write. It should fail.

```bash
psql "host=suta-pg-lab-replica1.postgres.database.azure.com port=5432 dbname=postgres user=pgadmin sslmode=require"
```

```sql
CREATE TABLE test_write (id int);
```

Expected output:

```
ERROR:  cannot execute CREATE TABLE in a read-only transaction
```

This confirms the replica is read-only. Applications can direct read queries here to offload the primary.

Exit psql.

```sql
\q
```

---

### Task 6 - Monitor Replication Lag via Azure Metrics

Check replication lag from the Azure side using metrics.

```bash
az monitor metrics list \
  --resource "/subscriptions/[SUBSCRIPTION_ID]/resourceGroups/suta-pg-lab-rg/providers/Microsoft.DBforPostgreSQL/flexibleServers/suta-pg-lab-replica1" \
  --metric "physical_replication_delay_in_seconds" \
  --interval PT1M \
  --query "value[0].timeseries[0].data[-5:].{Time:timeStamp, MaxLag:maximum}" \
  --output table
```

Replace `[SUBSCRIPTION_ID]` with your subscription ID.

Expected output (yours will differ):

```
Time                           MaxLag
-----------------------------  ------
2026-04-19T16:25:00+00:00      0.12
2026-04-19T16:26:00+00:00      0.08
2026-04-19T16:27:00+00:00      0.15
2026-04-19T16:28:00+00:00      0.09
2026-04-19T16:29:00+00:00      0.11
```

---

### Task 7 - Promote the Replica

Promote the replica to a standalone read-write server. This breaks replication permanently.

```bash
az postgres flexible-server replica stop-replication \
  --resource-group suta-pg-lab-rg \
  --name suta-pg-lab-replica1
```

Expected output (yours will differ):

```json
{
  "name": "suta-pg-lab-replica1",
  "replicationRole": "None",
  "state": "Ready"
}
```

The `replicationRole` changed to `None` - it is now an independent server.

---

### Task 8 - Verify Promoted Replica Accepts Writes

Connect to the promoted server and write data.

```bash
psql "host=suta-pg-lab-replica1.postgres.database.azure.com port=5432 dbname=postgres user=pgadmin sslmode=require"
```

```sql
CREATE TABLE promotion_test (id serial, message text);
```

```sql
INSERT INTO promotion_test (message) VALUES ('replica promoted successfully');
```

```sql
SELECT * FROM promotion_test;
```

Expected output (yours will differ):

```
 id |           message
----+------------------------------
  1 | replica promoted successfully
```

```sql
SELECT pg_is_in_recovery();
```

Expected output:

```
 pg_is_in_recovery
-------------------
 f
```

The `f` (false) confirms this server is no longer in recovery - it is a full read-write primary.

Exit psql.

```sql
\q
```

---

### Task 9 - Create a Cross-Region Replica

For disaster recovery, create a replica in a different region. The `--location` flag sets the target region.

```bash
az postgres flexible-server replica create \
  --resource-group suta-pg-lab-rg \
  --replica-name suta-pg-lab-replica-west \
  --source-server suta-pg-lab-server \
  --location westus
```

Expected output (yours will differ):

```json
{
  "location": "westus",
  "name": "suta-pg-lab-replica-west",
  "replicationRole": "AsyncReplica",
  "state": "Ready"
}
```

Cross-region replicas have higher replication lag due to network distance. Typical lag is 1-5 seconds depending on write volume.

---

### Task 10 - Clean Up

Delete the replicas and the promoted server.

```bash
az postgres flexible-server delete \
  --resource-group suta-pg-lab-rg \
  --name suta-pg-lab-replica1 \
  --yes
```

```bash
az postgres flexible-server delete \
  --resource-group suta-pg-lab-rg \
  --name suta-pg-lab-replica-west \
  --yes
```

---

## Checklist

- [ ] Source server is General Purpose or Memory Optimized tier
- [ ] Read replica created successfully
- [ ] Replication lag checked via psql (should be sub-second)
- [ ] Replica confirmed read-only (writes fail)
- [ ] Replication lag checked via Azure metrics
- [ ] Replica promoted to standalone server
- [ ] Promoted server accepts writes
- [ ] Cross-region replica created
- [ ] All replicas cleaned up
