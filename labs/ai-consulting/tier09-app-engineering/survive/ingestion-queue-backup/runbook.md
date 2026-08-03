# SURVIVE Runbook: Ingestion Queue Backed Up, Worker Dead

**Scenario:** admins uploaded a batch of documents, but none of them show up in search. The background worker is down, so jobs are piling up in `queued`. Worse, one job is stuck in `processing` - the worker died mid-job and left it orphaned, so it will never finish and never retry.

**Your job:** detect the backlog, recover the orphaned job safely, restart the worker, and drain the queue - without losing or double-processing any document.

**Where you are:** the **lab server** (CentOS Stream 9), as **ec2-user**, with Project 9 in `~/project9`.

---

## Step 1: See the backlog

On your **lab server**, as **ec2-user**, go to the project:

```bash
cd ~/project9
```

Load your database settings so `psql` works without typing them each time:

```bash
set -a; . ./.env; set +a
```

`set -a` marks every variable that follows for export; sourcing `.env` loads `DB_USER`, `DB_PASSWORD`, etc.; `set +a` turns that off again.

Now look at the queue, grouped by status:

```bash
PGPASSWORD=$DB_PASSWORD psql -h $DB_HOST -U $DB_USER -d $DB_NAME -c "SELECT status, count(*) FROM ingest_jobs GROUP BY status ORDER BY status;"
```

Expected output (yours will differ):

```
   status   | count
------------+-------
 processing |     1
 queued     |     4
(2 rows)
```

Four jobs waiting and one stuck in `processing`. That single `processing` row is the dangerous one: the worker that claimed it is gone, so it is frozen forever unless you act.

---

## Step 2: Confirm the worker is really down

Do not restart blindly - first confirm nothing is running, or you could end up with two workers.

Still on the **lab server**, as **ec2-user**:

```bash
pgrep -af worker.py
```

Expected output (nothing prints):

```
```

No output means no worker process. Good - it is safe to recover and restart.

---

## Step 3: Find the orphaned job

Look at what is stuck and how long it has been stuck.

Still on the **lab server**, as **ec2-user**:

```bash
PGPASSWORD=$DB_PASSWORD psql -h $DB_HOST -U $DB_USER -d $DB_NAME -c "SELECT id, source, status, updated_at FROM ingest_jobs WHERE status='processing';"
```

Expected output (yours will differ):

```
 id | source     |   status   |          updated_at
----+------------+------------+-------------------------------
  5 | orphan.txt | processing | 2026-07-25 15:28:27.85+00
(1 row)
```

`updated_at` is about an hour old. A job that has been `processing` far longer than any job should take is a **stale in-flight job**. A healthy worker would have finished it in seconds.

---

## Step 4: Requeue the orphaned job safely

Reset any job stuck in `processing` back to `queued` so the worker will pick it up again. We only reset jobs whose `updated_at` is older than 5 minutes, so we never yank a job a live worker is actively processing.

Still on the **lab server**, as **ec2-user**:

```bash
PGPASSWORD=$DB_PASSWORD psql -h $DB_HOST -U $DB_USER -d $DB_NAME -c "UPDATE ingest_jobs SET status='queued', updated_at=now() WHERE status='processing' AND updated_at < now() - interval '5 minutes';"
```

Expected output:

```
UPDATE 1
```

`UPDATE 1` means the one orphaned job is back in the queue. Because ingestion is designed to be safe to retry (the worker inserts a fresh document row when it runs), re-running it does no harm.

---

## Step 5: Start the worker

Now bring the worker back. Start it in the background so it keeps draining the queue.

Still on the **lab server**, as **ec2-user**:

```bash
nohup python3 worker.py > worker.log 2>&1 &
```

`nohup ... &` runs it detached so it survives your logout; output goes to `worker.log`. Give it a few seconds to work through the backlog:

```bash
sleep 8
```

Watch what it did:

```bash
cat worker.log
```

Expected output (yours will differ):

```
[worker] started, polling every 2s. Ctrl-C to stop.
[worker] job 1 done: 1 chunks from burst-1.txt
[worker] job 2 done: 1 chunks from burst-2.txt
[worker] job 3 done: 1 chunks from burst-3.txt
[worker] job 4 done: 1 chunks from burst-4.txt
[worker] job 5 done: 1 chunks from orphan.txt
```

Every job, including the recovered orphan, is now done.

---

## Step 6: Confirm the queue is empty

Still on the **lab server**, as **ec2-user**:

```bash
PGPASSWORD=$DB_PASSWORD psql -h $DB_HOST -U $DB_USER -d $DB_NAME -c "SELECT status, count(*) FROM ingest_jobs GROUP BY status ORDER BY status;"
```

Expected output (yours will differ):

```
 status | count
--------+-------
 done   |     5
(1 row)
```

Nothing queued, nothing processing - only `done`. The backlog is cleared.

---

## Step 7: Validate

Run the checker:

```bash
bash ~/project9/survive/ingestion-queue-backup/validate.sh
```

Expected output:

```
OK: no jobs left queued
OK: no jobs stuck in processing
OK: burst documents ingested (4 chunk rows)
PASS: ingestion queue drained safely, worker healthy.
```

---

## What you learned

- **Asynchronous work needs a supervised worker.** A queue only helps if something is draining it. In production the worker runs under a supervisor (systemd, a container restart policy, a Kubernetes Deployment) so a crash restarts it automatically.
- **Orphaned in-flight jobs are the silent failure.** A job stuck in `processing` never retries on its own. The fix is a **stale-job reaper**: reset jobs whose `updated_at` is older than a safe threshold back to `queued`. The 5-minute guard prevents stealing a job from a live worker.
- **Idempotent processing makes recovery safe.** Because re-running a job does no harm, you can requeue freely. Design async work so a retry is always safe.
- **Monitor queue depth.** `/metrics` exposes `ingest_queue`. Alert when `queued` stays high or any job sits in `processing` too long - that is your early warning, long before a user reports "my upload never appeared."

Prof. Happy (SUTA Labs)
