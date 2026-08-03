# Concepts - Database Security Layers

Read this before starting the BUILD guides. It covers the four layers of Aurora database security and how they work together.

---

## Why Security Has Layers

No single security measure is enough. If you only use a password but no encryption, someone on the network can steal the password. If you only encrypt the connection but give the app too many permissions, a compromised app can delete everything.

Security layers work like a series of locked doors. Each layer stops a different type of attacker. Even if one layer fails, the others still protect you.

```
  Attack from the internet
         |
         v
  +-------------------------------------+
  |  Layer 1: Network                   |
  |  VPC, private subnets, security     |
  |  groups, NACLs                      |
  +------------------+------------------+
                     | (gets through)
                     v
  +-------------------------------------+
  |  Layer 2: Authentication            |
  |  Password auth, IAM auth, or       |
  |  certificate-based auth             |
  +------------------+------------------+
                     | (gets through)
                     v
  +-------------------------------------+
  |  Layer 3: Authorization             |
  |  PostgreSQL roles, GRANT, REVOKE,   |
  |  least privilege                    |
  +------------------+------------------+
                     | (gets through)
                     v
  +-------------------------------------+
  |  Layer 4: Encryption                |
  |  In transit (SSL/TLS) and           |
  |  at rest (KMS)                      |
  +-------------------------------------+
```

All four layers together give you defense in depth. Let's look at each one.

---

---

## Layer 1 - Network Security

