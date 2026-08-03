# Module 04 - Aurora Security and IAM: Interview Questions

**Format:** Graduated Junior through Senior level
**Topics:** Security layers, IAM auth, SSL/TLS, Secrets Manager, RBAC, audit logging
**Questions:** 18

---

## How to Use This

Work through these questions after completing the BUILD guides and USE exercises. For each question:

1. Try to answer it yourself first (out loud or in writing)
2. Read the "What they are looking for" section
3. Read the "Strong answer" section
4. Note any gaps between your answer and the strong answer

The goal is not to memorize the strong answers. The goal is to understand the concepts deeply enough to explain them in your own words.

---

---

## Security Layers and Network

---

**Q1 (Junior) - What are the four layers of Aurora database security?**

What they are looking for: A structured understanding of defense in depth, not just listing features.

Strong answer:
The four layers are Network, Authentication, Authorization, and Encryption. Network is the outermost layer - VPC, private subnets, and security groups control who can even reach port 5432. Authentication verifies identity - passwords, IAM tokens, or certificates prove you are who you claim to be. Authorization controls what you can do after logging in - PostgreSQL GRANT and REVOKE control which tables you can read or write. Encryption protects data both in transit (SSL/TLS between app and database) and at rest (KMS encryption on the storage volume). Each layer stops a different kind of attacker. Even if one layer fails, the others still protect you.

---

**Q2 (Junior) - Why should an Aurora cluster never have PubliclyAccessible set to True?**

What they are looking for: Understanding of the attack surface concept.

Strong answer:
When PubliclyAccessible is True, the Aurora instance gets a public IP address reachable from the internet. Even with security groups blocking most traffic, having a public IP means the database is discoverable by automated scanners. Attackers continuously scan public IP ranges for open database ports. With PubliclyAccessible set to False, the instance only has a private IP - it is unreachable from outside the VPC. Applications connect through the VPC's private network, and administrators use a bastion host or VPN. This reduces the attack surface to zero from the internet. The only exception might be a development database, and even then I would use a VPN instead.

---

**Q3 (Mid-level) - Explain the difference between a security group and a NACL for protecting an Aurora cluster.**

What they are looking for: Understanding of both mechanisms and when each matters.

Strong answer:
Security groups and NACLs both filter network traffic but at different levels and with different behavior. A security group is attached directly to the Aurora cluster and acts as a stateful firewall - if you allow inbound traffic on port 5432, the return traffic is automatically allowed. You only write "allow" rules. A NACL operates at the subnet level and is stateless - you must explicitly allow both inbound and outbound traffic, including ephemeral port ranges for return traffic. NACLs also support "deny" rules, which security groups do not. For Aurora, the security group is the primary control. I reference the application server's security group as the source, which means only instances in that security group can connect. NACLs are a secondary layer - I use them when compliance requires subnet-level controls, but for most Aurora setups the default NACL with allow-all is fine because the security group handles the filtering.

---

---

## IAM Database Authentication

---

**Q4 (Junior) - What problem does IAM database authentication solve?**

What they are looking for: Connecting the feature to a real-world problem, not just stating what it does.

Strong answer:
The core problem is stored credentials. When you use a password, that password has to live somewhere - a config file, an environment variable, a secrets vault. Every place a password is stored is a potential leak point. With IAM auth, there is no password to store. The application makes an API call to AWS, gets a 15-minute token, and uses that token as the password. If someone steals the token, it expires in 15 minutes. If someone steals the IAM credentials, you revoke the IAM policy and access is immediately gone - no need to rotate a database password and redeploy every application. It also ties database access into your existing IAM audit trail - every connection attempt is traceable to an IAM identity in CloudTrail.

---

**Q5 (Junior) - What three things do you need to set up IAM database auth on Aurora?**

What they are looking for: Complete list with the correct order.

