# BUILD 02 - High Availability for Azure Database for PostgreSQL Flexible Server

## Overview

In this guide you will configure high availability (HA) for your Flexible Server. You will learn the difference between zone-redundant and same-zone HA, understand the failover mechanics, and test both planned and automatic failover.

---

## Prerequisites

- Completed BUILD 01 (server created and accessible)
- Azure CLI authenticated
- A Flexible Server running on General Purpose or Memory Optimized tier (Burstable does not support HA)

---

## Step 1 - Understand HA Options

Azure Flexible Server supports two HA modes:

| Mode | Description | RPO | RTO | Cost |
|------|-------------|-----|-----|------|
| Zone-redundant | Standby in a different availability zone | 0 (sync replication) | 60-120 seconds | ~2x compute cost |
| Same-zone | Standby in the same availability zone | 0 (sync replication) | 60-120 seconds | ~2x compute cost |

**Zone-redundant HA** protects against zone-level failures (entire datacenter goes down). The standby runs in a different availability zone.

**Same-zone HA** protects against server-level failures (single VM goes down). The standby runs in the same zone, so it does not protect against zone outages.

Both modes use synchronous replication - every committed transaction is written to both primary and standby before the client gets confirmation.

---

## Step 2 - Upgrade to General Purpose Tier

HA requires General Purpose or Memory Optimized tier. If your server is Burstable, upgrade it first. The `--sku-name` flag specifies the new compute SKU. The `--tier` flag sets the tier.

```bash
az postgres flexible-server update \
  --resource-group suta-pg-lab-rg \
  --name suta-pg-lab-server \
  --sku-name Standard_D2ds_v4 \
  --tier GeneralPurpose
```

Expected output (yours will differ):

```json
{
  "sku": {
    "name": "Standard_D2ds_v4",
    "tier": "GeneralPurpose"
  }
}
```

This causes a brief restart while the server moves to the new compute tier. Wait for the command to complete.

---

## Step 3 - Enable Zone-Redundant HA

Enable zone-redundant HA. The `--high-availability` flag sets the HA mode. The `--standby-zone` flag picks which availability zone the standby should run in (1, 2, or 3).

```bash
az postgres flexible-server update \
  --resource-group suta-pg-lab-rg \
  --name suta-pg-lab-server \
  --high-availability ZoneRedundant \
  --standby-zone 2
```

Expected output (yours will differ):

```json
{
  "highAvailability": {
    "mode": "ZoneRedundant",
    "standbyAvailabilityZone": "2",
    "state": "Healthy"
  }
}
```

Provisioning the standby takes 5-10 minutes. The server remains available during this time.

---

## Step 4 - Enable Same-Zone HA

If you prefer same-zone HA instead (cheaper in some configurations, does not protect against zone failures), use `SameZone` for the mode. You do not specify a standby zone.

```bash
az postgres flexible-server update \
  --resource-group suta-pg-lab-rg \
  --name suta-pg-lab-server \
  --high-availability SameZone
```

Expected output (yours will differ):

```json
{
  "highAvailability": {
    "mode": "SameZone",
    "state": "Healthy"
  }
}
```

---

## Step 5 - Verify HA Status

Check the current HA configuration and health.

```bash
az postgres flexible-server show \
  --resource-group suta-pg-lab-rg \
  --name suta-pg-lab-server \
  --query "{Name:name, HAMode:highAvailability.mode, HAState:highAvailability.state, StandbyZone:highAvailability.standbyAvailabilityZone, PrimaryZone:availabilityZone}" \
  --output table
```

Expected output (yours will differ):

```
Name                 HAMode          HAState  StandbyZone  PrimaryZone
-------------------  --------------  -------  -----------  -----------
suta-pg-lab-server   ZoneRedundant   Healthy  2            1
```

The `HAState` should be `Healthy`. If it says `NotEnabled` or `CreatingStandby`, wait a few minutes and check again.

---

## Step 6 - Understand Failover Mechanics

There are two types of failover:

**Automatic failover** - Azure detects the primary is unhealthy and promotes the standby automatically. This happens when:
- The primary VM becomes unavailable
- The primary zone experiences an outage (zone-redundant only)
- There is an unplanned restart of the primary

**Planned failover** - You manually trigger a failover for testing or maintenance. The sequence is:
1. Azure drains connections on the primary
2. The standby catches up on any remaining WAL
3. The standby promotes to primary
4. The old primary becomes the new standby
5. DNS updates to point to the new primary

In both cases, existing connections are dropped. Your application must handle reconnection.

---

## Step 7 - Create a Test Table Before Failover

Connect to the server and create a table with data. This lets you verify data survives the failover.

```bash
psql "host=suta-pg-lab-server.postgres.database.azure.com port=5432 dbname=postgres user=pgadmin sslmode=require"
```

Once connected, create a test table and insert data.

```sql
CREATE TABLE failover_test (
    id serial PRIMARY KEY,
    message text NOT NULL,
    created_at timestamptz DEFAULT now()
);
```

```sql
INSERT INTO failover_test (message)
VALUES ('before-failover-1'), ('before-failover-2'), ('before-failover-3');
```

Verify the data.

```sql
SELECT * FROM failover_test;
```

Expected output (yours will differ):

