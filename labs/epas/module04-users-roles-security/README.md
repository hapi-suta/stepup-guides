# Module 04 - Users, Roles, and Security

**Track:** EPAS (EDB Postgres Advanced Server 16)
**Topology:** `epas-single` (one server, the box you installed EPAS on in Module 02)
**Prerequisites:** Module 03 complete - EPAS 16 installed and running.

## What you will be able to do

By the end of this module you can run the access-control layer of an EPAS instance the
way a production DBA does:

- Create login users and group roles, and reason about what a user can do through role
  membership (a role is both a user and a group).
- Grant and revoke object privileges, spot the schema `USAGE` prerequisite everyone
  forgets, and read an ACL with `\dp` - including the `PUBLIC` grants that leak access.
- Put an Oracle-style password policy on an account with `CREATE PROFILE`
  (`FAILED_LOGIN_ATTEMPTS`, `PASSWORD_LIFE_TIME`, ...), and lock/unlock accounts, reading
  state from `DBA_USERS`/`DBA_PROFILES`.
- Use Row-Level Security so one table shows each user only their own rows - and explain
  when the table owner and superusers bypass it.

## Oracle bridge

If you run Oracle today: EPAS **profiles** are the same `CREATE PROFILE ... LIMIT`
password policy you already know, visible in the same `DBA_USERS`/`DBA_PROFILES`
dictionary views. A **role** is Oracle's user and role unified into one object. Object
`GRANT`/`REVOKE` behave as you expect. The one genuinely new tool is **Row-Level
Security** - it does the job you used Oracle VPD (`DBMS_RLS`) or Label Security for, in
plain SQL with `CREATE POLICY`.

## Structure

- `concepts/` - the three questions (who are you / what may you do / which rows) and the
  role-and-privilege mental model.
- `build/` - hands-on: roles and privileges, profiles and password policies, RLS.
- `use/` - four production tasks (least-privilege role, lock a compromised account,
  per-tenant RLS, audit access from the catalog).
- `survive/` - four access-control failures; you diagnose and fix them.
- `interview/` - 13 security discussion points with model answers.

## Time

About 2.5 hours for BUILD + USE. The SURVIVE scenarios are 10-15 minutes each.

## Next

Module 05 - MVCC, VACUUM, and Transactions.
