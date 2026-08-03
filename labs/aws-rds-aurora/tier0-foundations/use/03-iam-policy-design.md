# Exercise 03: IAM Policy Design

**Duration:** 25 minutes
**Objective:** Design least-privilege IAM policies for 4 common database team personas and identify security problems in an existing overly permissive policy.
**Prerequisites:** Build guide 03 (IAM and Access Control) complete

---

## Background

You have just joined [COMPANY] as the lead DBA. The team currently has one IAM policy that everyone uses - and it is a mess. Your job is to design role-specific IAM policies that follow least-privilege principles.

The company runs RDS PostgreSQL and Aurora PostgreSQL clusters in a single AWS account across two regions (us-east-1 and us-west-2). There are 8 RDS/Aurora instances total.

---

## Task 1: Design Policies for 4 Personas

For each persona below, describe the IAM permissions they need and write the core IAM policy JSON. You do not need to be exhaustive - focus on the key `Action` statements that define this role's access level.

Use `"Resource": "*"` where appropriate and add resource ARN constraints where it matters for security.

---

### Persona 1 - Junior DBA

**Who they are:** New hire, 0-2 years experience. Works on queries, performance analysis, and documentation. Should never be able to make infrastructure changes.

**What they need to do:**
- View RDS/Aurora instance details (engine version, parameter groups, endpoints)
- View CloudWatch metrics for RDS instances
- View parameter groups and option groups (read-only)
- View automated backup and snapshot lists
- Cannot start, stop, modify, delete, or create anything

**Write the IAM policy JSON for this persona.**

---

### Persona 2 - Senior DBA

**Who they are:** Experienced DBA who manages day-to-day database operations. Needs full operational control but should not be able to delete production instances or modify IAM.

**What they need to do:**
- Everything Persona 1 can do
- Create, modify, and delete parameter groups
- Create and delete manual snapshots
- Restore instances from snapshots
- Modify instance class, storage, and configuration
- Start and stop instances
- Add and remove read replicas
- View and modify maintenance windows
- Cannot delete production instances (enforce via tags - instances tagged `env=production` are off limits)

**Write the IAM policy JSON for this persona.**

---

### Persona 3 - Application Team

**Who they are:** Developers and application services that need to connect to databases using IAM database authentication. They should have zero ability to view or change infrastructure.

**What they need to do:**
- Generate IAM auth tokens to connect to RDS/Aurora instances
- Describe their specific DB instances (to get the endpoint)
- No snapshot access, no parameter group access, no ability to modify anything

**Write the IAM policy JSON for this persona.**

---

### Persona 4 - On-Call Engineer

**Who they are:** Ops engineers who handle incidents. They need read-only access most of the time but must be able to trigger failover in an emergency. This is a sensitive role.

**What they need to do:**
- Everything Persona 1 can do
- Trigger Multi-AZ failover (RebootDBInstance with force failover flag)
- Trigger Aurora cluster failover
- Start instances that have been stopped (e.g., if a dev instance was accidentally stopped)
- Cannot modify configuration, create or delete resources

**Write the IAM policy JSON for this persona.**

---

## Task 2: What Is Wrong with This Policy?

The current policy used by everyone at [COMPANY] is shown below. Identify every security problem, explain the risk of each, and state what it should be replaced with.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "rds:*",
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": "iam:*",
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": "secretsmanager:*",
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": "cloudwatch:*",
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": "ec2:*",
      "Resource": "*"
    }
  ]
}
}
```

---

## Answers

### Persona 1 - Junior DBA Policy

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "RDSReadOnly",
      "Effect": "Allow",
      "Action": [
        "rds:Describe*",
        "rds:List*",
        "rds:DownloadDBLogFilePortion"
      ],
      "Resource": "*"
    },
    {
      "Sid": "CloudWatchRDSMetrics",
      "Effect": "Allow",
      "Action": [
        "cloudwatch:GetMetricData",
        "cloudwatch:GetMetricStatistics",
        "cloudwatch:ListMetrics",
        "cloudwatch:DescribeAlarms"
      ],
      "Resource": "*"
    },
    {
      "Sid": "LogsReadOnly",
      "Effect": "Allow",
      "Action": [
        "logs:Describe*",
        "logs:Get*",
        "logs:FilterLogEvents"
      ],
      "Resource": "*"
    }
  ]
}
```

**Explanation:**
- `rds:Describe*` covers all the Describe calls (DescribeDBInstances, DescribeDBParameterGroups, DescribeDBSnapshots, etc.) with one wildcard.
- `rds:List*` covers ListTagsForResource and similar listing operations.
- `rds:DownloadDBLogFilePortion` allows downloading log files for query analysis - read-only but useful for a DBA.
- CloudWatch permissions are scoped to read-only metric operations. No `PutMetricAlarm` or `DeleteAlarms`.
- No `rds:Create*`, `rds:Modify*`, `rds:Delete*`, or `rds:Reboot*` anywhere in this policy.

---

