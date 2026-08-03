# USE: Data Validation Checks and a Transformation Model

**Tier 3 - USE phase.** In BUILD your pipeline validated data with hand-written checks inside the load loop. That works, but real teams use dedicated validation tooling (Great Expectations) and dedicated transformation tooling (dbt) so the checks and transforms are declarative, versioned, and testable on their own. This exercise teaches the ideas with lightweight, dependable stand-ins that run on the box, then shows how they map to the real tools.

**Validated on:** CentOS Stream 9, Python 3.12, PostgreSQL (labdb), on 2026-07-25.

**Prerequisite:** you finished BUILD Project 3 (you have `curated_customers` in labdb) and read Concepts 3.4-3.5. You should have a virtual environment with pandas and psycopg2 - if not, create one as shown below.

**Goal:** build (1) a Great-Expectations-style validation suite - named data expectations that pass or fail loudly - and (2) a simple dbt-style transformation model that builds a curated summary table with SQL, both runnable and repeatable.

**Why not the real tools?** Great Expectations and dbt are heavy installs that can drift on a bare lab box. The concepts - declarative expectations, a validation report, SQL-defined models, and model tests - are what matter and what interviewers ask about. We build faithful minimal versions here and point to the real tools at the end.

---

## Step 1: Set up the project

On your **lab server** (CentOS Stream 9), as **ec2-user**:

```bash
mkdir -p ~/use-validation
```

Move into it:

```bash
cd ~/use-validation
```

Create and activate a virtual environment:

```bash
python3.12 -m venv .venv
```

```bash
source .venv/bin/activate
```

Install the libraries:

```bash
pip install pandas psycopg2-binary
```

---

## Step 2: Understand the Great Expectations idea

Great Expectations lets you declare **expectations** about data - readable assertions like "column customer_id is never null" or "monthly_spend is between 0 and 10000" - then validates any batch against them and produces a report of which passed and which failed. The value is that expectations are declarative (you state the rule, not the loop), named, and versioned in git.

We build a tiny expectation engine that mirrors the real API's method names so the concept transfers directly.

Still on your **lab server**, as **ec2-user**, open a new file:

```bash
vi expectations.py
```

Press `i`, then enter:

```python
"""A minimal Great-Expectations-style validator. Each method is an 'expectation'
that records a pass/fail result. Mirrors the real GE method names so the concept
transfers 1:1 to the real library."""
import pandas as pd


class Expectations:
    def __init__(self, df, name="batch"):
        self.df = df
        self.name = name
        self.results = []

    def _record(self, expectation, success, detail):
        self.results.append({"expectation": expectation, "success": success, "detail": detail})

    def expect_column_values_to_not_be_null(self, col):
        n_null = self.df[col].isna().sum()
        self._record(f"{col} not null", n_null == 0, f"{n_null} nulls")
        return self

    def expect_column_values_to_be_unique(self, col):
        n_dupe = self.df[col].duplicated().sum()
        self._record(f"{col} unique", n_dupe == 0, f"{n_dupe} duplicates")
        return self

    def expect_column_values_to_be_between(self, col, low, high):
        bad = ((self.df[col] < low) | (self.df[col] > high)).sum()
        self._record(f"{col} in [{low},{high}]", bad == 0, f"{bad} out of range")
        return self

    def expect_column_values_to_be_in_set(self, col, allowed):
        bad = (~self.df[col].isin(allowed) & self.df[col].notna()).sum()
        self._record(f"{col} in set", bad == 0, f"{bad} not in {sorted(allowed)}")
        return self

    def report(self):
        passed = sum(r["success"] for r in self.results)
        total = len(self.results)
        print("=" * 55)
        print(f"VALIDATION REPORT - {self.name}: {passed}/{total} expectations passed")
        print("=" * 55)
        for r in self.results:
            mark = "PASS" if r["success"] else "FAIL"
            print(f"  [{mark}] {r['expectation']:22s} ({r['detail']})")
        return passed == total
```

Press `Esc`, type `:wq`, press Enter.

---

## Step 3: Run the validation suite against the curated table

Now point the expectations at the real `curated_customers` table your BUILD pipeline produced.

Still on your **lab server**, as **ec2-user**, open a new file:

```bash
vi validate_curated.py
```

Press `i`, then enter:

