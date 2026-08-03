# Concepts - IAM for Databases

Read this before starting BUILD 03 (IAM Database Authentication) and BUILD 04 (Secrets Manager Integration).

---

## What Is IAM?

**IAM** stands for Identity and Access Management. It is the service AWS uses to control who can do what across all AWS services.

Think of IAM as the security desk in an office building. It checks your badge (identity), looks up what rooms you can enter (permissions), and logs when you entered and left (audit trail).

Every AWS API call goes through IAM. When you run `aws rds describe-db-clusters`, IAM checks if your identity has permission to make that call. If not, you get "Access Denied."

---

## IAM Basics for Database Context

### IAM Users

An **IAM user** is a long-lived identity for a person or service. It has a username, an access key, and a secret key.

```
  IAM User: "happy"
  Access Key: AKIAIOSFODNN7EXAMPLE
  Secret Key: wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
```

IAM users are fine for human operators who need CLI access. They are not ideal for applications because the credentials are long-lived and must be stored somewhere.

### IAM Roles

An **IAM role** is a temporary identity that something can "assume." Roles do not have permanent credentials. Instead, they issue temporary credentials that expire.

Common use cases:
- An EC2 instance assumes a role to access AWS services (no stored credentials)
- A Lambda function assumes a role to read from S3 or connect to a database
- An ECS task assumes a task role to call AWS APIs
- A human assumes a role for elevated access (break-glass scenarios)

For database connections, IAM roles are better than IAM users because the credentials are temporary and automatically rotated.

```
  EC2 Instance
  +----------------------------+
  |                            |
  | Instance Role:             |
  |   "orders-service-role"    |
  |                            |
  | The instance can call      |
  | AWS APIs without storing   |
  | any access keys.           |
  |                            |
  | Temporary credentials are  |
  | fetched automatically from |
  | the instance metadata      |
  | service.                   |
  +----------------------------+
```

### IAM Policies

An **IAM policy** is a JSON document that defines permissions. It says: "This identity can perform these actions on these resources."

Example - allow connecting to a specific Aurora database user:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["rds-db:connect"],
      "Resource": "arn:aws:rds-db:us-east-1:123456789012:dbuser:cluster-ABCDE12345/app_user"
    }
  ]
}
```

Breaking this down:
- **Effect** - Allow or Deny
- **Action** - What API calls are permitted. `rds-db:connect` is the action for IAM database authentication
- **Resource** - The specific database and user. Uses the cluster resource ID (not the cluster name)

### The Resource ARN Format

The resource ARN for IAM database auth on Aurora uses a specific format:

```
arn:aws:rds-db:[region]:[account-id]:dbuser:[DbiResourceId]/[db-username]
```

| Part | Example | Where to find it |
|------|---------|-----------------|
| region | us-east-1 | Your AWS region |
| account-id | 123456789012 | `aws sts get-caller-identity` |
| DbiResourceId | cluster-ABCDE12345 | `aws rds describe-db-clusters` |
| db-username | app_user | The PostgreSQL role name |

The DbiResourceId is a stable internal identifier. It does not change when you rename the cluster or restore from a snapshot. The policy uses this ID instead of the cluster name because the name can change, but the resource ID stays the same.

---

## IAM Database Authentication

### The Problem with Passwords

Passwords create a chain of problems:

1. The password must be stored somewhere for the application to use
2. That "somewhere" is usually a config file, environment variable, or secret
3. Config files get committed to git
4. Git repos get made public by accident
5. Environment variables get logged by monitoring tools
6. Passwords never rotate unless someone manually changes them
7. When a password does change, every application using it must be updated

IAM database authentication breaks this chain by eliminating the password entirely.

### How IAM Auth Works

```
  Step 1: Application calls AWS
  +---------------------------+
  |  Your Application         |
  |                           |
  |  token = aws rds          |
  |    generate-db-auth-token |
  +----------+----------------+
             |
             v
  Step 2: AWS IAM returns a signed token
  +---------------------------+
  |  AWS IAM / STS            |
  |                           |
  |  Checks: does this IAM    |
  |  identity have the        |
  |  rds-db:connect action    |
  |  on this resource?        |
  |                           |
  |  Returns: signed token    |
  |  (valid 15 minutes)       |
  +----------+----------------+
             |
             v
  Step 3: Application connects to Aurora using the token as the password
  +---------------------------+
  |  Aurora PostgreSQL        |
  |                           |
  |  Validates the token      |
  |  with AWS IAM service     |
  |                           |
  |  Checks: PostgreSQL role  |
  |  has rds_iam granted?     |
  |                           |
  |  Connection allowed.      |
  +---------------------------+