### Persona 2 - Senior DBA Policy

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "RDSReadOnly",
      "Effect": "Allow",
      "Action": [
        "rds:Describe*",
        "rds:List*",
        "rds:DownloadDBLogFilePortion"
      ],
      "Resource": "*"
    },
    {
      "Sid": "RDSOperational",
      "Effect": "Allow",
      "Action": [
        "rds:CreateDBParameterGroup",
        "rds:ModifyDBParameterGroup",
        "rds:DeleteDBParameterGroup",
        "rds:ResetDBParameterGroup",
        "rds:CreateDBClusterParameterGroup",
        "rds:ModifyDBClusterParameterGroup",
        "rds:DeleteDBClusterParameterGroup",
        "rds:CreateDBSnapshot",
        "rds:DeleteDBSnapshot",
        "rds:CreateDBClusterSnapshot",
        "rds:DeleteDBClusterSnapshot",
        "rds:RestoreDBInstanceFromDBSnapshot",
        "rds:RestoreDBClusterFromSnapshot",
        "rds:RestoreDBInstanceToPointInTime",
        "rds:ModifyDBInstance",
        "rds:ModifyDBCluster",
        "rds:StartDBInstance",
        "rds:StopDBInstance",
        "rds:StartDBCluster",
        "rds:StopDBCluster",
        "rds:RebootDBInstance",
        "rds:CreateDBInstanceReadReplica",
        "rds:DeleteDBInstanceAutomatedBackup",
        "rds:AddTagsToResource",
        "rds:RemoveTagsFromResource"
      ],
      "Resource": "*",
      "Condition": {
        "StringNotEquals": {
          "rds:db-tag/env": "production"
        }
      }
    },
    {
      "Sid": "AllowModifyProductionReadOnly",
      "Effect": "Allow",
      "Action": [
        "rds:ModifyDBInstance",
        "rds:ModifyDBCluster"
      ],
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "rds:db-tag/env": "production"
        },
        "BoolIfExists": {
          "rds:MultiAZ": "true"
        }
      }
    },
    {
      "Sid": "DenyDeleteProduction",
      "Effect": "Deny",
      "Action": [
        "rds:DeleteDBInstance",
        "rds:DeleteDBCluster"
      ],
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "rds:db-tag/env": "production"
        }
      }
    },
    {
      "Sid": "CloudWatchFull",
      "Effect": "Allow",
      "Action": [
        "cloudwatch:*"
      ],
      "Resource": "*"
    }
  ]
}
```

**Explanation:**
- The tag condition `rds:db-tag/env: production` on the Deny statement prevents deletion of anything tagged as production. Note that tag-based conditions on RDS use the `rds:db-tag/` prefix.
- A separate explicit `Deny` is used for delete operations on production. Explicit Deny always overrides Allow, so this is a hard stop regardless of other policies the user might have.
- `rds:DeleteDBSnapshot` is allowed on non-production - senior DBAs need to clean up dev/staging snapshots.
- Tag conditions in IAM are not a perfect security control on their own. Pair this with SCPs (Service Control Policies) at the AWS Organizations level for production environments.

---

### Persona 3 - Application Team Policy

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "RDSIAMAuth",
      "Effect": "Allow",
      "Action": [
        "rds-db:connect"
      ],
      "Resource": [
        "arn:aws:rds-db:us-east-1:123456789012:dbuser:*/app_user",
        "arn:aws:rds-db:us-west-2:123456789012:dbuser:*/app_user"
      ]
    },
    {
      "Sid": "DescribeOwnInstances",
      "Effect": "Allow",
      "Action": [
        "rds:DescribeDBInstances",
        "rds:DescribeDBClusters"
      ],
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "rds:db-tag/team": "app-team"
        }
      }
    }
  ]
}
```

**Explanation:**
- `rds-db:connect` is the permission required for IAM database authentication. Note the service prefix is `rds-db`, not `rds`. This is a common mistake.
- The resource ARN format for `rds-db:connect` is: `arn:aws:rds-db:{region}:{account}:dbuser:{db-resource-id}/{db-username}`. The `*` wildcard for the db-resource-id allows connection to any instance, but only as the `app_user` database user.
- In practice, tighten the resource ARN to specific instance resource IDs rather than using `*`. The DB resource ID looks like `db-ABCDEF1234567890`.
- Replace `123456789012` with the actual AWS account ID.
- The application team cannot view snapshots, parameter groups, or any other infrastructure details.

---

