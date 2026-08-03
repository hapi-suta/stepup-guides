# Tier 2 Security - Core Concepts

Read this before starting the BUILD guides. Each section maps to one BUILD guide.

---

## T2.1 PostgreSQL Roles on RDS

### What is a role?

In PostgreSQL, a **role** is an identity. A role can log in (making it a user), own objects, and hold privileges. Roles can also contain other roles, making them act like groups.

On a normal PostgreSQL server you might have a `postgres` superuser who can do anything. On RDS, AWS removes that. You get a master user with the `rds_superuser` role instead.

### The RDS role hierarchy

```
                    ┌─────────────────────┐
                    │    rds_superuser     │
                    │  (granted by AWS)    │
                    └──────────┬──────────┘
                               │ has these privileges
                    ┌──────────▼──────────┐
                    │  - REPLICATION      │
                    │  - BYPASSRLS        │
                    │  - CREATE ROLE      │
                    │  - CREATE DB        │
                    │  - pg_monitor       │
                    │  - rds_replication  │
                    └──────────┬──────────┘
                               │ granted to
                    ┌──────────▼──────────┐
                    │    master user       │
                    │  (you created this)  │
                    └──────────┬──────────┘
                               │ creates
              ┌────────────────┼────────────────┐
              │                │                │
   ┌──────────▼──────┐ ┌───────▼──────┐ ┌──────▼──────────┐
   │   app_user       │ │  readonly    │ │   admin_user     │
   │ (INSERT, UPDATE, │ │  (SELECT     │ │ (owns schemas,   │
   │  DELETE, SELECT) │ │   only)      │ │  manages roles)  │
   └──────────────────┘ └──────────────┘ └─────────────────┘
```

### What rds_superuser cannot do

RDS blocks some superuser actions for safety:

- Cannot access OS files with `COPY ... TO/FROM file`
- Cannot load extensions not pre-approved by AWS
- Cannot change `max_connections` directly (use parameter groups)
- Cannot view other sessions' data from pg_stat_activity by default

### Least privilege

**Least privilege** means each role gets only the permissions it needs - nothing more.

An app that only reads data should not have INSERT or DELETE. A reporting user should not be able to drop tables. A migration script user might need schema-level create, but only during deploys.

```
BAD: GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO app_user;

GOOD: GRANT SELECT, INSERT, UPDATE, DELETE ON specific_table TO app_user;
```

### Common role patterns

| Role | Purpose | Typical grants |
|------|---------|----------------|
| app_user | Application connections | SELECT, INSERT, UPDATE, DELETE on app tables |
| readonly_user | Reports, BI tools | SELECT on all tables in schema |
| migration_user | Schema changes at deploy time | CREATE, ALTER (used briefly, then revoked) |
| admin_user | DBA tasks | rds_superuser (given to trusted humans only) |

---

## T2.2 IAM Database Authentication

### The problem with passwords

Passwords get stored in config files. Config files get checked into git. Git repos get made public by accident. Passwords get shared over Slack. Passwords never rotate.

IAM database authentication replaces the password with a **short-lived token** that expires after 15 minutes.

### How it works

```
  Your Application or EC2 Instance
  ────────────────────────────────

  1. App calls AWS API:
     aws rds generate-db-auth-token
               │
               ▼
  ┌────────────────────────┐
  │     AWS IAM / STS      │
  │                        │
  │  Checks: does this     │
  │  IAM identity have     │
  │  rds-db:connect        │
  │  permission?           │
  └────────────┬───────────┘
               │
               │ Returns a signed token (valid 15 minutes)
               ▼
  2. App connects to RDS:
     psql --password=[TOKEN]
               │
               ▼
  ┌────────────────────────┐
  │        RDS             │
  │                        │
  │  Validates token with  │
  │  AWS IAM service       │
  │  (not a real password) │
  │                        │
  │  Role must exist in    │
  │  PostgreSQL with       │
  │  rds_iam attribute     │
  └────────────────────────┘
```

