# SURVIVE Runbook: A Data-Quality Regression Slips Through

**Tier 3 - SURVIVE scenario 2 of 3**

## The situation

A stakeholder emails: "Why does the revenue report look off?" You look, and the total is higher than it should be. Nothing crashed, no alert fired, the pipeline ran green. But duplicates and a null customer slipped into the curated table and quietly corrupted the numbers. This is a **silent data-quality regression** (Concepts 3.4), and it is the kind of failure that destroys client trust because the system swore everything was fine.

Your job: find the root cause with RCA, clean the corrupted data, and add a **data contract** so the same bad rows can never load again.

Every command block tells you which server and which user you are. You do all of this on your **lab server** (CentOS Stream 9) as **ec2-user**.

---

## Step 1: Reproduce the regression

On your **lab server**, as **ec2-user**:

```bash
bash ~/aiconsult-staging/tier03-data-engineering/survive/data-quality-regression/inject.sh
```

(Adjust the path if your copy of the scenario lives elsewhere.)

Expected output (yours will differ, last lines):

```
[inject] DONE. Revenue report now reads: 385.00 (should be 280.00 = 220 + 60).
[inject]   - order_id 3 was DUPLICATED (a retry double-counted 80.00)
[inject]   - order_id 7 has a NULL customer_id (unattributable revenue)
...
[inject] Your job: RCA it, clean it, and add a data contract that blocks it.
```

The report reads 385.00. The legitimate total is 280.00 (the five seeded orders plus one real new order), but a double-counted 80.00 duplicate and a 25.00 order with no customer inflated it by 105.00.

---

## Step 2: Move into the lab and activate the environment

On your **lab server**, as **ec2-user**:

```bash
cd ~/survive-dq-lab
```

Activate the environment:

```bash
source .venv/bin/activate
```

---

## Step 3: Confirm the symptom

Look at the report the stakeholder saw.

Still on your **lab server**, as **ec2-user**:

```bash
PGPASSWORD=labpass psql -h 127.0.0.1 -U labuser -d labdb -c "SELECT sum(amount) AS reported_revenue, count(*) AS rows FROM dq_curated;"
```

Expected output:

```
 reported_revenue | rows
------------------+------
           385.00 |    8
(1 row)
```

8 rows and 385.00, against an expected 280.00. Something is inflating both.

---

## Step 4: RCA - find the duplicates

Do not just fix the total. Find why it is wrong. First, hunt for duplicate order_ids (uniqueness, Concepts 3.4).

Still on your **lab server**, as **ec2-user**:

```bash
PGPASSWORD=labpass psql -h 127.0.0.1 -U labuser -d labdb -c "SELECT order_id, count(*) FROM dq_curated GROUP BY order_id HAVING count(*) > 1;"
```

`GROUP BY ... HAVING count(*) > 1` returns only order_ids that appear more than once.

Expected output:

```
 order_id | count
----------+-------
        3 |     2
(1 row)
```

Order 3 appears twice - an 80.00 charge counted twice. That accounts for 80.00 of the error.

---

## Step 5: RCA - find the nulls

Now hunt for missing customer_ids (completeness, Concepts 3.4).

Still on your **lab server**, as **ec2-user**:

```bash
PGPASSWORD=labpass psql -h 127.0.0.1 -U labuser -d labdb -c "SELECT * FROM dq_curated WHERE customer_id IS NULL;"
```

Expected output:

```
 order_id | customer_id | amount
----------+-------------+--------
        7 |             | 25.00
(1 row)
```

Order 7 has no customer - unattributable revenue. Now write the five whys (Concepts 3.4):

1. The revenue report is wrong. **Why?** Duplicate and null-customer rows are in dq_curated.
2. Why are they there? The loader inserted a retried batch and a broken source row.
3. Why did the duplicate load? The loader has no dedup - a blind INSERT accepts retries.
4. Why did the null load? The loader has no completeness check on customer_id.
5. Why were there no checks? There was no data contract enforced before the load.

Root cause: **no data contract on the load** - the loader trusted whatever arrived.

---

## Step 6: Clean the corrupted data

Now repair the table: remove the duplicate (keep one copy of order 3) and fix the null customer. We will attribute the orphan order to a placeholder "unknown customer" (id 0) rather than dropping revenue, and flag it - a common real choice so revenue reconciles while the anomaly stays visible.

