# Build 03 - SSL/TLS Connections

**Time:** 30 minutes
**Goal:** Download the RDS CA certificate, connect with verified SSL, check connection status, and enforce SSL server-side.

---

## Before You Start

Read `concepts/security.md` section T2.3 first.

You need:
- A running RDS PostgreSQL instance
- psql installed
- AWS CLI configured

Set these variables:

```bash
export RDS_HOST="your-instance.abc123.us-east-1.rds.amazonaws.com"
export RDS_PORT="5432"
export RDS_MASTER_USER="postgres"
export RDS_DB="postgres"
export RDS_INSTANCE_ID="my-postgres-db"
export PARAM_GROUP_NAME="my-postgres-params"
export AWS_REGION="us-east-1"
```

---

## Step 1 - Connect Without SSL and See What Happens

First, try connecting with SSL disabled so you understand the difference.

```bash
psql \
  "host=$RDS_HOST \
   port=$RDS_PORT \
   dbname=$RDS_DB \
   user=$RDS_MASTER_USER \
   sslmode=disable"
```

`sslmode=disable` tells psql not to use SSL at all.

You may see one of two outcomes:

**If rds.force_ssl is already on (default for new instances):**

```
psql: error: connection to server at "..." failed:
FATAL:  no pg_hba.conf entry for host "...", user "postgres", database "postgres", SSL off
```

**If rds.force_ssl is off:**

```
psql (16.6)
Type "help" for help.

postgres=>
```

If you connected without SSL, run this to verify the connection is unencrypted:

```sql
SELECT ssl FROM pg_stat_ssl WHERE pid = pg_backend_pid();
```

Expected output:

```
 ssl
─────
 f
```

`f` means false - no SSL on this connection. This is a problem.

Exit psql:

```sql
\q
```

---

## Step 2 - Download the RDS CA Certificate Bundle

AWS signs RDS server certificates with its own Certificate Authority (CA). You need the CA bundle to verify you are talking to a real RDS server and not an impersonator.

Download the global bundle (works for all AWS regions):

```bash
curl -o ~/rds-ca-bundle.pem \
  https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem
```

`curl` downloads the file.
`-o ~/rds-ca-bundle.pem` saves it to your home directory.

Verify it downloaded correctly:

```bash
ls -lh ~/rds-ca-bundle.pem
```

Expected output (yours will differ):

```
-rw-r--r--  1 you  staff   230K Jan 15 14:23 /Users/you/rds-ca-bundle.pem
```

Check how many certificates are in the bundle:

```bash
grep -c 'BEGIN CERTIFICATE' ~/rds-ca-bundle.pem
```

Expected output (yours will differ):

```
96
```

The bundle contains many certificates because it includes CAs for all AWS regions and past rotation cycles.

> **Concept:** A Certificate Authority (CA) is a trusted organization that signs certificates. When RDS sends you its certificate, you check it against the CA bundle. If the signature matches, you know the certificate is genuine and you are talking to a real AWS RDS server.

---

## Step 3 - Connect With sslmode=require

Connect with SSL required but without certificate verification:

```bash
psql \
  "host=$RDS_HOST \
   port=$RDS_PORT \
   dbname=$RDS_DB \
   user=$RDS_MASTER_USER \
   sslmode=require"
```

`sslmode=require` demands an SSL connection but does not verify the server certificate.

This encrypts the connection but does not protect against a man-in-the-middle attack. A bad actor could intercept the connection and present their own certificate, and psql would not notice.

Verify SSL is active:

```sql
SELECT ssl, version, cipher, bits
FROM pg_stat_ssl
WHERE pid = pg_backend_pid();
```

Expected output (yours will differ):

```
 ssl │     version     │           cipher              │ bits
─────┼─────────────────┼───────────────────────────────┼──────
 t   │ TLSv1.3         │ TLS_AES_256_GCM_SHA384        │ 256
```

`ssl = t` means SSL is active.
`TLSv1.3` is the protocol version. 1.3 is the most secure.
`256` is the key size in bits.

Exit:

```sql
\q
```

---

## Step 4 - Connect With sslmode=verify-full

This is the most secure mode. It verifies the certificate AND the hostname.

```bash
psql \
  "host=$RDS_HOST \
   port=$RDS_PORT \
   dbname=$RDS_DB \
   user=$RDS_MASTER_USER \
   sslmode=verify-full \
   sslrootcert=$HOME/rds-ca-bundle.pem"
```

`sslmode=verify-full` verifies the server certificate is valid AND the hostname matches.
`sslrootcert` points to the CA bundle used to verify the certificate.

Expected output (yours will differ):