### What you need (three parts)

1. **IAM policy** - allows the IAM identity (user or role) to call `rds-db:connect`
2. **PostgreSQL role** - created with `IDENTIFIED WITH AWSAuthenticationPlugin` (MySQL) or granted `rds_iam` (PostgreSQL)
3. **Token** - generated fresh before each connection

### Token expiration

The token is valid for 15 minutes. Your application must generate a new one before connecting. This is not a problem in practice because:

- Connection pools generate the token at startup
- Lambda functions generate a new token each cold start
- Long-running apps refresh the token before it expires

### When to use IAM auth

Good fit:
- EC2 instances running your app (use an IAM instance role - no credentials stored anywhere)
- Lambda functions (same reason)
- ECS tasks with task roles

Not ideal:
- Tools like pgAdmin or DBeaver (harder to configure, token expires mid-session)
- Scripts that run infrequently and don't want the overhead

---

## T2.3 SSL/TLS Connections

### What SSL/TLS does

Without SSL, data between your app and the database travels as plain text. Anyone who can intercept the network packet can read your SQL queries and results.

SSL/TLS encrypts the connection so intercepted packets are unreadable.

```
  WITHOUT SSL:

  App ──── "SELECT * FROM users WHERE password='secret123'" ──── RDS
                    (readable by anyone on the network)

  WITH SSL:

  App ──── [encrypted bytes: 3f8a2c...] ──── RDS
                    (unreadable without the key)
```

### sslmode options

PostgreSQL has several SSL modes. Know these four:

| sslmode | What it does | Use case |
|---------|-------------|----------|
| disable | No SSL at all | Never use in production |
| require | Uses SSL but does not verify the server certificate | Basic encryption, no MITM protection |
| verify-ca | Verifies the certificate is signed by a trusted CA | Better - confirms you are talking to a real RDS server |
| verify-full | Verifies cert AND hostname matches | Best - prevents man-in-the-middle attacks |

### The RDS CA certificate bundle

AWS signs RDS certificates with its own Certificate Authority (CA). You need to download the CA bundle and tell psql to use it.

```bash
# Download the bundle
curl -o rds-ca-bundle.pem \
  https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem
```

Then connect with:

```bash
psql "sslmode=verify-full sslrootcert=rds-ca-bundle.pem host=..."
```

### rds.force_ssl

RDS has a parameter called `rds.force_ssl`. When set to `1`, the server rejects any connection that does not use SSL. This is the server-side enforcement.

Setting it in the parameter group is more reliable than trusting every application to set sslmode correctly.

### Certificate rotation

AWS periodically rotates the CA that signs RDS certificates. When this happens:

1. AWS publishes a new CA
2. You download the new bundle
3. You update your application to use the new bundle
4. You test the connection
5. AWS retires the old CA

The global bundle (`global-bundle.pem`) includes both old and new CAs, so updating to it early prevents outages during rotation.

---

## T2.4 Encryption at Rest

### What it means

Encryption at rest means the data files on the storage volume are encrypted. If someone stole the physical disk, they could not read your data.

RDS uses **AES-256** encryption. The encryption/decryption happens transparently - your queries work the same way, you just get the security benefit.

### What gets encrypted

When you enable encryption at rest on an RDS instance, ALL of these are encrypted:

```
  ┌──────────────────────────────────────────┐
  │           Encrypted with KMS             │
  │                                          │
  │  ┌─────────────┐   ┌──────────────────┐  │
  │  │  Data files  │   │  Transaction     │  │
  │  │  (tables,    │   │  logs (WAL)      │  │
  │  │   indexes)   │   │                  │  │
  │  └─────────────┘   └──────────────────┘  │
  │                                          │
  │  ┌─────────────┐   ┌──────────────────┐  │
  │  │  Automated  │   │  Read replica    │  │
  │  │  backups    │   │  storage         │  │
  │  └─────────────┘   └──────────────────┘  │
  └──────────────────────────────────────────┘
```

