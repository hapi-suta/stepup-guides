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

```sql
UPDATE wallets SET balance = balance + 150 WHERE owner = 'Bob'
RETURNING owner, balance AS new_balance;
```

```sql
SELECT owner, balance FROM wallets WHERE owner IN ('Alice', 'Bob') ORDER BY owner;
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

---

## Task 3: Multi-Step Transfer with SAVEPOINT

Transfer money from Charlie to both Alice and Dana. If the Dana transfer would fail (she already has a high balance and the business rule says max balance is $3000 conceptually), roll back only the Dana part and keep the Alice transfer.

For this exercise, manually simulate the "Dana max balance" business rule check in SQL.

Requirements:
- Use a single BEGIN/COMMIT
- Use SAVEPOINT after the Alice transfer
- If Dana's resulting balance would exceed $2500, ROLLBACK TO the savepoint (skipping Dana)
- Commit the transaction to keep Alice's transfer

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

Check if Dana's balance after the transfer would exceed $2500:

```sql
SELECT balance + 300 AS would_be FROM wallets WHERE owner = 'Dana';
```

If the "would_be" value exceeds 2500, run:

```sql
ROLLBACK TO SAVEPOINT after_alice_transfer;
```

Otherwise run the transfer. Either way, commit:

```sql
COMMIT;
```

Verify final balances:

```sql
SELECT owner, balance FROM wallets ORDER BY owner;
```

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
DETAIL:  Process XXXXX waits for ShareLock on transaction YYYYY; blocked by process ZZZZZ.
        Process ZZZZZ waits for ShareLock on transaction XXXXX; blocked by process YYYYY.
HINT:   See server log for query details.
```

The other session's UPDATE will complete.

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
