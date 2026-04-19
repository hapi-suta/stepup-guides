# Module 05 - SQL Fundamentals
## Guide 04: Transactions and Isolation Levels

**Objective:** Control transactions with BEGIN, COMMIT, ROLLBACK, and SAVEPOINT. Understand the four isolation levels and reproduce concurrency anomalies (dirty reads, non-repeatable reads, phantom reads) using two psql sessions.

**Time:** 40-45 minutes

**Prerequisites:**
- Guides 01-03 complete
- Two SSH sessions open to your server simultaneously

---

## 1. Setup - Open Two Sessions

You need two terminal windows for this guide. Each window runs a separate psql session to simulate concurrent database users.

**Terminal A - Session 1:**

```bash
ssh -i your-key.pem ec2-user@[YOUR_SERVER_IP]
```

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

**Terminal B - Session 2** (open a new terminal window, repeat the same steps):

```bash
ssh -i your-key.pem ec2-user@[YOUR_SERVER_IP]
```

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

Both sessions should now show the `stepup_store=#` prompt.

Create a test table in Session 1:

```sql
CREATE TABLE IF NOT EXISTS tx_accounts (
  account_id  SERIAL PRIMARY KEY,
  name        VARCHAR(100) NOT NULL,
  balance     NUMERIC(12,2) NOT NULL DEFAULT 0.00
);
```

```sql
INSERT INTO tx_accounts (name, balance) VALUES
  ('Alice', 1000.00),
  ('Bob',   500.00),
  ('Carol', 2500.00);
```

```sql
SELECT * FROM tx_accounts;
```

Expected output:

```
 account_id | name  | balance
------------+-------+---------
          1 | Alice | 1000.00
          2 | Bob   |  500.00
          3 | Carol | 2500.00
(3 rows)
```

---

## 2. Basic Transaction Control

Every SQL statement that does not have an explicit `BEGIN` runs in its own implicit single-statement transaction - it is automatically committed when it completes.

Start an explicit transaction with `BEGIN`:

```sql
BEGIN;
```

Expected output:

```
BEGIN
```

Make a change - transfer $200 from Alice to Bob:

```sql
UPDATE tx_accounts SET balance = balance - 200 WHERE name = 'Alice';
```

```sql
UPDATE tx_accounts SET balance = balance + 200 WHERE name = 'Bob';
```

Check the balances within this transaction:

```sql
SELECT name, balance FROM tx_accounts ORDER BY name;
```

Expected output:

```
 name  | balance
-------+---------
 Alice |  800.00
 Bob   |  700.00
 Carol | 2500.00
(3 rows)
```

**Switch to Session 2** and check what it sees:

```sql
SELECT name, balance FROM tx_accounts ORDER BY name;
```

Expected output (Session 2, before Session 1 commits):

```
 name  | balance
-------+---------
 Alice | 1000.00
 Bob   |  500.00
 Carol | 2500.00
(3 rows)
```

Session 2 still sees the original values. The changes in Session 1 are not visible until committed.

**Return to Session 1** and commit:

```sql
COMMIT;
```

Expected output:

```
COMMIT
```

**Switch to Session 2** and check again:

```sql
SELECT name, balance FROM tx_accounts ORDER BY name;
```

Expected output:

```
 name  | balance
-------+---------
 Alice |  800.00
 Bob   |  700.00
 Carol | 2500.00
(3 rows)
```

Now Session 2 sees the committed values.

> **Concept: Atomicity - all or nothing**
> A transaction is atomic. Either all statements inside it succeed and are committed, or none of them take effect. In the money transfer example, if the server crashed after debiting Alice but before crediting Bob, PostgreSQL would roll back the debit on recovery. Your data stays consistent even in crash scenarios.

---

## 3. ROLLBACK

Start a transaction in Session 1 and make changes:

```sql
BEGIN;
```

```sql
UPDATE tx_accounts SET balance = 0 WHERE name = 'Carol';
```

```sql
SELECT name, balance FROM tx_accounts WHERE name = 'Carol';
```

Expected output:

```
 name  | balance
-------+---------
 Carol |    0.00
(1 row)
```

Decide you made a mistake and roll back:

```sql
ROLLBACK;
```

Expected output:

```
ROLLBACK
```

Verify Carol's balance is restored:

```sql
SELECT name, balance FROM tx_accounts WHERE name = 'Carol';
```

