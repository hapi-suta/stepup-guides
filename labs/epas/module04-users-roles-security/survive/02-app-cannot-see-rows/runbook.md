# Runbook: The app that cannot see its own rows

## Symptoms

A reporting user (`chaos_reader`) runs a `SELECT` that used to return data and now gets
**zero rows** - no error, just an empty result. As the DBA (`enterprisedb`) the same
query returns every row, so at first glance the data looks fine and the app looks broken.

## Diagnostic Steps

### Step 1: Rule out a privilege problem

The query does not error - it returns an empty result. A missing `SELECT` privilege
would raise "permission denied," not return zero rows. So `SELECT` is granted; something
is filtering the rows, not blocking the statement.

### Step 2: Recognise that "works for me" is misleading here

You see all the rows because the table owner and superusers bypass Row-Level Security by
default. That does not mean RLS is off - it means it does not apply to you. Test as the
role that is actually failing, using `SET ROLE chaos_reader`, and you will reproduce the
empty result.

### Step 3: Check whether RLS is enabled and what policies exist

Look at the table (`\d chaos_m04.orders` reports "Row security enabled") and the policy
catalog (`pg_policies`). If row security is enabled but there is no policy - or no policy
whose `USING` expression matches `chaos_reader` - the table is default-deny for that role,
which is exactly the zero-rows symptom.

## Resolution Approach

The fix is to add the missing policy, not to disable RLS - disabling it would expose every
owner's rows to everyone. Write a policy whose `USING` expression lets a user see the rows
that belong to them, and confirm the role now sees its own rows and only its own.

## Prevention

Enabling RLS and its policy are two separate steps; enabling row security without adding a
policy is a self-inflicted outage. Make "enable + policy + test as the target role" one
change, and always verify by connecting as the real application role, never as the owner.
