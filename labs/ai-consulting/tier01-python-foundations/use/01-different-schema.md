# USE: Run Project 1 Against a Different Schema

**Goal:** prove that Project 1's summarizer logic is not hard-coded to support tickets. You will point the same categorization logic at a completely different table - IT incident tickets - and get a correct summary. If the logic is well written, it should adapt with almost no change. This is the difference between a demo and reusable software.

**Where you are:** the lab server, as **ec2-user**, with Project 1 in `~/project1` from the BUILD guide. PostgreSQL `labdb` (user `labuser`, password `labpass`) is running.

**What you will practice:** functions, dicts, environment-driven config, and SQL - the idea that clean code separates *logic* from *data*.

---

## Step 1: Look at the categorization logic you are about to reuse

On your **lab server**, as **ec2-user**, go to the project and view the function:

```bash
cd ~/project1
```

```bash
grep -A 12 "def categorize" app.py
```

Expected output (yours will differ):

```
def categorize(subject: str, body: str | None) -> str:
    """Assign a category from keyword rules, or 'uncategorized'."""
    text = f"{subject} {body or ''}".lower()
    for category, keywords in KEYWORD_RULES.items():
        if any(k in text for k in keywords):
            return category
    return "uncategorized"
```

`grep -A 12` prints the matching line plus the 12 lines after it (`-A` = "after"). Notice `categorize()` only knows about text and a rules dict. It does not know the word "support" or the table name. That is why it will work on a different schema.

---

## Step 2: Create the new schema (IT incidents)

You will make a second table with different column names on purpose, to prove the logic is not tied to `support_tickets`.

Still on the **lab server**, as **ec2-user**, create the seed file with `vi`:

```bash
vi it_incidents.sql
```

Press `i` to enter insert mode, type the following, then press `Esc` and type `:wq` to save and quit:

```sql
-- IT incident tickets: different table, different column names.
CREATE TABLE IF NOT EXISTS it_incidents (
    incident_id  SERIAL PRIMARY KEY,
    title        TEXT NOT NULL,
    detail       TEXT,
    team         TEXT,
    opened_at    TIMESTAMPTZ DEFAULT now()
);

INSERT INTO it_incidents (title, detail, team) VALUES
    ('VPN keeps disconnecting',     'Login drops every 5 minutes',        'network'),
    ('Cannot sign in to email',     'Password rejected after reset',       NULL),
    ('Printer offline',             'Timeout when sending large jobs',     'endpoint'),
    ('Laptop very slow',            'Everything lags after update',        NULL),
    ('Disk full on file server',    'Backup job crashed overnight',        'storage'),
    ('Shared drive error',          'Access denied, broken mapping',       NULL),
    ('New hire account request',    'Please create an account',            'identity'),
    ('',                            'blank title should be skipped',       NULL);
```

Note the last row has a blank title on purpose - your cleaning logic must skip it, just like it skips blank subjects in the support table.

---

## Step 3: Load the new table

Still on the **lab server**, as **ec2-user**:

```bash
PGPASSWORD=labpass psql -h 127.0.0.1 -U labuser -d labdb -f it_incidents.sql
```

`-f` runs the SQL file. `PGPASSWORD=labpass` passes the password for this one command without storing it.

Expected output:

```
CREATE TABLE
INSERT 0 8
```

`INSERT 0 8` means 8 rows loaded (7 real incidents plus the blank-title row).

---

## Step 4: Write a small reusable summarizer script

You will not edit `app.py`. Instead you write a tiny script that **imports** `categorize` from it and runs it against any table whose columns you name via environment variables. This is the payoff of writing a pure function - you reuse it without touching it.

Still on the **lab server**, as **ec2-user**, create the script with `vi`:

```bash
vi summarize_table.py
```

Press `i`, type the following, then `Esc` and `:wq`:

