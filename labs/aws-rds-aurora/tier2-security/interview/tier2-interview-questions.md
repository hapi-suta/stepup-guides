# Tier 2 - Security and Access Control: Interview Questions

**Format:** Graduated Junior through Principal level
**Topics:** 6 (matching the BUILD guides)
**Questions per topic:** 8-10

---

## How to Use This

Work through these questions after completing the BUILD guides and USE exercises. For each question:

1. Try to answer it yourself first (out loud or in writing)
2. Read the "What they're looking for" section
3. Read the "Strong answer" section
4. Note any gaps between your answer and the strong answer

The goal is not to memorize the strong answers. The goal is to understand the concepts deeply enough to explain them in your own words.

---

---

## Topic 1 - PostgreSQL Roles and Permissions on RDS

---

**Q1.1 (Junior) - What is the difference between a role and a user in PostgreSQL?**

What they're looking for: Understanding that PostgreSQL uses a single concept (role) for both users and groups, and the key difference is the LOGIN attribute.

Strong answer:
In PostgreSQL, there is no real distinction between users and roles - they are the same thing. A role with the LOGIN attribute can connect to the database and is what most people call a "user." A role without LOGIN is used as a group - you add other roles to it and manage permissions at the group level. On RDS, the master user you create is a role with LOGIN that has been granted the `rds_superuser` role.

---

**Q1.2 (Junior) - What is rds_superuser and how is it different from a true PostgreSQL superuser?**

What they're looking for: Knowing that RDS restricts true superuser access and explains why.

Strong answer:
`rds_superuser` is a special role AWS creates on every RDS PostgreSQL instance. It gives the master user broad privileges like creating roles, replication, and pg_monitor access. But it is not a true PostgreSQL superuser (`pg_roles.rolsuper = false`). A true superuser can bypass all access controls, access OS files, load arbitrary extensions, and modify any system object. AWS prevents this because RDS is a managed service - AWS needs to control the OS and certain system configurations. Giving customers true superuser access would let them break things AWS manages. So you get rds_superuser instead, which is enough for DBA work but cannot touch the underlying OS.

---

**Q1.3 (Junior) - What is least privilege and why does it matter?**

What they're looking for: Practical understanding, not just a textbook definition.

Strong answer:
Least privilege means giving each role or service only the exact permissions it needs to do its job, and nothing more. It matters because database breaches often happen not from direct attacks but from compromised application credentials. If your app connects with a role that has GRANT ALL, an attacker who takes over the application can delete tables, read data in other schemas, or modify audit records. If the app role only has SELECT, INSERT, UPDATE on specific tables, the blast radius of a breach is much smaller. In practice I enforce it by: never using the master user for application connections, creating a specific role per service, and regularly auditing the `information_schema.role_table_grants` view to catch drift.

---

**Q1.4 (Mid-level) - Walk me through setting up roles for three types of users: an application service, a read-only BI tool, and a DBA.**

What they're looking for: A complete, practical answer showing the actual SQL and the reasoning behind each choice.

Strong answer:
For each, I start from zero access and add only what is needed.

Application service: `CREATE ROLE app_service WITH LOGIN PASSWORD '...';` then `GRANT CONNECT ON DATABASE mydb TO app_service;`, `GRANT USAGE ON SCHEMA app TO app_service;`, `GRANT SELECT, INSERT, UPDATE, DELETE ON specific tables TO app_service;`, and `GRANT USAGE, SELECT ON sequences.` I never grant DROP, TRUNCATE, or CREATE to application roles.

BI/read-only tool: Same pattern but `GRANT SELECT` only. Critically, I also set `ALTER DEFAULT PRIVILEGES` so new tables automatically get SELECT granted, otherwise new tables become invisible to the tool and you get support tickets.

DBA: For a trusted human DBA, I grant them `rds_superuser` membership via `GRANT rds_superuser TO dba_user;`. They can then do almost anything except true superuser OS-level operations. For day-to-day work I still expect them to use a less-privileged personal role and only elevate when needed. I use IAM auth for DBA connections so there are no stored passwords.

---

**Q1.5 (Mid-level) - What is ALTER DEFAULT PRIVILEGES and when does it matter?**

What they're looking for: Practical knowledge - this trips up teams regularly.

Strong answer:
`ALTER DEFAULT PRIVILEGES IN SCHEMA x GRANT SELECT ON TABLES TO y` tells PostgreSQL that any new table created in schema x by the current user should automatically have SELECT granted to role y. Without this, every new table is visible only to its owner until someone explicitly grants access. This matters a lot for read-only reporting roles - whenever developers add a new table, without ALTER DEFAULT PRIVILEGES the reporting tool sees permission denied until someone manually grants SELECT. We discovered this the hard way when a new feature table was added to production and the BI dashboard showed errors. The fix is to set ALTER DEFAULT PRIVILEGES for each schema and each owner who creates tables in that schema.

---

**Q1.6 (Mid-level) - How would you audit which roles have access to a sensitive table?**

What they're looking for: Knowledge of the information_schema views and pg_catalog.

