---
layout: default
title: "Interview 01 - Security Discussion Points"
parent: "Module 04 - Users, Roles, and Security"
nav_order: 7
locked: "no"
---

# Interview 01 - Security Discussion Points

## What You Are Doing

You are rehearsing the 13 access-control questions an interviewer is most likely to put
to an Oracle DBA now claiming EPAS/PostgreSQL. Every answer is grounded in what you
actually did on your `epas-single` server this module - built roles, tripped a real
lockout, watched RLS filter rows - so you speak from experience, not from a blog post.

**Mode:** Study and rehearse out loud.

**Time:** 45 min.

**Prerequisite:** All other Module 04 phases complete.

---

## Question 1: What is the difference between a user and a role in EPAS?

**What they are really asking:** Do you know there is no difference under the hood?

There is one object - the **role**. A role with the `LOGIN` attribute is what we call a
user; a role without it is a group. `CREATE USER` is literally `CREATE ROLE ... LOGIN` -
EPAS even prints `CREATE ROLE` when you run `CREATE USER`. So I manage users and groups
with the same `CREATE ROLE`/`ALTER ROLE` commands and just toggle `LOGIN`.

## Question 2: How do you give ten users the same access without granting to each one?

**What they are really asking:** Do you use group roles, or grant object by object?

I grant privileges once to a **group role** (a `NOLOGIN` role), then add each login user
as a **member** with `GRANT group_role TO user`. Members inherit the group's privileges.
It is exactly Oracle's "grant a role to a user." When access needs to change I change the
one group role, not ten users.

## Question 3: What is the difference between a role attribute and a privilege?

**What they are really asking:** Do you conflate the two like most people?

An **attribute** is a power baked into the account - `LOGIN`, `SUPERUSER`, `CREATEDB`,
`CREATEROLE`, `BYPASSRLS` - set with `CREATE ROLE`/`ALTER ROLE`, and it lives in
`pg_roles`. A **privilege** is a grant on an object - `SELECT` on a table, `USAGE` on a
schema - handed out with `GRANT`/`REVOKE`. `ALTER ROLE x CREATEDB` changes an attribute;
`GRANT SELECT ON t TO x` changes a privilege. Different mechanism, different catalog.

## Question 4: You granted SELECT on a table but the user still gets "permission denied." Why?

**What they are really asking:** Do you know schema `USAGE` is a prerequisite?

Almost always they lack `USAGE` on the schema that contains the table. `SELECT` on the
table is not enough - the role has to be able to see into the schema first. I grant both:
`GRANT USAGE ON SCHEMA app TO role;` then `GRANT SELECT ON app.t TO role;`.

## Question 5: What is PUBLIC, and why does it matter for hardening?

**What they are really asking:** Do you know about the implicit grant that leaks access?

`PUBLIC` is an implicit role every account belongs to, now and in the future. A privilege
granted to `PUBLIC` is held by everyone, so a new database's default `PUBLIC` grants can
let accounts read things you never deliberately granted. In `\dp` it shows as an ACL
entry with an empty role name (`=r/owner`). Hardening often means `REVOKE ... FROM
PUBLIC` and then granting explicitly, not just adding grants.

## Question 6: How do you read a privilege ACL like `app_read=r/enterprisedb`?

**What they are really asking:** Can you actually interpret `\dp` output?

`role=privileges/grantor`. So `app_read=r/enterprisedb` means role `app_read` holds `r`
(SELECT), granted by `enterprisedb`. The letters map to privileges: `a` INSERT, `r`
SELECT, `w` UPDATE, `d` DELETE, and so on. An owner line like `enterprisedb=arwdDxt/...`
is the full set. An entry with no role name before `=` is a grant to `PUBLIC`.

## Question 7: EPAS supports Oracle-style profiles. What can you enforce with one?

**What they are really asking:** Do you know this EPAS feature that community PG lacks?

