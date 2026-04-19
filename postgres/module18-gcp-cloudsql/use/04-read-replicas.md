# USE 04 - Read Replicas

## Objective

Create read replicas (same region and cross-region), monitor replication lag, and promote a replica to a standalone instance.

---

## Exercise 1 - Create a Read Replica

Create a read replica in the same region as the primary. The `--master-instance-name` flag specifies the source instance.

```bash
gcloud sql instances create suta-pg-replica1 \
  --master-instance-name=suta-pg-lab \
  --tier=db-custom-2-7680 \
  --region=us-central1
```

This takes 5-10 minutes. Cloud SQL uses PostgreSQL streaming replication under the hood.

Expected output (yours will differ):

```
Creating Cloud SQL instance...done.
Created [https://sqladmin.googleapis.com/sql/v1beta4/projects/my-project/instances/suta-pg-replica1].
NAME               DATABASE_VERSION  LOCATION       TIER              STATUS
suta-pg-replica1   POSTGRES_16       us-central1-b  db-custom-2-7680  RUNNABLE
```

Verify the replica.

```bash
gcloud sql instances describe suta-pg-replica1 --format="yaml(name,masterInstanceName,replicaConfiguration,state)"
```

Expected output (yours will differ):

```yaml
masterInstanceName: suta-pg-lab
name: suta-pg-replica1
state: RUNNABLE
```

---

## Exercise 2 - Check Replication Lag

Get the replica IP.

```bash
gcloud sql instances describe suta-pg-replica1 --format="value(ipAddresses[0].ipAddress)"
```

Connect to the replica.

```bash
psql -h [REPLICA_IP] -U postgres -d suta_lab
```

Check replication lag. This view is available on the replica.

```sql
SELECT
    now() - pg_last_xact_replay_timestamp() AS replication_lag,
    pg_last_xact_replay_timestamp() AS last_replay,
    pg_is_in_recovery() AS is_replica;
```

Expected output (yours will differ):

```
 replication_lag |       last_replay        | is_replica
-----------------+--------------------------+------------
 00:00:00.123456 | 2026-04-19 14:30:00+00   | t
(1 row)
```

The `is_replica` column confirms this is a read replica. Replication lag should be under 1 second.

Verify data is replicated. The students table from the primary should be here.

```sql
SELECT count(*) FROM students;
```

Try to write to the replica. This should fail.

```sql
INSERT INTO students (name, email) VALUES ('Test', 'test@example.com');
```

Expected output (yours will differ):

```
ERROR:  cannot execute INSERT in a read-only transaction
```

Replicas are read-only. This is enforced by PostgreSQL's recovery mode.

Type `\q` to exit psql.

```
\q
```

---

## Exercise 3 - Monitor Replication via gcloud

Check replication lag using Cloud Monitoring metrics.

```bash
gcloud sql instances describe suta-pg-replica1 --format="yaml(replicaConfiguration)"
```

List all replicas of the primary.

```bash
gcloud sql instances describe suta-pg-lab --format="yaml(replicaNames)"
```

Expected output (yours will differ):

```yaml
replicaNames:
- suta-pg-replica1
```

---

## Exercise 4 - Create a Cross-Region Replica

Create a replica in a different region for disaster recovery.

```bash
gcloud sql instances create suta-pg-replica-east \
  --master-instance-name=suta-pg-lab \
  --tier=db-custom-2-7680 \
  --region=us-east1
```

This takes 5-10 minutes. Cross-region replication adds network latency but provides geographic redundancy.

Verify both replicas.

```bash
gcloud sql instances describe suta-pg-lab --format="yaml(replicaNames)"
```

Expected output (yours will differ):

```yaml
replicaNames:
- suta-pg-replica1
- suta-pg-replica-east
```

Check lag on the cross-region replica. It will be higher than the same-region replica.

```bash
psql -h [CROSS_REGION_REPLICA_IP] -U postgres -d suta_lab
```

```sql
SELECT
    now() - pg_last_xact_replay_timestamp() AS replication_lag,
    pg_is_in_recovery() AS is_replica;
```

Type `\q` to exit psql.

```
\q
```

---

## Exercise 5 - Promote a Replica

Promoting a replica makes it a standalone read-write instance. It permanently breaks replication.

WARNING: Promotion is irreversible. The promoted instance becomes independent.

Promote the same-region replica.

```bash
gcloud sql instances promote-replica suta-pg-replica1
```

Type `Y` when prompted.

Expected output (yours will differ):

```
Promoting Cloud SQL replica...done.
```

Verify the replica is now a standalone instance.

```bash
gcloud sql instances describe suta-pg-replica1 --format="yaml(masterInstanceName,state)"
```

Expected output (yours will differ):

```yaml
state: RUNNABLE
```

The `masterInstanceName` field is gone - it is now independent.

Connect and verify you can write.

```bash
psql -h [PROMOTED_IP] -U postgres -d suta_lab
```

```sql
INSERT INTO students (name, email) VALUES ('Promoted Test', 'promoted@example.com');
```

```sql
SELECT * FROM students WHERE email = 'promoted@example.com';
```

Expected output (yours will differ):

```
 student_id |     name      |        email         |         enrolled_at
------------+---------------+----------------------+-------------------------------
          6 | Promoted Test | promoted@example.com | 2026-04-19 15:00:00.123456+00
(1 row)
```

Write operations now work on the promoted instance.

Type `\q` to exit psql.

```
\q
```

---

## Cleanup

Delete the promoted instance and cross-region replica.

```bash
gcloud sql instances delete suta-pg-replica1
```

```bash
gcloud sql instances delete suta-pg-replica-east
```

---

## Checklist

- [ ] Created same-region read replica
- [ ] Verified replication lag under 1 second
- [ ] Confirmed replica is read-only
- [ ] Created cross-region replica
- [ ] Compared lag between same-region and cross-region
- [ ] Promoted replica to standalone
- [ ] Verified write operations on promoted instance