```
psql (16.6)
SSL connection (protocol: TLSv1.3, cipher: TLS_AES_256_GCM_SHA384, bits: 256, compression: off)
Type "help" for help.

postgres=>
```

Check the SSL details again:

```sql
SELECT pid, ssl, version, cipher, bits, client_dn, issuer_dn
FROM pg_stat_ssl
WHERE pid = pg_backend_pid();
```

Expected output (yours will differ):

```
  pid  │ ssl │     version     │           cipher              │ bits │ client_dn │       issuer_dn
───────┼─────┼─────────────────┼───────────────────────────────┼──────┼───────────┼───────────────────────
 12345 │ t   │ TLSv1.3         │ TLS_AES_256_GCM_SHA384        │ 256  │           │ CN=Amazon RDS ...
```

The `issuer_dn` shows you the certificate is signed by Amazon RDS. This confirms you are talking to a real RDS server.

Exit:

```sql
\q
```

---

## Step 5 - Check All Current Connections

While connected as the master user, you can see SSL status for all connections:

```bash
psql \
  "host=$RDS_HOST port=$RDS_PORT dbname=$RDS_DB user=$RDS_MASTER_USER sslmode=verify-full sslrootcert=$HOME/rds-ca-bundle.pem"
```

```sql
SELECT
    sa.pid,
    sa.usename,
    sa.client_addr,
    ss.ssl,
    ss.version,
    ss.cipher
FROM pg_stat_activity sa
JOIN pg_stat_ssl ss ON sa.pid = ss.pid
WHERE sa.usename IS NOT NULL
ORDER BY sa.usename;
```

Expected output (yours will differ):

```
  pid  │  usename  │ client_addr  │ ssl │     version     │           cipher
───────┼───────────┼──────────────┼─────┼─────────────────┼──────────────────────────────
 12345 │ postgres  │ 203.0.113.5  │ t   │ TLSv1.3         │ TLS_AES_256_GCM_SHA384
 12346 │ app_user  │ 203.0.113.5  │ t   │ TLSv1.3         │ TLS_AES_256_GCM_SHA384
```

Any row with `ssl = f` is a problem. Write down the username and client_addr so you can find where that unencrypted connection is coming from.

Exit:

```sql
\q
```

---

## Step 6 - Enforce SSL Server-Side with rds.force_ssl

Right now, applications can choose to connect without SSL. The server allows it unless you force SSL.

Setting `rds.force_ssl = 1` in the parameter group makes the server reject any non-SSL connection. This is the recommended production setting.

### Using the AWS Console

1. Go to **RDS > Parameter groups** in the Console
2. Click your parameter group (or create one if you are using the default)
3. Click **Edit**
4. Search for `force_ssl`
5. Find `rds.force_ssl`
6. Change the value from `0` to `1`
7. Click **Save changes**
8. Reboot the RDS instance for the change to take effect

> Note: If you are using the default parameter group, you cannot edit it. You must create a custom parameter group first, then assign it to your instance.

### Using the AWS CLI

First, create a custom parameter group if you do not have one:

```bash
aws rds create-db-parameter-group \
  --db-parameter-group-name my-postgres-params \
  --db-parameter-group-family postgres16 \
  --description "Custom parameters for my PostgreSQL 16 instance" \
  --region $AWS_REGION
```

`--db-parameter-group-family` must match your PostgreSQL version (postgres13, postgres14, postgres15, postgres16).

Expected output (yours will differ):

```json
{
    "DBParameterGroup": {
        "DBParameterGroupName": "my-postgres-params",
        "DBParameterGroupFamily": "postgres15",
        "Description": "Custom parameters for my PostgreSQL 16 instance",
        ...
    }
}
```

Set the `rds.force_ssl` parameter to `1`:

```bash
aws rds modify-db-parameter-group \
  --db-parameter-group-name $PARAM_GROUP_NAME \
  --parameters "ParameterName=rds.force_ssl,ParameterValue=1,ApplyMethod=pending-reboot" \
  --region $AWS_REGION
```

`--parameters` takes a comma-separated list of parameter name, value, and apply method.
`ApplyMethod=pending-reboot` means the change takes effect after the next reboot.

Expected output:

```json
{
    "DBParameterGroupName": "my-postgres-params"
}
```

Assign the parameter group to your instance:

```bash
aws rds modify-db-instance \
  --db-instance-identifier $RDS_INSTANCE_ID \
  --db-parameter-group-name $PARAM_GROUP_NAME \
  --apply-immediately \
  --region $AWS_REGION
```

Reboot the instance to apply the parameter:

```bash
aws rds reboot-db-instance \
  --db-instance-identifier $RDS_INSTANCE_ID \
  --region $AWS_REGION
```

Wait for it to come back up:

