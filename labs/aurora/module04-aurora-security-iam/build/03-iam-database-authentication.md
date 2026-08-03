# Build 03 - IAM Database Authentication

**Time:** 40 minutes
**Goal:** Enable IAM authentication on your Aurora cluster, create a database role that uses it, generate tokens, and connect without a password.

---

## Before You Start

Read `concepts/02-iam-for-databases.md` first.

You need:
- A running Aurora PostgreSQL cluster
- psql installed
- AWS CLI configured with credentials that have IAM and RDS permissions
- Your Aurora cluster identifier and endpoint

Set these variables:

```bash
export CLUSTER_ID="devops-lab-cluster"
export CLUSTER_ENDPOINT=$(aws rds describe-db-clusters \
  --db-cluster-identifier $CLUSTER_ID \
  --query 'DBClusters[0].Endpoint' \
  --output text \
  --region us-east-1)
export CLUSTER_PORT="5432"
export MASTER_DB="postgres"
export MASTER_USER="postgres"
export AWS_REGION="us-east-1"
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
```

Verify the account ID was captured:

```bash
echo $AWS_ACCOUNT_ID
```

Expected output (yours will differ):

```
123456789012
```

---

## Step 1 - Enable IAM Authentication on Your Aurora Cluster

### Using the AWS Console

1. Open the AWS Console in your browser
2. Search for **RDS** in the top search bar
3. Click **Databases** in the left sidebar
4. Click your cluster name (`devops-lab-cluster`)
5. Click the **Modify** button (top right)
6. Scroll down to **Database authentication**
7. Select **Password and IAM database authentication**
8. Scroll to the bottom and click **Continue**
9. Under "Scheduling of modifications", select **Apply immediately**
10. Click **Modify cluster**

The modification takes 1-2 minutes.

### Using the AWS CLI

```bash
aws rds modify-db-cluster \
  --db-cluster-identifier $CLUSTER_ID \
  --enable-iam-database-authentication \
  --apply-immediately \
  --region $AWS_REGION
```

`--enable-iam-database-authentication` turns on IAM auth support on the cluster.
`--apply-immediately` makes the change take effect now.

Expected output (yours will differ):

```json
{
    "DBCluster": {
        "DBClusterIdentifier": "devops-lab-cluster",
        "IAMDatabaseAuthenticationEnabled": true,
        "Status": "available",
        ...
    }
}
```

Verify IAM auth is now enabled:

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier $CLUSTER_ID \
  --query 'DBClusters[0].IAMDatabaseAuthenticationEnabled' \
  --region $AWS_REGION
```

Expected output:

```
true
```

---

## Step 2 - Create a PostgreSQL Role for IAM Auth

Connect to your Aurora cluster as the master user:

```bash
psql \
  --host=$CLUSTER_ENDPOINT \
  --port=$CLUSTER_PORT \
  --username=$MASTER_USER \
  --dbname=$MASTER_DB
```

Enter your master password when prompted.

Create the IAM database user. This is a PostgreSQL role with the `rds_iam` attribute:

```sql
CREATE ROLE iam_user WITH LOGIN;
```

`CREATE ROLE` creates the role.
`WITH LOGIN` allows it to connect.
Notice there is no `PASSWORD` clause. IAM users do not use passwords.

```sql
GRANT rds_iam TO iam_user;
```

This grants the `rds_iam` role to our user. Aurora checks for this role membership when validating an IAM token.

Verify the role was created:

```sql
SELECT rolname, rolcanlogin
FROM pg_roles
WHERE rolname = 'iam_user';
```

Expected output:

```
 rolname  | rolcanlogin
----------+-------------
 iam_user | t
```

Check that it has the rds_iam role:

```sql
SELECT r.rolname as user, m.rolname as member_of
FROM pg_auth_members am
JOIN pg_roles r ON r.oid = am.member
JOIN pg_roles m ON m.oid = am.roleid
WHERE r.rolname = 'iam_user';
```

Expected output:

```
  user   | member_of
---------+-----------
 iam_user | rds_iam