Strong answer:
I use two queries. First, the information_schema view:

```sql
SELECT grantee, privilege_type
FROM information_schema.role_table_grants
WHERE table_schema = 'sensitive_schema'
  AND table_name = 'sensitive_table'
ORDER BY grantee, privilege_type;
```

This shows direct grants. But if permissions are inherited through group roles, I also check:

```sql
SELECT r.rolname AS role, m.rolname AS inherited_from
FROM pg_auth_members am
JOIN pg_roles r ON r.oid = am.member
JOIN pg_roles m ON m.oid = am.roleid
ORDER BY r.rolname;
```

Combining both tells me who can directly or indirectly access the table. I run this as part of our quarterly access review.

---

**Q1.7 (Senior) - A developer asks for temporary write access to the production database to fix a bug. How do you handle this?**

What they're looking for: Process thinking, not just technical steps.

Strong answer:
I never give developers persistent write access to production. Instead, my process is: the developer files a request with justification. If approved, I create a time-limited role with only the specific tables and privileges they need for that specific fix. I set a password expiry: `ALTER ROLE temp_fix_user VALID UNTIL '2024-01-15 18:00:00';`. I shadow the session by watching `pg_stat_activity`. After the fix, I immediately revoke the role and document what was changed. I also make sure the developer is on a call with me during the change, not working alone. The principle is: break-glass access, not standing access. The bigger question is why a code fix requires direct DB write access in the first place - usually that points to a missing migration or tool.

---

**Q1.8 (Senior) - How do you manage PostgreSQL role permissions as infrastructure as code?**

What they're looking for: Awareness of tooling and operational maturity.

Strong answer:
The challenge with PostgreSQL permissions is they are stateful and drift happens - someone runs a manual GRANT and nobody knows six months later. I manage them with a declarative approach. We write all role definitions and grants in SQL migration files tracked in git, applied via Flyway or Liquibase. Every change goes through a PR with review. To detect drift between the declared state and actual state, I run a weekly script that exports the current grants from `information_schema.role_table_grants` and compares it to the expected state from our migrations. Any discrepancy creates a ticket. For Terraform shops, the `postgresql` Terraform provider handles this declaratively, though it has some rough edges around role membership.

---

**Q1.9 (Principal) - Describe how you would design a role system for a multi-tenant SaaS application where each customer's data must be completely isolated.**

What they're looking for: Schema-level isolation vs row-level security, trade-offs.

Strong answer:
There are three main approaches. Schema-per-tenant is simplest: each customer gets their own schema, and the application role for that customer is granted usage only on their schema. It scales to a few hundred tenants comfortably but creates operational complexity at thousands. Row-level security (RLS) keeps all customers in shared tables but uses a `customer_id` column and PostgreSQL policies to restrict what each connection can see. You create a policy like `CREATE POLICY tenant_isolation ON orders USING (customer_id = current_setting('app.current_customer_id')::int);` and the application sets that session variable at connection time. This scales better but requires the application to always set the session variable or you have a security hole. The third option is separate RDS instances per tenant - the most isolated but most expensive. For most SaaS, I recommend schema-per-tenant up to around 500 tenants, then row-level security, with the application enforcing tenant ID in every query as a defense-in-depth measure on top of RLS. The key question is your regulatory requirements - some compliance frameworks require physical isolation (separate instances), not just logical isolation (RLS or schemas).

---
---

## Topic 2 - IAM Database Authentication

---

**Q2.1 (Junior) - What problem does IAM database authentication solve?**

What they're looking for: Connecting the feature to a real-world problem, not just stating what it does.

Strong answer:
The core problem it solves is stored credentials. When you use a password, that password has to live somewhere - a config file, an environment variable, a secrets vault. Every place a password is stored is a potential leak point. With IAM auth, there is no password to store. The application makes an API call to AWS, gets a 15-minute token, and uses that token as the password. If someone steals the token, it expires in 15 minutes. If someone steals the IAM credentials, you revoke the IAM policy and access is immediately gone - you do not need to rotate a database password and redeploy every application. It also ties database access into your existing IAM audit trail - every connection attempt can be traced back to an IAM identity.

---

**Q2.2 (Junior) - How long is an IAM auth token valid? What happens when it expires?**

What they're looking for: 15 minutes, and knowing how applications should handle this.

Strong answer:
IAM auth tokens are valid for exactly 15 minutes. After that, any new connection attempt using the expired token gets `FATAL: PAM authentication failed`. Existing connections are not affected - only new connections. Applications must generate a fresh token before each connection. The pattern that fails is generating the token at startup and caching it indefinitely. The pattern that works is generating the token at connection creation time. For connection pools, you configure the pool to generate a fresh token for each new connection it creates. For Lambda functions, a cold start generates a new token every time anyway.

---

**Q2.3 (Junior) - What three things do you need to set up IAM database auth?**

What they're looking for: Instance-level enablement, PostgreSQL role, IAM policy.

