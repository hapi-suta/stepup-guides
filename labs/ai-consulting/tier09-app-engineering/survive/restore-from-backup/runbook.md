# SURVIVE Runbook: Restore-From-Backup Drill

**Scenario:** a bad migration wiped the knowledge base - every document and chunk is gone from the live database, and the app answers "I don't have that information" to everything. You have a backup. Now you must prove it actually works and use it to recover.

**The rule this drill teaches:** a backup you have never restored is not a backup, it is a hope. You verify a backup by restoring it.

**Where you are:** the **lab server** (CentOS Stream 9), as **ec2-user**, with Project 9 in `~/project9`.

**Prerequisite:** the `labuser` role can create databases (needed for the drill's isolated restore). If you see "permission denied to create database" in Step 3, run this once as the `postgres` superuser: `sudo su - postgres`, then `psql -c "ALTER ROLE labuser CREATEDB;"`, then `exit`.

---

## Step 1: Confirm the data loss

On your **lab server**, as **ec2-user**:

```bash
cd ~/project9
```

Load your database settings:

```bash
set -a; . ./.env; set +a
```

Count the documents and chunks in the live database:

```bash
PGPASSWORD=$DB_PASSWORD psql -h $DB_HOST -U $DB_USER -d $DB_NAME -c "SELECT (SELECT count(*) FROM documents) AS documents, (SELECT count(*) FROM chunks) AS chunks;"
```

Expected output (the disaster):

```
 documents | chunks
-----------+--------
         0 |      0
(1 row)
```

Both empty. The knowledge base is gone. Time to recover.

---

## Step 2: Find your most recent backup

The backup was taken before the disaster (the inject step ran `backup.sh`). List what you have.

Still on the **lab server**, as **ec2-user**:

```bash
ls -lt backups/
```

Expected output (yours will differ):

```
total 20
-rw-r--r--. 1 ec2-user ec2-user 16384 Jul 25 15:40 labdb-20260725-154012.dump
```

That `.dump` file is your last known good. Note its name.

---

## Step 3: Prove the backup restores (the drill)

Never restore straight into production on faith. First restore into a SEPARATE database and verify it. `restore.sh` does exactly this: it restores into `labdb_restore` and checks the row counts.

Still on the **lab server**, as **ec2-user**:

```bash
bash ./restore.sh
```

With no argument it uses the newest dump. Expected output (yours will differ):

```
[restore] using dump: backups/labdb-20260725-154012.dump
[restore] recreating labdb_restore
[restore] restoring into labdb_restore
[restore] restored app_users=2 chunks=2
PASS: backup restored and verified (2 users, 2 chunks).
```

`PASS` means the backup is real and restorable. Now you can trust it for the actual recovery.

---

## Step 4: Restore the lost data into the live database

The backup is good. Bring the documents and chunks back into the live `labdb`. We restore only the two wiped tables (data only), so we do not disturb users, sessions, or the audit log.

**Order matters.** `chunks.doc_id` is a foreign key to `documents.id`, so `documents` must be restored FIRST or the chunk rows will be rejected. Do it in two steps.

First capture the exact dump filename so both commands use the same file:

Still on the **lab server**, as **ec2-user**:

```bash
DUMP=$(ls -t backups/*.dump | head -1)
```

`ls -t` sorts newest first; `head -1` takes the newest dump into the `DUMP` variable.

Restore the parent table, `documents`, first:

```bash
PGPASSWORD=$DB_PASSWORD pg_restore -h $DB_HOST -U $DB_USER -d $DB_NAME --data-only --table=documents "$DUMP"
```

`--data-only` skips re-creating the table (it still exists, just empty); `--table` limits the restore to one table. Expected output (no errors printed means success):

```
```

Now restore the child table, `chunks`:

```bash
PGPASSWORD=$DB_PASSWORD pg_restore -h $DB_HOST -U $DB_USER -d $DB_NAME --data-only --table=chunks "$DUMP"
```

Expected output (again, no errors printed means success):

```
```

If you had restored `chunks` first, you would have seen a `violates foreign key constraint "chunks_doc_id_fkey"` error, because the parent `documents` rows would not exist yet. Parent before child, every time.

---

## Step 5: Confirm the live database is whole again

Still on the **lab server**, as **ec2-user**:

```bash
PGPASSWORD=$DB_PASSWORD psql -h $DB_HOST -U $DB_USER -d $DB_NAME -c "SELECT (SELECT count(*) FROM documents) AS documents, (SELECT count(*) FROM chunks) AS chunks;"
```

Expected output (yours will differ - both non-zero):

```
 documents | chunks
-----------+--------
         2 |      2
(1 row)
```

The data is back. If the API is running, it can answer questions again.

---

## Step 6: Validate

Run the checker:

```bash
bash ~/project9/survive/restore-from-backup/validate.sh
```

Expected output (yours will differ):

```
OK: backup file present (labdb-20260725-154012.dump)
OK: restore drill passed (backup restores into a fresh database)
OK: live database recovered (documents=2, chunks=2)
PASS: backup verified and live data restored.
```

---

## What you learned

- **A backup is only proven by a restore.** The single most common backup failure is discovering, during a real incident, that the backups were empty, corrupt, or unrestorable. Restore drills turn that unknown into a known.
- **Restore into an isolated target first.** `restore.sh` restores into `labdb_restore`, not production, so verifying the backup can never make the incident worse. Only after it passes do you touch the live database.
- **Restore the minimum you need.** `--data-only --table=...` brought back exactly the two wiped tables without clobbering sessions or the audit trail. Scope the recovery to the damage.
- **Automate and schedule both.** In production, `backup.sh` runs on a cron/timer, backups ship off the box (S3), and a scheduled restore drill (into a scratch DB) proves them regularly. Track RPO (how much data you can lose - your backup frequency) and RTO (how long recovery takes - measured by this drill).

Prof. Happy (SUTA Labs)
