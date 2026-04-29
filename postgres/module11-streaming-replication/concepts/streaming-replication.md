# Streaming Replication

## Why This Module Matters

A single PostgreSQL server is a single point of failure. Disk fails, instance crashes,
availability zone goes down - and your application is down with it. Streaming replication
is PostgreSQL's built-in answer to this problem. It keeps one or more standby servers
synchronized with the primary in near-real-time, ready to take over when the primary
cannot.

This is not complicated technology, but it has moving parts you need to understand before
you configure it. Get the concepts wrong and you end up with a replica that is silently
falling behind, or a failover that goes sideways because you did not understand timeline IDs.

---

## Why Replication

Three reasons to run replicas, and they are all different:

**High availability** - If the primary fails, promote a standby. Downtime goes from
"however long it takes to restore a backup" to "however long it takes to detect and
promote." That is usually seconds to minutes instead of hours.

**Read scaling** - Send read-only queries to standbys. The primary handles writes.
Reporting queries, analytics, and read-heavy workloads get their own server so they
do not compete with OLTP traffic.

**Disaster recovery** - Put a standby in a different data center, region, or cloud
provider. If an entire site goes dark, you have a copy of your data somewhere else.

These three goals have different requirements. DR often accepts more lag than HA.
Read scaling requires the standby to be accessible. Understanding what you are building
replication for shapes every configuration decision.

---

## Physical vs Logical Replication

PostgreSQL supports two replication modes. They are fundamentally different.

```
  Physical Replication               Logical Replication
  -------------------                -------------------
  Replicates at byte level           Replicates at row level
  Exact block-for-block copy         Decoded into logical changes (INSERT/UPDATE/DELETE)
  Must be same major version         Can replicate across major versions
  Replicates entire cluster          Can replicate individual tables
  No filtering possible              Can filter by table, operation
  Lower overhead                     Higher overhead
  Used for HA / standby servers      Used for migrations, selective sync
```

**Streaming replication is physical replication.** The standby receives raw WAL bytes
and applies them directly to its data files. The result is a byte-for-byte identical
copy of the primary (with a very short lag).

Logical replication is separate and not covered in this module. You will encounter it
in migration scenarios.

---

## WAL Shipping - The Foundation

Before streaming replication existed, PostgreSQL replicas worked via WAL shipping:
the primary would archive completed WAL segment files (16MB each), and the standby
would copy and replay them. This was simple but had significant lag - up to 16MB of
changes could occur before a segment was shipped.

Streaming replication replaced WAL shipping for most use cases. Instead of waiting for
a full segment, the standby connects directly to the primary and receives WAL records
as they are written - a continuous stream.

WAL archiving is still useful alongside streaming replication, mainly for:
- Point-in-time recovery (you need the archived WAL to recover to an arbitrary point)
- Feeding standbys that cannot maintain a continuous connection
- pgBackRest and similar backup tools

---

## How Streaming Replication Works

```
  PRIMARY                              STANDBY
  -------                              -------
  WAL writer writes records
  to pg_wal/
       |
       v
  WAL sender process  ---WAL records--->  WAL receiver process
  (one per connected standby)             |
                                          v
                                    startup process replays
                                    WAL against data files
                                          |
                                          v
                                    data files stay in sync
```

On the primary side, a **WAL sender** process is spawned for each connected standby.
It reads WAL from `pg_wal/` (or from memory if the records are still buffered) and
streams them over a replication connection to the standby.

On the standby side, the **WAL receiver** process accepts the stream and writes it to
the standby's own `pg_wal/`. A separate recovery process (the **startup process**)
continuously reads from `pg_wal/` and applies the changes to the data files.

The standby is always in recovery mode. It cannot accept writes. It is always replaying.

---

## Synchronous vs Asynchronous Replication

**Asynchronous (default)**

The primary commits a transaction and returns success to the client immediately, without
waiting for the standby to confirm it received the WAL. The standby applies changes
slightly behind the primary. If the primary crashes before the standby receives the
latest WAL, those transactions are lost.

```
  Client          Primary         Standby
  ------          -------         -------
  COMMIT  ------> commit
  <-- OK --       (standby may not have this yet)
```

Use this when you can tolerate a small amount of data loss (seconds worth) and want
zero added latency on writes. Most production systems use async replication.

**Synchronous**

The primary waits for the standby to confirm it wrote the WAL to disk before returning
success to the client. No data loss on failover (RPO = 0), but every write waits for
the round-trip to the standby. Network latency between primary and standby becomes
write latency for your application.

```
  Client          Primary         Standby
  ------          -------         -------
  COMMIT  ------> write WAL
                  wait... ------> receive WAL, write to disk
                  <-- ack --------
  <-- OK --
```

Configure it with:

```
synchronous_standby_names = 'standby1'
```

Important caveat: if the synchronous standby goes down, writes on the primary will
block indefinitely waiting for an acknowledgment that never comes. Plan for this.

---

## Hot Standby - Reading from a Replica

By default a standby in recovery mode rejects all connections. **Hot standby** lets
you run read-only queries against a replica while it is replaying WAL.

Enable it in postgresql.conf on the standby:

```
hot_standby = on
```

With hot standby on, the standby accepts read-only connections. Queries run against
whatever data the standby has replayed so far. If the standby is lagging, you will see
data that is slightly behind the primary - this is called **replication lag**.