Network security controls who can even reach your database over the network. If an attacker cannot send a packet to port 5432 (PostgreSQL's default port), they cannot even attempt to log in.

### VPC - Your Private Network

A **VPC** (Virtual Private Cloud) is your own isolated network inside AWS. Think of it as a building with walls. Nothing from outside can get in unless you open a door.

Your Aurora cluster runs inside a VPC. The cluster endpoint has a private IP address that is only reachable from inside the VPC.

### Private Subnets

A subnet is a section of your VPC. Subnets come in two types:

- **Public subnet** - has a route to the internet through an Internet Gateway
- **Private subnet** - has no route to the internet

Your Aurora cluster should always be in a **private subnet**. This means no one on the internet can reach it directly. Not even if they know the endpoint address.

```
  +------------------------------------------+
  |                 VPC                       |
  |                                           |
  |  +------------------+  +---------------+  |
  |  | Public Subnet    |  | Private       |  |
  |  |                  |  | Subnet        |  |
  |  | Bastion host     |  | Aurora        |  |
  |  | Load balancer    |  | cluster       |  |
  |  +--------+---------+  +-------+-------+  |
  |           |                     |          |
  |           +------> can reach -->+          |
  +------------------------------------------+
              |
       Internet Gateway
              |
         Internet
```

The bastion host (or your application server) in the public subnet can reach the Aurora cluster in the private subnet. The internet cannot.

### DB Subnet Groups

Aurora requires a **DB subnet group** - a collection of at least two private subnets in different Availability Zones. This is how Aurora knows where to place instances for high availability.

When you create an Aurora cluster, you must specify a DB subnet group. The subnets in this group must be private subnets - never public.

### Security Groups

A **security group** acts as a firewall around your Aurora cluster. It controls which IP addresses or other resources can send traffic to your cluster on which ports.

Good security group rule for Aurora:

```
  Inbound rule:
  Type:        PostgreSQL
  Protocol:    TCP
  Port:        5432
  Source:      sg-0abc123def456 (your app server security group)
```

This rule says: only allow traffic on port 5432 from resources that belong to the application server security group.

Bad security group rule (never do this):

```
  Inbound rule:
  Type:        PostgreSQL
  Protocol:    TCP
  Port:        5432
  Source:      0.0.0.0/0   <-- This means EVERYONE on the internet
```

Always reference another security group as the source, not an IP range. IP addresses change. Security group membership is managed and auditable.

### NACLs (Network Access Control Lists)

A **NACL** is a second layer of network filtering at the subnet level. It works differently from security groups:

| Feature | Security Group | NACL |
|---------|---------------|------|
| Level | Instance/cluster | Subnet |
| Default | Deny all inbound | Allow all |
| Stateful? | Yes - return traffic allowed automatically | No - must allow both inbound and outbound |
| Rules | Allow rules only | Allow and deny rules |
| Evaluation | All rules evaluated | Rules evaluated in order by number |

For most Aurora setups, the default NACL (allow all) is fine because the security group handles the filtering. But some compliance frameworks require explicit NACL rules too.

A typical NACL for a database subnet:

```
  Inbound rules:
  Rule 100: Allow TCP 5432 from 10.0.0.0/16 (your VPC CIDR)
  Rule 200: Allow TCP 1024-65535 from 10.0.0.0/16 (return traffic)
  Rule *:   Deny all (default)

  Outbound rules:
  Rule 100: Allow TCP 1024-65535 to 10.0.0.0/16 (return traffic)
  Rule *:   Deny all (default)
```

### Public Accessibility

When you create an Aurora cluster, AWS asks if you want the instances to be **publicly accessible**. The answer is almost always **No**.

Setting this to Yes gives the Aurora instances public IP addresses, which means the internet can try to reach them. Even with security groups blocking most traffic, this is unnecessary exposure.

---

---

## Layer 2 - Authentication

Authentication answers the question: **who are you?**

Aurora PostgreSQL supports three authentication methods. Each has different strengths.

### Password Authentication

This is the simplest method. You create a PostgreSQL role with a password, and the application provides that password when connecting.

```
  CREATE ROLE app_user WITH LOGIN PASSWORD 'StrongPass1!';
```

The password is stored as a hash inside the database. When someone connects, PostgreSQL hashes the provided password and compares it to the stored hash.

**Strengths:**
- Simple to set up
- Works with every PostgreSQL tool and driver
- No AWS-specific dependencies

**Weaknesses:**
- Passwords get stored in config files, which get committed to git
- Passwords get shared over Slack or email
- Passwords never rotate unless someone manually changes them
- No audit trail of who generated or used the password

### IAM Database Authentication

IAM auth replaces the password with a **short-lived token** that expires after 15 minutes.

```
  1. Application calls AWS API:
     aws rds generate-db-auth-token

  2. AWS returns a signed token (valid 15 minutes)

  3. Application connects to Aurora:
     psql --password=[TOKEN]

  4. Aurora validates the token with AWS IAM
```

**Strengths:**
- No password to store or rotate
- Token expires in 15 minutes - limited blast radius if stolen
- Ties into existing IAM policies and audit trails (CloudTrail)
- Works with EC2 instance roles - zero stored credentials

**Weaknesses:**
- Harder to set up than password auth
- Requires AWS CLI or SDK available to the connecting application
- GUI tools like DBeaver or pgAdmin struggle with token expiration
- Adds a dependency on AWS IAM availability

### Certificate-Based Authentication

Certificate auth uses SSL/TLS client certificates to verify the identity of the connecting application. The client presents a certificate signed by a trusted Certificate Authority, and the database verifies it.

On Aurora, this is less commonly used than password or IAM auth. The standard RDS certificate bundle handles server certificate verification (proving the server is who it says it is), but client certificate verification (proving the client is who it says it is) requires additional configuration that RDS does not fully expose.

For most Aurora deployments, IAM auth is the preferred passwordless authentication method.

---

---

## Layer 3 - Authorization

Authentication tells you who someone is. Authorization tells you what they can do.

### The PostgreSQL GRANT System

PostgreSQL uses a role-based access control system. Every permission is controlled by **GRANT** and **REVOKE** statements.

The hierarchy:

```
  Database level:
    GRANT CONNECT ON DATABASE mydb TO app_user;

  Schema level:
    GRANT USAGE ON SCHEMA app TO app_user;

  Table level:
    GRANT SELECT, INSERT, UPDATE, DELETE ON app.orders TO app_user;

  Column level:
    GRANT SELECT (name, email) ON app.users TO reporting;
```

Each level is independent. A role needs CONNECT to reach the database, USAGE to see inside a schema, and specific table grants to read or write data. Without all three, access is blocked.

### Common Privilege Types

| Privilege | What it allows | Who needs it |
|-----------|---------------|-------------|
| CONNECT | Connect to the database | Everyone |
| USAGE | See objects inside a schema | Everyone who accesses the schema |
| SELECT | Read rows from a table | Reporting, applications, analysts |
| INSERT | Add new rows | Applications that write data |
| UPDATE | Change existing rows | Applications that modify data |
| DELETE | Remove rows | Applications that delete data (use carefully) |
| TRUNCATE | Delete all rows at once | Almost nobody - do not grant this to apps |
| CREATE | Create new objects in a schema | Migration users only |
| ALL | Everything above | Almost never the right answer |

### The rds_superuser Role

On a self-managed PostgreSQL server, the `postgres` user is a true superuser - it can do anything. On Aurora, AWS removes true superuser access and gives you `rds_superuser` instead.

What `rds_superuser` can do:
- Create and manage roles
- Create databases
- Grant and revoke permissions
- Access pg_monitor views
- Set up replication

What `rds_superuser` cannot do:
- Access OS-level files
- Load arbitrary extensions
- Change parameters that require a restart (use parameter groups instead)
- Bypass RDS internal controls

### Least Privilege

**Least privilege** means each role gets only the permissions it needs - nothing more.

```
  BAD:
  GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO app_user;

  GOOD:
  GRANT SELECT, INSERT, UPDATE ON app.orders TO app_user;
  GRANT SELECT ON app.products TO app_user;
```

The "bad" example gives the application role permission to DELETE, TRUNCATE, and modify tables it may never touch. If the application gets compromised, the attacker inherits all those permissions.

The "good" example limits damage. Even if the app is compromised, the attacker can only read and write to the specific tables the app uses.

### Common Role Patterns

| Role | Purpose | Typical Grants |
|------|---------|----------------|
| app_user | Application connections | SELECT, INSERT, UPDATE, DELETE on app tables |
| readonly_user | Reports, BI tools | SELECT on all tables in schema |
| migration_user | Schema changes at deploy time | CREATE, ALTER (used briefly, then revoked) |
| admin_user | DBA tasks | rds_superuser (given to trusted humans only) |

### Group Roles

Instead of granting permissions to individual users, create a group role and add users to it:

```
  CREATE ROLE app_readwrite NOLOGIN;
  GRANT SELECT, INSERT, UPDATE, DELETE ON app.orders TO app_readwrite;

  CREATE ROLE alice WITH LOGIN PASSWORD '...';
  GRANT app_readwrite TO alice;

  CREATE ROLE bob WITH LOGIN PASSWORD '...';
  GRANT app_readwrite TO bob;
```

Now if you need to revoke Bob's access, you run one command:

```
  REVOKE app_readwrite FROM bob;
```

You do not need to touch any table-level grants. The group handles it.

### Row-Level Security (RLS)

RLS lets you restrict which rows a user can see, not just which tables. This is useful for multi-tenant applications where all customers share the same table.

```
  ALTER TABLE orders ENABLE ROW LEVEL SECURITY;

  CREATE POLICY tenant_isolation ON orders
    USING (tenant_id = current_setting('app.tenant_id')::int);
```

With this policy, a user can only see rows where `tenant_id` matches the session variable. Even if they run `SELECT * FROM orders`, they only get their own rows.

---

---

## Layer 4 - Encryption

Encryption protects your data from being read by unauthorized parties, both while it travels over the network and while it sits on disk.

### Encryption in Transit (SSL/TLS)

Without SSL, data between your application and Aurora travels as plain text. Anyone who can intercept network traffic can read your SQL queries and results.

```
  WITHOUT SSL:

  App ---- "SELECT * FROM users WHERE ssn='123-45-6789'" ---- Aurora
                    (readable by anyone on the network)

  WITH SSL:

  App ---- [encrypted bytes: 3f8a2c...] ---- Aurora
                    (unreadable without the key)
```

Aurora supports TLS 1.2 and TLS 1.3. You control the SSL mode from the client side:

| sslmode | Encrypts? | Verifies cert? | Verifies hostname? | Use when |
|---------|-----------|----------------|-------------------|----------|
| disable | No | No | No | Never in production |
| require | Yes | No | No | Basic encryption only |
| verify-ca | Yes | Yes | No | Certificate verified, hostname not |
| verify-full | Yes | Yes | Yes | Always - production standard |

Always use `sslmode=verify-full` in production. This ensures your connection is encrypted AND you are talking to a real Aurora server (not an impersonator).

### The RDS Certificate Bundle

AWS signs Aurora server certificates with its own Certificate Authority (CA). You need the CA bundle to verify the server's identity.

Download it from:

```
https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem
```

Use it in your connection string:

```
psql "sslmode=verify-full sslrootcert=global-bundle.pem host=..."
```

### Enforcing SSL Server-Side

Even if your applications use SSL, someone could connect without it. The `rds.force_ssl` parameter (set to `1`) makes the server reject any unencrypted connection.

This is a server-side enforcement - it does not rely on the client choosing to use SSL. Set it in the cluster parameter group and every connection must use SSL.

### Encryption at Rest (KMS)

Encryption at rest means the data files on the storage volume are encrypted. If someone stole the physical disk or gained unauthorized access to the storage layer, they could not read your data.

Aurora uses **AES-256** encryption through AWS Key Management Service (KMS). When enabled, everything is encrypted:

```
  Encrypted with KMS:
  - Data files (tables, indexes)
  - Transaction logs (WAL)
  - Automated backups and snapshots
  - Read replica storage
  - Cluster volume
```

The encryption and decryption happens transparently. Your queries work the same way. There is no performance penalty worth measuring.

### AWS Managed Key vs Customer Managed Key

| Type | What AWS does | What you control | Cost |
|------|--------------|-----------------|------|
| AWS managed key | Rotates automatically every year | Nothing - AWS manages it | Free |
| Customer managed key (CMK) | You manage rotation | Key policy, who can use it, rotation schedule | $1/month/key |

Use a customer managed key when:
- You need to audit who used the key (KMS CloudTrail logs)
- You need to disable or delete the key to instantly revoke access to all data
- Compliance requires you to manage your own keys

### Aurora Encryption Considerations

Aurora encryption must be enabled at cluster creation time. You cannot enable encryption on an existing unencrypted cluster.

If you have an unencrypted cluster and need to encrypt it, the process is:
1. Take a snapshot of the unencrypted cluster
2. Copy the snapshot with encryption enabled
3. Restore a new cluster from the encrypted snapshot
4. Update your application connection strings
5. Delete the old unencrypted cluster

This requires a maintenance window because the endpoint changes.

---

---

## How the Layers Work Together

Here is a real-world example showing all four layers protecting an Aurora cluster:

```
  1. NETWORK: Aurora is in a private subnet. Security group only
     allows traffic from the application server's security group
     on port 5432.

  2. AUTHENTICATION: The application uses IAM database auth. No
     password stored anywhere. The EC2 instance role generates a
     15-minute token for each connection.

  3. AUTHORIZATION: The PostgreSQL role has SELECT and INSERT on
     two specific tables. No DELETE, no DROP, no access to other
     schemas.

  4. ENCRYPTION: SSL/TLS with verify-full encrypts all traffic.
     KMS encryption at rest protects the storage volume. Even if
     a backup snapshot is somehow accessed, the data is
     unreadable without the KMS key.
```

If an attacker compromises the application code, they can only SELECT and INSERT on two tables (Layer 3 limits them). They cannot exfiltrate data by sniffing the network (Layer 4 encrypts it). They cannot connect from another machine (Layer 1 blocks it). And even if they steal the IAM token, it expires in 15 minutes (Layer 2 limits the window).

---

## Key Terms

| Term | Definition |
|------|-----------|
| VPC | Virtual Private Cloud - your isolated network in AWS |
| Security Group | Firewall rules controlling inbound and outbound traffic |
| NACL | Network Access Control List - subnet-level firewall |
| IAM Auth | Token-based authentication using AWS IAM instead of passwords |
| SSL/TLS | Encryption protocol protecting data in transit |
| KMS | Key Management Service - manages encryption keys for data at rest |
| rds_superuser | AWS-limited version of PostgreSQL superuser |
| Least Privilege | Granting only the minimum permissions needed |
| RLS | Row-Level Security - restricting access at the row level |
| Defense in Depth | Using multiple security layers so no single failure is catastrophic |

---

## What to Read Next

- **BUILD 01** - Security Groups and Network (Layer 1)
- **BUILD 02** - SSL/TLS Connections (Layer 4 - transit)
- **BUILD 03** - IAM Database Authentication (Layer 2)
- **BUILD 04** - Secrets Manager Integration (Layer 2)
- **BUILD 05** - Role-Based Access Control (Layer 3)
- **BUILD 06** - Audit Logging (monitoring all layers)
