# Tier 2 - Security and Access Control

**Level:** Beginner to Intermediate
**Estimated time:** 5-6 hours total
**Prerequisites:** Tier 0 (Foundations) and Tier 1 (Provisioning) complete

---

## What You Will Learn

By the end of this tier you will be able to:

- Create PostgreSQL roles with least-privilege permissions on RDS
- Enable and use IAM database authentication (token-based logins)
- Enforce SSL/TLS for all database connections
- Encrypt RDS instances at rest using AWS KMS
- Rotate database passwords automatically with Secrets Manager
- Isolate your database using PrivateLink and custom DNS

---

## Why Security Matters Here

RDS runs in the cloud. That means your database can be reached from anywhere unless you lock it down. A single weak role, an unencrypted connection, or a leaked password can expose every row in every table.

This tier teaches you the tools AWS gives you to prevent that.

---

## Module Map

```
tier2-security/
├── concepts/
│   └── security.md          - Theory and diagrams for all 6 topics
│
├── build/
│   ├── 01-roles-and-permissions.md   (35 min) - PostgreSQL roles on RDS
│   ├── 02-iam-database-auth.md       (40 min) - Token-based IAM login
│   ├── 03-ssl-tls-connections.md     (30 min) - Enforce encrypted connections
│   ├── 04-encryption-at-rest.md      (25 min) - KMS encryption
│   ├── 05-secrets-manager.md         (35 min) - Automatic password rotation
│   └── 06-network-isolation.md       (30 min) - PrivateLink and custom DNS
│
├── use/
│   ├── 01-role-audit.md              - Find and fix over-privileged roles
│   ├── 02-iam-auth-setup.md          - Set up IAM auth for an app team
│   ├── 03-ssl-enforcement.md         - Enforce SSL, verify all connections
│   ├── 04-encryption-migration.md    - Encrypt an unencrypted instance
│   └── 05-secrets-rotation.md        - Set up and test password rotation
│
├── survive/
│   ├── config.sh                     - Environment variables for all scenarios
│   ├── lib/common.sh                 - Shared helper functions
│   ├── 01-ssl-not-enforced/          - SSL disabled, connections unencrypted
│   ├── 02-iam-token-expired/         - App can't connect, token expired
│   ├── 03-password-leaked/           - Emergency password rotation
│   └── 04-overprivileged-role/       - Security audit finds excessive grants
│
└── interview/
    └── tier2-interview-questions.md  - 8-10 questions per topic, Junior to Principal
```

---

## How to Use This Tier

**Step 1 - Read concepts first.**
Open `concepts/security.md` and read the section for the topic you are about to build. The diagrams will help you understand what you are doing before you do it.

**Step 2 - Work through the BUILD guides.**
Each BUILD guide walks you through a real task step by step. Do not skip steps. Every command teaches you something.

**Step 3 - Practice with USE exercises.**
These are shorter tasks with less hand-holding. You apply what you learned in BUILD to a realistic scenario.

**Step 4 - Run the SURVIVE scenarios.**
These simulate real production incidents. An `inject.sh` script breaks something. You diagnose and fix it using the runbook. A `validate.sh` script confirms your fix worked.

**Step 5 - Review interview questions.**
These prepare you for real job interviews. Work through them after completing the exercises.

---

## Tools You Will Need

- AWS CLI configured with your account credentials
- psql (PostgreSQL client)
- An RDS PostgreSQL instance (created in Tier 1)
- AWS Console access in a browser

### Verify your setup

```bash
aws sts get-caller-identity
```

Expected output (yours will differ):

```
{
    "UserId": "AIDAIOSFODNN7EXAMPLE",
    "Account": "123456789012",
    "Arn": "arn:aws:iam::123456789012:user/your-username"
}
```

```bash
psql --version
```

Expected output:

```
psql (PostgreSQL) 16.6
```

---

## Key Terms at a Glance

| Term | What it means |
|------|--------------|
| Role | A named identity in PostgreSQL - can be a user or a group |
| rds_superuser | The highest role available on RDS (not a true superuser) |
| IAM auth | Log in with a temporary AWS token instead of a password |
| SSL/TLS | Encryption for data moving between your app and the database |
| KMS | AWS Key Management Service - manages encryption keys |
| Secrets Manager | AWS service that stores and rotates credentials automatically |
| PrivateLink | Connects two VPCs privately without traffic going to the internet |

---

## Estimated AWS Cost

These labs use minimal resources. Estimated cost for one student working through the full tier:

- RDS instance (db.t3.micro, single-AZ): ~$0.02/hour
- KMS key: $1.00/month (pro-rated, minimal for a few hours)
- Secrets Manager secret: $0.40/month (pro-rated)
- PrivateLink endpoint: ~$0.01/hour

**Stop or delete resources after each session to minimize cost.**

---

## Quick Reference - Useful Commands

```bash
# List all roles in PostgreSQL
psql -c "\du"

# Check SSL on your connection
psql -c "SELECT ssl FROM pg_stat_ssl WHERE pid = pg_backend_pid();"

# Generate an IAM auth token
aws rds generate-db-auth-token \
  --hostname [YOUR-RDS-ENDPOINT] \
  --port 5432 \
  --region [REGION] \
  --username [DB-USERNAME]

# Retrieve a secret from Secrets Manager
aws secretsmanager get-secret-value \
  --secret-id [SECRET-NAME] \
  --region [REGION]
```

---

## Getting Help

If a command fails, check:
1. Are your AWS credentials configured? Run `aws sts get-caller-identity`
2. Is your RDS instance running? Check the AWS Console under RDS > Databases
3. Can your IP reach port 5432? Check the security group inbound rules
4. Are you in the right region? Run `aws configure get region`