Expected output:

```
 name  | balance
-------+---------
 Carol | 2500.00
(1 row)
```

ROLLBACK discards every change made since `BEGIN`. The data returns to its state at the moment `BEGIN` was issued.

> **Concept: Error handling and transaction state**
> When a statement inside a transaction fails (syntax error, constraint violation, etc.), PostgreSQL puts the transaction into an "error state". Every subsequent command returns `ERROR: current transaction is aborted, commands ignored until end of transaction block`. You must issue `ROLLBACK` to clear the error state before you can do anything else. This prevents running subsequent statements against corrupted partial state.

---

## 4. SAVEPOINT

`SAVEPOINT` creates a named checkpoint inside a transaction. You can roll back to a savepoint without undoing the entire transaction.

Start a transaction and make some changes in Session 1:

```sql
BEGIN;
```

```sql
UPDATE tx_accounts SET balance = balance + 100 WHERE name = 'Alice';
```

```sql
SAVEPOINT after_alice;
```

Make another change:

```sql
UPDATE tx_accounts SET balance = balance - 500 WHERE name = 'Carol';
```

Realize the Carol change is wrong - roll back only to the savepoint:

```sql
ROLLBACK TO SAVEPOINT after_alice;
```

Expected output:

```
ROLLBACK
```

Check balances - Alice's change is preserved but Carol's is gone:

```sql
SELECT name, balance FROM tx_accounts ORDER BY name;
```

Expected output:

```
 name  | balance
-------+---------
 Alice |  900.00
 Bob   |  700.00
 Carol | 2500.00
(3 rows)
```

Alice has the $100 bonus. Carol is unchanged. Commit the transaction to keep Alice's change:

```sql
COMMIT;
```

Release a savepoint when it is no longer needed to free memory:

```sql
RELEASE SAVEPOINT after_alice;
```

Note: `RELEASE` on a savepoint that no longer exists after the transaction ends will give an error - release savepoints before committing or rolling back.

---

## 5. Isolation Levels

PostgreSQL supports four isolation levels. They differ in which concurrency anomalies they allow:

| Anomaly | Definition |
|---------|-----------|
| Dirty read | Reading uncommitted changes from another transaction |
| Non-repeatable read | Two reads of the same row return different values within one transaction |
| Phantom read | A query returns different rows on repeat due to another transaction's inserts/deletes |
| Serialization anomaly | Results differ from what would happen if transactions ran one after the other |

| Isolation Level | Dirty Read | Non-Repeatable Read | Phantom Read |
|-----------------|------------|---------------------|--------------|
| READ UNCOMMITTED | Possible (but PG treats as READ COMMITTED) | Possible | Possible |
| READ COMMITTED | Not possible | Possible | Possible |
| REPEATABLE READ | Not possible | Not possible | Not possible in PG |
| SERIALIZABLE | Not possible | Not possible | Not possible |

PostgreSQL's default isolation level is READ COMMITTED.

---

## 6. Demonstrate Non-Repeatable Read (READ COMMITTED)

In this demonstration, Session 1 reads the same row twice. Between those reads, Session 2 modifies the row. At READ COMMITTED, Session 1 sees different values.

**Session 1** - Start a transaction and read Alice's balance:

```sql
BEGIN;
```

```sql
SELECT balance FROM tx_accounts WHERE name = 'Alice';
```

Expected output:

```
 balance
---------
  900.00
(1 row)
```

**Session 2** - Without starting a transaction, update Alice's balance and auto-commit:

```sql
UPDATE tx_accounts SET balance = balance + 500 WHERE name = 'Alice';
```

**Session 1** - Read Alice's balance again in the same transaction:

```sql
SELECT balance FROM tx_accounts WHERE name = 'Alice';
```

Expected output:

```
 balance
---------
 1400.00
(1 row)
```

At READ COMMITTED, Session 1 saw two different values for the same row within a single transaction. This is a non-repeatable read.

**Session 1** - End the transaction:

```sql
ROLLBACK;
```

---

## 7. Demonstrate Stable Snapshot (REPEATABLE READ)

At REPEATABLE READ, Session 1 takes a snapshot of the database at the moment of its first query. All subsequent reads in that transaction see that snapshot, even if other sessions commit changes.

**Session 1** - Start a REPEATABLE READ transaction:

```sql
BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ;
```