### AWS managed key vs customer managed key

| Type | What AWS does | What you control | Cost |
|------|--------------|-----------------|------|
| AWS managed key | Rotates automatically every year | Nothing - AWS manages it | Free |
| Customer managed key (CMK) | You manage rotation | Key policy, who can use it, rotation schedule | $1/month/key |

Use a customer managed key when:
- You need to audit who used the key (KMS CloudTrail logs)
- You need to disable/delete the key to instantly revoke access
- Compliance requires you to manage your own keys

### The unencrypted-to-encrypted problem

You **cannot enable encryption on an existing unencrypted instance**. There is no toggle.

The workaround is the snapshot method:

```
  Unencrypted RDS Instance
          │
          │ 1. Take a snapshot
          ▼
  Unencrypted Snapshot
          │
          │ 2. Copy snapshot with encryption enabled
          ▼
  Encrypted Snapshot
          │
          │ 3. Restore from encrypted snapshot
          ▼
  New Encrypted RDS Instance
          │
          │ 4. Update connection strings, verify, delete old instance
          ▼
  Done
```

This requires downtime unless you redirect traffic carefully.

---

## T2.5 Secrets Manager

### The problem

Most teams store database credentials in:
- `.env` files
- Config files checked into git
- Hardcoded in application code
- Spreadsheets shared over email

Any of these can lead to a breach. And when a password needs to change, you have to find and update every place it is stored.

### What Secrets Manager does

Secrets Manager stores your credentials in an encrypted vault. Applications fetch the secret at runtime using the AWS API. No credentials in config files.

```
  ┌─────────────────────────────────────────────────┐
  │                Your Application                  │
  │                                                  │
  │  At startup:                                     │
  │  secret = get_secret("prod/myapp/db")            │
  │  db_password = secret["password"]                │
  └─────────────────┬───────────────────────────────┘
                    │ API call (over HTTPS)
                    ▼
  ┌─────────────────────────────────────────────────┐
  │              AWS Secrets Manager                 │
  │                                                  │
  │  Encrypted at rest with KMS                      │
  │  Access controlled by IAM                        │
  │  Full audit trail in CloudTrail                  │
  └─────────────────┬───────────────────────────────┘
                    │ Returns JSON
                    ▼
  ┌─────────────────────────────────────────────────┐
  │   { "username": "app_user",                      │
  │     "password": "Ab3$kP...",                     │
  │     "host": "mydb.cluster.us-east-1.rds...",     │
  │     "port": 5432,                                │
  │     "dbname": "production" }                     │
  └─────────────────────────────────────────────────┘
```

### Managed rotation

Secrets Manager can rotate the password automatically on a schedule you set. When rotation runs:

1. Secrets Manager generates a new password
2. It calls a Lambda function (AWS provides one for RDS)
3. The Lambda changes the password in the database
4. The Lambda updates the secret in Secrets Manager
5. Your application fetches the new secret on the next startup or cache refresh

Your application never knows the password changed. It just fetches the current secret.

### Rotation strategies

| Strategy | How it works | Downtime? |
|----------|-------------|-----------|
| Single user | Rotates the password for one user | Brief (seconds) |
| Alternating users | Two users, alternates between them | None |

For zero-downtime rotation, use the alternating users strategy with a connection pool that can handle brief auth failures.

---

## T2.6 Network Isolation - Kerberos, DNS, and PrivateLink

### The network security problem

Even with SSL and strong passwords, a database reachable from the public internet is at risk. Attackers will find the port and attempt brute-force logins.

The safest database is one that cannot be reached at all from outside your network.

### VPC peering vs PrivateLink