Applications need to be designed to handle this. A query on the standby will not see
data committed on the primary in the last N seconds (where N is the current lag). For
reporting workloads this is usually fine. For read-your-own-writes patterns, it is not.

---

## Replication Slots

Here is a scenario: you have a standby. It goes offline for maintenance for 4 hours.
During those 4 hours, the primary generates WAL. PostgreSQL's WAL recycling is
aggressive - it will delete old WAL segments to reclaim disk space. When the standby
comes back, it needs WAL from 4 hours ago. That WAL might be gone.

**Replication slots** solve this. A slot is a named marker on the primary that says
"this standby needs WAL back to this point - do not delete it."

```sql
-- Create a replication slot on the primary
SELECT pg_create_physical_replication_slot('standby1');

-- Check slot status
SELECT slot_name, active, restart_lsn FROM pg_replication_slots;
```

Configure the standby to use the slot:

```
primary_slot_name = 'standby1'
```

The risk of slots: if a standby using a slot is offline for a long time and you forget
about it, the primary will accumulate WAL indefinitely. Disk fills up. Primary crashes.
Monitor your slots. If a standby is permanently gone, drop its slot:

```sql
SELECT pg_drop_replication_slot('standby1');
```

---

## Monitoring Replication

On the primary, `pg_stat_replication` shows every connected standby:

```sql
SELECT
  application_name,
  state,
  sent_lsn,
  write_lsn,
  flush_lsn,
  replay_lsn,
  write_lag,
  flush_lag,
  replay_lag
FROM pg_stat_replication;
```

Expected output (yours will differ):

```
 application_name | state     | write_lag | flush_lag | replay_lag
------------------+-----------+-----------+-----------+------------
 pg-standby       | streaming | 00:00:00  | 00:00:00  | 00:00:00.2
```

**replay_lag** is the most operationally useful column - it tells you how far behind
the standby is in terms of applying WAL to its data files.

On the standby itself:

```sql
-- Is this server in recovery (i.e., is it a standby)?
SELECT pg_is_in_recovery();

-- How far behind is this standby?
SELECT now() - pg_last_xact_replay_timestamp() AS replication_lag;
```

---

## Failover - Promoting a Standby

When the primary is gone and you decide to promote a standby, the process is
straightforward:

```bash
# On the standby server
/usr/pgsql-16/bin/pg_ctl promote -D /var/lib/pgsql/16/data
```

Or use the trigger file method (configured in advance):

```bash
touch /tmp/promote_trigger
```

After promotion, the standby stops replaying WAL and becomes a writable primary.
It creates a new timeline (see below) and is ready for connections.

What promotion does NOT do:
- It does not reconfigure your application to point at the new primary
- It does not tell other standbys to follow the new primary
- It does not fence the old primary from coming back

These are the gaps that tools like repmgr and Patroni fill.

---

## Timeline IDs

Every PostgreSQL cluster has a timeline ID. It starts at 1. When a standby is promoted,
it increments the timeline ID. This matters because after a failover, the old primary
and the new primary may have diverged WAL history.

```
  Timeline 1 (original primary)
  ----[A]----[B]----[C]----[D (primary crashed here)]

  Timeline 2 (promoted standby, became new primary)
  ----[A]----[B]----[C]----[E]----[F]----[G]

  The old primary comes back.
  It has [D] which never happened on timeline 2.
  PostgreSQL detects the timeline divergence and refuses to let it rejoin.
```

This is a safety mechanism. You cannot accidentally reconnect an old primary as a
standby if its WAL history diverged from the new primary.

If you want to reuse the old primary as a standby after a failover, you must rebuild
it from a fresh base backup of the new primary (`pg_basebackup`). It then follows
timeline 2 forward from a known-good point.

---

## Recovery Target Settings

When recovering to a point in time (PITR) or setting up a standby with archived WAL,
you can tell PostgreSQL how far to replay:

```
# In postgresql.conf (PostgreSQL 12+) or recovery.conf (PostgreSQL 11 and earlier)

restore_command = 'cp /opt/pgsql/wal/%f %p'         # how to fetch archived WAL files
recovery_target_time = '2024-11-15 14:30:00 UTC'    # stop replay at this time
recovery_target_action = 'promote'                   # what to do when target is reached
```

**restore_command** - The shell command to fetch archived WAL files. `%f` is the
filename, `%p` is the path to write it to. This is how the standby finds WAL that
has been cleaned from the primary's `pg_wal/`.

**recovery_target_time** - Stop replaying at this exact point in time. Any transactions
committed after this timestamp will not be visible. Used for PITR restores when
recovering from human error (deleted the wrong table at 14:28? Recover to 14:27).

**recovery_target_action** - What to do when the target is reached: `promote` (start
accepting writes), `pause` (stop and wait for manual intervention), or `shutdown`.

---

## What to Watch For in the Lab

You will configure a primary and standby from scratch. Watch for:

- The replication user in pg_hba.conf - replication connections use a different auth type
- The base backup step (`pg_basebackup`) - this seeds the standby from the primary
- `pg_stat_replication` on the primary showing the standby connected
- What happens to `replay_lag` when you pause the standby
- The promotion sequence and what changes in the data directory afterward

The most common mistakes: forgetting the replication entry in pg_hba.conf (standby
connects but authentication fails), and not setting `wal_level = replica` on the
primary (streaming works but hot standby cannot be enabled).
