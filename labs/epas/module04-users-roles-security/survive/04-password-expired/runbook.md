# Runbook: The password that expired

## Symptoms

A batch account (`chaos_batch`) that worked before starts refusing logins. Unlike a
bad-password lockout, this account was not hammered with wrong passwords - it simply
stopped accepting the credential it always used. A login attempt is told the password
must be changed before anything else can run.

## Diagnostic Steps

### Step 1: Distinguish expiry from lockout

Expiry and lockout look similar (the account cannot log in) but are different states with
different fixes. Do not assume it is a lockout. Read `DBA_USERS.account_status`: an
`EXPIRED` (or grace) status means the password aged out, whereas `LOCKED`/`LOCKED(TIMED)`
would mean a bad-password lockout.

### Step 2: Confirm it is the password's age, not a lock

`EXPIRED` in `account_status`, and a login error about needing to change the password,
together confirm the password reached the end of its `PASSWORD_LIFE_TIME` (plus any
`PASSWORD_GRACE_TIME`). Check the account's profile (`DBA_USERS.profile`, `DBA_PROFILES`)
to see the policy that expired it.

### Step 3: Decide whether the policy even belongs on this account

A human account should rotate passwords - expiry is working as designed. A service or
batch account that must never be interrupted may not belong on a human-password cadence at
all. Note which case you are in before you fix it.

## Resolution Approach

An expired password is resolved by setting a new one, which resets the password clock and
returns the account to `OPEN`. `ACCOUNT UNLOCK` does not help here - the account is not
locked, the password is expired. If this is a service account that should not expire,
also reconsider the profile's `PASSWORD_LIFE_TIME` so you are not back here in 90 days.

## Prevention

Match the profile to the account type: human logins get expiry, service accounts get a
profile whose `PASSWORD_LIFE_TIME` reflects a deliberate rotation plan (or `UNLIMITED`
with compensating controls). Alert before expiry, not after the batch job fails.
