---
layout: default
title: "Build 02 - Profiles and password policies"
parent: "Module 04 - Users, Roles, and Security"
nav_order: 3
locked: "no"
---

# BUILD 02 - Profiles and password policies

This is the guide that will feel most like Oracle. EPAS supports **profiles** -
`CREATE PROFILE ... LIMIT` with `FAILED_LOGIN_ATTEMPTS`, `PASSWORD_LIFE_TIME`, and the
rest of the password-policy parameters you already know. You will build a profile,
attach it to a user, then actually **trip the lockout** with bad passwords and unlock
the account, watching `DBA_USERS.account_status` change at each step. Community
PostgreSQL cannot do any of this - it is an EPAS feature, and it is exactly why an
Oracle-grade shop chooses EPAS.

Every command below was run on a live EPAS 16 box; the outputs are real.

## 1. Connect as the superuser

On **epas-single**, as **ec2-user**:

```bash
sudo -iu enterprisedb
```

Still as **enterprisedb** on **epas-single**:

```bash
/usr/edb/as16/bin/edb-psql -p 5444 -d edb
```

You are at the `edb=#` prompt.

## 2. Create a profile with a password policy

Create a profile that locks an account after 3 bad passwords and keeps it locked for
1 day, with a 90-day password life and a 3-day grace period.

```sql
CREATE PROFILE secure_login LIMIT
    FAILED_LOGIN_ATTEMPTS 3
    PASSWORD_LOCK_TIME 1
    PASSWORD_LIFE_TIME 90
    PASSWORD_GRACE_TIME 3;
```

- `FAILED_LOGIN_ATTEMPTS 3` - after 3 consecutive bad passwords the account locks.
- `PASSWORD_LOCK_TIME 1` - it stays locked for 1 day (then unlocks itself).
- `PASSWORD_LIFE_TIME 90` - the password is valid for 90 days.
- `PASSWORD_GRACE_TIME 3` - after it expires, 3 more days before login is refused.

Expected output (yours will differ):

```
CREATE PROFILE
```

## 3. Read the profile back from the data dictionary

The policy lives in the `DBA_PROFILES` view - the same dictionary view you query in
Oracle. Note that `limit` is a reserved word, so it must be double-quoted:

```sql
SELECT profile, resource_name, "limit"
FROM DBA_PROFILES
WHERE profile = 'SECURE_LOGIN'
ORDER BY resource_name;
```

Expected output (yours will differ):

```
   profile    |      resource_name       |  limit
--------------+--------------------------+---------
 SECURE_LOGIN | FAILED_LOGIN_ATTEMPTS    | 3
 SECURE_LOGIN | PASSWORD_ALLOW_HASHED    | DEFAULT
 SECURE_LOGIN | PASSWORD_GRACE_TIME      | 3
 SECURE_LOGIN | PASSWORD_LIFE_TIME       | 90
 SECURE_LOGIN | PASSWORD_LOCK_TIME       | 1
 SECURE_LOGIN | PASSWORD_REUSE_MAX       | DEFAULT
 SECURE_LOGIN | PASSWORD_REUSE_TIME      | DEFAULT
 SECURE_LOGIN | PASSWORD_VERIFY_FUNCTION | DEFAULT
(8 rows)
```

The parameters you did not set show `DEFAULT` (they fall back to the built-in `default`
profile). Profile names are stored upper-cased, so query with `'SECURE_LOGIN'`.

## 4. Create a user and attach the profile

```sql
CREATE USER card_app WITH LOGIN PASSWORD 'GoodPass_2026' PROFILE secure_login;
```

- `PROFILE secure_login` - binds the policy to this account at creation. You can also
  attach it later with `ALTER USER card_app PROFILE secure_login`.

```
CREATE ROLE
```

Confirm the binding and the account state in `DBA_USERS`:

```sql
SELECT username, profile, account_status
FROM DBA_USERS WHERE username = 'CARD_APP';
```

Expected output (yours will differ):

```
 username |   profile    | account_status
----------+--------------+----------------
 CARD_APP | SECURE_LOGIN | OPEN
(1 row)
```

`account_status` is `OPEN` - the account is usable.

## 5. Confirm a good login works