```bash
aws rds wait db-instance-available \
  --db-instance-identifier $RDS_INSTANCE_ID \
  --region $AWS_REGION
```

This takes 2-5 minutes. The command returns with no output when the instance is available.

---

## Step 7 - Verify SSL is Enforced

Try to connect without SSL:

```bash
psql \
  "host=$RDS_HOST \
   port=$RDS_PORT \
   dbname=$RDS_DB \
   user=$RDS_MASTER_USER \
   sslmode=disable"
```

Expected output:

```
psql: error: connection to server at "..." (x.x.x.x) port 5432 failed:
FATAL:  no pg_hba.conf entry for host "x.x.x.x", user "postgres", database "postgres", SSL off
```

The server rejected the non-SSL connection. Good.

Now connect with SSL to confirm it still works:

```bash
psql \
  "host=$RDS_HOST \
   port=$RDS_PORT \
   dbname=$RDS_DB \
   user=$RDS_MASTER_USER \
   sslmode=verify-full \
   sslrootcert=$HOME/rds-ca-bundle.pem"
```

Expected output:

```
psql (16.6)
SSL connection (protocol: TLSv1.3, cipher: TLS_AES_256_GCM_SHA384, bits: 256, compression: off)
Type "help" for help.

postgres=>
```

---

## Step 8 - Certificate Rotation

AWS periodically updates its CA certificates. You will get an advance notice before the old CA expires. When that time comes:

**Check which CA your instance is using:**

```bash
aws rds describe-db-instances \
  --db-instance-identifier $RDS_INSTANCE_ID \
  --query 'DBInstances[0].CACertificateIdentifier' \
  --output text \
  --region $AWS_REGION
```

Expected output (yours will differ):

```
rds-ca-rsa2048-g1
```

**Update to the latest CA:**

```bash
aws rds modify-db-instance \
  --db-instance-identifier $RDS_INSTANCE_ID \
  --ca-certificate-identifier rds-ca-rsa4096-g1 \
  --apply-immediately \
  --region $AWS_REGION
```

**Update your certificate bundle:**

The global bundle already includes both old and new CAs. If you downloaded it recently, you are likely already covered. If in doubt, re-download it:

```bash
curl -o ~/rds-ca-bundle.pem \
  https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem
```

> **Concept:** The global bundle is the safest choice because it includes all current and recent CAs. Regional bundles (like `us-east-1-bundle.pem`) are smaller but may not include upcoming new CAs. Use the global bundle.

---

## Step 9 - Use a .pgpass File for SSL Connections

Typing the SSL options every time is tedious. Create a connection string alias.

Add this to your `~/.bash_profile` or `~/.zshrc`:

```bash
export PGSSLMODE=verify-full
export PGSSLROOTCERT=$HOME/rds-ca-bundle.pem
```

`PGSSLMODE` is an environment variable that psql reads automatically.
`PGSSLROOTCERT` points to the CA bundle.

Now any psql connection from this shell will use SSL with verification by default.

After adding these lines, reload your shell profile:

```bash
source ~/.zshrc
```

Or for bash:

```bash
source ~/.bash_profile
```

Test that the environment variables work:

```bash
psql \
  "host=$RDS_HOST port=$RDS_PORT dbname=$RDS_DB user=$RDS_MASTER_USER"
```

Expected output (yours will differ):

```
psql (16.6)
SSL connection (protocol: TLSv1.3, cipher: TLS_AES_256_GCM_SHA384, bits: 256, compression: off)
Type "help" for help.

postgres=>
```

No need to specify sslmode or sslrootcert - the environment variables handled it.

---

## What You Built

- Downloaded the RDS CA certificate bundle
- Connected with `sslmode=require` and `sslmode=verify-full`
- Checked SSL status with `pg_stat_ssl`
- Set `rds.force_ssl = 1` to reject non-SSL connections server-side
- Learned the certificate rotation process

---

## SSL Modes Quick Reference

| sslmode | Encrypts? | Verifies cert? | Verifies hostname? | Use when |
|---------|-----------|----------------|-------------------|----------|
| disable | No | No | No | Never in production |
| require | Yes | No | No | Basic encryption only |
| verify-ca | Yes | Yes | No | Certificate verified, hostname not |
| verify-full | Yes | Yes | Yes | Always - production standard |

---

## Key Rules to Remember

1. Always use `sslmode=verify-full` in production
2. Use the global bundle (`global-bundle.pem`) not regional bundles
3. Set `rds.force_ssl = 1` - do not rely on applications to choose SSL
4. Re-download the CA bundle before a certificate rotation
5. Set `PGSSLMODE` and `PGSSLROOTCERT` environment variables to make SSL automatic