First, delete the duplicate copy of order 3, keeping the lowest `ctid` (PostgreSQL's physical row identifier):

Still on your **lab server**, as **ec2-user**:

```bash
PGPASSWORD=labpass psql -h 127.0.0.1 -U labuser -d labdb -c "DELETE FROM dq_curated a USING dq_curated b WHERE a.order_id = b.order_id AND a.ctid > b.ctid;"
```

This self-join deletes any row (`a`) that shares an `order_id` with an earlier physical row (`b`), removing exactly the duplicate.

Expected output:

```
DELETE 1
```

Now attribute the orphan order to customer 0 (unknown) so revenue reconciles but the row is not lost:

```bash
PGPASSWORD=labpass psql -h 127.0.0.1 -U labuser -d labdb -c "UPDATE dq_curated SET customer_id = 0 WHERE customer_id IS NULL;"
```

Expected output:

```
UPDATE 1
```

Verify the report is now correct:

```bash
PGPASSWORD=labpass psql -h 127.0.0.1 -U labuser -d labdb -c "SELECT sum(amount) AS revenue, count(*) AS rows FROM dq_curated;"
```

Expected output:

```
 revenue | rows
---------+------
  305.00 |    7
(1 row)
```

305.00 across 7 rows. The duplicate 80.00 is gone (that removed the double-count), and the orphan order's 25.00 is retained but now attributed to the "unknown customer" (id 0) instead of being null - so revenue reconciles and the anomaly stays visible rather than being silently dropped. No customer_id is null.

---

## Step 7: Add a data contract so it never happens again

Cleaning is treating the symptom. The durable fix is a **data contract** (Concepts 3.4) enforced before any row loads. Write a contract-enforcing loader.

Still on your **lab server**, as **ec2-user**, open a new file:

```bash
vi contract_load.py
```

Press `i`, then enter:

```python
"""Contract-enforcing loader. The contract is checked BEFORE any row is loaded;
a violating batch is rejected in full, so bad data can never reach dq_curated."""
import sys
import psycopg2

# --- THE DATA CONTRACT (Concepts 3.4) ---
# order_id:    required, must be unique within the batch AND not already in the table
# customer_id: required, not null
# amount:      required, > 0
def enforce_contract(conn, batch):
    errors = []
    seen = set()
    with conn.cursor() as cur:
        cur.execute("SELECT order_id FROM dq_curated")
        existing = {r[0] for r in cur.fetchall()}
    for order_id, customer_id, amount in batch:
        if order_id is None:
            errors.append(f"order_id null in {batch}")
        if order_id in seen:
            errors.append(f"uniqueness: duplicate order_id {order_id} within batch")
        if order_id in existing:
            errors.append(f"uniqueness: order_id {order_id} already loaded")
        if customer_id is None:
            errors.append(f"completeness: null customer_id on order {order_id}")
        if amount is None or amount <= 0:
            errors.append(f"accuracy: bad amount {amount} on order {order_id}")
        seen.add(order_id)
    return errors

def load(batch):
    conn = psycopg2.connect(host="127.0.0.1", dbname="labdb", user="labuser", password="labpass")
    errors = enforce_contract(conn, batch)
    if errors:
        conn.close()
        print("[contract] REJECTED batch - contract violations:")
        for e in errors:
            print("  -", e)
        sys.exit(1)   # loud, non-zero exit so cron/CI catches it
    with conn.cursor() as cur:
        for order_id, customer_id, amount in batch:
            cur.execute(
                "INSERT INTO dq_curated (order_id, customer_id, amount) VALUES (%s,%s,%s)",
                (order_id, customer_id, amount),
            )
    conn.commit()
    conn.close()
    print(f"[contract] loaded {len(batch)} rows (contract passed)")

if __name__ == "__main__":
    # Re-play the same bad batch to prove the contract blocks it.
    bad_batch = [(8, 108, 15.00), (3, 103, 80.00), (9, None, 25.00)]
    load(bad_batch)
```

Press `Esc`, type `:wq`, press Enter.

---

## Step 8: Prove the contract blocks the bad batch

Run the contract loader with the same kind of bad batch the regression came from.

Still on your **lab server**, as **ec2-user**:

```bash
python contract_load.py
```

Expected output (yours will differ):

```
[contract] REJECTED batch - contract violations:
  - uniqueness: order_id 3 already loaded
  - completeness: null customer_id on order 9
[contract] ... 
```

Check the exit code:

```bash
echo "exit code: $?"
```

Expected output:

```
exit code: 1
```

The contract caught the duplicate and the null before either could load, and exited non-zero so an orchestrator would alert. The revenue report stays correct because nothing bad got in.

---

## Step 9: Confirm the good data is untouched

The rejected batch must not have partially loaded. Verify the table is still clean.

Still on your **lab server**, as **ec2-user**:

```bash
PGPASSWORD=labpass psql -h 127.0.0.1 -U labuser -d labdb -c "SELECT sum(amount) AS revenue, count(*) AS rows, count(*) FILTER (WHERE customer_id IS NULL) AS null_customers FROM dq_curated;"
```

`FILTER (WHERE ...)` counts only the rows matching the condition.

Expected output:

```
 revenue | rows | null_customers
---------+------+----------------
  305.00 |    7 |              0
(1 row)
```

Still 305.00, 7 rows, zero null customers. The contract rejected the whole bad batch atomically - no partial corruption.

---

## Step 10: Validate

Still on your **lab server**, as **ec2-user**:

```bash
bash ~/aiconsult-staging/tier03-data-engineering/survive/data-quality-regression/validate.sh
```

Expected output:

```
[validate] PASS: data cleaned (305.00, 7 rows, no dupes, no nulls) and contract_load.py enforces a contract
```

---

## The lesson

Silent regressions are worse than crashes because nobody knows to look. The fix has two parts you just practiced: (1) RCA to find the true root cause - "no contract," not "duplicates" - and (2) a contract enforced before the load, checking uniqueness, completeness, and accuracy, failing the whole batch loudly on any violation. A crash you notice in minutes; a silent regression you notice when a client stops trusting your numbers. Contracts turn silent regressions into loud, early rejections. This is the discipline behind data observability (Concepts 3.4).