Open a second terminal on the same server (leave this `edb=#` session open). In the new
terminal, on **epas-single**, as **ec2-user**, connect over TCP as `card_app` with the
correct password:

```bash
PGPASSWORD='GoodPass_2026' /usr/edb/as16/bin/edb-psql -h 127.0.0.1 -p 5444 -U card_app -d edb -c "SELECT 'login ok'"
```

- `-h 127.0.0.1` forces a TCP connection so the password is actually checked (a local
  socket login as the `enterprisedb` OS user would use peer auth and skip the
  password).

Expected output (yours will differ):

```
 ?column?
----------
 login ok
(1 row)
```

## 6. Trip the lockout with bad passwords

Still in the second terminal, attempt to connect three times with a **wrong** password:

```bash
PGPASSWORD='wrong1' /usr/edb/as16/bin/edb-psql -h 127.0.0.1 -p 5444 -U card_app -d edb -c "SELECT 1"
```

```bash
PGPASSWORD='wrong2' /usr/edb/as16/bin/edb-psql -h 127.0.0.1 -p 5444 -U card_app -d edb -c "SELECT 1"
```

```bash
PGPASSWORD='wrong3' /usr/edb/as16/bin/edb-psql -h 127.0.0.1 -p 5444 -U card_app -d edb -c "SELECT 1"
```

Each one fails with:

```
edb-psql: error: connection to server at "127.0.0.1", port 5444 failed: FATAL:  password authentication failed for user "card_app"
```

Now go back to your `edb=#` session (the superuser terminal) and check the status:

```sql
SELECT username, account_status
FROM DBA_USERS WHERE username = 'CARD_APP';
```

Expected output (yours will differ):

```
 username | account_status
----------+----------------
 CARD_APP | LOCKED(TIMED)
(1 row)
```

`LOCKED(TIMED)` - the profile's `FAILED_LOGIN_ATTEMPTS 3` tripped, and because we set
`PASSWORD_LOCK_TIME 1` it is a timed lock that would clear itself after a day.

## 7. Prove the correct password is now refused

Back in the second terminal, try the **correct** password again:

```bash
PGPASSWORD='GoodPass_2026' /usr/edb/as16/bin/edb-psql -h 127.0.0.1 -p 5444 -U card_app -d edb -c "SELECT 1"
```

Expected output (yours will differ):

```
edb-psql: error: connection to server at "127.0.0.1", port 5444 failed: FATAL:  role "card_app" is locked
```

This is the key point: once locked, **even the right password is refused**, and the
error changes from "password authentication failed" to "role is locked" - the signal a
DBA needs to tell "wrong password" apart from "account locked."

## 8. Unlock the account

In the `edb=#` superuser session, unlock it by hand instead of waiting out the timer:

```sql
ALTER USER card_app ACCOUNT UNLOCK;
```

```
ALTER ROLE
```

Confirm:

```sql
SELECT username, account_status
FROM DBA_USERS WHERE username = 'CARD_APP';
```

Expected output (yours will differ):

```
 username | account_status
----------+----------------
 CARD_APP | OPEN
(1 row)
```

Back in the second terminal, the correct password now works again:

```bash
PGPASSWORD='GoodPass_2026' /usr/edb/as16/bin/edb-psql -h 127.0.0.1 -p 5444 -U card_app -d edb -c "SELECT 'login ok'"
```

```
 ?column?
----------
 login ok
(1 row)
```

You can also lock an account on demand (for example, a departing employee) with
`ALTER USER card_app ACCOUNT LOCK;` - `account_status` then reads `LOCKED` (not timed).

## 9. Clean up

In the `edb=#` session:

```sql
DROP USER card_app;
```

```sql
DROP PROFILE secure_login;
```

Then close both terminals' clients with `\q` and `exit` back to `ec2-user`.

## What you did

You built an Oracle-style password policy with `CREATE PROFILE`, read it from
`DBA_PROFILES`, attached it to a user, and watched `DBA_USERS.account_status` go
`OPEN -> LOCKED(TIMED) -> OPEN` as three bad passwords locked the account and
`ACCOUNT UNLOCK` freed it. The one detail to carry into on-call: a locked account
refuses the **correct** password and says `role "..." is locked` - when an app suddenly
cannot log in with credentials that used to work, check `DBA_USERS.account_status`
before you touch the password.