Strong answer:
Three things. First, enable IAM auth on the RDS instance itself - it is off by default. You do this with a modify-db-instance call or in the Console under Database authentication. Second, create a PostgreSQL role with `GRANT rds_iam TO that_role;` - this is how the database knows to validate the connection against IAM instead of checking a password. Third, create an IAM policy that allows `rds-db:connect` on the specific resource ARN. The ARN format is `arn:aws:rds-db:[region]:[account]:dbuser:[db-resource-id]/[pg-role-name]` - note it uses the DB resource ID (like `db-ABCDE12345`), not the instance identifier.

---

**Q2.4 (Mid-level) - How does the IAM auth token actually work? What does the database validate?**

What they're looking for: Understanding of the SigV4 signing and the IAM-RDS validation chain.

Strong answer:
The token is an AWS Signature Version 4 signed request URL. When you call `generate-db-auth-token`, the SDK uses your current AWS credentials to sign a request with the database hostname, port, and username embedded in the URL. This signature is time-stamped. When you pass the token as the password to psql, the RDS database engine sends it to the AWS IAM service for validation. IAM checks: is the signature valid? Is the signing identity (your IAM user or role) allowed to call `rds-db:connect` on this database resource and username? Has the token expired? If all three checks pass, the connection is allowed. The PostgreSQL database itself does not check the password against a stored hash - it delegates that to the IAM service. This is why the PostgreSQL role must have `rds_iam` granted - that tells PostgreSQL to use the IAM validation path instead of the normal pg_hba.conf password check.

---

**Q2.5 (Mid-level) - When would you NOT use IAM database authentication?**

What they're looking for: Honest trade-off thinking, not just advocating for IAM auth.

Strong answer:
IAM auth adds operational complexity and does not fit every situation. I avoid it for GUI tools like DBeaver or pgAdmin because they do not natively support token generation - you would have to manually generate a token and paste it as the password before it expires in 15 minutes. Operational scripts that run infrequently and need to stay simple are better served by a password in Secrets Manager. Situations where the host generating the token has no AWS API access (air-gapped networks, slow or unreliable internet) are also poor fits. The best use cases are EC2 instances with instance profiles and Lambda functions - both can call the AWS API cheaply and reliably, and neither requires storing credentials anywhere.

---

**Q2.6 (Senior) - You are designing a containerized application using ECS. How would you set up IAM database auth end to end?**

What they're looking for: ECS task role, token generation timing, connection pool configuration.

Strong answer:
ECS uses task roles, not instance profiles. First, create an IAM role for the ECS task and attach a policy allowing `rds-db:connect` on the specific database user ARN. Assign this task role to the task definition. At container startup, the application calls the EC2 metadata endpoint (which ECS also provides) to get temporary credentials for the task role. It uses those credentials to call `generate-db-auth-token`. The token goes into the connection string. For the connection pool (say, pgBouncer or the application-level pool), configure max connection lifetime to under 15 minutes - I use 10 minutes as a buffer. Before each new connection the pool creates, it generates a fresh token. I also set up a health check that catches authentication failures and triggers a pool refresh. The certificate bundle for SSL (`sslmode=verify-full`) is baked into the container image or mounted as a config map so it does not need to be downloaded at runtime.

---

**Q2.7 (Senior) - Explain the IAM policy resource ARN format for rds-db:connect. Why is it the DB resource ID and not the instance ID?**

What they're looking for: Deep understanding, not just reciting the format.

Strong answer:
The ARN format is `arn:aws:rds-db:[region]:[account-id]:dbuser:[DbiResourceId]/[db-username]`. The `DbiResourceId` is a stable internal identifier that starts with `db-` (like `db-ABCDEFGHIJ1234`). It is used instead of the instance identifier because it remains the same when you restore the instance from a snapshot, rename the instance, or perform certain maintenance operations. The instance identifier (like `my-postgres-db`) can change. If the policy used the instance identifier and you renamed the instance or restored to a new one with a different name, the IAM policy would break. The resource ID never changes for the lifetime of that database. You get it from `describe-db-instances` with the query for `DbiResourceId`.

---

**Q2.8 (Principal) - A customer says their Lambda functions work fine with IAM auth but periodically get authentication failures under load. What do you investigate?**

What they're looking for: Token generation timing, concurrency, IAM rate limits, Lambda cold starts.

Strong answer:
Several possibilities. First, under high concurrency, many Lambda instances might try to call `generate-db-auth-token` simultaneously and hit IAM API rate limits - the call is throttled and the function gets an error before it even tries to connect. Solution: implement exponential backoff on the token generation call. Second, a Lambda instance might cache the token in a global variable for efficiency, not realizing that Lambda instances are reused for multiple invocations over longer periods. If an instance is warm for longer than 15 minutes and the token was generated at cold start, the next invocation uses a stale token. Fix: store the token generation timestamp alongside the token and refresh it if it is older than 10 minutes. Third, the IAM policy might have insufficient `rds-db:connect` rate limits if scoped to a specific condition. Fourth, under load, if you are creating new connections rapidly (Lambda not using a connection pool or pool filling up), each new connection requires a new token, and the IAM API calls add latency. The real solution here is often RDS Proxy - it handles the connection pooling and IAM auth outside the Lambda, so Lambda connections reuse a pool with stable credentials.

