# Exercise 03 - Password Rotation

**Module:** 06 - Users, Roles & Connections
**Time:** 15 minutes

---

## Scenario

Security policy requires rotating the app_user password every 90 days. The Pulse app is currently running. Your job is to rotate the password without downtime.

The safe rotation procedure is:
1. Change the password in PostgreSQL
2. Verify the old password no longer works
3. Update the app configuration with the new password
4. Restart the app
5. Confirm the app is healthy

---

## Setup

```bash
ssh -i your-key.pem ec2-user@NODE1
```

---

## Task 1 - Record the current password (simulated)

In this lab, the current password is `apppass123`. Write it down as if you retrieved it from your secrets manager.

Current password: `apppass123`
New password: `apppass456-newrotation`

---

## Task 2 - Change the password in PostgreSQL

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

```sql
ALTER ROLE app_user PASSWORD 'apppass456-newrotation';
```

Expected output:

```
ALTER ROLE
```

---

## Task 3 - Verify the new password works

Open a second terminal. Connect using the new password:

```bash
/usr/pgsql-16/bin/psql -h 127.0.0.1 -p 5432 -U app_user -d stepup_store
```

Enter `apppass456-newrotation` when prompted.

```sql
SELECT current_user, now();
```

Expected output (yours will differ):

```
 current_user |              now
--------------+-------------------------------
 app_user     | 2026-04-19 10:00:00.123456+00
(1 row)
```

```bash
\q
```

---

## Task 4 - Verify the old password no longer works

Try connecting with the old password:

```bash
/usr/pgsql-16/bin/psql -h 127.0.0.1 -p 5432 -U app_user -d stepup_store
```

Enter `apppass123` when prompted.

Expected output:

```
psql: error: connection to server at "127.0.0.1", port 5432 failed: FATAL:  password authentication failed for user "app_user"
```

---

## Task 5 - Update the Pulse app configuration

The Pulse app reads its connection string from an environment file or configuration file. Locate and update it.

```bash
sudo find /etc /opt /home -name "*.env" -o -name "*.conf" 2>/dev/null | xargs grep -l "app_user" 2>/dev/null
```

Update the password in the app configuration file. The exact file path depends on how Pulse is deployed. For example:

```bash
sudo vi /etc/pulse/database.conf
```

Change the line containing the database password to:

```
DB_PASSWORD=apppass456-newrotation
```

Save and exit vi with `:wq`.

---

## Task 6 - Restart the Pulse app

```bash
sudo systemctl restart pulse-dashboard
```

Wait 5 seconds for the app to come up:

```bash
sudo systemctl status pulse-dashboard
```

Expected output (yours will differ):

```
 pulse-dashboard.service
   Active: active (running) since ...
```

---

## Task 7 - Confirm the dashboard is healthy

Open your browser and go to `http://NODE1:8080`. Confirm the database status indicator shows green.

---

## Task 8 - Set a password expiry (optional best practice)

You can configure a role's password to expire automatically:

Back in the postgres terminal:

```sql
ALTER ROLE app_user VALID UNTIL '2026-07-19 00:00:00 UTC';
```

This sets the password to expire on July 19, 2026. After this date, the role cannot connect until a new password is set.

Expected output:

```
ALTER ROLE
```

View the expiry:

```sql
SELECT rolname, rolvaliduntil FROM pg_roles WHERE rolname = 'app_user';
```

Expected output (yours will differ):

```
  rolname  |       rolvaliduntil
-----------+----------------------------
 app_user  | 2026-07-19 00:00:00+00
(1 row)
```

---

## Task 9 - Exit

```bash
\q
```

```bash
exit
```

---

## Review Questions

1. Why did we change the password in PostgreSQL BEFORE updating the app config? What would happen if we did it the other way around?
2. What is the risk of setting VALID UNTIL to a date in the past during a rotation? (Hint: read about scenario 06.)
3. How would you rotate the password with zero downtime if the app cannot be restarted?