```
  VPC PEERING:

  ┌────────────────┐         ┌────────────────┐
  │   App VPC      │         │   DB VPC       │
  │                │◄───────►│                │
  │  10.0.0.0/16   │ peering │  10.1.0.0/16   │
  │                │  (all   │                │
  │                │ traffic)│                │
  └────────────────┘         └────────────────┘

  Both VPCs can see each other's resources.
  CIDR ranges must not overlap.

  ─────────────────────────────────────────────────

  PRIVATELINK:

  ┌────────────────┐         ┌────────────────┐
  │   App VPC      │         │   DB VPC       │
  │                │         │                │
  │  ┌──────────┐  │         │  ┌──────────┐  │
  │  │  VPC     │  │──────── │  │ Endpoint │  │
  │  │ Endpoint │  │ one-way │  │ Service  │  │
  │  └──────────┘  │ tunnel  │  └──────────┘  │
  └────────────────┘         └────────────────┘

  App VPC can only reach the specific service, not the whole DB VPC.
  More secure. CIDRs can overlap.
```

### When to use each

| Situation | Use |
|-----------|-----|
| Both VPCs are yours, you need broad access | VPC peering |
| Exposing a database to a customer's VPC | PrivateLink |
| Multi-tenant SaaS, strict isolation | PrivateLink |
| CIDRs overlap between VPCs | PrivateLink (peering won't work) |

### Custom DNS with Route53

RDS endpoints look like this:

```
mydb.ch87abc123de.us-east-1.rds.amazonaws.com
```

That is hard to remember and hard to change when you swap the instance. Use Route53 to create a friendly CNAME:

```
db.internal.mycompany.com  →  mydb.ch87abc123de.us-east-1.rds.amazonaws.com
```

Now your applications connect to `db.internal.mycompany.com`. When you replace the RDS instance, you update one DNS record instead of changing 20 config files.

### Kerberos authentication

Kerberos is an enterprise authentication protocol. It is used in companies that have Active Directory (Windows domains). RDS supports Kerberos so that Windows domain users can log into the database with their Windows credentials.

This is relevant for:
- Large enterprises with existing Active Directory infrastructure
- Companies that require centralized identity management
- Environments where every login must tie back to a named person (for auditing)

For most teams starting out, IAM auth is simpler and more appropriate than Kerberos.

### Security groups - the last line

Even with all the above, security groups control what can reach port 5432:

```
  Good security group rule for RDS:

  Inbound:
  Port 5432, TCP, Source: sg-0abc123 (app server security group)

  NOT:
  Port 5432, TCP, Source: 0.0.0.0/0  ← NEVER do this
```

Always reference the app server's security group as the source, not an IP range. IP ranges change. Security group membership is managed.

---

## Summary - The Security Layers

Think of RDS security as layers. Each layer stops a different kind of attacker:

```
  Attack from the internet
         │
         ▼
  ┌─────────────────────────────────────┐
  │  Layer 1: Network isolation          │
  │  VPC + private subnets + no public  │
  │  IP + security groups               │
  └──────────────────┬──────────────────┘
                     │ (gets through)
                     ▼
  ┌─────────────────────────────────────┐
  │  Layer 2: Authentication             │
  │  IAM auth or strong passwords in    │
  │  Secrets Manager, not hardcoded     │
  └──────────────────┬──────────────────┘
                     │ (gets through)
                     ▼
  ┌─────────────────────────────────────┐
  │  Layer 3: Encryption in transit      │
  │  SSL/TLS with verify-full           │
  └──────────────────┬──────────────────┘
                     │ (gets through)
                     ▼
  ┌─────────────────────────────────────┐
  │  Layer 4: Authorization              │
  │  Least-privilege roles, no GRANT    │
  │  ALL to app users                   │
  └──────────────────┬──────────────────┘
                     │ (gets through)
                     ▼
  ┌─────────────────────────────────────┐
  │  Layer 5: Encryption at rest         │
  │  KMS encryption - stolen disk is    │
  │  unreadable                         │
  └─────────────────────────────────────┘
```

No single layer is enough. All five together give you defense in depth.
