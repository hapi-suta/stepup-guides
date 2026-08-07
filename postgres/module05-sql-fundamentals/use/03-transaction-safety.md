# Exercise 03: Transaction Safety

**Duration:** 30 minutes
**Objective:** Implement safe money transfers between accounts using transactions and SAVEPOINT. Reproduce a deadlock between two sessions and observe how PostgreSQL handles it.

**Prerequisites:** Build guide 04 (transactions) complete. Two terminal sessions open.

---

## Background

Transferring value between rows is the classic transaction test. If you debit one account and the server crashes before crediting the other, you lose money. Transactions prevent this. Deadlocks happen when two transactions each hold a lock the other needs - PostgreSQL detects and breaks them automatically.

---

## Setup

Open two terminals. In Terminal A and Terminal B, run:

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

In Terminal A, create and populate a wallet table:

```sql
CREATE TABLE IF NOT EXISTS wallets (
  wallet_id   SERIAL PRIMARY KEY,
  owner       VARCHAR(100) NOT NULL UNIQUE,
  balance     NUMERIC(12,2) NOT NULL DEFAULT 0.00,
  CHECK (balance >= 0)
);
```

```sql
INSERT INTO wallets (owner, balance) VALUES
  ('Alice',   1000.00),
  ('Bob',     500.00),
  ('Charlie', 2000.00),
  ('Dana',    750.00);
```

---

## Task 1: Safe Transfer Function

Write a transfer that moves $150 from Alice to Bob. Requirements:
- Use a single transaction
- Debit the sender before crediting the receiver
- If the sender does not have enough funds, roll back and print an error
- Use RETURNING to verify the debit and credit amounts
- End with a SELECT showing both balances

You should not use a stored function for this - write the raw SQL transaction.

### Answer

```sql
BEGIN;
```

```sql
UPDATE wallets SET balance = balance - 150 WHERE owner = 'Alice'
RETURNING owner, balance AS new_balance;
```

Expected output:

```
 owner | new_balance
-------+-------------
 Alice |      850.00
(1 row)
```

```sql
UPDATE wallets SET balance = balance + 150 WHERE owner = 'Bob'
RETURNING owner, balance AS new_balance;
```

Expected output:

```
 owner | new_balance
-------+-------------
 Bob   |      650.00
(1 row)
```

```sql
SELECT owner, balance FROM wallets WHERE owner IN ('Alice', 'Bob') ORDER BY owner;
```

Expected output:

```
 owner | balance
-------+---------
 Alice |  850.00
 Bob   |  650.00
(2 rows)
```

```sql
COMMIT;
```

---

## Task 2: Overdraft Protection

Try to transfer $2000 from Bob (who only has $650 after Task 1). The `CHECK (balance >= 0)` constraint should stop you.

```sql
BEGIN;
```

```sql
UPDATE wallets SET balance = balance - 2000 WHERE owner = 'Bob';
```

Expected output:

```
ERROR:  new row for relation "wallets" violates check constraint "wallets_balance_check"
DETAIL:  Failing row contains (2, Bob, -1350.00).
```

The transaction is now in an error state. You must roll it back:

```sql
ROLLBACK;
```

Verify Bob's balance is unchanged:

```sql
SELECT owner, balance FROM wallets WHERE owner = 'Bob';
```

Expected output:

```
 owner | balance
-------+---------
 Bob   |  650.00
(1 row)
```

---

## Task 3: Multi-Step Transfer with SAVEPOINT

Transfer money from Charlie to both Alice and Dana. The business rule says Dana's balance is not supposed to exceed $2500 - if crediting her $300 would push her over that, roll back only the Dana leg and keep the Alice transfer.

For this exercise, manually check the "Dana max balance" business rule with a SELECT, then decide which branch to run.

Requirements:
- Use a single BEGIN/COMMIT
- Use SAVEPOINT after the Alice transfer
- If Dana's resulting balance would exceed $2500, ROLLBACK TO the savepoint (skipping Dana)
- Otherwise, run the Dana transfer
- Commit the transaction either way, to keep Alice's transfer

### Answer

```sql
BEGIN;
```

Transfer $200 from Charlie to Alice:

```sql
UPDATE wallets SET balance = balance - 200 WHERE owner = 'Charlie';
```