```python
"""Summarize ANY ticket-like table by reusing app.categorize.

Table and column names come from environment variables, so nothing
is hard-coded. Config out of code - same idea as app.py's DB settings.
"""
import os
from collections import Counter

import psycopg2
import psycopg2.extras

from app import categorize  # reuse the exact logic from Project 1

DB = dict(
    host=os.environ.get("DB_HOST", "127.0.0.1"),
    dbname=os.environ.get("DB_NAME", "labdb"),
    user=os.environ.get("DB_USER", "labuser"),
    password=os.environ.get("DB_PASSWORD", "labpass"),
)

# which table and columns to read - defaults to the original support table
TABLE = os.environ.get("TABLE", "support_tickets")
SUBJECT_COL = os.environ.get("SUBJECT_COL", "subject")
BODY_COL = os.environ.get("BODY_COL", "body")
CATEGORY_COL = os.environ.get("CATEGORY_COL", "category")

query = (
    f"SELECT {SUBJECT_COL} AS subject, {BODY_COL} AS body, "
    f"{CATEGORY_COL} AS category FROM {TABLE};"
)

conn = psycopg2.connect(**DB)
try:
    with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
        cur.execute(query)
        rows = cur.fetchall()
finally:
    conn.close()

counts: Counter = Counter()
skipped = 0
for row in rows:
    subject = (row["subject"] or "").strip()
    if not subject:
        skipped += 1
        continue
    category = row["category"] or categorize(subject, row["body"])
    counts[category] += 1

print("table:", TABLE)
print("skipped_blank:", skipped)
print("total:", sum(counts.values()))
for category, n in sorted(counts.items(), key=lambda kv: (-kv[1], kv[0])):
    print(f"  {category}: {n}")
```

Note: the SQL column names come from config here to keep the exercise focused. In production you would use an allow-list of column names, never raw user input, to avoid SQL injection - a point you will meet again in later tiers.

---

## Step 5: Run it against the ORIGINAL table first (sanity check)

Activate the virtual environment, then run with the defaults so you confirm the reused logic still matches BUILD.

Still on the **lab server**, as **ec2-user**, in `~/project1`:

```bash
source .venv/bin/activate
```

```bash
python summarize_table.py
```

Expected output (yours will differ):

```
table: support_tickets
skipped_blank: 0
total: 10
  billing: 3
  auth: 2
  bug: 2
  feature: 1
  performance: 1
  uncategorized: 1
```

This matches the BUILD `/summary` result. The imported `categorize` behaves identically - good.

---

## Step 6: Run it against the NEW schema by changing only environment variables

Now point the same script at `it_incidents` by setting the table and column names. You change **zero lines of code** - only the environment.

Still in the activated environment, as **ec2-user**:

```bash
TABLE=it_incidents SUBJECT_COL=title BODY_COL=detail CATEGORY_COL=team python summarize_table.py
```

Setting variables before the command applies them just for that run. `TABLE=it_incidents` tells the script the new table; `SUBJECT_COL=title` maps the incident's `title` to what the logic calls "subject", and so on.

Expected output (yours will differ):

```
table: it_incidents
skipped_blank: 1
total: 7
  network: 1
  storage: 1
  endpoint: 1
  identity: 1
  auth: 2
  uncategorized: 1
```

Read this carefully:

- **skipped_blank: 1** - the blank-title row was correctly skipped by the same cleaning rule.
- Rows that already had a `team` value (network, storage, endpoint, identity) kept it.
- The two rows with no team but text like "sign in" / "password" got `auth` from the keyword rules - the exact same rules from `app.py`.
- "New hire account request" matched no keyword and had no team, so it correctly became `uncategorized`.

---

## Step 7: Prove it is the reuse, not a copy

Confirm you never modified `app.py`:

```bash
grep -c "it_incidents" app.py
```

Expected output:

```
0
```

Zero. The original application has no knowledge of the new schema. All the new behavior came from importing one function and changing environment variables.

Deactivate when done:

```bash
deactivate
```

---

## What you just proved

- `categorize()` is a **pure, reusable function** - it works on any text, not just support tickets.
- **Config out of code** (environment variables) let the same script target a different table and different column names with no code change.
- **Cleaning rules generalize**: blank-subject skipping and keyword categorization applied correctly to a schema they were never written for.

This is the core lesson of Tier 1 software engineering: separate your *logic* from your *data and config*, and your code becomes reusable instead of disposable.

## Stretch (optional)

- Add an `it_incidents`-specific keyword rule (for example a `network` category with keywords `vpn`, `wifi`, `disconnect`) by extending `KEYWORD_RULES` in a copy of the script, and see how the counts change - without touching `app.py`.
- Move the summary logic in `summarize_table.py` into a function `summarize(rows)` and write a pytest for it, the way `test_app.py` tests `categorize`.