```
 id |      message       |          created_at
----+--------------------+-------------------------------
  1 | before-failover-1  | 2026-04-19 14:30:00.123456+00
  2 | before-failover-2  | 2026-04-19 14:30:00.123789+00
  3 | before-failover-3  | 2026-04-19 14:30:00.124012+00
```

Exit psql.

```sql
\q
```

---

## Step 8 - Perform a Planned Failover

Trigger a planned failover. This swaps the primary and standby roles. The `--failover-mode` flag can be `PlannedFailover` or `ForcedFailover`.

```bash
az postgres flexible-server restart \
  --resource-group suta-pg-lab-rg \
  --name suta-pg-lab-server \
  --failover Forced
```

Expected output (yours will differ):

```
Command ran in 90 seconds.
```

Planned failover typically takes 60-120 seconds. During this time, connections are dropped.

---

## Step 9 - Verify After Failover

Check the server status after failover. Notice the primary and standby zones should have swapped.

```bash
az postgres flexible-server show \
  --resource-group suta-pg-lab-rg \
  --name suta-pg-lab-server \
  --query "{Name:name, HAMode:highAvailability.mode, HAState:highAvailability.state, StandbyZone:highAvailability.standbyAvailabilityZone, PrimaryZone:availabilityZone, State:state}" \
  --output table
```

Expected output (yours will differ):

```
Name                 HAMode          HAState  StandbyZone  PrimaryZone  State
-------------------  --------------  -------  -----------  -----------  -----
suta-pg-lab-server   ZoneRedundant   Healthy  1            2            Ready
```

Notice the `PrimaryZone` changed from 1 to 2, and `StandbyZone` changed from 2 to 1.

---

## Step 10 - Verify Data Survived Failover

Reconnect and check that your test data is intact.

```bash
psql "host=suta-pg-lab-server.postgres.database.azure.com port=5432 dbname=postgres user=pgadmin sslmode=require"
```

```sql
SELECT * FROM failover_test;
```

Expected output (yours will differ):

```
 id |      message       |          created_at
----+--------------------+-------------------------------
  1 | before-failover-1  | 2026-04-19 14:30:00.123456+00
  2 | before-failover-2  | 2026-04-19 14:30:00.123789+00
  3 | before-failover-3  | 2026-04-19 14:30:00.124012+00
```

All three rows are present. Synchronous replication ensures zero data loss.

Insert a row after failover to confirm writes work on the new primary.

```sql
INSERT INTO failover_test (message) VALUES ('after-failover');
```

```sql
SELECT * FROM failover_test ORDER BY id;
```

Expected output (yours will differ):

```
 id |      message       |          created_at
----+--------------------+-------------------------------
  1 | before-failover-1  | 2026-04-19 14:30:00.123456+00
  2 | before-failover-2  | 2026-04-19 14:30:00.123789+00
  3 | before-failover-3  | 2026-04-19 14:30:00.124012+00
  4 | after-failover     | 2026-04-19 14:32:15.456789+00
```

Exit psql.

```sql
\q
```

---

## Step 11 - Monitor Failover Events

Check the activity log for failover events. The `--query` flag filters for the last 2 hours and shows only relevant fields. The `--offset` flag limits the time window.

```bash
az monitor activity-log list \
  --resource-group suta-pg-lab-rg \
  --offset 2h \
  --query "[?contains(operationName.localizedValue, 'Failover')].{Operation:operationName.localizedValue, Status:status.localizedValue, Time:eventTimestamp}" \
  --output table
```

Expected output (yours will differ):

```
Operation                                              Status     Time
-----------------------------------------------------  ---------  -------------------------
Start Flexible Server Failover                         Succeeded  2026-04-19T14:31:00.000Z
```

---

## Step 12 - Understand Standby Architecture

The standby server has these characteristics:

- **Not directly accessible** - You cannot connect to the standby. It has no public endpoint.
- **Synchronous replication** - Uses PostgreSQL streaming replication in synchronous mode.
- **Same storage** - The standby has its own copy of the data on premium SSD.
- **Automatic rebuild** - If the standby fails, Azure automatically provisions a new one.
- **No read traffic** - Unlike read replicas, the HA standby does not accept read queries. Use read replicas for read scaling.

---

## Step 13 - Disable HA

To disable HA (for cost savings in non-production), set the mode to `Disabled`.

```bash
az postgres flexible-server update \
  --resource-group suta-pg-lab-rg \
  --name suta-pg-lab-server \
  --high-availability Disabled
```

Expected output (yours will differ):

```json
{
  "highAvailability": {
    "mode": "Disabled",
    "state": "NotEnabled"
  }
}
```

The standby is decommissioned and you stop paying for the extra compute.

---

## Step 14 - Clean Up Test Table

Connect and drop the test table.

```bash
psql "host=suta-pg-lab-server.postgres.database.azure.com port=5432 dbname=postgres user=pgadmin sslmode=require"
```

```sql
DROP TABLE IF EXISTS failover_test;
```

```sql
\q
```

---

## Summary

You have completed the following:

- Upgraded from Burstable to General Purpose tier
- Enabled zone-redundant and same-zone HA
- Understood automatic vs planned failover mechanics
- Performed a planned failover and verified zero data loss
- Monitored failover events in the activity log
- Learned standby architecture limitations
- Disabled HA when no longer needed

Key takeaway: HA doubles your compute cost but provides automatic failover with zero data loss and 60-120 second recovery time.