```

Exit psql:

```sql
\q
```

---

## Step 3 - Create an IAM Policy

The IAM identity that will connect to Aurora needs a policy that allows the `rds-db:connect` action.

First, get the DB cluster resource ID. For Aurora, this starts with `cluster-`:

```bash
export DB_RESOURCE_ID=$(aws rds describe-db-clusters \
  --db-cluster-identifier $CLUSTER_ID \
  --query 'DBClusters[0].DbClusterResourceId' \
  --output text \
  --region $AWS_REGION)

echo "DB Resource ID: $DB_RESOURCE_ID"
```

Expected output (yours will differ):

```
DB Resource ID: cluster-ABCDEFGHIJ1234567890
```

Create the policy document with your real values:

```bash
cat > /tmp/aurora-iam-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["rds-db:connect"],
      "Resource": "arn:aws:rds-db:${AWS_REGION}:${AWS_ACCOUNT_ID}:dbuser:${DB_RESOURCE_ID}/iam_user"
    }
  ]
}
EOF
```

This policy says: allow the `rds-db:connect` action on the specific Aurora cluster and specific database username `iam_user`.

Create the IAM policy:

```bash
aws iam create-policy \
  --policy-name AuroraIAMAuthPolicy \
  --policy-document file:///tmp/aurora-iam-policy.json
```

`--policy-name` gives the policy a name.
`--policy-document` points to the JSON file you just created.

Expected output (yours will differ):

```json
{
    "Policy": {
        "PolicyName": "AuroraIAMAuthPolicy",
        "PolicyId": "ANPAIOSFODNN7EXAMPLE",
        "Arn": "arn:aws:iam::123456789012:policy/AuroraIAMAuthPolicy",
        ...
    }
}
```

Attach this policy to your current IAM user or role:

```bash
export MY_IAM_USER=$(aws sts get-caller-identity --query Arn --output text | cut -d/ -f2)

echo "My IAM user: $MY_IAM_USER"
```

```bash
aws iam attach-user-policy \
  --user-name $MY_IAM_USER \
  --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/AuroraIAMAuthPolicy"
```

`--user-name` is your IAM username.
`--policy-arn` is the ARN of the policy you just created.

> **Concept:** If you are running this from an EC2 instance, attach the policy to the EC2 instance's IAM role instead, using `aws iam attach-role-policy`. Using an instance role means no credentials are stored anywhere on the instance.

---

## Step 4 - Download the RDS Certificate Bundle

IAM auth connections must use SSL. Download the certificate bundle if you have not already:

```bash
curl -o ~/rds-ca-bundle.pem \
  https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem
```

`curl` downloads the file from the URL.
`-o` specifies where to save it.

Verify the download:

```bash
wc -l ~/rds-ca-bundle.pem
```

Expected output (yours will differ):

```
4599 /Users/you/rds-ca-bundle.pem
```

---

## Step 5 - Generate an IAM Auth Token

Generate the auth token. This token replaces a password:

```bash
export PGPASSWORD=$(aws rds generate-db-auth-token \
  --hostname $CLUSTER_ENDPOINT \
  --port $CLUSTER_PORT \
  --region $AWS_REGION \
  --username iam_user)
```

`generate-db-auth-token` calls the RDS API to create a signed token.
`--hostname` is your Aurora cluster endpoint.
`--username` must match the PostgreSQL role name exactly.

We store the token in `$PGPASSWORD` because psql reads this environment variable for the password.

Inspect the token (it is long):

```bash
echo $PGPASSWORD | cut -c1-100
echo "... (token continues)"
```

Expected output (yours will differ):

```
devops-lab-cluster.cluster-abc123.us-east-1.rds.amazonaws.com:5432/?Action=connect&DBUser=iam_user&X
... (token continues)
```

The token is a signed URL. It encodes who you are, when it was generated, and when it expires (15 minutes from now).

---

## Step 6 - Connect Using the IAM Token

Connect to Aurora using the token as the password:

```bash
psql \
  "host=$CLUSTER_ENDPOINT \
   port=$CLUSTER_PORT \
   dbname=$MASTER_DB \
   user=iam_user \
   sslmode=verify-full \
   sslrootcert=$HOME/rds-ca-bundle.pem"