Strong answer:
Three things. First, enable IAM auth on the Aurora cluster itself - it is off by default. You do this with `modify-db-cluster` or in the Console under Database authentication. Second, create a PostgreSQL role in the database and grant it `rds_iam` - this is how Aurora knows to validate the connection against IAM instead of checking a password hash. Third, create an IAM policy that allows `rds-db:connect` on the specific cluster resource ID and username. The ARN format uses the `DbClusterResourceId` (like `cluster-ABCDE12345`), not the cluster identifier. The resource ID stays stable even if you rename the cluster.

---

**Q6 (Mid-level) - When would you NOT use IAM database authentication?**

What they are looking for: Honest trade-off thinking, not just advocating for IAM auth.

Strong answer:
IAM auth adds complexity and does not fit every situation. I avoid it for GUI tools like DBeaver or pgAdmin because they do not natively support token generation - you would need to manually generate a token and paste it as the password before it expires in 15 minutes. For operational scripts that run infrequently and need to stay simple, a password in Secrets Manager with automatic rotation is more practical. Environments without reliable AWS API access are also poor fits. The best use cases are EC2 instances with instance profiles, Lambda functions, and ECS tasks - all of these can call the AWS API reliably with no stored credentials. I would also avoid it if the application's connection pool cannot be configured to generate a fresh token per connection.

---

**Q7 (Senior) - How does the IAM auth token actually work? What does Aurora validate?**

What they are looking for: Understanding of the SigV4 signing and the validation chain.

Strong answer:
The token is an AWS Signature Version 4 signed request URL. When you call `generate-db-auth-token`, the SDK uses your current AWS credentials to sign a request with the hostname, port, and username embedded in the URL. The signature includes a timestamp. When you pass the token as the password to psql, Aurora sends it to the AWS IAM service for validation. IAM checks three things: is the signature valid (was it signed by real AWS credentials)? Is the signing identity allowed to call `rds-db:connect` on this specific cluster resource ID and username? Has the token expired (15-minute window)? If all three pass, the connection is allowed. The PostgreSQL database itself does not check a password hash - it delegates entirely to IAM. This is why the role must have `rds_iam` granted - that flag tells Aurora to use the IAM validation path instead of the normal password check.

---

---

## SSL/TLS Connections

---

**Q8 (Junior) - What is the difference between sslmode=require and sslmode=verify-full?**

What they are looking for: Understanding of what each mode protects against.

Strong answer:
`sslmode=require` encrypts the connection but does not verify who you are talking to. The data is encrypted in transit, so someone sniffing the network cannot read your SQL queries. But it does not prevent a man-in-the-middle attack - an attacker could intercept the connection, present their own certificate, and relay traffic between you and the real server while reading everything. `sslmode=verify-full` encrypts the connection AND verifies the server's certificate against a trusted Certificate Authority AND checks that the hostname in the certificate matches the server you are connecting to. This prevents man-in-the-middle attacks. In production, always use `verify-full` with the RDS CA bundle.

---

**Q9 (Mid-level) - How do you enforce SSL on an Aurora cluster so that applications cannot choose to connect without it?**

What they are looking for: Server-side enforcement, not relying on client configuration.

Strong answer:
Set `rds.force_ssl = 1` in the cluster parameter group. This is a server-side enforcement - the cluster rejects any connection attempt that does not use SSL, regardless of what the client requests. The error the client sees is `FATAL: no pg_hba.conf entry for host ... SSL off`. On Aurora, `rds.force_ssl` is a dynamic parameter, so it takes effect immediately without a reboot. This is important because relying on every application to set `sslmode=require` is fragile - one misconfigured app or a new tool deployed without SSL settings creates an unencrypted connection. Server-side enforcement eliminates that risk entirely.

---

**Q10 (Senior) - Walk me through the RDS certificate rotation process and how you would prepare for it.**

What they are looking for: Proactive preparation, not reactive firefighting.

