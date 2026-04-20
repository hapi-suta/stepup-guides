# USE Exercise 04 - Point-in-Time Recovery Precision

| | |
|---|---|
| **Time** | 25 minutes |
| **What you'll practice** | Performing a precise point-in-time recovery (PITR), understanding timelines, and recovering to an exact moment before a bad operation |
| **Prerequisites** | Completed BUILD guides 01-06 (pgBackRest installed, backups taken, basic restore and PITR experience) |

---

## The Scenario

A developer calls you in a panic:

> "I just ran a DELETE without a WHERE clause on the employees table. I think it deleted everything. Can you undo it?"

You need to recover the database to the exact moment before the DELETE happened. Not a second after. This is point-in-time recovery (PITR) - the most precise and powerful tool in a DBA's toolkit.

In this exercise, you will simulate this scenario: insert marker rows at known times, simulate the bad DELETE, then recover to the exact right moment.

---

## Exercise 1: Take a Pre-Test Backup

Before doing anything, take a fresh full backup. This gives you a clean starting point.

Switch to the postgres user:

```bash
sudo -i -u postgres
```

Take a full backup:

```bash
pgbackrest --stanza=main --type=full backup
```

Expected output (yours will differ):

```
2026-04-20 16:30:00.123 P00   INFO: backup command begin 2.54: ...
2026-04-20 16:30:00.456 P00   INFO: execute non-exclusive backup start
...
2026-04-20 16:32:30.789 P00   INFO: new backup label = 20260420-163000F
2026-04-20 16:32:31.012 P00   INFO: full backup command end: completed successfully
```

> **Concept: Always Backup Before Risky Operations**
> Before doing anything that modifies data or tests recovery, take a fresh backup. This gives you a known-good state to return to if something goes wrong during your test.

---

## Exercise 2: Record Your Starting Data

Connect to appdb and check the current state:

```bash
psql -d appdb
```

Count the current rows:

```sql
SELECT COUNT(*) FROM employees;
```

Write this number down. This is your baseline.

Now check the current time - you will need precise timestamps:

```sql
SELECT now();
```

Expected output (yours will differ):

```
              now
-------------------------------
 2026-04-20 16:35:00.123456+00
(1 row)
```

Stay connected to psql for the next exercises.

---

## Exercise 3: Insert Marker Rows at Known Times

You will insert three marker rows with deliberate pauses between them. Record the EXACT time of each insert. These timestamps are critical for the PITR.

Insert MARKER_ONE and record the time:

```sql
INSERT INTO employees (name, department_id) VALUES ('MARKER_ONE', 1);
```

```sql
SELECT now() AS marker_one_time;
```

Expected output (yours will differ):

```
        marker_one_time
-------------------------------
 2026-04-20 16:36:00.123456+00
(1 row)
```

**Write down this exact timestamp.** Label it T1.

Now force a WAL switch so this insert is archived:

```sql
SELECT pg_switch_wal();
```

Wait 10 seconds. This creates a clear time gap between markers.

Insert MARKER_TWO and record the time:

```sql
INSERT INTO employees (name, department_id) VALUES ('MARKER_TWO', 1);
```

```sql
SELECT now() AS marker_two_time;
```

**Write down this exact timestamp.** Label it T2.

Force another WAL switch:

```sql
SELECT pg_switch_wal();
```

Wait 10 seconds again.

Insert MARKER_THREE and record the time:

```sql
INSERT INTO employees (name, department_id) VALUES ('MARKER_THREE', 1);
```

```sql
SELECT now() AS marker_three_time;
```

**Write down this exact timestamp.** Label it T3.

Force one more WAL switch:

```sql
SELECT pg_switch_wal();
```

Verify all three markers exist:

```sql
SELECT id, name FROM employees WHERE name LIKE 'MARKER%' ORDER BY id;
```

Expected output (yours will differ):

```
 id  |     name
-----+--------------
 108 | MARKER_ONE
 109 | MARKER_TWO
 110 | MARKER_THREE
(3 rows)
```

> **Concept: WAL Switches and PITR**
> Each `pg_switch_wal()` forces the current WAL segment to be closed and archived. This ensures the INSERT is recorded in an archived WAL file before you move on. Without this, the data might still be in the current (not yet archived) WAL segment, and PITR could not replay it.

---

## Exercise 4: Simulate the Disaster

This is the moment the developer runs the bad DELETE. First, record the time:

```sql
SELECT now() AS disaster_time;
```