---
---

## Topic 3 - SSL/TLS Connections

---

**Q3.1 (Junior) - What does sslmode=disable vs sslmode=require vs sslmode=verify-full mean in a connection string?**

What they're looking for: Practical knowledge of the four modes, not just definitions.

Strong answer:
`sslmode=disable` tells the client not to use SSL at all. The connection is plaintext. Never use this in production. `sslmode=require` tells the client to use SSL but does not verify the server's certificate. The traffic is encrypted but a man-in-the-middle attacker could present a fake certificate and the client would not notice - it just sees an SSL connection. `sslmode=verify-full` is the secure option - it encrypts the traffic and validates that the server certificate is signed by a trusted CA AND that the hostname in the certificate matches the hostname you are connecting to. To use it, you need to download the RDS CA bundle and point `sslrootcert` at it. In production I always use `verify-full`.

---

**Q3.2 (Junior) - How do you download the RDS CA certificate and why do you need it?**

What they're looking for: The download URL, why it is needed, and which bundle to use.

Strong answer:
You need the CA certificate to verify that the RDS server's certificate is legitimate. Without it, verify-full mode cannot check the certificate chain. For RDS, AWS signs certificates with its own Certificate Authority. You download it with `curl -o rds-ca-bundle.pem https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem`. The global bundle includes CAs for all AWS regions and both current and previous rotation cycles. I always use the global bundle instead of region-specific bundles because the global bundle survives certificate rotation events - the new CA is added to the bundle before the old one is retired. You point psql to it with `sslrootcert=/path/to/rds-ca-bundle.pem`.

---

**Q3.3 (Mid-level) - How do you enforce SSL server-side on RDS? Why is server-side enforcement important?**

What they're looking for: rds.force_ssl, parameter groups, and the "trust but verify" principle.

Strong answer:
You set `rds.force_ssl = 1` in the instance's parameter group, then reboot the instance. After that, the server rejects any connection that does not use SSL - the connection is terminated with `FATAL: no pg_hba.conf entry ... SSL off` before any authentication happens. Server-side enforcement matters because you cannot trust all applications to set sslmode correctly. A legacy script, a developer's quick psql command, or a misconfigured application might connect without SSL even if your standards say they should not. Server-side enforcement removes the choice - non-SSL connections are impossible regardless of how the client is configured. Defense in depth: the server enforces the policy, not just individual clients.

---

**Q3.4 (Mid-level) - You are checking all connections to a production RDS instance. How do you identify which connections are not using SSL?**

What they're looking for: Knowledge of pg_stat_ssl.

Strong answer:
```sql
SELECT sa.pid, sa.usename, sa.client_addr, sa.application_name, ss.ssl, ss.cipher
FROM pg_stat_activity sa
JOIN pg_stat_ssl ss ON sa.pid = ss.pid
WHERE sa.backend_type = 'client backend'
ORDER BY ss.ssl;
```
The `ssl` column is boolean. Any row with `ssl = f` is an unencrypted connection. I look at the `usename` and `client_addr` to identify what is connecting without SSL. Then I go fix those applications and require them to use sslmode=require or sslmode=verify-full. After enforcement, I run this query again to confirm all rows show `ssl = t`.

---

**Q3.5 (Mid-level) - RDS certificate rotation is coming up. What do you need to do and in what order?**

What they're looking for: Proactive steps, update the bundle first, then rotate the cert.

Strong answer:
The key is: update the CA bundle on all clients before the certificate is rotated on the server. The order is: first, download the updated global bundle which includes both old and new CAs. Deploy it to all application servers and update the `sslrootcert` path if needed. Test a connection from each application. Only after all applications are using the new bundle do you rotate the server certificate (either wait for AWS to do it or manually rotate). If you rotate the server certificate before updating clients, any client using only the old CA bundle gets `SSL certificate verify failed` and cannot connect. The global bundle protects against this because it always includes both the current and upcoming CA.

---

**Q3.6 (Senior) - Explain TLS 1.3 and what advantages it has over TLS 1.2 for database connections.**

What they're looking for: Security depth, not just "1.3 is newer."

Strong answer:
TLS 1.3 simplifies the handshake from two round trips down to one (and zero round trips for session resumption), which reduces connection latency - important for databases where new connections are frequent. More importantly for security: TLS 1.3 eliminates all the weak cipher suites that existed in TLS 1.2 - no more RC4, DES, 3DES, or export-grade ciphers. The key exchange in TLS 1.3 always uses Diffie-Hellman ephemeral (DHE), which provides perfect forward secrecy. This means that if someone records encrypted traffic today and later steals the server's private key, they still cannot decrypt past sessions because each session used a unique ephemeral key. For RDS, you can see the protocol version in `pg_stat_ssl.version`. Most modern clients default to TLS 1.3 and fall back to 1.2. You can verify TLS 1.3 is being used and if needed configure the client to reject 1.2 connections.

---

**Q3.7 (Principal) - A security team finds that some database connections use cipher suites they consider weak. How do you investigate and remediate on RDS?**