Strong answer:
AWS periodically rotates the CA that signs RDS certificates. The process is: AWS publishes a new CA months in advance. You download the new global certificate bundle from `truststore.pki.rds.amazonaws.com/global/global-bundle.pem` - this bundle includes both old and new CAs. You update the `sslrootcert` path in all application connection strings to use the new bundle. You test connections in a staging environment to verify both old and new certificates work. Then you update each Aurora instance to use the new CA using `modify-db-instance --ca-certificate-identifier`. The key is to do this before the old CA expires. Using the global bundle is safest because it contains all CAs - current, upcoming, and recent past. I schedule this proactively when AWS announces the rotation rather than waiting for the deadline.

---

---

## Secrets Manager

---

**Q11 (Junior) - Why should database passwords be stored in Secrets Manager instead of environment variables?**

What they are looking for: Understanding of the security and operational problems with environment variables.

Strong answer:
Environment variables have several problems. They get logged by monitoring tools and crash reporters - if an application crashes, the core dump may include environment variables with the password in plain text. They get inherited by child processes, so a subprocess you did not intend to have the password gets it. They show up in process listings on some systems. They get committed to git when stored in `.env` files. And they never rotate unless someone manually changes them everywhere. Secrets Manager solves all of these: the password is encrypted at rest with KMS, access is controlled by IAM, every access is logged in CloudTrail, rotation can be automatic, and the application fetches the password at runtime via an API call - it never touches the filesystem or environment.

---

**Q12 (Mid-level) - Explain the difference between single-user and alternating-user rotation strategies in Secrets Manager.**

What they are looking for: Understanding of the trade-offs, especially around downtime.

Strong answer:
Single-user rotation changes the password for one database user. During the brief moment between the password change in the database and the secret update in Secrets Manager, applications using the old password will fail to connect. This window is typically seconds, but it exists. Alternating-user rotation maintains two database users - the main user and a clone. When rotation triggers, it changes the password on the inactive clone, tests the connection, then updates the secret to point to the clone. Now the clone is active and the original is inactive. The next rotation swaps them back. This provides zero downtime because one user is always valid. The trade-off is complexity - you have two database users to manage and the rotation Lambda is more complex. For production systems where even seconds of connection failures are unacceptable, I use alternating users.

---

**Q13 (Senior) - A team stores database credentials in Secrets Manager but the rotation Lambda fails silently. How do you detect and prevent this?**

What they are looking for: Monitoring, alerting, and operational maturity.