A `CREATE PROFILE ... LIMIT` enforces password policy: `FAILED_LOGIN_ATTEMPTS` (lock
after N bad passwords), `PASSWORD_LIFE_TIME` (days valid), `PASSWORD_LOCK_TIME` (how long
it stays locked), `PASSWORD_GRACE_TIME`, `PASSWORD_REUSE_TIME`/`PASSWORD_REUSE_MAX`, and
`PASSWORD_VERIFY_FUNCTION` for complexity. I attach it with `ALTER USER ... PROFILE`, and
read it back from `DBA_PROFILES`. Community PostgreSQL has none of this - it is a core
reason a shop that needs Oracle-grade account policy runs EPAS.

## Question 8: An app can't log in with a password that used to work. How do you tell a locked account from a wrong password?

**What they are really asking:** Do you know the lockout signal?

I check `DBA_USERS.account_status` for that user. A locked account reads `LOCKED` or
`LOCKED(TIMED)`, and the login error itself changes - a wrong password says "password
authentication failed," but a locked account says `role "..." is locked` even with the
**correct** password. That distinction tells me to unlock the account
(`ALTER USER ... ACCOUNT UNLOCK`) and hunt the client spraying bad passwords, not to
reset the password.

## Question 9: What does account_status = LOCKED(TIMED) mean versus LOCKED?

**What they are really asking:** Do you understand timed vs manual locks?

`LOCKED(TIMED)` means the account was auto-locked by `FAILED_LOGIN_ATTEMPTS` and will
unlock itself after `PASSWORD_LOCK_TIME`. Plain `LOCKED` means a DBA locked it by hand
with `ALTER USER ... ACCOUNT LOCK` and it stays locked until someone unlocks it - which
is what I use to disable a departing employee or a compromised account without dropping
it.

## Question 10: What problem does Row-Level Security solve that table privileges cannot?

**What they are really asking:** Do you know RLS is row-grain, privileges are table-grain?

Table privileges are all-or-nothing: `SELECT` means every row, or you see nothing. RLS
adds a per-row filter, so one table can show each user only their own rows - multi-tenant
isolation, "salespeople see only their accounts." It is the job I used Oracle VPD or
Label Security for; in EPAS it is plain SQL with `CREATE POLICY`.

## Question 11: A developer says "I enabled RLS and now the app sees nothing." What happened?

**What they are really asking:** Do you know RLS-with-no-policy is default-deny?

Enabling RLS with no matching policy is **default-deny** - non-owners get zero rows until
a policy grants visibility. They almost certainly enabled row security but did not create
a policy whose `USING` expression matches the app's role. The fix is to add the correct
policy, never to disable RLS - disabling it would expose every row to everyone.

## Question 12: Someone tests an RLS policy as the table owner and it "doesn't filter." Why?

**What they are really asking:** Do you know the owner/superuser bypass?

The table owner and superusers **bypass RLS by default**, so testing as the owner or as
`enterprisedb` shows all rows - the policy is fine, it just does not apply to them. My
first question on any "RLS isn't working" ticket is which role they connected as. To make
a non-superuser owner obey policies too, use `ALTER TABLE ... FORCE ROW LEVEL SECURITY` -
but a superuser (or a role with `BYPASSRLS`) still bypasses even under `FORCE`.

## Question 13: Explain USING versus WITH CHECK in a policy.

**What they are really asking:** Do you know reads versus writes in RLS?

`USING` decides which **existing** rows a role can see or affect - it filters SELECT,
UPDATE, and DELETE. `WITH CHECK` decides which **new** row values a role may write - it
gates INSERT and the post-image of UPDATE. If I only write `USING`, it implicitly applies
to writes too. I use a separate `WITH CHECK` when a user should read rows under one
condition but only be allowed to insert or update rows that meet another - for example,
see all their tenant's rows but never write a row tagged to a different tenant.

---

## How to Use This

Say each answer out loud before you read the model answer. If you cannot answer from what
you did on your server this week - the lockout you tripped, the RLS rows you watched
filter - go back and do that phase again. A real answer always beats a memorized one.
