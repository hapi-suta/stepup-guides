# SURVIVE Runbook: Malformed CSV Crashes the Ingest CLI

**Scenario:** a batch of support tickets arrives as `tickets.csv`. The naive ingester crashes on one malformed row, and because it crashes mid-batch, none of the good rows load either. A single bad record took down the whole pipeline.

**Your job:** make the ingester survive bad rows - process the good ones, route the bad ones to a **dead-letter file** for later inspection, and never crash on data it cannot parse. You are on the **lab server**, as **ec2-user**, with Project 1 in `~/project1`.

The rule you are enforcing: **a data pipeline must be robust to bad input.** Bad data is not exceptional - it is guaranteed. Good rows must not be held hostage by one bad row.

---

## Step 1: Reproduce the crash

On your **lab server**, as **ec2-user**:

```bash
cd ~/project1
```

```bash
.venv/bin/python import_tickets.py tickets.csv
```

Expected output (the crash):

```
Traceback (most recent call last):
  File "/home/ec2-user/project1/import_tickets.py", line 30, in <module>
    subject, body, category = row
    ^^^^^^^^^^^^^^^^^^^^^^^^
ValueError: too many values to unpack (expected 3)
```

Read the traceback bottom-up: the last line is the real error. `too many values to unpack` means a CSV row had more than the 3 fields the code assumed. Row 3 in the file has extra commas. The program died and, critically, **no rows were inserted** - the whole batch failed because of one row.

---

## Step 2: Confirm nothing loaded (the blast radius)

Check that the crash lost the good rows too.

Still on the **lab server**, as **ec2-user**:

```bash
PGPASSWORD=labpass psql -h 127.0.0.1 -U labuser -d labdb \
  -c "SELECT count(*) FROM support_tickets WHERE body = 'Reset email never arrives';"
```

Expected output:

```
 count
-------
     0
(1 row)
```

Zero. The good "Cannot reset password" row never made it in, even though it was perfectly valid. That is the real damage: one bad row lost three good ones.

---

## Step 3: Rewrite the ingester with error handling and a dead-letter file

The fix has three parts: wrap each row in `try/except`, validate the field count, and send bad rows to a **dead-letter file** (`tickets.deadletter.csv`) instead of crashing. A dead-letter file is where records that could not be processed go, so a human can inspect and fix them later without blocking the pipeline.

Still on the **lab server**, as **ec2-user**, open the file with `vi`:

```bash
vi import_tickets.py
```

Press `i` to enter insert mode. Delete the old contents (in command mode you can type `:%d` first, then `i`) and enter this robust version:

```python
"""Robust CSV ingester: good rows load, bad rows go to a dead-letter file.

A data pipeline must survive bad input. One malformed row must never stop
the batch or crash the process.
"""
import csv
import logging
import os
import sys

import psycopg2

logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
log = logging.getLogger("ingest")

DB = dict(
    host=os.environ.get("DB_HOST", "127.0.0.1"),
    dbname=os.environ.get("DB_NAME", "labdb"),
    user=os.environ.get("DB_USER", "labuser"),
    password=os.environ.get("DB_PASSWORD", "labpass"),
)

path = sys.argv[1] if len(sys.argv) > 1 else "tickets.csv"
deadletter = "tickets.deadletter.csv"

conn = psycopg2.connect(**DB)
inserted = 0
rejected = 0

with conn, conn.cursor() as cur, \
     open(path, newline="") as f, \
     open(deadletter, "w", newline="") as dead:
    reader = csv.reader(f)
    writer = csv.writer(dead)
    header = next(reader)  # keep the header
    writer.writerow(header + ["_error"])  # dead-letter keeps the header + reason

    for line_no, row in enumerate(reader, start=2):
        try:
            if len(row) != 3:
                raise ValueError(f"expected 3 fields, got {len(row)}")
            subject, body, category = row
            if not subject.strip():
                raise ValueError("blank subject")
            cur.execute(
                "INSERT INTO support_tickets (subject, body, category) "
                "VALUES (%s, %s, %s)",
                (subject, body, category or None),
            )
            inserted += 1
        except (ValueError, psycopg2.Error) as exc:
            # do NOT crash - log it and route the row to the dead-letter file
            log.warning("row %d rejected: %s", line_no, exc)
            writer.writerow(row + [str(exc)])
            rejected += 1

conn.close()
log.info("done: inserted=%d rejected=%d dead_letter=%s",
         inserted, rejected, deadletter)
print(f"inserted {inserted} rows, rejected {rejected} rows -> {deadletter}")
```

Then press `Esc` and type `:wq` to save and quit.

Key changes:

- Each row is processed inside `try/except`, so one bad row cannot stop the loop.
- `if len(row) != 3` validates the field count and rejects the malformed row instead of unpacking-crashing.
- Bad rows are written to `tickets.deadletter.csv` with the reason, so nothing is silently lost.
- Good rows still load. The batch survives.

---

## Step 4: Run the fixed ingester

Still on the **lab server**, as **ec2-user**:

```bash
.venv/bin/python import_tickets.py tickets.csv
```

Expected output (yours will differ):

```
WARNING row 4 rejected: expected 3 fields, got 8
inserted 3 rows, rejected 1 rows -> tickets.deadletter.csv
```

Three good rows loaded; the one malformed row was rejected, not fatal. The process exited normally (exit code 0).

---

## Step 5: Inspect the dead-letter file

The bad row is preserved with its reason so a human can fix and re-submit it.

Still on the **lab server**, as **ec2-user**:

```bash
cat tickets.deadletter.csv
```

Expected output (yours will differ):

```
subject,body,category,_error
THIS ROW IS BROKEN,it has,too,many,commas,and,no,category,"expected 3 fields, got 8"
```

The malformed row is captured, tagged with why it failed. Nothing was lost, and no manual archaeology is needed.

---

## Step 6: Confirm the good rows loaded

Still on the **lab server**, as **ec2-user**:

```bash
PGPASSWORD=labpass psql -h 127.0.0.1 -U labuser -d labdb \
  -c "SELECT count(*) FROM support_tickets WHERE body = 'Reset email never arrives';"
```

Expected output:

```
 count
-------
     1
(1 row)
```

The good row is now in the database. The pipeline survived the bad input.

---

## What you learned

- **A single bad row must never take down a batch.** Wrapping per-row work in `try/except` isolates failures to the row that caused them.
- **Validate before you trust.** Checking `len(row) != 3` catches structural problems before they become cryptic unpacking errors.
- **Dead-letter, do not drop.** Rejected records go to a file with the reason - visible, recoverable, and auditable - instead of vanishing or crashing the job.
- **Log the rejects.** A `WARNING` per bad row means you can see how much bad data you are getting over time.

## Prevention

- Use the `csv` module (never `line.split(",")`) so quoted commas do not fool you into wrong field counts.
- Report a rejected-row count and alert if it crosses a threshold - a sudden spike means the upstream source changed.
- In a real system, re-drive the dead-letter file after fixing the source, so no data is permanently lost.