```

`sslmode=verify-full` is required - IAM auth only works over SSL.
`sslrootcert` points to the CA bundle you downloaded.
psql will read the password from the `$PGPASSWORD` environment variable automatically.

Expected output (yours will differ):

```
psql (16.6)
SSL connection (protocol: TLSv1.3, cipher: TLS_AES_256_GCM_SHA384, bits: 256, compression: off)
Type "help" for help.

postgres=>
```

Verify you are connected as `iam_user`:

```sql
SELECT current_user, session_user;
```

Expected output:

```
 current_user | session_user
--------------+--------------
 iam_user     | iam_user
```

Exit psql:

```sql
\q
```

---

## Step 7 - Test Token Expiration

The token expires after 15 minutes. Let's understand what happens.

Generate a token and save the timestamp:

```bash
echo "Token generated at: $(date)"

export PGPASSWORD=$(aws rds generate-db-auth-token \
  --hostname $CLUSTER_ENDPOINT \
  --port $CLUSTER_PORT \
  --region $AWS_REGION \
  --username iam_user)
```

After the token expires (15 minutes later), a connection attempt would fail:

```
psql: error: connection to server at "..." failed:
FATAL:  PAM authentication failed for user "iam_user"
```

This is expected behavior. The fix is always to generate a new token.

> **Note:** For this lab, you do not need to wait the full 15 minutes. The key point is that tokens expire and your application must generate a fresh one before connecting.

---

## Step 8 - Application Pattern

Here is how a real application handles IAM tokens. This is for reference - you do not need to run this in the lab.

**Python (boto3):**

```python
import boto3
import psycopg2

def get_db_connection():
    """
    Get a fresh IAM auth token and connect to Aurora.
    Always generate a new token - do not cache it.
    """
    rds_client = boto3.client("rds", region_name="us-east-1")

    token = rds_client.generate_db_auth_token(
        DBHostname="devops-lab-cluster.cluster-abc123.us-east-1.rds.amazonaws.com",
        Port=5432,
        DBUsername="iam_user",
        Region="us-east-1"
    )

    conn = psycopg2.connect(
        host="devops-lab-cluster.cluster-abc123.us-east-1.rds.amazonaws.com",
        port=5432,
        database="postgres",
        user="iam_user",
        password=token,
        sslmode="verify-full",
        sslrootcert="/etc/ssl/certs/rds-ca-bundle.pem"
    )

    return conn
```

The key rule: generate a new token every time you create a connection. Do not reuse tokens.

---

## Step 9 - Console Verification

Verify IAM auth is enabled in the Console:

1. Open the AWS Console
2. Go to **RDS > Databases**
3. Click your cluster (`devops-lab-cluster`)
4. Click the **Configuration** tab
5. Look for **IAM DB authentication: Enabled**

---

## What You Built

- Enabled IAM database authentication on your Aurora cluster
- Created a PostgreSQL role (`iam_user`) with the `rds_iam` attribute
- Created an IAM policy allowing `rds-db:connect` on the cluster resource ID
- Generated an auth token with `aws rds generate-db-auth-token`
- Connected to Aurora using the token instead of a password

---

## Troubleshooting

| Error | Cause | Fix |
|-------|-------|-----|
| `PAM authentication failed` | Token expired or IAM policy missing | Generate new token, check IAM policy |
| `FATAL: IAM auth not enabled` | IAM auth not turned on at cluster level | Run the modify command in Step 1 |
| `SSL required` | Connecting without SSL | Add `sslmode=require` to connection string |
| `pg_hba.conf rejects connection` | Role not granted rds_iam | Run `GRANT rds_iam TO iam_user` in psql |

---

## Clean Up (Optional)

Remove the IAM user and policy:

```sql
-- In psql as master user
DROP ROLE iam_user;
```

```bash
aws iam detach-user-policy \
  --user-name $MY_IAM_USER \
  --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/AuroraIAMAuthPolicy"

aws iam delete-policy \
  --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/AuroraIAMAuthPolicy"
```

---

## Key Facts to Remember

1. Tokens expire after 15 minutes - generate fresh ones
2. The PostgreSQL role must have `rds_iam` granted
3. IAM auth requires SSL - it does not work without it
4. The IAM policy resource ARN uses the DB cluster resource ID (not the cluster identifier)
5. EC2 instance roles are the best way to use IAM auth - no stored credentials anywhere