```sql
SELECT balance FROM tx_accounts WHERE name = 'Alice';
```

Expected output:

```
 balance
---------
 1400.00
(1 row)
```

**Session 2** - Update Alice's balance:

```sql
UPDATE tx_accounts SET balance = 9999.00 WHERE name = 'Alice';
```

**Session 1** - Read Alice's balance again:

```sql
SELECT balance FROM tx_accounts WHERE name = 'Alice';
```

Expected output:

```
 balance
---------
 1400.00
(1 row)
```

Session 1 sees the same value despite Session 2's commit. REPEATABLE READ guarantees a consistent snapshot for the duration of the transaction.

**Session 1** - Commit:

```sql
COMMIT;
```

**Session 1** - Read Alice's balance again outside the transaction:

```sql
SELECT balance FROM tx_accounts WHERE name = 'Alice';
```

Expected output:

```
 balance
---------
 9999.00
(1 row)
```

Outside the transaction, the current committed value is visible.

> **Concept: REPEATABLE READ and write conflicts**
> At REPEATABLE READ, if two transactions both try to update the same row, the second one to commit will get an error: `ERROR: could not serialize access due to concurrent update`. PostgreSQL forces one of them to retry, preventing "lost updates". This is an important difference from READ COMMITTED where the second update silently runs on top of the first.

---

## 8. SERIALIZABLE Isolation

SERIALIZABLE is the strictest level. PostgreSQL uses Serializable Snapshot Isolation (SSI). It detects read-write dependencies between transactions and aborts any combination that could not have occurred if the transactions ran one at a time.

**Session 1** - Start a SERIALIZABLE transaction:

```sql
BEGIN TRANSACTION ISOLATION LEVEL SERIALIZABLE;
```

```sql
SELECT SUM(balance) FROM tx_accounts;
```

**Session 2** - Start another SERIALIZABLE transaction and insert a new account:

```sql
BEGIN TRANSACTION ISOLATION LEVEL SERIALIZABLE;
```

```sql
INSERT INTO tx_accounts (name, balance) VALUES ('Dave', 100.00);
```

```sql
COMMIT;
```

**Session 1** - Check the sum again:

```sql
SELECT SUM(balance) FROM tx_accounts;
```

**Session 1** - Commit:

```sql
COMMIT;
```

PostgreSQL may or may not abort one of these transactions depending on whether it detects a serialization anomaly. When it does abort, you will see:

```
ERROR:  could not serialize access due to read/write dependencies among transactions
DETAIL:  Reason code: Canceled on identification as a pivot, during commit attempt.
HINT:  The transaction might succeed if retried.
```

Applications using SERIALIZABLE must be prepared to retry the transaction when this error occurs.

---

## 9. Set Isolation Level for a Session

Instead of specifying the level per-transaction, you can set a default for the session:

```sql
SET SESSION default_transaction_isolation = 'repeatable read';
```

Verify the setting:

```sql
SHOW default_transaction_isolation;
```

Expected output:

```
 default_transaction_isolation
-------------------------------
 repeatable read
(1 row)
```

Reset to the default:

```sql
SET SESSION default_transaction_isolation = 'read committed';
```

---

## 10. Cleanup

In Session 1, drop the test table:

```sql
DROP TABLE IF EXISTS tx_accounts;
```

Exit psql in both sessions:

```sql
\q
```

Exit the postgres user in both terminals:

```bash
exit
```

---

## Summary

| Command | What It Does |
|---------|-------------|
| `BEGIN` | Start a transaction |
| `COMMIT` | Permanently save all changes since BEGIN |
| `ROLLBACK` | Discard all changes since BEGIN |
| `SAVEPOINT name` | Create a checkpoint inside a transaction |
| `ROLLBACK TO SAVEPOINT name` | Undo changes back to a savepoint |
| `RELEASE SAVEPOINT name` | Delete a savepoint (free memory) |
| `BEGIN ISOLATION LEVEL ...` | Start a transaction with a specific isolation level |

| Level | Use When |
|-------|---------|
| READ COMMITTED (default) | General OLTP - good performance, acceptable for most apps |
| REPEATABLE READ | Financial reporting - need consistent view of data |
| SERIALIZABLE | Accounting - correctness is paramount, can retry on conflict |

**Next:** Guide 05 covers window functions, EXPLAIN ANALYZE, JSON operations, and array handling.
