# Runbook: The account that locked itself out

## Symptoms

An application user (`chaos_card_app`) that logged in fine before now fails every
connection. The app team insists the password is unchanged. The login error is not
"password authentication failed" - it is `role "chaos_card_app" is locked`.

## Diagnostic Steps

### Step 1: Separate "wrong password" from "locked account"

A wrong password and a locked account are different failures with different fixes. The
error text is your first clue: `is locked` is not the same as `password authentication
failed`. Do not touch the password yet.

### Step 2: Read the account state from the data dictionary

The authoritative answer is in `DBA_USERS`. Look at `account_status` for this user. A
value of `LOCKED` or `LOCKED(TIMED)` confirms the account is locked, not that the
password is wrong. `LOCKED(TIMED)` specifically means it was auto-locked by a profile's
`FAILED_LOGIN_ATTEMPTS` and would eventually clear on its own after `PASSWORD_LOCK_TIME`.

### Step 3: Understand the policy you are operating under

Check which profile the account carries (`DBA_USERS.profile`) and what that profile
enforces (`DBA_PROFILES`). This tells you how many failures triggered the lock and
whether there is a lingering bad-credential client that will just lock it again.

## Resolution Approach

The account is locked, so the fix is to unlock it - not to reset the password. Once the
account is `OPEN` again the existing correct password works. Before you unlock, make sure
whatever was sending bad passwords has stopped, or you will be back here in minutes.

## Prevention

Profiles with `FAILED_LOGIN_ATTEMPTS` are a good control - but a service account behind a
flapping client will lock repeatedly. Alert on `account_status` changes, and make sure
rotated secrets reach every host before the old one starts failing.
