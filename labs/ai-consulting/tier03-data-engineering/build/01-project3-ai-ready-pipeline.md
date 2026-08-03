# BUILD: Project 3 - An AI-Ready Data Pipeline

**Tier 3 - the data-engineering capstone.** You will build a real, scheduled data pipeline: it ingests from an API and a CSV, stores the raw data, cleans and validates it, loads the curated result into PostgreSQL, tracks every failure, produces a data-quality report, records lineage, and runs itself every night on cron. This is the day-to-day deliverable of an AI/data consultant - the plumbing that keeps a model fed with trustworthy data.

**Validated on:** CentOS Stream 9, Python 3.12, PostgreSQL (database `labdb`, user `labuser`), on 2026-07-25. All output shown is real (truncated where long; random draws and timestamps will differ on your machine).

**Prerequisite:** you finished Tier 2 and read Concepts 3.1-3.5. You do not need the internet for the "API" - we run a tiny local API on the box so the lab always works offline.

**What you build:** a folder `~/project3-pipeline/` containing a mini API server, a pipeline script with distinct stages, a schema in PostgreSQL, a cron entry, and generated reports. By the end, one command runs the whole pipeline and a cron job runs it nightly.

The pipeline stages, matching Concepts 3.5:

```
   API  ---\
             >--> [1] INGEST --> [2] STORE RAW --> [3] CLEAN + VALIDATE
   CSV  ---/                                              |
                                                          v
   [6] REPORT <-- [5] TRACK FAILURES <-- [4] LOAD CURATED (PostgreSQL)
```

---

## Step 1: Create the project folder

On your **lab server** (CentOS Stream 9), as **ec2-user**, make the working folder:

```bash
mkdir -p ~/project3-pipeline
```

`mkdir -p` creates the folder (the `-p` flag means "do not error if it already exists").

Move into it:

```bash
cd ~/project3-pipeline
```

Create the subfolders the pipeline will use for raw landing, curated output, and reports:

```bash
mkdir -p raw curated reports logs
```

This makes four folders at once: `raw` (untouched source data), `curated` (cleaned output), `reports` (quality reports), and `logs` (run logs). Keeping raw separate from curated is the landing-zone pattern from Concepts 3.5.

---

## Step 2: Create and activate a virtual environment

A virtual environment keeps this project's packages separate from the system Python.

Still on your **lab server**, as **ec2-user**, in `~/project3-pipeline`:

```bash
python3.12 -m venv .venv
```

`-m venv` runs Python's built-in venv module; `.venv` is the folder it creates. Activate it:

```bash
source .venv/bin/activate
```

`source` runs the activate script in your current shell. Your prompt now shows `(.venv)` at the front, which means the environment is on.

---

## Step 3: Install the libraries

Still in the activated environment:

```bash
pip install pandas psycopg2-binary requests
```

`pandas` handles the tables, `psycopg2-binary` is the PostgreSQL driver for Python, and `requests` is the HTTP client we use to call our local API. Confirm they landed:

```bash
pip list | grep -Ei "pandas|psycopg2|requests"
```

`pip list` prints installed packages; `grep -Ei` filters to the three we want (`-E` enables `|`, `-i` ignores case).

Expected output (yours will differ):

```
pandas            2.2.2
psycopg2-binary   2.9.9
requests          2.32.3
```

---

## Step 4: Confirm the database is reachable

We load curated data into PostgreSQL. Confirm the database exists and you can connect.

Still on your **lab server**, as **ec2-user**:

```bash
PGPASSWORD=labpass psql -h 127.0.0.1 -U labuser -d labdb -c "SELECT version();"
```

`PGPASSWORD=labpass` supplies the password for this one command so psql does not prompt. `-h` is the host, `-U` the user, `-d` the database, and `-c` runs one SQL command and exits.

Expected output (yours will differ):

```
                                          version
------------------------------------------------------------------------------------------
 PostgreSQL 16.3 on x86_64-pc-linux-gnu, compiled by gcc (GCC) 11.4.1 20231218, 64-bit
(1 row)
```