### Persona 4 - On-Call Engineer Policy

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "RDSReadOnly",
      "Effect": "Allow",
      "Action": [
        "rds:Describe*",
        "rds:List*",
        "rds:DownloadDBLogFilePortion"
      ],
      "Resource": "*"
    },
    {
      "Sid": "CloudWatchReadOnly",
      "Effect": "Allow",
      "Action": [
        "cloudwatch:GetMetricData",
        "cloudwatch:GetMetricStatistics",
        "cloudwatch:ListMetrics",
        "cloudwatch:DescribeAlarms"
      ],
      "Resource": "*"
    },
    {
      "Sid": "FailoverAndRestart",
      "Effect": "Allow",
      "Action": [
        "rds:RebootDBInstance",
        "rds:FailoverDBCluster",
        "rds:StartDBInstance",
        "rds:StartDBCluster"
      ],
      "Resource": "*"
    }
  ]
}
```

**Explanation:**
- `rds:RebootDBInstance` with the `ForceFailover` parameter triggers Multi-AZ failover. The IAM permission is `RebootDBInstance` - the force-failover behavior is a parameter in the API call, not a separate permission.
- `rds:FailoverDBCluster` handles Aurora cluster failover specifically.
- `rds:StartDBInstance` and `rds:StartDBCluster` are included so on-call can restart accidentally stopped dev/staging instances.
- There is no `rds:StopDBInstance` here - on-call should not stop running instances without authorization.
- No `rds:Modify*` permissions. On-call can restore service (failover, restart) but cannot change configuration.
- For higher-security environments, consider using IAM Roles Anywhere or a break-glass role that requires MFA to assume, and limit the time window the role can be used.

---

## Task 2 Answer - Problems with the Current Policy

### Problem 1: `"Action": "rds:*"` with no restrictions
**Risk:** Anyone with this policy can delete any RDS instance, delete any snapshot, modify any parameter group, or disable deletion protection. A junior DBA, a compromised account, or a misconfigured automation script can destroy production databases.

**Fix:** Replace with action-specific permissions per role. Use explicit `Deny` statements for destructive actions on production resources.

---

### Problem 2: `"Action": "iam:*"`
**Risk:** This is privilege escalation. Any user with `iam:*` can create new IAM users, create new IAM policies, and attach those policies to themselves or others - including `AdministratorAccess`. This effectively makes every person with this policy a super-admin. One compromised account compromises the entire AWS account.

**Fix:** Remove `iam:*` entirely from DBA policies. IAM management should be handled by a dedicated IAM administrator role, not the DBA team. If DBAs need to view IAM roles (e.g., to check what role an RDS instance is using), grant `iam:GetRole` and `iam:ListRoles` only.

---

### Problem 3: `"Action": "secretsmanager:*"`
**Risk:** With `secretsmanager:*`, anyone can read every secret in the account (not just database passwords), modify secret values, or delete secrets. This exposes API keys, third-party credentials, and any other sensitive values stored in Secrets Manager. Deleting a secret used by an application causes an immediate outage.

**Fix:** Scope Secrets Manager access to specific secret ARNs that belong to the DBA team's databases. Use resource-based policies on the secrets themselves as an additional layer of control.

---

### Problem 4: `"Action": "cloudwatch:*"`
**Risk:** `cloudwatch:*` includes the ability to delete alarms, delete dashboards, and modify alert thresholds. Someone could silence production alerts, delete the disk-space alarm, or tamper with monitoring in ways that hide problems.

**Fix:** Use `cloudwatch:Get*`, `cloudwatch:List*`, `cloudwatch:Describe*` for read-only access. Only grant `cloudwatch:PutMetricAlarm` and `cloudwatch:DeleteAlarms` to roles that actually manage alerting.

---

### Problem 5: `"Action": "ec2:*"`
**Risk:** RDS runs on EC2 VPC infrastructure, but `ec2:*` goes far beyond what any DBA needs. This allows: creating and terminating EC2 instances, modifying security groups (including the ones protecting RDS), changing route tables, creating VPC peering connections, and allocating Elastic IPs. Any of these changes can expose databases to the internet or take down production networking.

**Fix:** DBAs typically only need `ec2:DescribeVpcs`, `ec2:DescribeSubnets`, `ec2:DescribeSecurityGroups`, and `ec2:DescribeAvailabilityZones` to understand the network topology their databases live in. Remove the rest.

---

### Problem 6: `"Resource": "*"` on every statement
**Risk:** Combined with broad Action wildcards, this means every permission applies to every resource in every region in the account. There is no resource-level isolation between production and development, between regions, or between database instances owned by different teams.

**Fix:** Use resource ARNs where the service supports resource-level permissions. For RDS, ARNs look like `arn:aws:rds:us-east-1:123456789012:db:my-db-name`. Use tag-based conditions (`rds:db-tag/env: production`) as an additional guard.

---

## Summary of Key Takeaways

- Least privilege means defining exactly what each role needs to do - nothing more. Start with no permissions and add only what is required.
- The difference between `rds:*` and a specific action list is the difference between a skeleton key and a door key. Never give skeleton keys to operational roles.
- `iam:*` is the most dangerous permission in AWS. It enables privilege escalation to full account administrator. Never include it in any operational policy.
- `rds-db:connect` (with the `rds-db` prefix) is the permission for IAM database authentication. It is separate from `rds:*` and often overlooked.
- Explicit `Deny` statements are the reliable way to protect production resources. Unlike conditions on `Allow`, an explicit `Deny` cannot be overridden by any other policy.
- Tag-based access control (TBAC) requires that your tagging strategy is enforced. Use SCPs to prevent tag removal from production resources.
- Review IAM policies quarterly. Permissions accumulate over time as team members request access for specific tasks and nobody removes the access afterward.