```

### What You Need (Three Parts)

1. **IAM policy** - Allows the IAM identity (user or role) to call `rds-db:connect` on the specific database user
2. **PostgreSQL role** - Created in the database with `GRANT rds_iam TO that_role;` so Aurora knows to validate using IAM instead of checking a password
3. **Token** - Generated fresh before each connection using `aws rds generate-db-auth-token`

### Token Expiration

The token is valid for exactly 15 minutes. After that:
- New connections using the expired token get `FATAL: PAM authentication failed`
- Existing connections are not affected - only new connections

Your application must generate a new token before each connection attempt. Do not cache tokens.

### When to Use IAM Auth

Good fit:
- EC2 instances running your app (use an IAM instance role - no credentials stored anywhere)
- Lambda functions (same reason - the function's execution role provides credentials)
- ECS tasks with task roles
- Any service that can call the AWS API reliably

Not ideal:
- GUI tools like pgAdmin or DBeaver (harder to configure, token expires mid-session)
- Scripts that run infrequently and need to stay simple
- Environments without reliable AWS API access

---

## Secrets Manager for Credential Rotation

Not every application can use IAM auth. Legacy apps, third-party tools, and some frameworks expect a traditional username and password. For these cases, **AWS Secrets Manager** is the solution.

### What Secrets Manager Does

Secrets Manager stores your credentials in an encrypted vault. Applications fetch the secret at runtime using the AWS API. No credentials in config files.

```
  +------------------------------------------+
  |           Your Application               |
  |                                          |
  |  At startup:                             |
  |  secret = get_secret("prod/myapp/db")    |
  |  password = secret["password"]           |
  +-----------------+------------------------+
                    | API call (over HTTPS)
                    v
  +------------------------------------------+
  |         AWS Secrets Manager              |
  |                                          |
  |  Encrypted at rest with KMS              |
  |  Access controlled by IAM               |
  |  Full audit trail in CloudTrail          |
  +-----------------+------------------------+
                    | Returns JSON
                    v
  +------------------------------------------+
  |  { "username": "app_user",               |
  |    "password": "kX9m...rotated...",      |
  |    "host": "devops-lab-cluster...",      |
  |    "port": 5432 }                        |
  +------------------------------------------+
```

### Managed Rotation

Secrets Manager can rotate the password automatically on a schedule you set. When rotation runs:

1. Secrets Manager generates a new strong password
2. It calls a Lambda function (AWS provides one for Aurora/RDS)
3. The Lambda connects to the database and runs `ALTER ROLE ... PASSWORD ...`
4. The Lambda updates the secret value in Secrets Manager
5. Your application fetches the new password on the next connection

Your application never knows the password changed. It fetches the current secret from Secrets Manager every time it needs to connect.

### Rotation Strategies

| Strategy | How it works | Downtime? |
|----------|-------------|-----------|
| Single user | Rotates the password for one user | Brief (seconds) |
| Alternating users | Creates two users, alternates between them | None |

For zero-downtime rotation, use the alternating users strategy. Secrets Manager maintains two users (e.g., `app_user` and `app_user_clone`) and alternates which one is "current." While one password is being changed, the other is still valid.

### When to Use Secrets Manager vs IAM Auth

| Situation | Use |
|-----------|-----|
| EC2/Lambda/ECS apps you control | IAM auth (no password at all) |
| Legacy apps that need a username/password | Secrets Manager (rotated password) |
| Third-party tools (monitoring, BI) | Secrets Manager |
| Multiple teams needing different access | Secrets Manager with separate secrets per team |
| Maximum security, zero stored credentials | IAM auth |

You can use both together. Some roles use IAM auth, others use passwords stored in Secrets Manager. The key rule is: never hardcode a password in application code or config files.

---

## Least Privilege Applied to Databases

The principle of least privilege applies at multiple levels:

### IAM Level

- Do not give `rds:*` to application roles. Give only the specific actions needed.
- Scope IAM policies to specific resource ARNs, not `*`.
- Use separate IAM roles for different services.

```
  BAD:
  {
    "Effect": "Allow",
    "Action": "rds:*",
    "Resource": "*"
  }

  GOOD:
  {
    "Effect": "Allow",
    "Action": "rds-db:connect",
    "Resource": "arn:aws:rds-db:us-east-1:123456789012:dbuser:cluster-ABC/app_user"
  }
```

### Database Level

- Do not use the master user for application connections.
- Create a specific role per service with only the needed grants.
- Use group roles for scalable permission management.
- Set `ALTER DEFAULT PRIVILEGES` so new tables automatically get correct grants.

### Secrets Manager Level

- Scope IAM policies to the specific secret ARN, not all secrets.
- Give applications only `secretsmanager:GetSecretValue` - not `PutSecretValue` or `DeleteSecret`.
- Use separate secrets for different environments (dev, staging, production).

---

## Audit Trail

Every layer produces an audit trail:

| Layer | What gets logged | Where to find it |
|-------|-----------------|-----------------|
| IAM API calls | Who called what API, when | CloudTrail |
| IAM auth tokens | Token generation events | CloudTrail |
| Secrets Manager access | Who fetched which secret | CloudTrail |
| Database connections | Who connected, from where | PostgreSQL logs (CloudWatch) |
| Database queries | What SQL was executed | pgAudit extension logs |

CloudTrail captures all AWS API calls. If someone generates an IAM auth token, fetches a secret, or modifies a security group, CloudTrail logs it with the IAM identity, timestamp, and source IP.

PostgreSQL logs capture connection attempts and disconnections. The pgAudit extension captures the actual SQL statements executed. Together, these give you a complete picture of who did what.

---

## Summary

| Concept | What it does | When to use it |
|---------|-------------|---------------|
| IAM Users | Long-lived credentials for humans | CLI access for operators |
| IAM Roles | Temporary credentials for services | EC2, Lambda, ECS - always |
| IAM Policies | Define permissions | Always - attached to users or roles |
| IAM Auth | Replace password with 15-minute token | Application connections from AWS compute |
| Secrets Manager | Store and rotate passwords | Legacy apps, third-party tools |
| Least Privilege | Minimum permissions only | Every role, every policy, every time |

---

## What to Read Next

- **BUILD 03** - IAM Database Authentication (hands-on setup)
- **BUILD 04** - Secrets Manager Integration (store, rotate, retrieve)
- **BUILD 05** - Role-Based Access Control (PostgreSQL grants)
