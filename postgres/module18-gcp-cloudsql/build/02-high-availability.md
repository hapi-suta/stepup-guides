# BUILD 02 - Cloud SQL for PostgreSQL: High Availability

## What You Will Build

A highly available Cloud SQL instance with regional availability, automatic failover, and a failover replica. You will test failover and observe how Cloud SQL handles it transparently.

---

## Prerequisites

- Completed BUILD 01 (instance `suta-pg-lab` exists and is running)
- `gcloud` CLI authenticated and project set

---

## Step 1 - Understand Cloud SQL HA Architecture

Cloud SQL HA uses a regional configuration with two zones:

- **Primary instance**: Runs in one zone (e.g., us-central1-a)
- **Standby instance**: Runs in another zone (e.g., us-central1-f)
- **Shared regional disk**: Data is written to a regional persistent disk that replicates synchronously across both zones

This is NOT streaming replication. Cloud SQL uses Google's regional persistent disk technology. The standby is a hot standby that can take over the same disk.

When failover happens:
1. Cloud SQL detects the primary is unhealthy (about 60 seconds)
2. The standby takes over the regional persistent disk
3. The standby becomes the new primary
4. The IP address stays the same - apps reconnect automatically
5. Total downtime is typically 30-120 seconds

---

## Step 2 - Enable HA on an Existing Instance

Check the current availability type. The `--format` flag extracts just the field we need.

```bash
gcloud sql instances describe suta-pg-lab --format="value(settings.availabilityType)"
```

Expected output (yours will differ):

```
ZONAL
```

Upgrade to regional HA. The `--availability-type` flag controls this. Changing from ZONAL to REGIONAL creates a standby in another zone.

```bash
gcloud sql instances patch suta-pg-lab --availability-type=REGIONAL
```

Expected output (yours will differ):

```
Patching Cloud SQL instance...done.
```

This takes 5-10 minutes. Cloud SQL creates a standby instance in a different zone.

Verify HA is enabled.

```bash
gcloud sql instances describe suta-pg-lab --format="yaml(settings.availabilityType,gceZone,secondaryGceZone)"
```

Expected output (yours will differ):

```yaml
gceZone: us-central1-a
secondaryGceZone: us-central1-f
settings:
  availabilityType: REGIONAL
```

The `gceZone` is where the primary runs. The `secondaryGceZone` is where the standby runs. Google chooses the secondary zone automatically.

---

## Step 3 - Understand Failover Triggers

Cloud SQL triggers automatic failover when:

- The primary instance becomes unresponsive
- The primary zone has an outage
- The primary instance crashes
- A maintenance event requires it (during the maintenance window)

You can also trigger a manual failover for testing.

---

## Step 4 - Test Manual Failover

Before triggering failover, note the current primary zone.

```bash
gcloud sql instances describe suta-pg-lab --format="value(gceZone)"
```

Expected output (yours will differ):

```
us-central1-a
```

Connect to the instance and create a marker to verify data survives failover.

```bash
psql -h 127.0.0.1 -U postgres -d suta_lab
```

Create a failover test record.

```sql
CREATE TABLE IF NOT EXISTS failover_test (
    id SERIAL PRIMARY KEY,
    tested_at TIMESTAMPTZ DEFAULT now(),
    note TEXT
);
```

```sql
INSERT INTO failover_test (note) VALUES ('pre-failover marker');
```

```sql
SELECT * FROM failover_test;
```

Expected output (yours will differ):

```
 id |          tested_at           |        note
----+------------------------------+--------------------
  1 | 2026-04-19 11:00:00.123+00   | pre-failover marker
(1 row)
```

Type `\q` to exit psql.

```
\q
```

Trigger a manual failover. The `--async` flag returns immediately instead of waiting. Remove it if you want to wait for completion.

```bash
gcloud sql instances failover suta-pg-lab
```

Type `Y` when prompted.

Expected output (yours will differ):

```
Failing over Cloud SQL instance...done.
```

This takes 1-3 minutes. During this time, connections will be dropped.

---

## Step 5 - Verify After Failover

Check which zone is now the primary. It should have swapped.

```bash
gcloud sql instances describe suta-pg-lab --format="yaml(gceZone,secondaryGceZone)"
```

Expected output (yours will differ):

```yaml
gceZone: us-central1-f
secondaryGceZone: us-central1-a
```

The zones swapped. The former standby (us-central1-f) is now the primary.

Reconnect and verify data survived.

```bash
psql -h 127.0.0.1 -U postgres -d suta_lab
```

```sql
SELECT * FROM failover_test;
```

Expected output (yours will differ):

```
 id |          tested_at           |        note
----+------------------------------+--------------------
  1 | 2026-04-19 11:00:00.123+00   | pre-failover marker
(1 row)
```

The data is intact. Zero data loss because Cloud SQL uses synchronous regional disk replication.