**Write down this timestamp.** Label it T_DISASTER.

Now simulate the bad DELETE:

```sql
DELETE FROM employees WHERE name LIKE 'MARKER%';
```

Expected output:

```
DELETE 3
```

Verify the markers are gone:

```sql
SELECT COUNT(*) FROM employees WHERE name LIKE 'MARKER%';
```

Expected output:

```
 count
-------
     0
(1 row)
```

The markers are gone. In a real scenario, this could be thousands of rows of critical business data.

Exit psql:

```sql
\q
```

> **Concept: The DELETE Problem**
> Unlike some operations, a committed DELETE cannot be undone with a simple "undo" button. The rows are gone. Your only options are: (1) recover from a backup with PITR, or (2) query a replica if one exists. PITR is the most reliable option.

---

## Exercise 5: Stop PostgreSQL

To perform a PITR, you must stop the database server first.

```bash
pg_ctl -D /opt/pgsql/data stop
```

Expected output:

```
waiting for server to shut down.... done
server stopped
```

Verify it is stopped:

```bash
pg_ctl -D /opt/pgsql/data status
```

Expected output:

```
pg_ctl: no server running
```

---

## Exercise 6: Choose Your Recovery Target

This is the most critical decision in PITR: choosing the exact timestamp.

You have these timestamps from your notes:
- **T1** - When MARKER_ONE was inserted
- **T2** - When MARKER_TWO was inserted
- **T3** - When MARKER_THREE was inserted
- **T_DISASTER** - When the DELETE happened

Your goal: recover to a point AFTER MARKER_TWO was inserted but BEFORE MARKER_THREE was inserted.

The recovery target should be a timestamp between T2 and T3. A safe choice is a few seconds after T2.

For example, if T2 was `2026-04-20 16:36:15.123456+00`, your target might be `2026-04-20 16:36:18+00` (3 seconds later, before T3).

**Write down your chosen recovery target timestamp.** You will use it in the next step.

> **Concept: PITR Timestamp Precision**
> PITR stops replaying WAL records at the first transaction whose commit timestamp is after your target. This means you get every transaction committed before your target time, and none committed after it. Choose a timestamp that is clearly after the last "good" transaction and clearly before the first "bad" transaction.

---

## Exercise 7: Perform the PITR Restore

Now restore the backup with a specific time target. Replace the timestamp below with YOUR chosen recovery target from Exercise 6.

```bash
pgbackrest --stanza=main --type=time --target="2026-04-20 16:36:18+00" --target-action=promote --delta restore
```

Let's break down each flag:

- `--type=time` - Tells pgBackRest to do a point-in-time recovery based on a timestamp.
- `--target="..."` - The exact timestamp to recover to. Replace this with YOUR timestamp.
- `--target-action=promote` - After reaching the target, promote the server to accept writes.
- `--delta` - Only restore files that are different from what is already on disk. This is faster than a full restore and is safe to use here because we stopped PostgreSQL cleanly.

Expected output (yours will differ):

```
2026-04-20 16:40:00.123 P00   INFO: restore command begin 2.54: ...
2026-04-20 16:40:00.456 P00   INFO: repo1: restore backup set 20260420-163000F
2026-04-20 16:40:15.789 P00   INFO: write updated /opt/pgsql/data/postgresql.auto.conf
2026-04-20 16:40:16.012 P00   INFO: restore command end: completed successfully
...
```

> **Concept: --delta Restores**
> The `--delta` flag tells pgBackRest to compare existing files with the backup and only replace files that are different. Without `--delta`, pgBackRest removes the entire data directory and restores everything from scratch. Delta is faster but requires that the existing files came from a valid previous state.

---

## Exercise 8: Start PostgreSQL and Watch Recovery

Start PostgreSQL:

```bash
pg_ctl -D /opt/pgsql/data -l /opt/pgsql/log/recovery.log start
```

Expected output:

```
waiting for server to start.... done
server started
```

Check the recovery log to see what happened:

```bash
tail -20 /opt/pgsql/log/recovery.log
```

Expected output (yours will differ):

```
LOG:  starting PostgreSQL 16.x ...
LOG:  redo starts at 0/5000028
LOG:  consistent recovery state reached at 0/5000100
LOG:  recovery stopping before commit of transaction 789, time 2026-04-20 16:36:25.123456+00
LOG:  redo done at 0/6000050 system usage: ...
LOG:  last completed transaction was at log time 2026-04-20 16:36:15.789012+00
LOG:  selected new timeline ID: 2
LOG:  archive recovery complete
LOG:  database system is ready to accept connections
...
```

