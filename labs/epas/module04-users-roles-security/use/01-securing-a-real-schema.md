---
layout: default
title: "Use 01 - Securing a real schema"
parent: "Module 04 - Users, Roles, and Security"
nav_order: 5
locked: "no"
---

# USE 01 - Securing a real schema

Four production tasks that put Build 01-03 together. Do them in order on your server as
the `enterprisedb` superuser. Each names the outcome and the checks that prove you got
it right - work out the commands yourself; the model answers are at the bottom, but try
first.

Set up once. On **epas-single**, as **ec2-user**:

```bash
sudo -iu enterprisedb
```

Still as **enterprisedb**:

```bash
/usr/edb/as16/bin/edb-psql -p 5444 -d edb
```

Then create the working schema at the `edb=#` prompt:

```sql
CREATE SCHEMA billing;
CREATE TABLE billing.invoices (id int PRIMARY KEY, tenant text, amount numeric, note text);
INSERT INTO billing.invoices VALUES
  (1,'acme',500,'net30'),(2,'globex',900,'net60'),(3,'acme',150,'net30');
```

---

## Exercise 1: Least-privilege application role

**Goal:** the application connects as a login user that can `SELECT` and `INSERT` on
`billing.invoices` but can never `UPDATE`, `DELETE`, or touch anything else in the
schema. Build it as a group role plus a login member (so you can add more app instances
later without re-granting).

**Prove it:** connected as the app user (via `SET ROLE`), a `SELECT` and an `INSERT`
succeed, an `UPDATE` fails with "permission denied," and `\dp billing.invoices` shows
the group role holding only `ar` (SELECT, INSERT).

---

## Exercise 2: Lock a compromised account now

**Goal:** security tells you the `card_app` account may be compromised - lock it
immediately so no one can log in with it, without dropping it (you need it back after
investigation). First create it (`CREATE USER card_app LOGIN PASSWORD 'x';`), then lock
it.

**Prove it:** `DBA_USERS.account_status` for `CARD_APP` reads `LOCKED`. After the
investigation, unlock it and confirm the status is `OPEN` again.

---

## Exercise 3: Per-tenant isolation with RLS

**Goal:** `billing.invoices` holds rows for multiple tenants (`acme`, `globex`). Two
login roles, `acme_user` and `globex_user`, must each see only their own tenant's rows.
Give each role `SELECT`, then use RLS so `acme_user` sees only `acme` rows and
`globex_user` only `globex` rows. (Hint: the policy compares the `tenant` column to a
value tied to the role - the simplest version names each role after its tenant and
tests `tenant = current_user`.)

**Prove it:** `SET ROLE acme_user; SELECT tenant FROM billing.invoices;` returns only
`acme` rows; the same as `globex_user` returns only `globex` rows; as the superuser you
still see all rows (and you can explain why).

---

## Exercise 4: Audit "who can read this table"

**Goal:** an auditor asks who can read `billing.invoices`. Produce the answer from the
catalog, not from memory. Show (a) the table's ACL, and (b) whether `PUBLIC` has any
grant on it that would let unintended roles read it.

**Prove it:** you can point at the `\dp billing.invoices` output and name every role
with `r` (SELECT), and you have checked that `PUBLIC` (shown as an ACL entry with an
empty role name, `=...`) holds nothing on the table.

---

## Clean up

```sql
DROP SCHEMA billing CASCADE;
DROP ROLE IF EXISTS card_app;
-- plus any app/tenant roles you created
```

---

## Model answers

<details markdown="1">
<summary>Exercise 1</summary>

```sql
CREATE ROLE inv_rw NOLOGIN;
GRANT USAGE ON SCHEMA billing TO inv_rw;
GRANT SELECT, INSERT ON billing.invoices TO inv_rw;
CREATE USER app1 LOGIN PASSWORD 'AppPass_2026';
GRANT inv_rw TO app1;

SET ROLE app1;
SELECT count(*) FROM billing.invoices;              -- works
INSERT INTO billing.invoices VALUES (9,'acme',1,''); -- works
UPDATE billing.invoices SET amount=0 WHERE id=1;     -- ERROR: permission denied
RESET ROLE;
\dp billing.invoices
```
The ACL shows `inv_rw=ar/enterprisedb` (a=INSERT, r=SELECT) and nothing more.
</details>

<details markdown="1">
<summary>Exercise 2</summary>

```sql
CREATE USER card_app LOGIN PASSWORD 'x';
ALTER USER card_app ACCOUNT LOCK;
SELECT username, account_status FROM DBA_USERS WHERE username='CARD_APP';  -- LOCKED
-- after investigation:
ALTER USER card_app ACCOUNT UNLOCK;
SELECT username, account_status FROM DBA_USERS WHERE username='CARD_APP';  -- OPEN
```
</details>

<details markdown="1">
<summary>Exercise 3</summary>

```sql
CREATE ROLE acme_user   LOGIN PASSWORD 'x';
CREATE ROLE globex_user LOGIN PASSWORD 'x';
GRANT USAGE ON SCHEMA billing TO acme_user, globex_user;
GRANT SELECT ON billing.invoices TO acme_user, globex_user;

ALTER TABLE billing.invoices ENABLE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON billing.invoices
    FOR SELECT USING (tenant = current_user);

SET ROLE acme_user;   SELECT tenant FROM billing.invoices;  -- only acme
SET ROLE globex_user; SELECT tenant FROM billing.invoices;  -- only globex
RESET ROLE;           SELECT tenant FROM billing.invoices;  -- all (owner/superuser bypass)
```
The superuser sees all rows because the owner and superusers bypass RLS - the policy is
still correct.
</details>

<details markdown="1">
<summary>Exercise 4</summary>

```sql
\dp billing.invoices
```
Read every ACL line: each `role=...r.../grantor` entry with an `r` can read. An ACL
entry whose role name is empty (`=r/enterprisedb`) means the privilege is granted to
`PUBLIC` - if you see one, everyone can read, and you would
`REVOKE SELECT ON billing.invoices FROM PUBLIC;` to close it. In this exercise no
`PUBLIC` grant exists, so only the roles you explicitly granted can read.
</details>

## What you practiced

Least-privilege role design, on-demand account lockout for incident response,
multi-tenant isolation with RLS, and auditing access from the catalog instead of
memory. These four are the day-job of the access-control DBA - and every one of them is
a question an auditor or an interviewer will actually ask.