```python
import sys
import pandas as pd
import psycopg2
from expectations import Expectations

conn = psycopg2.connect(host="127.0.0.1", dbname="labdb", user="labuser", password="labpass")
df = pd.read_sql("SELECT * FROM curated_customers", conn)
conn.close()

exp = Expectations(df, name="curated_customers")
(exp
 .expect_column_values_to_not_be_null("customer_id")
 .expect_column_values_to_not_be_null("email")
 .expect_column_values_to_be_unique("customer_id")
 .expect_column_values_to_be_between("monthly_spend", 0, 10000)
 .expect_column_values_to_be_in_set("region", {"East", "West", "North", "South"}))

ok = exp.report()
sys.exit(0 if ok else 1)   # non-zero exit so a pipeline/cron can detect failure
```

Press `Esc`, type `:wq`, press Enter. Run it:

```bash
python validate_curated.py
```

Expected output (yours will differ):

```
=======================================================
VALIDATION REPORT - curated_customers: 5/5 expectations passed
=======================================================
  [PASS] customer_id not null    (0 nulls)
  [PASS] email not null          (0 nulls)
  [PASS] customer_id unique      (0 duplicates)
  [PASS] monthly_spend in [0,10000] (0 out of range)
  [PASS] region in set           (0 not in ['East', 'North', 'South', 'West'])
```

All five pass because your BUILD pipeline already cleaned the data. The `sys.exit(1)` on failure is what lets you wire this into cron so a bad batch is caught automatically. Confirm the exit code:

```bash
echo "exit code: $?"
```

Expected output:

```
exit code: 0
```

---

## Step 4: Prove the suite catches bad data

A validation suite that only ever passes is useless. Deliberately insert a bad row, re-run, and watch it fail loudly.

Still on your **lab server**, as **ec2-user**, insert one bad row directly:

```bash
PGPASSWORD=labpass psql -h 127.0.0.1 -U labuser -d labdb -c "INSERT INTO curated_customers (customer_id, email, full_name, region, monthly_spend, run_id) VALUES (999, 'bad@x.com', 'Bad Row', 'Mars', 99999, 'manual-bad');"
```

`region` is `Mars` (not an allowed value) and `monthly_spend` is 99999 (out of range). Re-run the suite:

```bash
python validate_curated.py
```

Expected output (yours will differ):

```
=======================================================
VALIDATION REPORT - curated_customers: 3/5 expectations passed
=======================================================
  [PASS] customer_id not null    (0 nulls)
  [PASS] email not null          (0 nulls)
  [PASS] customer_id unique      (0 duplicates)
  [FAIL] monthly_spend in [0,10000] (1 out of range)
  [FAIL] region in set           (1 not in ['East', 'North', 'South', 'West'])
```

Two expectations fail, naming exactly what is wrong. Check the exit code:

```bash
echo "exit code: $?"
```

Expected output:

```
exit code: 1
```

A non-zero exit is how cron or a CI job knows to alert. Now clean up the bad row:

```bash
PGPASSWORD=labpass psql -h 127.0.0.1 -U labuser -d labdb -c "DELETE FROM curated_customers WHERE run_id = 'manual-bad';"
```

Expected output:

```
DELETE 1
```

---

## Step 5: Understand the dbt idea

dbt (data build tool) lets you define transformations as **SQL models** - each model is a `SELECT` that builds a table or view - plus **tests** on those models, all versioned in git. The pattern is "transform in the warehouse with SQL" (the T in ELT, Concepts 3.5). We build a minimal version: a SQL model file and a runner that materializes it as a table.

Still on your **lab server**, as **ec2-user**, create a models folder:

```bash
mkdir -p models
```

Open the first model - a per-region summary over the curated customers:

```bash
vi models/customer_summary.sql
```

Press `i`, then enter:

```sql
-- dbt-style model: customer_summary
-- Depends on: curated_customers (upstream lineage)
-- Builds a per-region rollup a dashboard or a model can consume.
SELECT
    region,
    count(*)                       AS customer_count,
    round(avg(monthly_spend), 2)   AS avg_spend,
    round(sum(monthly_spend), 2)   AS total_spend,
    max(signup_date)               AS latest_signup
FROM curated_customers
WHERE region IS NOT NULL
GROUP BY region
ORDER BY total_spend DESC
```

Press `Esc`, type `:wq`, press Enter.

---

## Step 6: Write the model runner

The runner reads a `.sql` model and materializes it as a table named after the file, using `CREATE TABLE AS`. This is what dbt does under the hood.

Still on your **lab server**, as **ec2-user**, open a new file:

```bash
vi run_models.py
```

Press `i`, then enter:

