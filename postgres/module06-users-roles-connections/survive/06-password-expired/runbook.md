# Scenario 06 - Password Expired

**Severity:** HIGH
**Expected Recovery Time:** 3-5 minutes
**Single Node:** NODE1 only

---

## Alert

```
ALERT: Pulse dashboard is showing authentication failure.
Application log shows: FATAL: password authentication failed for user 'app_user'
Ops team suspects the password was changed, but the password itself is correct.
Something else is wrong.
```

---

## Key Concepts for Revision

- **VALID UNTIL controls password expiry** - The `VALID UNTIL` attribute on a role sets a timestamp after which the role's password is considered expired. Once expired, authentication fails even if the correct password is provided. The error message looks identical to "wrong password," which makes this a tricky diagnosis.

- **Check pg_roles for expiry** - The `rolvaliduntil` column in `pg_roles` shows the expiry timestamp. If it is in the past, the role cannot authenticate via password. A value of `NULL` or `infinity` means the password never expires.

- **Resetting expiry** - Use `ALTER ROLE rolename VALID UNTIL 'infinity';` to remove the expiry entirely, or set a new future date. This is the correct fix - do not change the password unnecessarily.

- **Diagnosing "password failed" errors** - When authentication fails, always check: (1) is the password actually wrong, (2) is VALID UNTIL in the past, (3) is the role marked NOLOGIN, (4) is the role's CONNECTION LIMIT exhausted, (5) is the pg_hba.conf method incompatible with how the client is connecting.

---

## Diagnostic Steps

### Step 1 - Confirm the error

```bash
/usr/pgsql-16/bin/psql -h 127.0.0.1 -p 5432 -U app_user -d stepup_store
```

Enter `apppass123`. Even with the correct password:

Expected output:

```
psql: error: connection to server at "127.0.0.1", port 5432 failed: FATAL:  password authentication failed for user "app_user"
```

### Step 2 - Connect as postgres via socket

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

### Step 3 - Check role attributes

```sql
SELECT rolname, rolcanlogin, rolconnlimit, rolvaliduntil
FROM pg_roles
WHERE rolname = 'app_user';
```

Expected output:

```
  rolname  | rolcanlogin | rolconnlimit |     rolvaliduntil
-----------+-------------+--------------+------------------------
 app_user  | t           |           10 | 2000-01-01 00:00:00+00
```

The `rolvaliduntil` is in the year 2000 - clearly in the past. This is the problem. The password has "expired" by this definition.

---

## Resolution

### Step 1 - Extend the VALID UNTIL date

If the password should not expire, remove the expiry entirely:

```sql
ALTER ROLE app_user VALID UNTIL 'infinity';
```

Or set a future date if your security policy requires expiry:

```sql
ALTER ROLE app_user VALID UNTIL '2027-01-01 00:00:00 UTC';
```

Expected output:

```
ALTER ROLE
```

### Step 2 - Verify the fix

```sql
SELECT rolname, rolvaliduntil FROM pg_roles WHERE rolname = 'app_user';
```

Expected output (if set to infinity):

```
  rolname  | rolvaliduntil
-----------+---------------
 app_user  |
(1 row)
```

NULL means no expiry (infinity).

### Step 3 - Test the connection

```bash
\q
```

```bash
exit
```

```bash
/usr/pgsql-16/bin/psql -h 127.0.0.1 -p 5432 -U app_user -d stepup_store -c "SELECT current_user;"
```

Enter `apppass123`.

Expected output:

```
 current_user
--------------
 app_user
(1 row)
```

### Step 4 - Verify the Pulse dashboard recovers

Open your browser and go to `http://NODE1:8080`. Confirm the dashboard returns to green status.

---

## Validation

Run the validation script to confirm the scenario is resolved.

```bash
./validate.sh
```

Expected checks:
- PostgreSQL is running
- app_user VALID UNTIL is NULL (infinity) or in the future
- app_user can authenticate via TCP

---

## Interview Discussion Points

1. **Why does an expired VALID UNTIL produce the same error as a wrong password?** - PostgreSQL intentionally returns a generic "authentication failed" message to prevent information leakage. If it said "password expired" instead, an attacker would know the account exists and the password is correct - useful intelligence for an attack. The opaque error message is a security feature.

2. **What is the right VALID UNTIL value for an application service account?** - Most service accounts should have `VALID UNTIL 'infinity'` or no expiry set. Password rotation for service accounts should be handled by your secrets management system (e.g., HashiCorp Vault, AWS Secrets Manager), not by PostgreSQL's built-in expiry. Setting expiry in PostgreSQL on service accounts creates operational risk when the expiry is missed.

3. **How do you set up automated alerts for approaching VALID UNTIL dates?** - Query `pg_roles WHERE rolvaliduntil < now() + interval '14 days'` on a scheduled basis. If any rows return, page the on-call team. Add this to your monitoring system as a regular check.

4. **Does VALID UNTIL affect Unix socket (local) connections?** - Yes. VALID UNTIL applies to password authentication regardless of connection type. However, `trust` and `peer` methods do not check the password at all, so VALID UNTIL has no effect when those methods are used.

5. **Can you set VALID UNTIL on a group role that has no LOGIN?** - Yes, but it has no effect. VALID UNTIL only applies to password authentication, which requires the LOGIN attribute. Setting it on a NOLOGIN group role is harmless but meaningless.
