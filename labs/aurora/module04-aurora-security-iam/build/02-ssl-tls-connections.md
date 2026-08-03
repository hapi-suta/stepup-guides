# Build 02 - SSL/TLS Connections

**Time:** 30 minutes
**Goal:** Download the RDS CA certificate, connect with verified SSL, check connection status, and enforce SSL server-side on your Aurora cluster.

---

## Before You Start

Read `concepts/01-database-security-layers.md` (Layer 4 - Encryption in Transit).

You need:
- A running Aurora PostgreSQL cluster
- psql installed
- AWS CLI configured

Set these variables:

```bash
export CLUSTER_ID="devops-lab-cluster"
export CLUSTER_ENDPOINT=$(aws rds describe-db-clusters \
  --db-cluster-identifier $CLUSTER_ID \
  --query 'DBClusters[0].Endpoint' \
  --output text \
  --region us-east-1)
export CLUSTER_PORT="5432"
export MASTER_USER="postgres"
export MASTER_DB="postgres"
export PARAM_GROUP_NAME="devops-lab-cluster-params"
export AWS_REGION="us-east-1"
```

Verify the endpoint was captured:

```bash
echo "Cluster endpoint: $CLUSTER_ENDPOINT"
```

---

## Step 1 - Connect Without SSL and See What Happens

Try connecting with SSL disabled so you understand the difference:

```bash
psql \
  "host=$CLUSTER_ENDPOINT \
   port=$CLUSTER_PORT \
   dbname=$MASTER_DB \
   user=$MASTER_USER \
   sslmode=disable"
```

`sslmode=disable` tells psql not to use SSL at all.

You may see one of two outcomes:

**If rds.force_ssl is already on:**

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

If you connected without SSL, verify the connection is unencrypted:

```sql
SELECT ssl FROM pg_stat_ssl WHERE pid = pg_backend_pid();
```

Expected output:

```
 ssl
-----
 f
```

`f` means false - no SSL on this connection. This is a problem.

Exit psql:

```sql
\q
```

---

## Step 2 - Download the RDS CA Certificate Bundle

AWS signs Aurora server certificates with its own Certificate Authority (CA). You need the CA bundle to verify you are talking to a real Aurora server and not an impersonator.

Download the global bundle (works for all AWS regions):

```bash
curl -o ~/rds-ca-bundle.pem \
  https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem
```

`curl` downloads the file from the URL.
`-o ~/rds-ca-bundle.pem` saves it to your home directory.

Verify it downloaded correctly:

```bash
ls -lh ~/rds-ca-bundle.pem
```

Expected output (yours will differ):

```
-rw-r--r--  1 you  staff   230K Jun  9 14:23 /Users/you/rds-ca-bundle.pem
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

> **Concept:** A Certificate Authority (CA) is a trusted organization that signs certificates. When Aurora sends you its certificate, you check it against the CA bundle. If the signature matches, you know the certificate is genuine and you are talking to a real AWS Aurora server.

---

## Step 3 - Connect With sslmode=require

Connect with SSL required but without certificate verification:

```bash
psql \
  "host=$CLUSTER_ENDPOINT \
   port=$CLUSTER_PORT \
   dbname=$MASTER_DB \
   user=$MASTER_USER \
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
 ssl |     version     |           cipher              | bits
-----+-----------------+-------------------------------+------
 t   | TLSv1.3         | TLS_AES_256_GCM_SHA384        | 256
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
  "host=$CLUSTER_ENDPOINT \
   port=$CLUSTER_PORT \
   dbname=$MASTER_DB \
   user=$MASTER_USER \
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

Check the SSL details:

```sql
SELECT pid, ssl, version, cipher, bits, client_dn, issuer_dn
FROM pg_stat_ssl
WHERE pid = pg_backend_pid();
```

Expected output (yours will differ):

```
  pid  | ssl |     version     |           cipher              | bits | client_dn |       issuer_dn
-------+-----+-----------------+-------------------------------+------+-----------+-----------------------
 12345 | t   | TLSv1.3         | TLS_AES_256_GCM_SHA384        | 256  |           | CN=Amazon RDS ...
```

The `issuer_dn` shows the certificate is signed by Amazon RDS. This confirms you are talking to a real Aurora server.

Exit:

```sql
\q
```

---

## Step 5 - Check All Current Connections

Connect as the master user and view SSL status for all connections:

```bash
psql \
  "host=$CLUSTER_ENDPOINT port=$CLUSTER_PORT dbname=$MASTER_DB user=$MASTER_USER sslmode=verify-full sslrootcert=$HOME/rds-ca-bundle.pem"
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
  pid  |  usename  | client_addr  | ssl |     version     |           cipher
-------+-----------+--------------+-----+-----------------+------------------------------
 12345 | postgres  | 203.0.113.5  | t   | TLSv1.3         | TLS_AES_256_GCM_SHA384
```

