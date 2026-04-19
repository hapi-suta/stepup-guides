# USE 06 - IAM Database Authentication

## Objective

Enable IAM authentication, create IAM-based database users, connect using IAM credentials through the Auth Proxy, and audit access.

---

## Exercise 1 - Enable IAM Authentication

Check if IAM auth is currently enabled.

```bash
gcloud sql instances describe suta-pg-lab --format="yaml(settings.databaseFlags)"
```

Look for `cloudsql.iam_authentication=on` in the output. If missing, enable it.

```bash
gcloud sql instances patch suta-pg-lab \
  --database-flags=cloudsql.iam_authentication=on,log_statement=ddl,log_min_duration_statement=1000,log_connections=on,log_disconnections=on
```

Remember to include all existing flags you want to keep.

Verify the flag is set.

```bash
gcloud sql instances describe suta-pg-lab --format="yaml(settings.databaseFlags)" | grep iam_authentication
```

Expected output (yours will differ):

```
  - name: cloudsql.iam_authentication
    value: 'on'
```

---

## Exercise 2 - Create an IAM Database User

Get your current IAM identity.

```bash
gcloud auth list --filter=status:ACTIVE --format="value(account)"
```

Expected output (yours will differ):

```
user@example.com
```

Create an IAM database user mapped to your GCP identity.

```bash
gcloud sql users create user@example.com \
  --instance=suta-pg-lab \
  --type=CLOUD_IAM_USER
```

Expected output (yours will differ):

```
Creating Cloud SQL user...done.
```

List all database users.

```bash
gcloud sql users list --instance=suta-pg-lab --format="table(name,type)"
```

Expected output (yours will differ):

```
NAME                TYPE
postgres            BUILT_IN
user@example.com    CLOUD_IAM_USER
```

---

## Exercise 3 - Grant PostgreSQL Permissions

IAM auth handles authentication (who are you?). PostgreSQL roles handle authorization (what can you do?).

Connect as postgres to grant permissions to the IAM user.

```bash
psql -h 127.0.0.1 -U postgres -d suta_lab
```

Grant read access on existing tables.

```sql
GRANT USAGE ON SCHEMA public TO "user@example.com";
```

```sql
GRANT SELECT ON ALL TABLES IN SCHEMA public TO "user@example.com";
```

Grant read/write on future tables.

```sql
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO "user@example.com";
```

Verify the grants.

```sql
SELECT grantee, table_name, privilege_type
FROM information_schema.table_privileges
WHERE grantee = 'user@example.com'
ORDER BY table_name, privilege_type;
```

Expected output (yours will differ):

```
      grantee       | table_name | privilege_type
--------------------+------------+----------------
 user@example.com   | students   | SELECT
...
```

Type `\q` to exit psql.

```
\q
```

---

## Exercise 4 - Connect with IAM Authentication

Start the Auth Proxy with automatic IAM authentication. The `--auto-iam-authn` flag tells the proxy to generate IAM tokens for login.

```bash
cloud-sql-proxy --auto-iam-authn [CONNECTION_NAME]
```

In a new terminal, connect as the IAM user. No password needed - the proxy provides the IAM token.

```bash
psql "host=127.0.0.1 user=user@example.com dbname=suta_lab sslmode=disable"
```

Verify your identity.

```sql
SELECT current_user, session_user;
```

Expected output (yours will differ):

```
    current_user    |   session_user
--------------------+------------------
 user@example.com   | user@example.com
(1 row)
```

Test that you have SELECT access.

```sql
SELECT * FROM students LIMIT 3;
```

Test that you cannot do operations outside your grants (if only SELECT was granted).

```sql
DROP TABLE students;
```

Expected output (yours will differ):

```
ERROR:  must be owner of table students
```

Type `\q` to exit psql.

```
\q
```

---

## Exercise 5 - Create an IAM Service Account User

Create a service account for application access.

```bash
gcloud iam service-accounts create app-db-user \
  --display-name="Application Database User"
```

Grant the service account the Cloud SQL Client role.

```bash
gcloud projects add-iam-policy-binding [PROJECT_ID] \
  --member="serviceAccount:app-db-user@[PROJECT_ID].iam.gserviceaccount.com" \
  --role="roles/cloudsql.client"
```

Create an IAM database user for the service account. Note: use `.iam` suffix, not `.iam.gserviceaccount.com`.

```bash
gcloud sql users create app-db-user@[PROJECT_ID].iam \
  --instance=suta-pg-lab \
  --type=CLOUD_IAM_SERVICE_ACCOUNT
```

Grant PostgreSQL permissions.

```bash
psql -h 127.0.0.1 -U postgres -d suta_lab
```

```sql
GRANT USAGE ON SCHEMA public TO "app-db-user@[PROJECT_ID].iam";
```

```sql
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO "app-db-user@[PROJECT_ID].iam";
```

Type `\q` to exit psql.

```
\q
```

---

## Exercise 6 - Audit IAM Access

Check who has connected recently. Connection logs show the IAM user.

```bash
gcloud logging read 'resource.type="cloudsql_database" AND textPayload:"connection authorized"' \
  --limit=10 \
  --format="table(timestamp,textPayload)"
```

Expected output (yours will differ):

```
TIMESTAMP                    TEXT_PAYLOAD
2026-04-19T15:30:00.000Z    [1234]: connection authorized: user=user@example.com database=suta_lab
2026-04-19T15:25:00.000Z    [1234]: connection authorized: user=postgres database=suta_lab
...
```

Check Cloud Audit Logs for IAM user creation.

```bash
gcloud logging read 'protoPayload.methodName="cloudsql.users.create"' \
  --limit=5 \
  --format="table(timestamp,protoPayload.methodName,protoPayload.request.body)"
```

List all database users with their types.

```bash
gcloud sql users list --instance=suta-pg-lab --format="table(name,type)"
```

Expected output (yours will differ):

```
NAME                                    TYPE
postgres                                BUILT_IN
user@example.com                        CLOUD_IAM_USER
app-db-user@my-project.iam              CLOUD_IAM_SERVICE_ACCOUNT
```

---

## Exercise 7 - Revoke IAM Access

Remove PostgreSQL permissions.

```bash
psql -h 127.0.0.1 -U postgres -d suta_lab
```

```sql
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM "user@example.com";
```

```sql
REVOKE USAGE ON SCHEMA public FROM "user@example.com";
```

Type `\q` to exit psql.

```
\q
```

Delete the IAM database user.

```bash
gcloud sql users delete user@example.com --instance=suta-pg-lab
```

---

## Checklist

- [ ] IAM authentication flag enabled
- [ ] IAM database user created for your GCP identity
- [ ] PostgreSQL permissions granted to IAM user
- [ ] Connected via Auth Proxy with `--auto-iam-authn`
- [ ] Verified IAM user identity inside PostgreSQL
- [ ] Tested permission boundaries (SELECT works, DROP fails)
- [ ] Created IAM service account user
- [ ] Audited IAM access in Cloud Logging