Insert a post-failover marker.

```sql
INSERT INTO failover_test (note) VALUES ('post-failover - new primary working');
```

```sql
SELECT * FROM failover_test;
```

Expected output (yours will differ):

```
 id |          tested_at           |                note
----+------------------------------+-------------------------------------
  1 | 2026-04-19 11:00:00.123+00   | pre-failover marker
  2 | 2026-04-19 11:05:00.456+00   | post-failover - new primary working
(2 rows)
```

Type `\q` to exit psql.

```
\q
```

---

## Step 6 - Configure Maintenance Windows

Maintenance windows control when Google applies updates, patches, and maintenance. During maintenance on an HA instance, Cloud SQL performs a failover to minimize downtime.

Set the maintenance window. The `--maintenance-window-day` accepts SUN through SAT (or 1-7). The `--maintenance-window-hour` is in UTC.

```bash
gcloud sql instances patch suta-pg-lab \
  --maintenance-window-day=SUN \
  --maintenance-window-hour=3
```

Expected output (yours will differ):

```
Patching Cloud SQL instance...done.
```

Set the maintenance update preference. `canary` gets updates early (good for non-prod), `stable` gets them later (good for prod).

```bash
gcloud sql instances patch suta-pg-lab \
  --maintenance-release-channel=production
```

Verify maintenance settings.

```bash
gcloud sql instances describe suta-pg-lab --format="yaml(settings.maintenanceWindow)"
```

Expected output (yours will differ):

```yaml
settings:
  maintenanceWindow:
    day: 7
    hour: 3
    updateTrack: stable
```

Day 7 is Sunday. Hour 3 is 3:00 AM UTC.

---

## Step 7 - Monitor HA Status

Check the instance state. A healthy HA instance shows `RUNNABLE`.

```bash
gcloud sql instances describe suta-pg-lab --format="value(state)"
```

Expected output (yours will differ):

```
RUNNABLE
```

List recent operations on the instance. This shows failovers, patches, and restarts.

```bash
gcloud sql operations list --instance=suta-pg-lab --limit=10
```

Expected output (yours will differ):

```
NAME                                  TYPE      STATUS  START_TIME                   END_TIME
abc123-def456                         FAILOVER  DONE    2026-04-19T11:00:00.000Z     2026-04-19T11:02:30.000Z
xyz789-abc012                         UPDATE    DONE    2026-04-19T10:45:00.000Z     2026-04-19T10:50:00.000Z
...
```

---

## Step 8 - Understand Failover Behavior for Applications

When failover happens, your application experiences:

1. **Connection drop**: All existing connections are terminated
2. **Brief DNS propagation**: The instance IP stays the same, but it takes a moment to route
3. **Reconnection**: Applications must implement retry logic

If you are using the Cloud SQL Auth Proxy, it handles reconnection automatically. This is one of the key reasons to use the proxy.

For direct connections, your application should:

- Use connection pooling (pgBouncer or built-in pool)
- Implement exponential backoff on connection failures
- Set a reasonable `connect_timeout` (5-10 seconds)
- Set `target_session_attrs=read-write` in the connection string to verify the primary

Example connection string with failover awareness:

```
postgresql://postgres:[PASSWORD]@[IP]:5432/suta_lab?connect_timeout=10&target_session_attrs=read-write
```

---

## Step 9 - Failover Back (Optional)

Trigger another failover to return to the original zone.

```bash
gcloud sql instances failover suta-pg-lab
```

Verify the zones swapped back.

```bash
gcloud sql instances describe suta-pg-lab --format="yaml(gceZone,secondaryGceZone)"
```

Expected output (yours will differ):

```yaml
gceZone: us-central1-a
secondaryGceZone: us-central1-f
```

---

## Step 10 - HA Cost Considerations

Regional HA doubles certain costs:

| Component | Zonal | Regional HA |
|---|---|---|
| Compute | 1x | 2x (primary + standby) |
| Storage | 1x | 1x (shared regional disk) |
| Network | Standard | Standard |
| Backups | Same | Same |

The standby instance is the same tier as the primary. You cannot use a smaller standby.

For non-production environments, consider staying with ZONAL and relying on backups for recovery.

---

## Summary

| Task | Command |
|---|---|
| Enable HA | `gcloud sql instances patch --availability-type=REGIONAL` |
| Check zones | `gcloud sql instances describe --format="yaml(gceZone,secondaryGceZone)"` |
| Trigger failover | `gcloud sql instances failover [INSTANCE]` |
| Set maintenance window | `gcloud sql instances patch --maintenance-window-day= --maintenance-window-hour=` |
| List operations | `gcloud sql operations list --instance=[INSTANCE]` |

You now have a regionally available Cloud SQL instance that survives zone outages with automatic failover and zero data loss.