Any row with `ssl = f` is a problem. Write down the username and client_addr so you can find where that unencrypted connection is coming from.

Exit:

```sql
\q
```

---

## Step 6 - Enforce SSL Server-Side with rds.force_ssl

Right now, applications can choose to connect without SSL. The server allows it unless you force SSL.

Setting `rds.force_ssl = 1` in the cluster parameter group makes the server reject any non-SSL connection.

### Using the AWS Console

1. Go to **RDS > Parameter groups** in the Console
2. Click your cluster parameter group (or create one if using the default)
3. Click **Edit**
4. Search for `force_ssl`
5. Find `rds.force_ssl`
6. Change the value from `0` to `1`
7. Click **Save changes**

> Note: For Aurora cluster parameter groups, `rds.force_ssl` is a dynamic parameter. It does not require a reboot.

### Using the AWS CLI

First, check if you have a custom cluster parameter group. If using the default, create a custom one:

```bash
aws rds create-db-cluster-parameter-group \
  --db-cluster-parameter-group-name $PARAM_GROUP_NAME \
  --db-parameter-group-family aurora-postgresql16 \
  --description "Custom parameters for devops lab Aurora cluster" \
  --region $AWS_REGION
```

`--db-parameter-group-family` must match your Aurora PostgreSQL version.

Set the `rds.force_ssl` parameter to `1`:

```bash
aws rds modify-db-cluster-parameter-group \
  --db-cluster-parameter-group-name $PARAM_GROUP_NAME \
  --parameters "ParameterName=rds.force_ssl,ParameterValue=1,ApplyMethod=immediate" \
  --region $AWS_REGION
```

`--parameters` sets the parameter name, value, and apply method.
`ApplyMethod=immediate` applies the change right away without a reboot.

Expected output:

```json
{
    "DBClusterParameterGroupName": "devops-lab-cluster-params"
}
```

If you created a new parameter group, assign it to your cluster:

```bash
aws rds modify-db-cluster \
  --db-cluster-identifier $CLUSTER_ID \
  --db-cluster-parameter-group-name $PARAM_GROUP_NAME \
  --region $AWS_REGION
```

> **Note:** After assigning a new parameter group to a cluster, you may need to reboot the cluster instances for some parameters. For `rds.force_ssl`, it is dynamic and takes effect without a reboot on Aurora.

---

## Step 7 - Verify SSL is Enforced

Try to connect without SSL:

```bash
psql \
  "host=$CLUSTER_ENDPOINT \
   port=$CLUSTER_PORT \
   dbname=$MASTER_DB \
   user=$MASTER_USER \
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
  "host=$CLUSTER_ENDPOINT \
   port=$CLUSTER_PORT \
   dbname=$MASTER_DB \
   user=$MASTER_USER \
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

AWS periodically updates its CA certificates. You will get advance notice before the old CA expires.

**Check which CA your cluster instances are using:**

```bash
aws rds describe-db-instances \
  --filters "Name=db-cluster-id,Values=$CLUSTER_ID" \
  --query 'DBInstances[*].{Instance:DBInstanceIdentifier,CA:CACertificateIdentifier}' \
  --output table \
  --region $AWS_REGION
```

Expected output (yours will differ):

```
+----------------------------------+--------------------+
|           Instance               |       CA           |
+----------------------------------+--------------------+
| devops-lab-cluster-instance-1    | rds-ca-rsa2048-g1  |
+----------------------------------+--------------------+
```

The global bundle already includes both old and new CAs. If you downloaded it recently, you are covered. If in doubt, re-download it:

```bash
curl -o ~/rds-ca-bundle.pem \
  https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem
```

---

## Step 9 - Set Environment Variables for Automatic SSL

Typing SSL options every time is tedious. Set environment variables so psql uses SSL by default.

Add these to your `~/.zshrc` or `~/.bash_profile`:

```bash
export PGSSLMODE=verify-full
export PGSSLROOTCERT=$HOME/rds-ca-bundle.pem
```

`PGSSLMODE` tells psql which SSL mode to use by default.
`PGSSLROOTCERT` points to the CA bundle.

Reload your shell profile:

```bash
source ~/.zshrc
```

Test that the environment variables work:

```bash
psql \
  "host=$CLUSTER_ENDPOINT port=$CLUSTER_PORT dbname=$MASTER_DB user=$MASTER_USER"
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
- Set environment variables for automatic SSL

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
