# Use 03 - SSL Enforcement Exercise

**Time:** 20 minutes
**Prerequisite:** Build 02 (SSL/TLS Connections)

---

## Scenario

Your security team at [COMPANY] ran a network scan and found that some connections to your Aurora cluster are not using SSL. This is a compliance violation under your data protection policy.

Your tasks:
1. Find which connections are not using SSL
2. Determine why
3. Fix the issue server-side (enforce SSL)
4. Verify all connections now use SSL
5. Document which applications need updating

---

## Setup

Set these variables:

```bash
export CLUSTER_ID="devops-lab-cluster"
export CLUSTER_ENDPOINT=$(aws rds describe-db-clusters \
  --db-cluster-identifier $CLUSTER_ID \
  --query 'DBClusters[0].Endpoint' \
  --output text \
  --region us-east-1)
export AWS_REGION="us-east-1"
export PARAM_GROUP_NAME="devops-lab-cluster-params"
```

Connect as master user:

```bash
psql \
  "host=$CLUSTER_ENDPOINT port=5432 dbname=postgres user=postgres sslmode=require"
```

Create a test user for simulating the problem:

```sql
CREATE ROLE legacy_app WITH LOGIN PASSWORD 'LegacyPass1!';
GRANT CONNECT ON DATABASE postgres TO legacy_app;
```

Exit:

```sql
\q
```

---

## Task 1 - Simulate Unencrypted Connections

Open a second terminal and connect without SSL:

```bash
psql \
  "host=$CLUSTER_ENDPOINT port=5432 dbname=postgres user=legacy_app sslmode=disable"
```

If this fails (SSL already enforced), note that and skip to Task 4.

If it succeeds, leave this connection open and continue.

---

## Task 2 - Find Unencrypted Connections

In your master user session, run this query:

```sql
SELECT
    sa.pid,
    sa.usename,
    sa.client_addr,
    sa.application_name,
    ss.ssl,
    ss.version AS ssl_version,
    ss.cipher
FROM pg_stat_activity sa
LEFT JOIN pg_stat_ssl ss ON sa.pid = ss.pid
WHERE sa.backend_type = 'client backend'
  AND sa.usename IS NOT NULL
ORDER BY ss.ssl, sa.usename;
```

Write down:
- Which users are connecting without SSL (`ssl = f`)
- Their `client_addr`
- Their `application_name`

<details>
<summary>Hint - What to look for</summary>

Any row with `ssl = f` and empty `ssl_version` and `cipher` columns is an unencrypted connection. Note the username and IP address - these are the connections you need to fix.

</details>

---

## Task 3 - Check Current SSL Enforcement Status

```sql
SHOW rds.force_ssl;
```

Write down the result. If it says `off`, SSL is not being enforced.

Also count encrypted vs unencrypted connections:

```sql
SELECT
    COUNT(*) FILTER (WHERE ss.ssl = TRUE) AS ssl_connections,
    COUNT(*) FILTER (WHERE ss.ssl = FALSE) AS non_ssl_connections,
    COUNT(*) AS total_connections
FROM pg_stat_activity sa
JOIN pg_stat_ssl ss ON sa.pid = ss.pid
WHERE sa.backend_type = 'client backend';
```

<details>
<summary>Expected output if SSL is not enforced</summary>

```
 ssl_connections | non_ssl_connections | total_connections
-----------------+---------------------+-------------------
               1 |                   1 |                 2
```

`non_ssl_connections` greater than 0 is the problem.

</details>

---

## Task 4 - Enable SSL Enforcement

Set `rds.force_ssl = 1` in the cluster parameter group:

<details>
<summary>Solution</summary>

```bash
aws rds modify-db-cluster-parameter-group \
  --db-cluster-parameter-group-name $PARAM_GROUP_NAME \
  --parameters "ParameterName=rds.force_ssl,ParameterValue=1,ApplyMethod=immediate" \
  --region $AWS_REGION
```

For Aurora, `rds.force_ssl` is a dynamic parameter - no reboot required.

</details>

---