```sql
UPDATE wallets SET balance = balance + 200 WHERE owner = 'Alice';
```

```sql
SAVEPOINT after_alice_transfer;
```

Check if Dana's balance after a $300 transfer would exceed $2500:

```sql
SELECT balance + 300 AS would_be FROM wallets WHERE owner = 'Dana';
```

Expected output (yours will differ if you changed the numbers above - Dana started this exercise at $750):

```
 would_be
----------
  1050.00
(1 row)
```

`1050.00` does not exceed `2500`, so the business rule passes - run the Dana transfer instead of rolling back:

```sql
UPDATE wallets SET balance = balance - 300 WHERE owner = 'Charlie';
```

```sql
UPDATE wallets SET balance = balance + 300 WHERE owner = 'Dana';
```

(If `would_be` had exceeded 2500, you would instead run `ROLLBACK TO SAVEPOINT after_alice_transfer;` here to undo nothing but keep the earlier Alice transfer intact, then skip straight to COMMIT.)

Commit the transaction to keep both transfers:

```sql
COMMIT;
```

Verify final balances:

```sql
SELECT owner, balance FROM wallets ORDER BY owner;
```

Expected output:

```
  owner  | balance
---------+---------
 Alice   | 1050.00
 Bob     |  650.00
 Charlie | 1500.00
 Dana    | 1050.00
(4 rows)
```

Alice gained $200 from Charlie (850 -> 1050). Charlie paid out $200 + $300 = $500 (2000 -> 1500). Dana gained $300 (750 -> 1050). Bob is untouched from Task 1's $650.

> **Concept: Why SAVEPOINT here even though we did not roll back?**
> The savepoint costs nothing if you never use it, and it gives you a clean undo point for the Dana leg specifically - without it, an unwanted Dana transfer could only be undone by rolling back the entire transaction, which would also undo the Alice transfer you wanted to keep. Always place a savepoint before any step whose outcome is conditional.

---

## Task 4: Reproduce a Deadlock

A deadlock occurs when Transaction A holds a lock on Row 1 and wants Row 2, while Transaction B holds Row 2 and wants Row 1. Neither can proceed.

Run these steps in exact order, switching between Terminal A and Terminal B as noted.

**Terminal A:**

```sql
BEGIN;
```

```sql
UPDATE wallets SET balance = balance - 10 WHERE owner = 'Alice';
```

**Terminal B:**

```sql
BEGIN;
```

```sql
UPDATE wallets SET balance = balance - 10 WHERE owner = 'Bob';
```

**Terminal A** (Alice is locked by A, now try to lock Bob):

```sql
UPDATE wallets SET balance = balance + 10 WHERE owner = 'Bob';
```

Terminal A will hang - it is waiting for Terminal B's lock on Bob.

**Terminal B** (Bob is locked by B, now try to lock Alice - this creates the deadlock):

```sql
UPDATE wallets SET balance = balance + 10 WHERE owner = 'Alice';
```

Within a few seconds, PostgreSQL will break the deadlock. One session will see:

```
ERROR:  deadlock detected
DETAIL:  Process 16709 waits for ShareLock on transaction 824; blocked by process 16710.
        Process 16710 waits for ShareLock on transaction 825; blocked by process 16709.
HINT:   See server log for query details.
CONTEXT:  while updating tuple (0,8) in relation "wallets"
```

(Your process numbers and transaction IDs will differ - PostgreSQL assigns them at connection and transaction start time.) The other session's UPDATE will complete - Terminal A's hung UPDATE finally returns once Terminal B is chosen as the deadlock victim and its transaction is aborted.

The session that got the deadlock error must roll back:

```sql
ROLLBACK;
```

The other session should commit or roll back:

```sql
ROLLBACK;
```

**What happened:** PostgreSQL's lock manager detected the circular dependency and automatically chose one transaction as the "victim" to abort. Applications must be prepared to catch deadlock errors (SQLSTATE 40P01) and retry the transaction.

---

## Cleanup

In Terminal A:

```sql
DROP TABLE IF EXISTS wallets;
```

```sql
\q
```

```bash
exit
```

In Terminal B:

```sql
\q
```

```bash
exit
```
