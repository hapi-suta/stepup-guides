# SURVIVE 06 - SSL Not Enforced

## Symptom

A security audit reveals that unencrypted connections to the RDS instance are possible. Clients can connect with `sslmode=disable` and send credentials in plaintext.

---

## Diagnosis

### Step 1 - Test for non-SSL connections

```bash
RDS_ENDPOINT=$(aws rds describe-db-instances --db-instance-identifier suta-pg-lab --query "DBInstances[0].Endpoint.Address" --output text)
```

```bash
psql "host=${RDS_ENDPOINT} user=sutaadmin dbname=postgres sslmode=disable"
```

If this connects, the instance accepts unencrypted connections. Once connected, check the SSL status:

```sql
SELECT ssl FROM pg_stat_ssl WHERE pid = pg_backend_pid();
```

If the output shows `ssl = f`, the connection is unencrypted. This is the vulnerability.

Exit psql:

```sql
\q
```

### Step 2 - Check the rds.force_ssl parameter

```bash
PARAM_GROUP=$(aws rds describe-db-instances --db-instance-identifier suta-pg-lab --query "DBInstances[0].DBParameterGroups[0].DBParameterGroupName" --output text)
```

```bash
aws rds describe-db-parameters \
    --db-parameter-group-name "${PARAM_GROUP}" \
    --query "Parameters[?ParameterName=='rds.force_ssl'].{Name:ParameterName,Value:ParameterValue,Source:Source}" \
    --output table
```

If the value is `0` or empty, SSL is not enforced.

Expected output (vulnerable state):

```
-----------------------------------------------
|          DescribeDBParameters               |
+----------------+-------+--------------------+
|     Name       | Value |      Source        |
+----------------+-------+--------------------+
| rds.force_ssl  | 0     | user               |
+----------------+-------+--------------------+
```

---

## Fix

### Step 3 - Enable SSL enforcement

```bash
aws rds modify-db-parameter-group \
    --db-parameter-group-name "${PARAM_GROUP}" \
    --parameters "ParameterName=rds.force_ssl,ParameterValue=1,ApplyMethod=immediate"
```

The `rds.force_ssl` parameter is dynamic - it takes effect immediately without a reboot.

### Step 4 - Wait for the change to propagate

The parameter change applies within a few seconds to a minute:

```bash
sleep 15
```

### Step 5 - Verify non-SSL connections are rejected

```bash
psql "host=${RDS_ENDPOINT} user=sutaadmin dbname=postgres sslmode=disable"
```

Expected output:

```
psql: error: connection to server at "suta-pg-lab.c9abcdef12gh.us-east-1.rds.amazonaws.com" (10.0.1.50), port 5432 failed: FATAL:  no pg_hba.conf entry for host "10.0.2.100", user "sutaadmin", database "postgres", no encryption
```

The connection is rejected because SSL is required.

### Step 6 - Verify SSL connections still work

```bash
psql "host=${RDS_ENDPOINT} user=sutaadmin dbname=postgres sslmode=require"
```

Once connected, verify SSL details:

```sql
SELECT ssl, version FROM pg_stat_ssl WHERE pid = pg_backend_pid();
```

Expected output:

```
 ssl | version
-----+---------
 t   | TLSv1.3
(1 row)
```

Exit psql:

```sql
\q
```

### Step 7 - Verify the parameter is set correctly

```bash
aws rds describe-db-parameters \
    --db-parameter-group-name "${PARAM_GROUP}" \
    --query "Parameters[?ParameterName=='rds.force_ssl'].{Name:ParameterName,Value:ParameterValue}" \
    --output table
```

Expected output:

```
-------------------------------
| DescribeDBParameters        |
+----------------+------------+
|     Name       |   Value    |
+----------------+------------+
| rds.force_ssl  | 1          |
+----------------+------------+
```

---

## Verification

Run both tests to confirm:

Test 1 - Non-SSL should fail:

```bash
psql "host=${RDS_ENDPOINT} user=sutaadmin dbname=postgres sslmode=disable"
```

Expected output (yours will differ):

```
psql: error: connection to server ... failed: FATAL:  no pg_hba.conf entry ... no encryption
```

This confirms unencrypted connections are blocked.

Test 2 - SSL should succeed:

```bash
psql "host=${RDS_ENDPOINT} user=sutaadmin dbname=postgres sslmode=require"
```

Once connected, verify:

```sql
SELECT 'ssl_enforced' AS status;
```

Expected output:

```
    status
--------------
 ssl_enforced
(1 row)
```

Exit psql:

```sql
\q
```

---

## Discussion Questions

1. Why is `rds.force_ssl` an RDS-specific parameter and not a standard PostgreSQL setting?
2. What is the difference between `sslmode=require` and `sslmode=verify-full`?
3. How does SSL enforcement affect performance?
4. Should you enforce SSL at the security group level, parameter level, or both?
