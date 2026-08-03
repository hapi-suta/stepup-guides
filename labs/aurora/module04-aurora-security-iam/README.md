# Module 04: Aurora Security and IAM

**Track:** DevOps DBA Training
**Duration:** ~12 hours
**Week:** 2-3
**Prerequisites:** Module 01-03

---

## What You Will Learn

This module covers every layer of Aurora security. By the end, you will:

- Understand how database security works in layers - network, transport, authentication, authorization, audit
- Lock down network access with security groups and NACLs
- Enforce encrypted connections with SSL/TLS
- Authenticate to Aurora using IAM tokens instead of passwords
- Store and rotate credentials automatically with Secrets Manager
- Implement role-based access control with least-privilege grants
- Enable and interpret audit logs for compliance

---

## Module Contents

### Concepts (read first)
1. [Database Security Layers](concepts/01-database-security-layers.md) - Network, transport, auth, authorization, audit - defense in depth
2. [IAM for Databases](concepts/02-iam-for-databases.md) - IAM policies, roles, token-based auth, when to use IAM vs passwords

### BUILD (hands-on, follow step by step)
1. [Security Groups and Network](build/01-security-groups-and-network.md) - Restrict inbound access, NACLs, private subnets (30 min)
2. [SSL/TLS Connections](build/02-ssl-tls-connections.md) - Download RDS CA bundle, force SSL, verify connections (30 min)
3. [IAM Database Authentication](build/03-iam-database-authentication.md) - Enable IAM auth, create IAM policy, generate tokens (45 min)
4. [Secrets Manager Integration](build/04-secrets-manager-integration.md) - Store credentials, automatic rotation, Lambda rotation function (45 min)
5. [Role-Based Access Control](build/05-role-based-access-control.md) - Create roles, grant privileges, revoke defaults (45 min)
6. [Audit Logging](build/06-audit-logging.md) - Enable pgAudit, configure log groups, query CloudWatch Logs (30 min)

### USE (practice with less hand-holding)
1. [Security Audit Exercise](use/01-security-audit-exercise.md)
2. [SSL Enforcement Exercise](use/02-ssl-enforcement-exercise.md)
3. [IAM Auth Exercise](use/03-iam-auth-exercise.md)
4. [Secrets Rotation Exercise](use/04-secrets-rotation-exercise.md)
5. [Least Privilege Exercise](use/05-least-privilege-exercise.md)

### SURVIVE (break it, fix it)
1. [SSL Not Enforced](survive/01-ssl-not-enforced/) - Detect and fix unencrypted connections
2. [IAM Token Expired](survive/02-iam-token-expired/) - Diagnose expired token errors, automate renewal
3. [Password Leaked](survive/03-password-leaked/) - Rotate credentials under pressure, audit for damage
4. [Overprivileged Role](survive/04-overprivileged-role/) - Find and fix roles with excessive grants

### Interview Prep
1. [Interview Questions](interview/01-interview-prep.md) - 15-20 questions, Junior to Senior

---

## What is Next

After completing this module, you will move to [Module 05: HA, Replication and Failover](../module05-ha-replication-failover/) where you build multi-AZ clusters and practice failover scenarios.

---

## Cost Warning

Minimal cost beyond your existing cluster. Secrets Manager charges $0.40 per secret per month plus $0.05 per 10,000 API calls. All other security features - security groups, SSL, IAM auth, pgAudit - are included at no extra charge.