```python
"""Minimal dbt-style model runner: reads models/*.sql and materializes each as a
table named after the file (model name). Idempotent via DROP ... IF EXISTS."""
from pathlib import Path
import psycopg2

conn = psycopg2.connect(host="127.0.0.1", dbname="labdb", user="labuser", password="labpass")

for sql_file in sorted(Path("models").glob("*.sql")):
    model = sql_file.stem                      # filename without .sql = model/table name
    body = sql_file.read_text()
    with conn.cursor() as cur:
        cur.execute(f"DROP TABLE IF EXISTS {model}")          # idempotent rebuild
        cur.execute(f"CREATE TABLE {model} AS\n{body}")
        cur.execute(f"SELECT count(*) FROM {model}")
        rows = cur.fetchone()[0]
    conn.commit()
    print(f"[model] built {model} ({rows} rows) from {sql_file}")

conn.close()
```

Press `Esc`, type `:wq`, press Enter. Run it:

```bash
python run_models.py
```

Expected output (yours will differ):

```
[model] built customer_summary (4 rows) from models/customer_summary.sql
```

Inspect the model output:

```bash
PGPASSWORD=labpass psql -h 127.0.0.1 -U labuser -d labdb -c "SELECT * FROM customer_summary;"
```

Expected output (yours will differ):

```
 region | customer_count | avg_spend | total_spend | latest_signup
--------+----------------+-----------+-------------+---------------
 East   |              3 |    206.83 |      620.50 | 2026-06-01
 West   |              3 |    108.50 |      325.50 | 2026-06-15
 South  |              1 |     60.00 |       60.00 | 2026-07-10
(3 rows)
```

You just ran an ELT transform: raw was already loaded, and this SQL model shaped it into a curated summary inside the warehouse.

---

## Step 7: Add a model test

dbt models come with tests - assertions about the model's output. Add a test that the summary has no null region and every count is positive.

Still on your **lab server**, as **ec2-user**, open a new file:

```bash
vi test_models.py
```

Press `i`, then enter:

```python
import sys
import psycopg2

conn = psycopg2.connect(host="127.0.0.1", dbname="labdb", user="labuser", password="labpass")
failures = []
with conn.cursor() as cur:
    cur.execute("SELECT count(*) FROM customer_summary WHERE region IS NULL")
    if cur.fetchone()[0] > 0:
        failures.append("customer_summary has NULL region")
    cur.execute("SELECT count(*) FROM customer_summary WHERE customer_count <= 0")
    if cur.fetchone()[0] > 0:
        failures.append("customer_summary has non-positive customer_count")
conn.close()

if failures:
    for f in failures:
        print("[test] FAIL:", f)
    sys.exit(1)
print("[test] PASS: all model tests passed")
```

Press `Esc`, type `:wq`, press Enter. Run it:

```bash
python test_models.py
```

Expected output:

```
[test] PASS: all model tests passed
```

---

## Step 8: How this maps to the real tools

You built the concepts by hand. Here is the exact mapping so you can speak to it in an interview and pick up the real tools quickly:

- **Great Expectations.** Your `Expectations` class methods (`expect_column_values_to_not_be_null`, `expect_column_values_to_be_between`, `expect_column_values_to_be_in_set`) are the real GE method names. In GE you write these in an "expectation suite" (JSON/YAML), run `checkpoint`s that validate a batch, and get an HTML "data docs" report. The pass/fail-with-exit-code pattern you built is exactly how GE gates a pipeline.
- **dbt.** Your `models/customer_summary.sql` is a dbt model; dbt uses `{{ ref('curated_customers') }}` to wire lineage automatically and `dbt run` to materialize models as tables or views. Your `test_models.py` maps to dbt's built-in tests (`not_null`, `unique`, `accepted_values`) declared in a `schema.yml`. dbt also auto-generates lineage graphs and docs.

The reason we teach the concepts first: tools change, the ideas do not. A consultant who understands "declarative expectations, validated per batch, gating the pipeline on a non-zero exit" and "SQL models with tests and lineage" can adopt GE, dbt, Soda, or whatever a client already uses in a day.

---

## What you built

You have a validation suite that declares named expectations, validates the real curated table, fails loudly with a non-zero exit when data is bad (proven by inserting and catching a bad row), plus a dbt-style SQL transformation model with its own test. Together these are the two pieces that turn a fragile pipeline into a trustworthy one: automated checks that gate the data, and versioned SQL transforms that shape it. This is what "add validation and a transformation model" means in a real engagement, and you can now do it with hand-rolled code or with Great Expectations and dbt.
