---
layout: default
title: "Concepts 01 - How authorization works in EPAS"
parent: "Module 04 - Users, Roles, and Security"
nav_order: 1
locked: "no"
---

# Concepts 01 - How authorization works in EPAS

Read this before you touch the server. Every command in the three BUILD guides assumes
the mental model below. If you get this model right, the syntax is easy; if you skip it,
you will grant the wrong thing to the wrong role and not understand why.

Security in EPAS is three separate questions, asked in order, every time a client
connects and runs a statement:

1. **Authentication - who are you?** Decided by `pg_hba.conf` and the password (you met
   `pg_hba.conf` in Module 03). EPAS profiles add a password *policy* on top -
   expiry, lockout after bad attempts.
2. **Authorization - what may you do?** Decided by **roles** and the **privileges**
   granted to them.
3. **Row visibility - which rows may you see?** Decided by **Row-Level Security**.

Keep them separate in your head. A login can pass authentication (right password) and
still do nothing (no privileges). A user can hold `SELECT` on a table (privilege) and
still see zero rows (RLS policy). Most "permissions" confusion is really two of these
three layers being confused for each other.

---

## 1. Roles are the whole story (a role is a user AND a group)

In Oracle you have users and, separately, roles. In PostgreSQL and EPAS there is **one
concept: the role.** A role with the `LOGIN` attribute is what you would call a user. A
role without `LOGIN` is what you would call a group. The same `CREATE ROLE` /
`ALTER ROLE` commands manage both. `CREATE USER` is nothing more than
`CREATE ROLE ... LOGIN` with a friendlier name.

```
CREATE ROLE app_read   NOLOGIN;              -- a "group"
CREATE USER app_service WITH LOGIN PASSWORD; -- a "user" (= CREATE ROLE ... LOGIN)
GRANT app_read TO app_service;               -- app_service is now a MEMBER of app_read
```

Because a role is a group, you grant privileges to a **group role** once, then add
**login roles** to it as members. The members inherit the group's privileges. This is
exactly Oracle's "grant a role to a user" - same idea, one command name.

### Role attributes vs privileges - do not confuse them

Two different things both feel like "permissions":

- **Role attributes** are cluster-wide powers baked into the role itself:
  `LOGIN`, `SUPERUSER`, `CREATEDB`, `CREATEROLE`, `BYPASSRLS`. Set with
  `CREATE ROLE ... <attribute>` or `ALTER ROLE`. These are not granted on objects -
  they are properties of the account.
- **Privileges** are grants **on an object** (`SELECT` on a table, `USAGE` on a
  schema, `CONNECT` on a database), handed out with `GRANT` and taken back with
  `REVOKE`.

`ALTER ROLE app CREATEDB` changes an attribute. `GRANT SELECT ON t TO app` changes a
privilege. Different mechanisms, different catalogs.

---

## 2. Privileges: object grants, and the `PUBLIC` trap

A privilege is the right to do one thing to one object. The ones you use daily:

| Privilege | On | Meaning |
|:--|:--|:--|
| `CONNECT` | database | may open a connection to it |
| `USAGE` | schema | may "see into" the schema (needed before any table access) |
| `SELECT` / `INSERT` / `UPDATE` / `DELETE` | table | the obvious row operations |
| `EXECUTE` | function/procedure | may call it |

Two gotchas that bite Oracle DBAs:

- **`USAGE` on the schema is a prerequisite.** Granting `SELECT` on a table does
  nothing if the role cannot `USAGE` the schema that contains it. You almost always
  grant both.
- **`PUBLIC` is an implicit role every account belongs to.** New databases grant
  `CONNECT` and some defaults to `PUBLIC`. A privilege granted to `PUBLIC` is held by
  everyone, including accounts you create later. Hardening a database often means
  `REVOKE`-ing things from `PUBLIC`, not just granting to your roles.

You read the resulting grants with `\dp` (display privileges). The ACL string
`app_read=r/enterprisedb` reads as "role `app_read` has `r` (SELECT), granted by
`enterprisedb`."

---

## 3. Profiles: the Oracle password policy, unchanged

This is the part that will feel like home. EPAS supports Oracle-style **profiles** -
`CREATE PROFILE ... LIMIT` with the exact parameters you know:

- `FAILED_LOGIN_ATTEMPTS` - lock the account after N bad passwords.
- `PASSWORD_LIFE_TIME` - days a password is valid before it must change.
- `PASSWORD_LOCK_TIME` - how long the account stays locked after lockout.
- `PASSWORD_GRACE_TIME`, `PASSWORD_REUSE_TIME`, `PASSWORD_REUSE_MAX`,
  `PASSWORD_VERIFY_FUNCTION`.

You assign a profile with `ALTER USER ... PROFILE`, and you can `ALTER USER ...
ACCOUNT LOCK` / `ACCOUNT UNLOCK` by hand. The account's state shows up in the
`DBA_USERS` view (`account_status` = `OPEN` / `LOCKED` / `LOCKED(TIMED)` / `EXPIRED`)
and the policy itself in `DBA_PROFILES` - the same data-dictionary views you query in
Oracle. Community PostgreSQL has none of this; it is an EPAS value-add, and it is why
shops that need Oracle-grade account policy pick EPAS.

---

## 4. Row-Level Security: the row filter that replaces VPD

Table privileges are all-or-nothing: hold `SELECT` and you see every row, hold none
and you see the table not at all. **Row-Level Security (RLS)** adds a per-row filter on
top of that.

You turn it on per table (`ALTER TABLE ... ENABLE ROW LEVEL SECURITY`) and attach one
or more **policies** - boolean expressions evaluated per row:

- `USING (expr)` decides which existing rows a role can **see** (SELECT/UPDATE/DELETE).
- `WITH CHECK (expr)` decides which new rows a role may **write** (INSERT/UPDATE).

Two rules you must remember, because they surprise people:

- **The table owner and superusers bypass RLS by default.** Your `enterprisedb`
  superuser will see every row and think the policy "isn't working." It is working -
  it just does not apply to superusers. `ALTER TABLE ... FORCE ROW LEVEL SECURITY`
  makes a **non-superuser** owner obey policies too; a superuser still bypasses,
  always.
- **Enabling RLS with no policy means default-deny** - the table returns zero rows to
  non-owners until you add a policy. Enabling RLS and forgetting the policy is a
  classic self-inflicted outage.

This is the tool you reached for Oracle VPD (`DBMS_RLS`) or Label Security to do:
"salespeople see only their own accounts", "each tenant sees only their own data". In
EPAS it is plain SQL - `CREATE POLICY`.

---

## The one-paragraph summary

A **role** is both user and group; privileges are granted to group roles and inherited
through membership. **Attributes** (`LOGIN`, `SUPERUSER`, `BYPASSRLS`) are powers of the
account; **privileges** (`SELECT`, `USAGE`) are grants on objects - and `USAGE` on the
schema is the prerequisite everyone forgets. **Profiles** bring Oracle password policy
(lockout, expiry) to EPAS, visible in `DBA_USERS`/`DBA_PROFILES`. **RLS** filters rows
with policies, and the owner/superuser bypass it unless you `FORCE` it. Hold those four
ideas and the three BUILD guides are just practice.