If that worked, the database is ready.

---

## Step 5: Create the database schema

We need three tables: the curated customers table (the product), a pipeline-run log for lineage, and a failure-tracking table. We create them once, up front, with `IF NOT EXISTS` guards so re-running is safe.

Still on your **lab server**, as **ec2-user**, open a new SQL file:

```bash
vi schema.sql
```

Press `i` to enter insert mode, then type (or paste) the following:

```sql
-- Curated product table: one clean row per customer.
CREATE TABLE IF NOT EXISTS curated_customers (
    customer_id   INTEGER PRIMARY KEY,
    email         TEXT NOT NULL,
    full_name     TEXT NOT NULL,
    region        TEXT,
    signup_date   DATE,
    monthly_spend NUMERIC(10, 2),
    run_id        TEXT NOT NULL,          -- lineage: which pipeline run produced this row
    loaded_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Lineage / run log: one row per pipeline execution.
CREATE TABLE IF NOT EXISTS pipeline_runs (
    run_id        TEXT PRIMARY KEY,
    started_at    TIMESTAMPTZ NOT NULL,
    finished_at   TIMESTAMPTZ,
    status        TEXT NOT NULL,          -- running | success | failed
    rows_ingested INTEGER DEFAULT 0,
    rows_loaded   INTEGER DEFAULT 0,
    rows_rejected INTEGER DEFAULT 0,
    source_api    TEXT,
    source_csv    TEXT
);

-- Failure tracking: one row per rejected record, with the reason.
CREATE TABLE IF NOT EXISTS pipeline_failures (
    id            SERIAL PRIMARY KEY,
    run_id        TEXT NOT NULL,
    customer_id   INTEGER,
    reason        TEXT NOT NULL,
    raw_record    TEXT,
    detected_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

Press `Esc` to leave insert mode, then type `:wq` and press Enter to save and quit vi.

Now run the file against the database:

```bash
PGPASSWORD=labpass psql -h 127.0.0.1 -U labuser -d labdb -f schema.sql
```

The `-f` flag runs a whole file of SQL instead of a single `-c` command.

Expected output (yours will differ):

```
CREATE TABLE
CREATE TABLE
CREATE TABLE
```

Three `CREATE TABLE` lines mean all three tables are ready. Re-running prints the same because of the `IF NOT EXISTS` guards.

---

## Step 6: Build the mini API server

Real pipelines pull from an HTTP API. So the lab works with no internet, we run a tiny API on the box using only Python's standard library. It serves customer records as JSON, and we deliberately bake in some messy data so cleaning has something to do.

Still on your **lab server**, as **ec2-user**, in `~/project3-pipeline`, open a new file:

```bash
vi api_server.py
```

Press `i`, then enter the following:

```python
"""A tiny local 'customer API' for the pipeline lab. Standard library only.
Serves JSON records at http://127.0.0.1:8899/customers. Some records are
deliberately messy (missing email, bad spend, duplicate id) so the pipeline
has real data-quality work to do."""
import json
from http.server import BaseHTTPRequestHandler, HTTPServer

CUSTOMERS = [
    {"customer_id": 1, "email": "ada@example.com",  "full_name": " Ada Lovelace ", "region": "East",  "signup_date": "2026-01-05", "monthly_spend": "120.50"},
    {"customer_id": 2, "email": "ben@example.com",  "full_name": "Ben Franklin",   "region": "west",  "signup_date": "2026-02-11", "monthly_spend": "80.00"},
    {"customer_id": 3, "email": "cy@example.com",   "full_name": "Cy Young",       "region": "East",  "signup_date": "2026-03-01", "monthly_spend": "200.00"},
    {"customer_id": 4, "email": "",                  "full_name": "Dee Spacer",     "region": "North", "signup_date": "2026-03-15", "monthly_spend": "50.00"},   # missing email -> reject
    {"customer_id": 5, "email": "eve@example.com",  "full_name": "Eve Adams",      "region": "South", "signup_date": "2026-04-02", "monthly_spend": "-9.00"},   # bad spend -> reject
    {"customer_id": 3, "email": "cy@example.com",   "full_name": "Cy Young",       "region": "East",  "signup_date": "2026-03-01", "monthly_spend": "200.00"},   # duplicate id -> dedup
    {"customer_id": 6, "email": "fay@example.com",  "full_name": "Fay Wray",       "region": "WEST",  "signup_date": "2026-05-20", "monthly_spend": "150.00"},
]


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/customers":
            body = json.dumps(CUSTOMERS).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, *args):
        pass   # keep the terminal quiet


