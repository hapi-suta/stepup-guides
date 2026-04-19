# Runbook 07 - PITR Wrong Target

**Severity:** High - Recovery went past the desired point, data state is incorrect
**Time to resolve:** 15-25 minutes

---

## Fix Path

### Step 1: Understand the current state

SSH to [NODE1] and examine the pitr_marker table:

```sql
SELECT * FROM pitr_marker ORDER BY id;
```

Expected: GOOD_STATE row is missing, BAD_STATE rows are present. This means the current state is AFTER the destructive changes.

### Step 2: Review the misleading recovery notes

```bash
cat /tmp/pitr-recovery-notes.txt
```

The target time listed here is too far in the future. Recovering to this point would replay past the destructive changes - you would end up with the same bad state.

> **Concept - recovery_target_time**: This parameter tells PostgreSQL where to stop WAL replay during PITR. If set too far in the future, recovery replays all WAL including the destructive operations. The target must be BEFORE the unwanted changes occurred.

### Step 3: Find the correct recovery target

Use pg_waldump to examine WAL and find when the DELETE happened:

```bash
# Find the WAL files covering recent activity
sudo -u postgres ls -lt /opt/pgsql/data/pg_wal/ | head -10

# Scan WAL for DELETE operations on the pitr_marker table
# First get the relfilenode of pitr_marker
sudo -u postgres /usr/pgsql-16/bin/psql -p 5432 -d labdb -c \
  "SELECT pg_relation_filenode('pitr_marker');"

# Then scan WAL for that relation
sudo -u postgres /usr/pgsql-16/bin/pg_waldump /opt/pgsql/data/pg_wal/[WAL_FILE] 2>/dev/null | grep DELETE | head -5
```

Alternatively, check the PostgreSQL log for timestamps:

```bash
sudo grep -i 'pitr_marker\|GOOD_STATE' /opt/pgsql/log/postgresql-*.log
```

Or use the state file timestamp as a reference:

```bash
cat /tmp/stepup-07-state.env | grep CORRECT_TARGET
```

> **Concept - pg_waldump**: This tool decodes WAL files into human-readable format. It shows the exact LSN, timestamp, and operation for every WAL record. Use it to find the precise point where unwanted changes occurred.

### Step 4: Restore to a scratch location with the correct target

```bash
# Use the correct target time (BEFORE the DELETE, AFTER the GOOD_STATE insert)
sudo -u postgres pgbackrest --stanza=main \
  --pg1-path=/tmp/pg-pitr-scratch \
  --type=time \
  --target="[CORRECT_TIMESTAMP]" \
  --target-action=promote \
  restore
```

Start the scratch instance:

```bash
sudo -u postgres /usr/pgsql-16/bin/pg_ctl \
  -D /tmp/pg-pitr-scratch -o "-p 5433" start
```

Wait for recovery to complete and verify the state:

```bash
sudo -u postgres /usr/pgsql-16/bin/psql -p 5433 -d labdb -c "SELECT * FROM pitr_marker ORDER BY id;"
```

Expected: GOOD_STATE row exists, no BAD_STATE rows.

### Step 5: Extract the correct data

```bash
# Dump just the pitr_marker table from the scratch instance
sudo -u postgres /usr/pgsql-16/bin/pg_dump -p 5433 -d labdb -t pitr_marker -Fc -f /tmp/pitr_marker.dump
```

### Step 6: Restore the correct data to production

```bash
# Drop the current bad table and restore the good one
sudo -u postgres /usr/pgsql-16/bin/psql -p 5432 -d labdb -c "DROP TABLE IF EXISTS pitr_marker;"
/usr/pgsql-16/bin/pg_restore -h localhost -p 5432 -U postgres -d labdb /tmp/pitr_marker.dump
```

Verify:

```bash
sudo -u postgres /usr/pgsql-16/bin/psql -p 5432 -d labdb -c "SELECT * FROM pitr_marker ORDER BY id;"
```

Expected: GOOD_STATE row exists.

### Step 7: Clean up the scratch instance

```bash
sudo -u postgres /usr/pgsql-16/bin/pg_ctl -D /tmp/pg-pitr-scratch stop
rm -rf /tmp/pg-pitr-scratch
rm -f /tmp/pitr_marker.dump
```

### Step 8: Take a fresh backup

```bash
sudo -u postgres pgbackrest --stanza=main --type=diff backup
```

---

## Key Concepts for Revision

- **recovery_target_time** must be set to a timestamp BEFORE the unwanted operation. Setting it too far in the future replays everything, including the destructive changes.
- **recovery_target_action** controls what happens when the target is reached: `pause` (default in PG 12+) pauses recovery so you can inspect, `promote` promotes to read-write, `shutdown` stops the server.
- **pg_waldump** is the tool for forensic WAL analysis. It shows exact LSN and timestamps for every database operation. Essential for finding the precise recovery target.
- **recovery_target_lsn** is more precise than recovery_target_time. If two operations happen in the same second, LSN-based targeting lets you stop between them.
- **Side-restore pattern** avoids risk: restore to a scratch directory, verify the state is correct, then extract what you need. Never blindly PITR your production cluster.
- **recovery_target_inclusive** controls whether the target transaction itself is included. Default is true - the transaction AT the target time is replayed.
- **Multiple PITR attempts** are normal. If the first target is wrong, stop the scratch instance, remove it, and try again with a different target. Each attempt takes minutes, not hours.

---

## Interview Discussion Points

1. **Finding the right target**: You know "something bad happened around 3 PM." How do you narrow down the exact recovery target? What tools and techniques do you use?

2. **recovery_target_action choices**: When would you use `pause` vs `promote` vs `shutdown`? How does `pause` help you verify the recovery state before committing?

3. **LSN vs time targeting**: What are the tradeoffs between recovery_target_time and recovery_target_lsn? When is each more appropriate?

4. **Forensic WAL analysis**: How do you use pg_waldump in practice? What information does it provide and what are its limitations? (Hint: it shows physical operations, not logical SQL.)

5. **PITR on a live cluster**: Why is it dangerous to PITR the production cluster directly? What happens to transactions that occurred after your target time?

6. **Recovery validation**: After a PITR restore, how do you verify the data is in the expected state? What if you do not know exactly what the correct state should look like?

7. **Time synchronization**: PITR depends on timestamps. What happens if the server clock was wrong when the backup was taken or when WAL was generated? How does NTP factor into PITR reliability?
