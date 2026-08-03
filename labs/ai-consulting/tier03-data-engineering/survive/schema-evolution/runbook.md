# SURVIVE Runbook: Schema Evolution Breaks the Pipeline

**Tier 3 - SURVIVE scenario 1 of 3**

## The situation

Your nightly pipeline has run fine for weeks. This morning it either crashed or - worse - loaded a column full of nulls. Nobody on your team changed anything. What happened: the upstream team that owns the source data renamed a column (`full_name` became `customer_name`) and added a new one (`phone`), and did not tell you. This is **schema drift**, and it is the single most common way a working pipeline breaks (Concepts 3.5).

Your job: detect the change, adapt the loader to the new schema, and backfill the row that arrived during the break - without losing the historical data you already loaded.

Every command block tells you which server and which user you are. You do all of this on your **lab server** (CentOS Stream 9) as **ec2-user**.

---

## Step 1: Reproduce the failure

First, break it so you can practice the fix.

On your **lab server**, as **ec2-user**:

```bash
bash ~/aiconsult-staging/tier03-data-engineering/survive/schema-evolution/inject.sh
```

(If your copy of the scenario is elsewhere, adjust the path to where `inject.sh` lives.)

This builds a mini pipeline in `~/survive-schema-lab`, runs it once cleanly, then evolves the source schema underneath it.

Expected output (yours will differ, last lines):

```
[inject] DONE. The source schema changed under the pipeline:
[inject]   - 'full_name' was RENAMED to 'customer_name'
...
[inject] Your job: detect the drift, adapt the loader, and backfill row 4.
```

---

## Step 2: Move into the lab and activate the environment

On your **lab server**, as **ec2-user**:

```bash
cd ~/survive-schema-lab
```

`cd` changes into the lab folder. Activate the virtual environment the injector built:

```bash
source .venv/bin/activate
```

Your prompt now shows `(.venv)`.

---

## Step 3: Watch it fail

Run the pipeline exactly as cron would.

Still on your **lab server**, as **ec2-user**:

```bash
python load.py
```

Expected output (this is the symptom):

```
Traceback (most recent call last):
  ...
    (int(r["customer_id"]), r["email"], r["full_name"], r["region"]),
                                        ~^^^^^^^^^^^^^
KeyError: 'full_name'
```

The loader asked for `full_name`, which no longer exists in the source. In a pipeline that used `.get()` instead of `[]`, you would get no crash at all - just a column silently filled with nulls, which is far more dangerous.

---

## Step 4: Diagnose - compare actual schema to expected

Do not guess. Print what the source actually has now versus what the pipeline expected.

Still on your **lab server**, as **ec2-user**:

```bash
python -c "import pandas as pd; print('actual:', list(pd.read_csv('source.csv').columns))"
```

`python -c` runs a one-line program. This prints the source's current columns.

Expected output:

```
actual: ['customer_id', 'email', 'customer_name', 'region', 'phone']
```

Compare against the pipeline's `EXPECTED` list:

```bash
grep EXPECTED load.py
```

`grep` finds the line so you can read the expected schema.

Expected output:

```
EXPECTED = ["customer_id", "email", "full_name", "region"]   # the schema we were built for
```

The diff is clear: `full_name` is gone (renamed to `customer_name`), and `phone` is new. This is the detect step of detect-and-adapt (Concepts 3.5).

---

## Step 5: Add schema-drift detection to the loader

The real lesson is not "hand-fix it once" - it is "make the pipeline detect drift and refuse to load garbage." Open the loader:

```bash
vi load.py
```

Press `i` to enter insert mode. We add a drift check and a rename map. Replace the whole file contents with the following adapted version (select-all in vi: with the cursor at the top, you can also delete existing lines first with `dG`, then paste):