## Task 5 - Verify SSL Is Enforced

Try to connect without SSL:

```bash
psql \
  "host=$CLUSTER_ENDPOINT port=5432 dbname=postgres user=legacy_app sslmode=disable"
```

<details>
<summary>Expected result</summary>

```
psql: error: connection to server at "..." failed:
FATAL:  no pg_hba.conf entry for host "...", user "legacy_app", database "postgres", SSL off
```

Good - the server rejected the non-SSL connection.

</details>

Now connect with SSL to confirm it still works:

```bash
psql \
  "host=$CLUSTER_ENDPOINT port=5432 dbname=postgres user=legacy_app sslmode=require"
```

<details>
<summary>Expected result</summary>

```
psql (16.6)
SSL connection (protocol: TLSv1.3, ...)
Type "help" for help.

postgres=>
```

SSL connections still work.

</details>

---

## Task 6 - Verify All Connections Use SSL

Reconnect as master user with SSL and check:

```sql
SELECT
    COUNT(*) FILTER (WHERE ss.ssl = TRUE) AS ssl_connections,
    COUNT(*) FILTER (WHERE ss.ssl = FALSE) AS non_ssl_connections
FROM pg_stat_activity sa
JOIN pg_stat_ssl ss ON sa.pid = ss.pid
WHERE sa.backend_type = 'client backend';
```

<details>
<summary>Expected result</summary>

```
 ssl_connections | non_ssl_connections
-----------------+---------------------
               2 |                   0
```

`non_ssl_connections = 0`. All connections are encrypted.

</details>

---

## Task 7 - Test Different SSL Modes

Test each SSL mode and document what happens:

**Test sslmode=disable:**

```bash
psql "host=$CLUSTER_ENDPOINT port=5432 dbname=postgres user=postgres sslmode=disable" 2>&1 | head -3
```

**Test sslmode=require:**

```bash
psql "host=$CLUSTER_ENDPOINT port=5432 dbname=postgres user=postgres sslmode=require" -c "SELECT ssl FROM pg_stat_ssl WHERE pid = pg_backend_pid();"
```

**Test sslmode=verify-full:**

```bash
psql "host=$CLUSTER_ENDPOINT port=5432 dbname=postgres user=postgres sslmode=verify-full sslrootcert=$HOME/rds-ca-bundle.pem" -c "SELECT ssl, version FROM pg_stat_ssl WHERE pid = pg_backend_pid();"
```

Fill in this table:

| sslmode | Result | Encrypted? | Certificate verified? |
|---------|--------|-----------|----------------------|
| disable | ? | ? | ? |
| require | ? | ? | ? |
| verify-full | ? | ? | ? |

<details>
<summary>Solution</summary>

| sslmode | Result | Encrypted? | Certificate verified? |
|---------|--------|-----------|----------------------|
| disable | Connection refused (FATAL: SSL off) | No | No |
| require | Connected, ssl=t | Yes | No |
| verify-full | Connected, ssl=t, TLSv1.3 | Yes | Yes |

`verify-full` is the correct choice for production.

</details>

---

## Task 8 - Write the Remediation Report

Write a brief report covering:

1. How many connections were found without SSL before enforcement?
2. What parameter was changed and to what value?
3. Confirmation that all connections now use SSL
4. Recommendation: should applications use `sslmode=require` or `sslmode=verify-full`? Why?

<details>
<summary>Sample report</summary>

```
SSL Enforcement Remediation Report
Date: [TODAY]
Cluster: devops-lab-cluster

Findings:
- 1 non-SSL connection found (user: legacy_app)
- rds.force_ssl was set to 'off'

Actions taken:
- Set rds.force_ssl = 1 in cluster parameter group
- Verified all connections now use SSL (0 non-SSL connections)

Recommendation:
- All applications should use sslmode=verify-full (not just require)
- verify-full validates both the certificate and hostname, preventing
  man-in-the-middle attacks
- Applications need the RDS CA bundle at:
  https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem
```

</details>

---

## Clean Up

```sql
DROP ROLE legacy_app;
```