Key lines to look for:
- **"recovery stopping before commit of transaction..."** - This confirms PostgreSQL stopped at the right point.
- **"selected new timeline ID: 2"** - The database is now on a new timeline (more on this in Exercise 10).
- **"database system is ready to accept connections"** - Recovery is complete.

---

## Exercise 9: Verify the PITR Was Accurate

This is the moment of truth. Connect to appdb and check the markers.

```bash
psql -d appdb
```

Check for marker rows:

```sql
SELECT id, name FROM employees WHERE name LIKE 'MARKER%' ORDER BY id;
```

Expected output (yours will differ):

```
 id  |    name
-----+------------
 108 | MARKER_ONE
 109 | MARKER_TWO
(2 rows)
```

**Verify these three things:**

1. MARKER_ONE exists (it was inserted before your recovery target) - YES
2. MARKER_TWO exists (it was inserted before your recovery target) - YES
3. MARKER_THREE does NOT exist (it was inserted after your recovery target) - YES

If all three checks pass, your PITR was successful. You recovered to the exact right moment.

Check the total employee count:

```sql
SELECT COUNT(*) FROM employees;
```

This should be your original baseline count plus 2 (for MARKER_ONE and MARKER_TWO, but without MARKER_THREE).

Exit psql:

```sql
\q
```

> **Concept: PITR Is Surgical**
> You just recovered to a specific moment in time with second-level precision. Every transaction committed before your target is present. Every transaction committed after your target is gone. This is why continuous WAL archiving is so valuable - it makes this kind of precision recovery possible.

---

## Exercise 10: Take a New Full Backup

After a PITR, you MUST take a new full backup. This is not optional.

```bash
pgbackrest --stanza=main --type=full backup
```

Expected output (yours will differ):

```
2026-04-20 16:45:00.123 P00   INFO: backup command begin 2.54: ...
...
2026-04-20 16:47:30.789 P00   INFO: new backup label = 20260420-164500F
2026-04-20 16:47:31.012 P00   INFO: full backup command end: completed successfully
```

**Why is this mandatory?**

When you did the PITR, PostgreSQL created a new timeline (timeline 2). The old backups were taken on timeline 1. Differential and incremental backups taken on the old timeline cannot be used as a base for backups on the new timeline. You need a fresh full backup on the new timeline.

Check the info to confirm:

```bash
pgbackrest --stanza=main info
```

You should see the new backup listed.

> **Concept: Timelines and PITR**
> Every time you do a PITR, PostgreSQL creates a new timeline. Think of it like a fork in the road - you went back in time and took a different path forward. Old WAL files from before the fork are still valid (they are on the original timeline), but new WAL files will be on the new timeline. Old backups cannot be mixed with new timeline WAL, so you need a new full backup.

---

## Exercise 11: Think About What Could Go Wrong

Answer these questions:

**Question A:** What if you PITR'd to the wrong time and recovered too far back (lost more data than intended)?

You have options: (1) Stop PostgreSQL, restore again with a later target time. (2) If you took a backup before the PITR test (Exercise 1), you can restore that backup to get back to the pre-test state.

**Question B:** What if you PITR'd to the wrong time and did not go back far enough (the bad DELETE is still present)?

Stop PostgreSQL and restore again with an earlier target time. This is why the time gaps between your markers matter - they give you room to adjust.

**Question C:** What if there were no WAL archives for the time period you need?

Then PITR to that time is impossible. You can only recover to the point of the last backup. This is why continuous WAL archiving and monitoring are critical.

**Question D:** In a real incident, how would you find the exact time of the bad DELETE?

Check the PostgreSQL log files for the query. If `log_statement = 'all'` or `log_statement = 'mod'` is set, every DELETE will be logged with a timestamp. You can also check `pg_stat_activity` if the transaction is still running.

Exit back to ec2-user:

```bash
exit
```

---

## What You Learned

- How to plan and execute a precise point-in-time recovery
- How to insert marker data at known timestamps for verification
- How to use `pg_switch_wal()` to ensure data is archived before proceeding
- How to choose the correct PITR target timestamp
- How to use `--type=time`, `--target`, and `--delta` restore flags
- How to verify PITR accuracy by checking which markers survived
- Why a new full backup is mandatory after PITR (timeline changes)
- How to think through PITR mistakes and recovery strategies