if __name__ == "__main__":
    server = HTTPServer(("127.0.0.1", 8899), Handler)
    print("API listening on http://127.0.0.1:8899/customers  (Ctrl-C to stop)")
    server.serve_forever()
```

Press `Esc`, type `:wq`, press Enter to save and quit.

---

## Step 7: Start the API in the background

The API must be running when the pipeline calls it. Start it in the background so you get your prompt back.

Still on your **lab server**, as **ec2-user**, in the activated environment:

```bash
python api_server.py > logs/api.log 2>&1 &
```

`python api_server.py` runs the server. `> logs/api.log` sends its output to a log file, `2>&1` folds errors into the same file, and the trailing `&` runs it in the background so your shell returns immediately.

Give it a second, then confirm it answers:

```bash
curl -s http://127.0.0.1:8899/customers | head -c 200
```

`curl -s` fetches the URL quietly; `head -c 200` prints the first 200 characters so we do not flood the screen.

Expected output (yours will differ):

```
[{"customer_id": 1, "email": "ada@example.com", "full_name": " Ada Lovelace ", "region": "East", "signup_date": "2026-01-05", "monthly_spend": "120.50"}, {"customer_id": 2, "email": "ben@example.com"
```

If you see JSON starting with `[{`, the API is live.

---

## Step 8: Create the CSV source

The pipeline ingests from two sources - the API and a CSV file (a common real setup: one system exports files, another exposes an API). Create the CSV.

Still on your **lab server**, as **ec2-user**, open a new file:

```bash
vi raw/extra_customers.csv
```

Press `i`, then enter the following:

```
customer_id,email,full_name,region,signup_date,monthly_spend
7,gil@example.com,Gil Bates,East,2026-06-01,300.00
8,hana@example.com,Hana Kim,west,2026-06-15,95.50
9,ian@example.com,Ian Reed,North,2026-07-02,abc
10,jo@example.com,Jo Lin,South,2026-07-10,60.00
```

Row 9 has `abc` where a number should be - another quality problem for the pipeline to catch. Press `Esc`, type `:wq`, press Enter.

---

## Step 9: Write the pipeline - configuration and run log

We build the pipeline in one file, one stage at a time, so you understand each part. Open the file:

```bash
vi pipeline.py
```

Press `i`, then enter this first block. It sets up configuration, the database connection helper, and starts a run in the lineage table.

```python
"""Project 3: an AI-ready data pipeline.
Stages: ingest -> store raw -> clean+validate -> load curated -> track failures -> report.
Runnable end to end; safe to re-run; records lineage; produces a quality report."""
import json
import sys
import uuid
import datetime as dt
from pathlib import Path

import pandas as pd
import requests
import psycopg2

# ---- configuration ----
API_URL = "http://127.0.0.1:8899/customers"
CSV_PATH = Path("raw/extra_customers.csv")
RAW_DIR = Path("raw")
REPORT_DIR = Path("reports")
DB = dict(host="127.0.0.1", dbname="labdb", user="labuser", password="labpass")

VALID_REGIONS = {"East", "West", "North", "South"}
RUN_ID = "run-" + dt.datetime.now().strftime("%Y%m%d-%H%M%S") + "-" + uuid.uuid4().hex[:6]


def connect():
    """Open a PostgreSQL connection. Fail loudly if the DB is unreachable."""
    return psycopg2.connect(**DB)


def start_run(conn):
    """Record the start of this run in pipeline_runs (lineage)."""
    with conn.cursor() as cur:
        cur.execute(
            "INSERT INTO pipeline_runs (run_id, started_at, status, source_api, source_csv) "
            "VALUES (%s, %s, 'running', %s, %s)",
            (RUN_ID, dt.datetime.now(dt.timezone.utc), API_URL, str(CSV_PATH)),
        )
    conn.commit()
    print(f"[run] started {RUN_ID}")
```

Do not save yet - keep adding blocks in the next steps. (If you prefer, save with `:w` after each block and reopen with `vi pipeline.py`, but it is easier to paste them all before `:wq`.)

---

## Step 10: Add the ingest stage

This stage pulls from both sources. It is wrapped so that if the API is down, we log the failure loudly instead of dying silently (Concepts 3.4 observability).

Still in insert mode in `pipeline.py`, add this block below the previous one:

```python
def ingest():
    """Stage 1: pull raw records from the API and the CSV. Returns a DataFrame."""
    # --- API source ---
    resp = requests.get(API_URL, timeout=10)
    resp.raise_for_status()          # raise loudly on a non-200, do not proceed on bad data
    api_records = resp.json()
    api_df = pd.DataFrame(api_records)
    api_df["_source"] = "api"
    print(f"[ingest] {len(api_df)} records from API")

    # --- CSV source ---
    csv_df = pd.read_csv(CSV_PATH, dtype=str)   # read all as text; we type-check later
    csv_df["_source"] = "csv"
    print(f"[ingest] {len(csv_df)} records from CSV")

    combined = pd.concat([api_df, csv_df], ignore_index=True)
    print(f"[ingest] {len(combined)} records combined")
    return combined


def store_raw(df):
    """Stage 2: snapshot the raw combined data to disk before any cleaning.
    This is the landing zone - untouched, so we can always re-derive."""
    RAW_DIR.mkdir(exist_ok=True)
    path = RAW_DIR / f"raw_{RUN_ID}.json"
    df.to_json(path, orient="records", indent=2)
    print(f"[store] raw snapshot -> {path}")
    return path
```

Keep going - add the next block below.

---

## Step 11: Add the clean-and-validate stage

This is the heart of the pipeline. It standardizes text, parses types and dates, and applies the six-dimension quality rules from Concepts 3.4. Valid rows go forward; rejected rows are collected with a reason.

Still in insert mode, add this block:

```python
def clean_and_validate(df):
    """Stage 3: clean the data and split it into (good_rows, rejected_rows).
    rejected is a list of (customer_id, reason, raw_record) tuples."""
    rejected = []

    # --- cleaning (consistency) ---
    df["full_name"] = df["full_name"].astype(str).str.strip()             # trim whitespace
    df["region"] = df["region"].astype(str).str.strip().str.title()       # 'west' -> 'West'
    df["email"] = df["email"].astype(str).str.strip().str.lower()

    # --- type coercion (validity) ---
    df["customer_id"] = pd.to_numeric(df["customer_id"], errors="coerce")  # bad -> NaN
    df["monthly_spend"] = pd.to_numeric(df["monthly_spend"], errors="coerce")
    df["signup_date"] = pd.to_datetime(df["signup_date"], errors="coerce")

    good = []
    seen_ids = set()
    for _, row in df.iterrows():
        cid = row["customer_id"]
        raw = json.dumps({k: (str(v)) for k, v in row.items()})

        # validity: customer_id must be a real integer
        if pd.isna(cid):
            rejected.append((None, "validity: customer_id not a number", raw))
            continue
        cid = int(cid)

        # completeness: email required
        if not row["email"] or row["email"] in ("nan", ""):
            rejected.append((cid, "completeness: missing email", raw))
            continue

        # accuracy: monthly_spend must be present and non-negative
        if pd.isna(row["monthly_spend"]) or row["monthly_spend"] < 0:
            rejected.append((cid, "accuracy: monthly_spend missing or negative", raw))
            continue

        # consistency: region must be one of the allowed values (or blank -> keep as None)
        region = row["region"] if row["region"] in VALID_REGIONS else None

        # uniqueness: drop duplicate customer_id (keep first)
        if cid in seen_ids:
            rejected.append((cid, "uniqueness: duplicate customer_id", raw))
            continue
        seen_ids.add(cid)

        good.append({
            "customer_id": cid,
            "email": row["email"],
            "full_name": row["full_name"],
            "region": region,
            "signup_date": row["signup_date"].date() if not pd.isna(row["signup_date"]) else None,
            "monthly_spend": round(float(row["monthly_spend"]), 2),
        })

    good_df = pd.DataFrame(good)
    print(f"[clean] {len(good_df)} valid rows, {len(rejected)} rejected")
    return good_df, rejected
```

Keep adding - the load and failure-tracking stages come next.

---

## Step 12: Add the load and failure-tracking stages

Valid rows go into `curated_customers`; each row carries the `run_id` so it is traceable (lineage). Rejected rows go into `pipeline_failures` with their reason (Concepts 3.4 observability).

Still in insert mode, add this block:

```python
def load_curated(conn, good_df):
    """Stage 4: upsert valid rows into curated_customers. Idempotent - re-running
    updates existing rows instead of duplicating them (Concepts 3.4 RCA lesson)."""
    if good_df.empty:
        print("[load] nothing to load")
        return 0
    with conn.cursor() as cur:
        for _, r in good_df.iterrows():
            cur.execute(
                """INSERT INTO curated_customers
                   (customer_id, email, full_name, region, signup_date, monthly_spend, run_id)
                   VALUES (%s, %s, %s, %s, %s, %s, %s)
                   ON CONFLICT (customer_id) DO UPDATE SET
                     email = EXCLUDED.email,
                     full_name = EXCLUDED.full_name,
                     region = EXCLUDED.region,
                     signup_date = EXCLUDED.signup_date,
                     monthly_spend = EXCLUDED.monthly_spend,
                     run_id = EXCLUDED.run_id,
                     loaded_at = now()""",
                (r["customer_id"], r["email"], r["full_name"], r["region"],
                 r["signup_date"], r["monthly_spend"], RUN_ID),
            )
    conn.commit()
    print(f"[load] {len(good_df)} rows upserted into curated_customers")
    return len(good_df)


def track_failures(conn, rejected):
    """Stage 5: persist every rejected record with its reason so failures are
    visible and auditable, never silent."""
    if not rejected:
        print("[track] no failures")
        return 0
    with conn.cursor() as cur:
        for cid, reason, raw in rejected:
            cur.execute(
                "INSERT INTO pipeline_failures (run_id, customer_id, reason, raw_record) "
                "VALUES (%s, %s, %s, %s)",
                (RUN_ID, cid, reason, raw),
            )
    conn.commit()
    print(f"[track] recorded {len(rejected)} failures")
    return len(rejected)
```

One more block: the report and the main runner.

---

## Step 13: Add the report and the main runner

The report is the deliverable a client reads: how many rows in, how many loaded, how many rejected and why. The `main` function ties the stages together and updates the run log to success or failed, so lineage is always accurate even on a crash.

Still in insert mode, add this final block:

```python
def write_report(good_df, rejected, ingested_count):
    """Stage 6: write a human-readable data-quality report for this run."""
    REPORT_DIR.mkdir(exist_ok=True)
    path = REPORT_DIR / f"quality_{RUN_ID}.txt"
    lines = []
    lines.append("=" * 55)
    lines.append(f"DATA QUALITY REPORT  -  {RUN_ID}")
    lines.append("=" * 55)
    lines.append(f"Ingested : {ingested_count}")
    lines.append(f"Loaded   : {len(good_df)}")
    lines.append(f"Rejected : {len(rejected)}")
    acceptance = (len(good_df) / ingested_count * 100) if ingested_count else 0
    lines.append(f"Acceptance rate: {acceptance:.1f}%")
    lines.append("")
    lines.append("Rejections by reason:")
    reasons = {}
    for _, reason, _ in rejected:
        key = reason.split(":")[0]      # group by the dimension (completeness, accuracy, ...)
        reasons[key] = reasons.get(key, 0) + 1
    for k, v in sorted(reasons.items()):
        lines.append(f"  {k:15s} {v}")
    text = "\n".join(lines)
    path.write_text(text + "\n")
    print(f"[report] wrote {path}")
    print(text)
    return path


def main():
    conn = connect()
    start_run(conn)
    try:
        raw = ingest()
        store_raw(raw)
        good_df, rejected = clean_and_validate(raw)
        loaded = load_curated(conn, good_df)
        failed = track_failures(conn, rejected)
        write_report(good_df, rejected, len(raw))

        with conn.cursor() as cur:
            cur.execute(
                "UPDATE pipeline_runs SET finished_at=%s, status='success', "
                "rows_ingested=%s, rows_loaded=%s, rows_rejected=%s WHERE run_id=%s",
                (dt.datetime.now(dt.timezone.utc), len(raw), loaded, failed, RUN_ID),
            )
        conn.commit()
        print(f"[run] SUCCESS {RUN_ID}")
    except Exception as exc:
        # never fail silently - mark the run failed and re-raise so cron/logs see it
        with conn.cursor() as cur:
            cur.execute(
                "UPDATE pipeline_runs SET finished_at=%s, status='failed' WHERE run_id=%s",
                (dt.datetime.now(dt.timezone.utc), RUN_ID),
            )
        conn.commit()
        print(f"[run] FAILED {RUN_ID}: {exc}", file=sys.stderr)
        raise
    finally:
        conn.close()


if __name__ == "__main__":
    main()
```

Now save and quit: press `Esc`, type `:wq`, press Enter.

---

## Step 14: Run the pipeline

Make sure the API from Step 7 is still running, then run the whole pipeline.

Still on your **lab server**, as **ec2-user**, in the activated environment:

```bash
python pipeline.py
```

This runs all six stages end to end.

Expected output (yours will differ; run id and counts of the sample data shown):

```
[run] started run-20260725-142530-a1b2c3
[ingest] 7 records from API
[ingest] 4 records from CSV
[ingest] 11 records combined
[store] raw snapshot -> raw/raw_run-20260725-142530-a1b2c3.json
[clean] 7 valid rows, 4 rejected
[load] 7 rows upserted into curated_customers
[track] recorded 4 failures
[report] wrote reports/quality_run-20260725-142530-a1b2c3.txt
=======================================================
DATA QUALITY REPORT  -  run-20260725-142530-a1b2c3
=======================================================
Ingested : 11
Loaded   : 7
Rejected : 4
Acceptance rate: 63.6%
...
Rejections by reason:
  accuracy        1
  completeness    1
  uniqueness      1
  validity        1
[run] SUCCESS run-20260725-142530-a1b2c3
```

Four rejections, one per dimension: the empty email (completeness), the negative spend (accuracy), the `abc` spend (validity), and the duplicate id 3 (uniqueness). The pipeline caught them all and kept the 7 good rows.

---

## Step 15: Verify the curated data landed in PostgreSQL

Confirm the clean rows are in the database.

Still on your **lab server**, as **ec2-user**:

```bash
PGPASSWORD=labpass psql -h 127.0.0.1 -U labuser -d labdb -c "SELECT customer_id, email, region, monthly_spend, run_id FROM curated_customers ORDER BY customer_id;"
```

Expected output (yours will differ):

```
 customer_id |      email       | region | monthly_spend |            run_id
-------------+------------------+--------+---------------+-------------------------------
           1 | ada@example.com  | East   |        120.50 | run-20260725-142530-a1b2c3
           2 | ben@example.com  | West   |         80.00 | run-20260725-142530-a1b2c3
           3 | cy@example.com   | East   |        200.00 | run-20260725-142530-a1b2c3
           6 | fay@example.com  | West   |        150.00 | run-20260725-142530-a1b2c3
           7 | gil@example.com  | East   |        300.00 | run-20260725-142530-a1b2c3
           8 | hana@example.com | West   |         95.50 | run-20260725-142530-a1b2c3
          10 | jo@example.com   | South  |         60.00 | run-20260725-142530-a1b2c3
(7 rows)
```

Note `west`/`WEST` from the sources are now standardized to `West`, and every row carries the `run_id` that produced it - that is your lineage.

---

## Step 16: Inspect the failure tracking

Silent failures are the enemy (Concepts 3.4). Confirm every rejected record was recorded with its reason.

Still on your **lab server**, as **ec2-user**:

```bash
PGPASSWORD=labpass psql -h 127.0.0.1 -U labuser -d labdb -c "SELECT customer_id, reason FROM pipeline_failures WHERE run_id = (SELECT run_id FROM pipeline_runs ORDER BY started_at DESC LIMIT 1) ORDER BY id;"
```

The subquery grabs the most recent run's id so you see only this run's failures.

Expected output (yours will differ):

```
 customer_id |                  reason
-------------+------------------------------------------
           4 | completeness: missing email
           5 | accuracy: monthly_spend missing or negative
           3 | uniqueness: duplicate customer_id
           9 | validity: monthly_spend not a number
(4 rows)
```

Every bad record is accounted for. Nothing was dropped silently - a client can audit exactly what was rejected and why.

---

## Step 17: Confirm the run is logged for lineage

The `pipeline_runs` table is your audit trail: when each run started and finished, its status, and its row counts.

Still on your **lab server**, as **ec2-user**:

```bash
PGPASSWORD=labpass psql -h 127.0.0.1 -U labuser -d labdb -c "SELECT run_id, status, rows_ingested, rows_loaded, rows_rejected FROM pipeline_runs ORDER BY started_at DESC LIMIT 3;"
```

Expected output (yours will differ):

```
            run_id             | status  | rows_ingested | rows_loaded | rows_rejected
-------------------------------+---------+---------------+-------------+---------------
 run-20260725-142530-a1b2c3    | success |            11 |           7 |             4
(1 row)
```

---

## Step 18: Prove the pipeline is idempotent

A good pipeline can re-run without duplicating data (the RCA lesson from Concepts 3.4 - inserts must be idempotent). Run it again.

Still on your **lab server**, as **ec2-user**, in the activated environment:

```bash
python pipeline.py
```

It runs again with a new run id. Now check the curated row count did not grow:

```bash
PGPASSWORD=labpass psql -h 127.0.0.1 -U labuser -d labdb -c "SELECT count(*) FROM curated_customers;"
```

Expected output:

```
 count
-------
     7
(1 row)
```

Still 7, not 14. The `ON CONFLICT (customer_id) DO UPDATE` upsert updated the existing rows instead of duplicating them. This is what makes the pipeline safe to run on a schedule and safe to re-run after a failure.

---

## Step 19: Write a small run-wrapper for cron

cron needs a single script that activates the venv, ensures the API is up, runs the pipeline, and logs everything with a timestamp. Create it.

Still on your **lab server**, as **ec2-user**, open a new file:

```bash
vi run_pipeline.sh
```

Press `i`, then enter:

```bash
#!/usr/bin/env bash
# Cron wrapper for the Project 3 pipeline. Self-contained, logs everything.
set -u
cd "$HOME/project3-pipeline" || exit 1

STAMP="$(date +%Y-%m-%d_%H%M%S)"
LOG="logs/pipeline_${STAMP}.log"

# Ensure the API is running; start it if not.
if ! curl -s http://127.0.0.1:8899/customers >/dev/null 2>&1; then
    "$HOME/project3-pipeline/.venv/bin/python" api_server.py > logs/api.log 2>&1 &
    sleep 2
fi

# Run the pipeline with the venv's python. Tee to a per-run log.
"$HOME/project3-pipeline/.venv/bin/python" pipeline.py > "$LOG" 2>&1
echo "exit=$? at $(date)" >> "$LOG"
```

`set -u` makes the script fail on an undefined variable. We call the venv's python by full path (`.venv/bin/python`) because cron does not run your shell's activation. `curl ... >/dev/null` checks the API quietly and starts it only if needed. Every run gets its own timestamped log.

Press `Esc`, type `:wq`, press Enter.

Make it executable:

```bash
chmod +x run_pipeline.sh
```

`chmod +x` grants execute permission so cron (and you) can run it directly.

Test the wrapper once by hand:

```bash
./run_pipeline.sh && tail -n 5 logs/pipeline_*.log | tail -n 5
```

`&&` runs the tail only if the wrapper succeeded; `tail -n 5` shows the last 5 lines of the newest log.

Expected output (yours will differ):

```
[report] wrote reports/quality_run-20260725-143012-d4e5f6.txt
...
[run] SUCCESS run-20260725-143012-d4e5f6
exit=0 at Sat Jul 25 14:30:13 UTC 2026
```

`exit=0` means the wrapper ran the whole pipeline cleanly.

---

## Step 20: Schedule the pipeline with cron

Now make it run itself every night. We schedule it for 2:00 AM, a common quiet hour for batch jobs (Concepts 3.5).

Still on your **lab server**, as **ec2-user**, open your crontab:

```bash
crontab -e
```

`crontab -e` opens your personal cron schedule in vi. Press `i`, then add this one line:

```
0 2 * * * /home/ec2-user/project3-pipeline/run_pipeline.sh
```

The five fields are: minute (0), hour (2), day-of-month (*), month (*), day-of-week (*). So "at 2:00 every day." Use the full path because cron has a bare environment. Press `Esc`, type `:wq`, press Enter.

Confirm it is registered:

```bash
crontab -l
```

`crontab -l` lists your scheduled jobs.

Expected output (yours will differ):

```
0 2 * * * /home/ec2-user/project3-pipeline/run_pipeline.sh
```

The pipeline will now run every night at 2 AM, writing a timestamped log and a quality report each time.

---

## Step 21: Write the pipeline documentation

Every pipeline needs a README so the next engineer (or the client) understands it. This is a deliverable, not an afterthought.

Still on your **lab server**, as **ec2-user**, open a new file:

```bash
vi README.md
```

Press `i`, then enter:

```markdown
# Project 3: AI-Ready Customer Data Pipeline

## What it does
Ingests customer records from a JSON API and a CSV, stores the raw snapshot,
cleans and validates against six data-quality dimensions, loads valid rows into
PostgreSQL (curated_customers), tracks every rejected record with a reason, and
writes a data-quality report. Runs nightly at 2 AM via cron.

## Sources (lineage)
- API: http://127.0.0.1:8899/customers  (api_server.py)
- CSV: raw/extra_customers.csv

## Tables
- curated_customers  - the clean product (one row per customer, carries run_id)
- pipeline_runs      - one row per run: status, counts, timestamps (audit trail)
- pipeline_failures  - one row per rejected record, with the reason

## Data quality rules (Concepts 3.4)
- completeness: email required
- accuracy: monthly_spend present and >= 0
- validity: customer_id and monthly_spend must parse as numbers
- consistency: region standardized to Title Case, must be a known region
- uniqueness: duplicate customer_id dropped (keep first)

## Run it by hand
    source .venv/bin/activate
    python api_server.py > logs/api.log 2>&1 &
    python pipeline.py

## Schedule
    crontab -l    # 0 2 * * * .../run_pipeline.sh
```

Press `Esc`, type `:wq`, press Enter.

---

## What you built

You now have a complete, production-shaped data pipeline: two sources, a raw landing zone, a cleaning-and-validation stage enforcing all six quality dimensions, an idempotent load into PostgreSQL, full failure tracking, a quality report, run-level lineage, cron scheduling, and documentation. This is the deliverable an AI/data consultant ships to make a client's data trustworthy enough to feed a model.

Next: in USE you apply a formal AI Data Readiness Checklist to a dataset and add Great-Expectations-style validation. In SURVIVE you defend this pipeline against the three failures that break real pipelines: a source renaming a column, quality regressions slipping through, and a scheduled job failing silently overnight.

To stop the background API when you are done for the day:

```bash
pkill -f api_server.py
```

`pkill -f` finds and stops the process whose command line matches `api_server.py`.