What they're looking for: Understanding of what you can and cannot control on RDS vs self-managed PostgreSQL.

Strong answer:
First, identify the weak ciphers. Query `pg_stat_ssl` for the `cipher` column on active connections - this shows what each connection is actually using. On RDS, your ability to restrict ciphers is limited compared to self-managed PostgreSQL. On self-managed, you would edit `ssl_ciphers` in postgresql.conf. On RDS, this parameter is exposed in the parameter group but the effective values depend on the OpenSSL version baked into the RDS binary. The practical remediation is to control the cipher on the client side. In psql, use `sslminprotocolversion=TLSv1.3` to force TLS 1.3, which only supports strong ciphers. In application connection strings, you can specify the SSL minimum protocol. If TLS 1.3 is required across the board, TLS 1.2 connections from older clients will start failing - test that before enforcing it. RDS Proxy is worth considering here: it handles TLS termination and you have more control over its TLS configuration. For the security team, I document what ciphers RDS actually supports and get a sign-off that they accept the constraints of managed RDS versus self-managed PostgreSQL.

---
---

## Topic 4 - Encryption at Rest

---

**Q4.1 (Junior) - What does "encryption at rest" mean on RDS?**

What they're looking for: AES-256, what is encrypted, transparent to queries.

Strong answer:
Encryption at rest means the data files stored on the EBS volumes behind the RDS instance are encrypted. This protects against physical theft or unauthorized access at the storage layer. AWS uses AES-256. Everything is encrypted: the database files, transaction logs (WAL), automated backups, snapshots, and read replicas. Encryption is transparent - your SQL queries work exactly the same way. RDS decrypts data as it reads it and encrypts data as it writes it, all in memory on the database server. The encryption key comes from AWS KMS.

---

**Q4.2 (Junior) - Can you enable encryption on an existing unencrypted RDS instance?**

What they're looking for: No, and know the workaround.