```python
import sys
import pandas as pd
import psycopg2

DB = dict(host="127.0.0.1", dbname="labdb", user="labuser", password="labpass")

# The contract: the columns the pipeline needs, and how to map renamed sources.
REQUIRED = ["customer_id", "email", "full_name", "region"]
RENAMES = {"customer_name": "full_name"}     # adapt known upstream renames
OPTIONAL_NEW = {"phone"}                       # new columns we tolerate (do not fail on them)

def detect_and_adapt(df):
    """Detect schema drift against the contract, adapt known renames, and
    fail loudly on anything we cannot handle (Concepts 3.5 detect-and-adapt)."""
    incoming = set(df.columns)

    # 1. Apply known renames so the rest of the pipeline sees the expected names.
    df = df.rename(columns=RENAMES)

    # 2. New columns we did not expect: tolerate the allow-listed ones, warn on the rest.
    known = set(REQUIRED) | OPTIONAL_NEW | set(RENAMES.keys())
    unexpected = incoming - known
    if unexpected:
        print(f"[drift] WARNING: unexpected new columns ignored: {sorted(unexpected)}")

    # 3. Required columns still missing after renames: FAIL loudly, do not load nulls.
    missing = [c for c in REQUIRED if c not in df.columns]
    if missing:
        raise SystemExit(f"[drift] FATAL: required columns missing after adapt: {missing}. "
                         f"Update RENAMES in load.py or contact the source owner.")
    print(f"[drift] schema OK after adapt (source had {sorted(incoming)})")
    return df

def main():
    df = pd.read_csv("source.csv")
    df = detect_and_adapt(df)

    conn = psycopg2.connect(**DB)
    with conn.cursor() as cur:
        cur.execute("""CREATE TABLE IF NOT EXISTS schema_curated (
            customer_id INTEGER PRIMARY KEY,
            email TEXT,
            full_name TEXT,
            region TEXT,
            phone TEXT)""")
        # Backfill the new 'phone' column onto the existing table if it is not there yet.
        cur.execute("ALTER TABLE schema_curated ADD COLUMN IF NOT EXISTS phone TEXT")
        for _, r in df.iterrows():
            phone = r["phone"] if "phone" in df.columns else None
            cur.execute(
                """INSERT INTO schema_curated (customer_id, email, full_name, region, phone)
                   VALUES (%s,%s,%s,%s,%s)
                   ON CONFLICT (customer_id) DO UPDATE SET
                     email=EXCLUDED.email, full_name=EXCLUDED.full_name,
                     region=EXCLUDED.region, phone=EXCLUDED.phone""",
                (int(r["customer_id"]), r["email"], r["full_name"], r["region"], phone),
            )
    conn.commit()
    conn.close()
    print(f"[load] loaded {len(df)} rows")

if __name__ == "__main__":
    main()
```

Press `Esc`, type `:wq`, press Enter to save and quit.

The three changes that matter: a `RENAMES` map that adapts the known upstream rename, an `ALTER TABLE ... ADD COLUMN IF NOT EXISTS` that backfills the new `phone` column onto the existing table without dropping history, and a loud `SystemExit` if a required column is still missing - so the pipeline never silently loads nulls.

---

## Step 6: Re-run the adapted pipeline

Still on your **lab server**, as **ec2-user**:

```bash
python load.py
```

Expected output (yours will differ):

```
[drift] schema OK after adapt (source had ['customer_id', 'email', 'customer_name', 'phone', 'region'])
[load] loaded 4 rows
```

It adapted the rename, tolerated the new `phone` column, and loaded all 4 rows including the new customer that arrived during the break.

---

## Step 7: Verify the data and the backfill

Confirm the historical rows kept their names AND the new column and row are present.

Still on your **lab server**, as **ec2-user**:

```bash
PGPASSWORD=labpass psql -h 127.0.0.1 -U labuser -d labdb -c "SELECT customer_id, full_name, region, phone FROM schema_curated ORDER BY customer_id;"
```

Expected output (yours will differ):

```
 customer_id |   full_name   | region |  phone
-------------+---------------+--------+----------
           1 | Ada Lovelace  | East   | 555-0001
           2 | Ben Franklin  | West   | 555-0002
           3 | Cy Young      | East   | 555-0003
           4 | Dee Spacer    | North  | 555-0004
(4 rows)
```

Rows 1-3 kept their `full_name` (the rename was adapted, not lost) and gained a backfilled `phone`; row 4 arrived cleanly. No nulls, no lost history.

---

## Step 8: Validate

Run the validator to confirm the scenario is solved.

Still on your **lab server**, as **ec2-user**:

```bash
bash ~/aiconsult-staging/tier03-data-engineering/survive/schema-evolution/validate.sh
```

Expected output:

```
[validate] PASS: schema drift adapted, phone backfilled, row 4 loaded, no nulls
```

---

## The lesson (RCA)

Ask the five whys (Concepts 3.4):

1. The pipeline broke. **Why?** A required column disappeared.
2. Why did it disappear? The source team renamed `full_name` to `customer_name`.
3. Why did that break us? Our loader hard-coded the source's column names.
4. Why was there no warning? We had no schema check - we assumed the schema was fixed.
5. Why did we assume that? No data contract existed between us and the source team.

The root cause is not "the rename" - upstream schemas will always change. The root cause is **no contract and no drift detection**. The durable fix you just built is detect-and-adapt driven by a defined schema: adapt known changes, tolerate additive ones, and fail loudly (never silently) on breaking ones. In a real engagement you would also write a data contract (Concepts 3.4) so the source team is on the hook to announce changes.