Strong answer:
First, detection: I set up a CloudWatch alarm on the Secrets Manager metric `RotationFailed`. If rotation fails, the alarm fires and the on-call team is notified. I also monitor the `LastRotatedDate` - if it has not changed in the expected rotation window plus a buffer (e.g., 35 days for a 30-day rotation), something is wrong. Second, the Lambda itself: I check its CloudWatch Logs for errors. Common failures are network connectivity (the Lambda cannot reach the database because it is not in the VPC or missing a NAT gateway), IAM permission issues (the Lambda's execution role cannot call `secretsmanager:PutSecretValue`), or the database rejecting the new password (password policy violation). Prevention: I test the rotation Lambda in staging by triggering a manual rotation and verifying the password changes. I also set up a dead-letter queue on the Lambda so failed invocations are captured for analysis.

---

---

## Role-Based Access Control

---

**Q14 (Junior) - What is least privilege and why does it matter for database roles?**

What they are looking for: Practical understanding, not just a textbook definition.

Strong answer:
Least privilege means giving each role only the exact permissions it needs to do its job, nothing more. It matters because database breaches often happen through compromised application credentials, not direct attacks. If your app connects with a role that has `GRANT ALL`, an attacker who takes over the application can delete tables, read data in other schemas, or modify audit records. If the app role only has SELECT and INSERT on two specific tables, the blast radius of a breach is much smaller. In practice I enforce it by: never using the master user for application connections, creating a specific role per service, using group roles for scalable management, and regularly auditing `information_schema.role_table_grants` to catch drift.

---

**Q15 (Mid-level) - Walk me through setting up the "role as group" pattern for managing database permissions.**

What they are looking for: The complete pattern with SQL and reasoning.

Strong answer:
The pattern has three parts. First, create a group role with NOLOGIN - it cannot connect directly, it just holds permissions: `CREATE ROLE app_readwrite NOLOGIN;`. Second, grant all the needed permissions to the group role: `GRANT USAGE ON SCHEMA app TO app_readwrite;`, `GRANT SELECT, INSERT, UPDATE ON app.orders TO app_readwrite;`, and so on. Third, create individual login roles and add them to the group: `CREATE ROLE alice WITH LOGIN PASSWORD '...'; GRANT app_readwrite TO alice;`. When a new person joins, one GRANT command gives them all the right permissions. When someone leaves, one REVOKE removes everything. You never touch table-level grants when adding or removing people. The key addition is `ALTER DEFAULT PRIVILEGES` so new tables automatically get the right grants - without this, every new table requires manual intervention.

---

**Q16 (Senior) - How would you design a role system for a multi-tenant SaaS application where each customer's data must be completely isolated?**

What they are looking for: Understanding of schema isolation vs row-level security, and trade-offs.

Strong answer:
There are three approaches. Schema-per-tenant is simplest: each customer gets their own schema, and the application role is granted USAGE only on the active customer's schema. This scales to a few hundred tenants comfortably but creates operational complexity at thousands (migrations, monitoring). Row-Level Security (RLS) keeps all customers in shared tables with a `tenant_id` column and PostgreSQL policies that filter rows. You create a policy like `CREATE POLICY tenant_isolation ON orders USING (tenant_id = current_setting('app.tenant_id')::int);` and the application sets that session variable at connection time. This scales better but requires the application to always set the session variable - if it forgets, you have a data leak. The third option is separate Aurora clusters per tenant - maximum isolation but most expensive and operationally heavy. For most SaaS, I recommend schema-per-tenant up to about 500 tenants, then RLS with the application enforcing tenant ID as a defense-in-depth measure on top of RLS.

---

---

## Audit Logging

---

**Q17 (Junior) - What is pgAudit and what does it log that PostgreSQL does not log by default?**

What they are looking for: Understanding of what native logging misses.

Strong answer:
pgAudit is a PostgreSQL extension that provides detailed audit logging. Native PostgreSQL logging with `log_statement` captures the SQL text but does not categorize it or provide structured audit entries. pgAudit adds categorized logging with labels like DDL (schema changes), ROLE (permission changes), READ (SELECT), and WRITE (INSERT/UPDATE/DELETE). Each audit entry includes the session user, the object accessed, and the full SQL statement in a structured format. This makes it easier to answer questions like "who ran DDL statements in the last 24 hours?" or "which user selected from the PII table?" You can also configure per-role auditing - for example, log ALL statements from a sensitive admin role but only DDL from regular users.

---

**Q18 (Senior) - Design an audit and monitoring strategy for an Aurora cluster handling financial data.**

What they are looking for: A comprehensive, layered approach covering multiple tools.

Strong answer:
For financial data I use five layers of auditing. First, `pgaudit.log=ddl,role` to capture all schema changes and permission changes - these are the highest-risk operations. Second, `log_connections=on` and `log_disconnections=on` to track every session with source IP, duration, and user. Third, per-role auditing: `ALTER ROLE admin_user SET pgaudit.log = 'all';` for any role that can modify data, so we capture the actual SQL. Fourth, CloudTrail for all AWS API calls - who modified the cluster, who changed parameter groups, who accessed Secrets Manager. Fifth, CloudWatch alarms: one for failed login attempts (pattern: `FATAL: password authentication failed` with threshold > 5 in 5 minutes), one for DDL outside maintenance windows, and one for connections from unexpected IP ranges. I send all PostgreSQL logs to CloudWatch Logs and set retention to 365 days for compliance. I also create a monthly report that aggregates: total connections by user, failed auth attempts, DDL changes, and privilege modifications. This gives the compliance team everything they need and gives me early warning of anomalies.