Strong answer:
No, you cannot enable encryption on an existing instance. There is no toggle. Once an instance is created unencrypted, it stays unencrypted. The workaround is the snapshot method: take a snapshot of the unencrypted instance, copy the snapshot with encryption enabled (specifying a KMS key in the copy command), then restore from the encrypted snapshot as a new RDS instance. The old instance can then be deleted after validating the new one. This migration requires a downtime window because you need a clean snapshot - if the application is writing during the snapshot, you either need to accept minor inconsistency (PostgreSQL's MVCC means the snapshot is crash-consistent) or stop the application briefly to get a clean snapshot.

---

**Q4.3 (Mid-level) - What is the difference between an AWS managed key and a customer managed key (CMK) in KMS?**

What they're looking for: Control, auditability, cost, and the ability to revoke access.

Strong answer:
An AWS managed key (like `aws/rds`) is created and managed entirely by AWS. It rotates automatically every year. You cannot customize the key policy, cannot disable it, cannot view detailed usage logs, and cannot delete it yourself. It is free. A customer managed key is one you create in KMS. You define the key policy (who can use it, who can manage it), you can enable or disable rotation on your schedule, you can view every call that used the key in CloudTrail, and critically - you can disable or delete the key. Disabling the key immediately makes all data encrypted with it inaccessible. This is a powerful security control: if you need to immediately cut off access to a database (say, in a breach situation or when decommissioning a system), disabling the KMS key achieves that faster than anything else. CMKs cost $1/month per key. For production databases holding sensitive data, I always use CMKs.

---

**Q4.4 (Mid-level) - Walk me through the snapshot-copy-restore method for encrypting an unencrypted RDS instance.**

What they're looking for: All three steps plus the consideration around downtime.

Strong answer:
Three steps. First, create a snapshot of the unencrypted instance: `aws rds create-db-snapshot --db-instance-identifier my-db --db-snapshot-identifier my-db-pre-encrypt`. Wait for it to complete. Second, copy the snapshot with a KMS key specified: `aws rds copy-db-snapshot --source-db-snapshot-identifier my-db-pre-encrypt --target-db-snapshot-identifier my-db-encrypted --kms-key-id alias/my-rds-key`. This creates a new snapshot that is a byte-for-byte copy of the original but encrypted. Third, restore the encrypted snapshot as a new RDS instance: `aws rds restore-db-instance-from-db-snapshot --db-instance-identifier my-db-v2 --db-snapshot-identifier my-db-encrypted`. The new instance has a different endpoint. You update your application configuration to point to the new endpoint. After validating the new instance works, delete the old one. The downtime is the gap between the snapshot and when you point traffic to the new instance. For zero-downtime, you can take a final snapshot after stopping writes to the old instance, restore it, and do a quick DNS cutover.

---

**Q4.5 (Senior) - What happens to encryption if you create a read replica of an encrypted RDS instance?**

What they're looking for: Replicas inherit the encryption, cross-region replicas can use a different key.

Strong answer:
Read replicas of an encrypted instance are always encrypted. You cannot create an unencrypted replica of an encrypted primary - AWS enforces this. In the same region, the replica uses the same KMS key as the primary. For cross-region replicas, you must specify a KMS key in the destination region (KMS keys are regional) - you can use the AWS managed key in that region or a CMK you created there. This means if you have a CMK, you need to create or grant the appropriate key in each region where you have replicas. It also means that if you are using a CMK and you want to promote a cross-region replica to a standalone instance after a regional failure, the KMS key in that region must be accessible.

---

**Q4.6 (Senior) - Explain the KMS key policy and why it matters for RDS encryption.**

What they're looking for: Key policy is the authoritative source for access, not IAM alone.

Strong answer:
KMS key policies are unique in AWS because they are the primary access control mechanism - IAM policies alone are not enough. A KMS key policy explicitly lists who can use and manage the key. For RDS encryption, the key policy must include the RDS service principal (`rds.amazonaws.com`) so that RDS can use the key to encrypt and decrypt data. It should also include the IAM role that creates and restores snapshots. If the key policy restricts access too tightly and RDS cannot use the key, the instance will fail to start after a reboot or fail to restore from a snapshot. I have seen this happen in prod when someone audited and "tightened" a key policy without realizing RDS needed a specific statement. The fix is to check the key policy with `aws kms get-key-policy` and ensure the RDS-related statements are present. CloudTrail shows all KMS API calls, so you can see exactly where the access failure is occurring.

---

**Q4.7 (Principal) - A customer is being acquired. Their data needs to be encrypted with your company's KMS key, not theirs. How do you handle this?**

What they're looking for: Cross-account KMS, snapshot sharing, re-encryption.

Strong answer:
KMS keys cannot be transferred across accounts, so you cannot just "move" the key. The process involves re-encrypting the data with a new key. Take a snapshot of their RDS instances. Share the snapshot with your AWS account using the RDS snapshot sharing feature. In your account, copy the shared snapshot and specify a KMS key from your account: `aws rds copy-db-snapshot --source-db-snapshot-identifier arn:aws:rds:region:their-account:snapshot:their-snap --target-db-snapshot-identifier their-data-our-key --kms-key-id arn:aws:kms:region:our-account:key/our-key-id`. The copy command re-encrypts the data with your key. Restore the copy as an RDS instance in your account. This works because during the copy, the data is decrypted using their key (you need permission on their key for the copy operation) and re-encrypted with your key. The permission model requires their account to grant your account's role usage on their KMS key, which is done through the key policy's cross-account statements. Coordinate with their team and validate data integrity after the restore.

---
---

## Topic 5 - Secrets Manager

---

**Q5.1 (Junior) - Why should database passwords be stored in Secrets Manager instead of environment variables?**

What they're looking for: The difference in security posture, not just "Secrets Manager is better."

Strong answer:
Environment variables end up in a lot of places: system process tables readable by any user on the host, Docker inspect output, CloudFormation templates, CI/CD logs, error messages, crash dumps, and application logs when the startup code prints them for debugging. They are also static - whoever set the environment variable owns that credential forever unless someone manually rotates it. Secrets Manager stores the secret encrypted with KMS, audits every access in CloudTrail, allows automatic rotation on a schedule, allows fine-grained IAM access control (this Lambda function can read this secret, that one cannot), and supports versioning so rollback is possible. The key operational advantage is rotation: when Secrets Manager rotates a password, it updates the secret in the vault AND changes the password in the database atomically. The application just fetches the current secret - it does not need to be redeployed.

---

**Q5.2 (Junior) - What is the JSON format for an RDS secret in Secrets Manager?**

What they're looking for: The standard fields and why they are structured this way.

Strong answer:
The standard format is:
```json
{
  "username": "app_user",
  "password": "the-actual-password",
  "host": "mydb.abc123.us-east-1.rds.amazonaws.com",
  "port": 5432,
  "dbname": "mydb",
  "engine": "postgres"
}
```
The reason all the connection details are in the secret - not just the password - is so the application only needs to call one API to get everything it needs to connect. If the host or database name also changes (for example, after migrating to a new RDS instance), you update the secret and the application picks it up without a code change. When you create the secret through the Console and choose "Credentials for Amazon RDS database," this format is populated automatically.

---

**Q5.3 (Mid-level) - How does Secrets Manager rotation work for RDS?**

What they're looking for: The Lambda, the multi-step rotation process, and version stages.

Strong answer:
Rotation uses a Lambda function. AWS provides pre-built rotation Lambdas for RDS. When rotation is triggered (on schedule or manually), the Lambda is invoked with the secret ID. It goes through four steps: createSecret (generates a new password and writes it as AWSPENDING version), setSecret (changes the password in the RDS database using the master credentials you configured), testSecret (connects to the database with the new password to confirm it works), and finishSecret (moves the AWSPENDING label to AWSCURRENT and moves AWSCURRENT to AWSPREVIOUS). The version staging means there is a brief window where both old and new passwords work, which prevents connection failures for applications that still have the old password cached. For zero-downtime rotation, the alternating users strategy is safer: two database users alternate, and the application always uses AWSCURRENT.

---

**Q5.4 (Mid-level) - How do you write application code that is resilient to Secrets Manager rotation?**

What they're looking for: Fetch fresh credentials, handle auth errors, retry once.

Strong answer:
The pattern is: fetch credentials at connection creation, not at application startup. In code:
1. When creating a new database connection, call `GetSecretValue` for the secret.
2. Use the returned credentials for that connection.
3. If the connection returns an authentication error (not a network error - an auth error specifically), catch it, call `GetSecretValue` again to get fresh credentials, and retry the connection once.
4. If the second attempt also fails, surface the error.

The "retry once on auth failure" pattern handles the case where rotation happens between the time the application cached credentials and the time it tries to reconnect. The key mistake to avoid is caching the credentials globally for the application lifetime - that leads to failures after rotation. SDK-level caching (like the AWS Secrets Manager caching client) handles this more elegantly with a configurable TTL.

---

**Q5.5 (Senior) - You need to give a third-party vendor read access to one Secrets Manager secret. How do you do this without giving them access to anything else in your account?**

What they're looking for: Resource-based policy on the secret, cross-account access.

Strong answer:
Secrets Manager supports resource-based policies on individual secrets, similar to S3 bucket policies. You add a policy directly to the secret that grants the vendor's AWS account (or specific IAM role in their account) `GetSecretValue` permission on that secret only. The policy looks like:
```json
{
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"AWS": "arn:aws:iam::vendor-account-id:role/their-role"},
    "Action": "secretsmanager:GetSecretValue",
    "Resource": "*"
  }]
}
```
The vendor then calls `aws secretsmanager get-secret-value` using their credentials, assuming a cross-account role if needed. This is better than creating an IAM user in your account for them because there are no long-lived credentials to manage. Their access is limited to this one secret by the resource policy. They cannot see or enumerate other secrets in your account.

---

**Q5.6 (Principal) - Design a secrets management strategy for a company with 50 microservices, each with its own database user, and compliance requirement that no secret is shared between services.**

What they're looking for: Naming convention, access scoping, rotation strategy, auditability.

Strong answer:
Naming convention is the foundation: `[env]/[service-name]/[credential-type]`, for example `prod/payment-service/db-credentials`. This makes IAM policies manageable. Each service gets an IAM role (ECS task role, Lambda execution role, or EC2 instance profile) with a policy that only allows `secretsmanager:GetSecretValue` on `arn:aws:secretsmanager:*:*:secret:prod/payment-service/*`. No cross-access between services. For the database side, each service has its own PostgreSQL role - if payment_service and order_service both need to read the `orders` table, they both get SELECT granted separately. Never share a database user between services. Rotation is enabled on all secrets with 30-day rotation. Each service is tested with rotation in staging before production. For auditability, CloudTrail captures every `GetSecretValue` call with the IAM identity, timestamp, and secret ID. A weekly audit query surfaces any services accessing secrets they should not (though IAM policies prevent this, the audit confirms). The compliance team gets a monthly report from CloudTrail showing which service accessed which secret and when.

---
---

## Topic 6 - Network Isolation

---

**Q6.1 (Junior) - What does "publicly accessible" mean on an RDS instance? Should production databases have this enabled?**

What they're looking for: What it does, and a firm "no" for production with reasoning.

Strong answer:
When an RDS instance is publicly accessible, AWS assigns it a DNS record that resolves to a public IP address. Anyone on the internet who knows the endpoint and has the right credentials can attempt a connection. No, production databases should never be publicly accessible. The database should only be reachable from inside your VPC - from your application servers, bastion hosts, and VPN endpoints. The principle is: never expose a database port to the internet. Even with strong passwords and SSL, public accessibility means attackers can attempt brute force logins, exploit any zero-day vulnerabilities in the PostgreSQL protocol, or conduct denial-of-service attacks against the port. Moving the database off the public internet eliminates this entire attack surface.

---

**Q6.2 (Junior) - What is the difference between using an IP range vs a security group reference as the source in an RDS security group rule?**

What they're looking for: Security groups as dynamic references vs static IP ranges.

Strong answer:
When you reference a security group as the source (like `sg-0abc123`), the rule means "allow traffic from any EC2 instance that is a member of this security group." When instances are added or removed from that security group, the rule updates dynamically. IP ranges are static - if your EC2 instance is terminated and a new one starts with a different IP, the old IP is no longer valid and the new IP might not be in the allowed range. For databases, I always use security group references, never IP ranges. The only exceptions are fixed corporate VPN IPs for bastion hosts, where the IP does not change.

---

**Q6.3 (Mid-level) - Explain VPC peering. What are its limitations?**

What they're looking for: Bidirectional, no transitive routing, CIDR overlap restriction.

Strong answer:
VPC peering creates a direct network route between two VPCs. Traffic stays on the AWS backbone and does not touch the internet. It is bidirectional - both VPCs can initiate connections to the other. Limitations: CIDRs cannot overlap between peered VPCs (if both use 10.0.0.0/16, peering fails). Routing is not transitive - if VPC A peers with VPC B, and VPC B peers with VPC C, traffic from VPC A cannot reach VPC C through VPC B. You need direct peering for each pair. At scale with many VPCs, the number of peering connections grows quadratically. For that, AWS Transit Gateway is the better solution - it acts as a hub. Finally, peering is a full VPC connection, meaning if you want to give a customer access to one service in your VPC, peering gives them access to the entire CIDR range (security groups still apply, but network-level isolation is weaker than PrivateLink).

---

**Q6.4 (Mid-level) - When would you use PrivateLink instead of VPC peering?**

What they're looking for: Cross-account/cross-tenant access, strict isolation, CIDR overlap scenarios.

Strong answer:
PrivateLink is one-directional and service-specific. The consumer can reach only the specific service exposed via the endpoint, not anything else in the provider's VPC. I use PrivateLink when: (1) giving customers in their own AWS accounts access to your database - you do not want to peer their VPC with yours because that would expose your internal network, (2) CIDRs overlap between the VPCs (PrivateLink has no CIDR requirement), (3) strict compliance isolation is required - some regulations mandate that customer A cannot have any network path to customer B's data, and PrivateLink provides that guarantee at the network level. VPC peering is simpler and better when both VPCs are under your control and you need broad connectivity, not just one specific service.

---

**Q6.5 (Senior) - Your application is in us-east-1 and needs to access an RDS instance in eu-west-1. How do you set this up with proper security?**

What they're looking for: Cross-region VPC peering or Transit Gateway, encryption considerations, latency awareness.

Strong answer:
Cross-region VPC peering works but has important implications: the traffic crosses AWS's backbone network between regions, and you pay data transfer charges. SSL/TLS is especially important here because the data traverses a longer network path. You create a peering connection just like same-region peering, but specify the peer region. The routing tables in both VPCs need routes for the other VPC's CIDR pointing to the peering connection. The RDS endpoint is the same regional endpoint - nothing changes there. However, I would question this architecture first. Cross-region database access adds 100+ milliseconds of latency per query. If this is unavoidable (say, for compliance, data sovereignty, or DR reasons), consider: can we read from a cross-region replica instead of the primary? Can we replicate the data we need to the local region? If cross-region direct access is truly required, I would use AWS Transit Gateway with inter-region peering for scalability and then VPN or Direct Connect overlaid for consistent latency. For the database, I would also enable SSL with verify-full and restrict the security group source to the specific Transit Gateway attachment IP range.

---

**Q6.6 (Senior) - How do you configure a custom DNS name for an RDS instance and why is it important?**

What they're looking for: Route53 CNAME, private hosted zone, TTL, and the operational benefit.

Strong answer:
I create a private Route53 hosted zone associated with my VPC and add a CNAME record pointing a friendly name to the RDS endpoint. For example, `db.internal.mycompany.com` pointing to `mydb.abc123.us-east-1.rds.amazonaws.com`. The TTL should be 60 seconds or less - this is important. The reason: when you need to switch the RDS endpoint (during failover, migration, or major version upgrade), updating the CNAME takes effect within TTL seconds. If all 20 application servers have hardcoded the RDS endpoint, you have to update all 20 config files and restart the applications. If they connect to `db.internal.mycompany.com`, you update one DNS record and the applications pick it up within 60 seconds without restarting. This is the single most valuable operational change I make on every new RDS deployment. It costs nothing and saves hours during incidents.

---

**Q6.7 (Principal) - Design the network architecture for a multi-tenant SaaS product where tenants are large enterprises that require their own dedicated RDS instances and strict isolation guarantees.**

What they're looking for: Per-tenant RDS, VPC isolation, PrivateLink for customer access, management plane architecture.

Strong answer:
Each enterprise tenant gets their own VPC and their own RDS instance. No shared infrastructure. The tenant's VPC is isolated - no peering with other tenant VPCs. The tenant accesses their database through PrivateLink: we create an NLB in front of their RDS instance, wrap it in a VPC endpoint service, and the tenant creates a VPC endpoint in their own AWS account. This means the tenant never has access to our VPC - they only see the specific database endpoint through PrivateLink. For management access (backups, monitoring, maintenance), we have a management VPC peered to each tenant VPC. The management VPC is never peered to other tenant VPCs (no transitive routing anyway, but we explicitly keep the route tables clean). The management plane uses Transit Gateway with strict routing policies - the operations team connects through a VPN or bastion in the management VPC. Monitoring goes through CloudWatch in each account, aggregated centrally with CloudWatch cross-account observability. Tenant credentials are stored in a Secrets Manager secret in our account that the tenant's application fetches using a cross-account IAM role - tenants do not directly manage database credentials. This architecture means a breach of one tenant's environment cannot reach another tenant's database at the network level.

---
---

## Quick Reference - What Each Level Should Know

**Junior** - Can explain the concepts, knows the basic CLI commands, can follow a runbook.

**Mid-level** - Can design role hierarchies from scratch, knows the trade-offs, can diagnose issues from symptoms.

**Senior** - Can design complete security architectures, thinks about edge cases and failure modes, knows what to do when things break under load.

**Principal** - Can navigate enterprise constraints, multi-account architectures, compliance frameworks, and guide teams toward correct solutions at organizational scale.
