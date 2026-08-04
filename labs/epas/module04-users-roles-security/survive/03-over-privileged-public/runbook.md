# Runbook: The user who can see too much

## Symptoms

An audit finds a role (`chaos_nobody`) reading a sensitive table (`chaos_m04b.salaries`)
that nobody deliberately granted to it. The account has no explicit grants of its own,
yet it can `SELECT` the data.

## Diagnostic Steps

### Step 1: Confirm the account has no direct grant

Check what `chaos_nobody` was granted. It has nothing on this table directly - so the
access is coming from somewhere else. In PostgreSQL/EPAS that "somewhere else" is almost
always role membership or the implicit `PUBLIC` role.

### Step 2: Read the table's ACL

Look at the access privileges with `\dp chaos_m04b.salaries`. Read each ACL line as
`role=privileges/grantor`. The one that matters here is the entry with an **empty role
name** before the `=` (for example `=r/enterprisedb`) - an empty role name means the
grant is to `PUBLIC`, the implicit role every account belongs to now and in future.

### Step 3: Understand why granting narrowly did not help

A privilege on `PUBLIC` is held by everyone. Granting the table only to your intended
roles does nothing to restrict access while `PUBLIC` still holds `SELECT` - every current
and future role can read it regardless.

## Resolution Approach

Remove the privilege from `PUBLIC`, then grant it explicitly only to the roles that
genuinely need it. After the revoke, an account like `chaos_nobody` that was never granted
the table should get "permission denied." Verify by testing as that role, not as the
owner.

## Prevention

Treat `PUBLIC` grants as a red flag. When hardening a database, review `\dp` for `PUBLIC`
entries and revoke what should not be world-readable - including the default `PUBLIC`
grants a fresh database ships with. Grant to named roles, never to `PUBLIC`, for anything
sensitive.
