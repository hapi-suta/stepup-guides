# BUILD 02 - Option Groups

**Time:** 20 minutes
**Goal:** Understand what option groups are, why they matter less for PostgreSQL, and create one through Console and CLI.

---

## Prerequisites

- AWS CLI configured (`aws configure`)
- RDS PostgreSQL instance running

---

## What Are Option Groups?

Option groups add features to a database engine that are not part of the core engine. They were designed for engines like Oracle and SQL Server where extra features (like Oracle Application Express, SQL Server Transparent Data Encryption) must be explicitly enabled.

For **PostgreSQL on RDS**, option groups have almost no practical use. PostgreSQL handles additional features through **extensions** (`CREATE EXTENSION`), not option groups.

> **Concept:** Think of option groups as a configuration container for engine-level plugins. PostgreSQL uses a different mechanism (extensions) for the same purpose. You will still see option groups when provisioning RDS PostgreSQL instances - they just don't do much.

### Option Groups vs Extensions (PostgreSQL)

| | Option Groups | Extensions |
|---|---|---|
| Used for | Engine-level plugins | Database-level add-ons |
| PostgreSQL use | Minimal | Primary method |
| Oracle/SQL Server use | Heavy | N/A |
| Applied at | Instance level | Database level |
| Activation | Attach to instance | `CREATE EXTENSION` |

### What Options Exist for PostgreSQL?

As of PostgreSQL 16 on RDS, there are no meaningful options available for PostgreSQL in option groups. AWS does not offer PostgreSQL-specific option group features the way they do for Oracle or SQL Server.

You can confirm this by looking at what options are available when you try to add one to a PostgreSQL option group - the list will be empty or contain only deprecated items.

---

## Part 1 - Create an Option Group

Even though PostgreSQL option groups have no useful options to add, you need to know how to create and manage them. Some automation scripts and IaC templates require an explicit option group reference.

### Console Steps

1. Open the AWS Console and go to **RDS**.
2. In the left sidebar, click **Option groups**.
3. Click the **Create group** button.
4. Fill in the form:
   - **Name:** `tier3-options-pg16`
   - **Description:** `Option group for tier3 PostgreSQL labs`
   - **Engine:** `postgres`
   - **Major engine version:** `16`
5. Click **Create**.

You will be redirected to the option group detail page. The **Options** section will be empty - this is expected for PostgreSQL.

---

### CLI Steps

**Step 1 - Create the option group.**

```bash
aws rds create-option-group \
  --option-group-name tier3-options-pg16 \
  --engine-name postgres \
  --major-engine-version 16 \
  --option-group-description "Option group for tier3 PostgreSQL labs"
```

The `--engine-name` flag specifies the database engine. For RDS PostgreSQL, this is `postgres`. The `--major-engine-version` flag is the major PostgreSQL version number only (not the minor version).

Expected output (yours will differ):
```
{
    "OptionGroup": {
        "OptionGroupName": "tier3-options-pg16",
        "OptionGroupDescription": "Option group for tier3 PostgreSQL labs",
        "EngineName": "postgres",
        "MajorEngineVersion": "16",
        "Options": [],
        "AllowsVpcAndNonVpcInstanceMemberships": false,
        "OptionGroupArn": "arn:aws:rds:us-east-1:123456789012:og:tier3-options-pg16"
    }
}
```

Notice `"Options": []` - the options list is empty because PostgreSQL has no engine-level options to add.

**Step 2 - List available options for PostgreSQL (to confirm the empty list).**

```bash
aws rds describe-option-group-options \
  --engine-name postgres \
  --major-engine-version 16 \
  --query 'OptionGroupOptions[*].Name' \
  --output table
```

Expected output (yours will differ):
```
--------------------
|DescribeOptionGroupOptions|
+--------------------+
(no options returned)
```

This confirms there are no options to add for PostgreSQL 16.

---

## Part 2 - Attach an Option Group to an Instance

Even with an empty option group, you can attach it to an instance. Some deployment scripts require this step.

### Console Steps

1. In RDS console, click **Databases**.
2. Click on your instance name.
3. Click **Modify**.
4. Scroll to **Additional configuration**.
5. Under **Option group**, choose `tier3-options-pg16`.
6. Click **Continue** then **Modify DB instance**.

### CLI Steps

```bash
aws rds modify-db-instance \
  --db-instance-identifier [YOUR-INSTANCE-ID] \
  --option-group-name tier3-options-pg16 \
  --apply-immediately
```

Replace `[YOUR-INSTANCE-ID]` with your actual instance identifier.

---

## Part 3 - Describe the Option Group

**Verify the option group is attached to your instance:**

```bash
aws rds describe-db-instances \
  --db-instance-identifier [YOUR-INSTANCE-ID] \
  --query 'DBInstances[0].OptionGroupMemberships'
```

Expected output (yours will differ):
```
[
    {
        "OptionGroupName": "tier3-options-pg16",
        "Status": "in-sync"
    }
]
```

---

## When Option Groups Actually Matter

Option groups are important when working with:
- **Oracle RDS** - features like Oracle Application Express (APEX), Oracle Statspack, Oracle Enterprise Manager
- **SQL Server RDS** - features like Transparent Data Encryption (TDE), SQL Server Agent
- **MySQL RDS** - some minor options like memcached

If you ever move to Oracle or SQL Server on RDS, option groups become a central configuration concern.

---

## Cleanup (Optional)

If you don't need this option group attached:

```bash
# Revert to the default option group
aws rds modify-db-instance \
  --db-instance-identifier [YOUR-INSTANCE-ID] \
  --option-group-name default:postgres-16 \
  --apply-immediately
```

---

## Summary

| Task | Result |
|---|---|
| Created option group | `aws rds create-option-group` |
| Listed available options | Empty list - expected for PostgreSQL |
| Attached to instance | `aws rds modify-db-instance --option-group-name` |
| Confirmed attachment | `OptionGroupMemberships[0].Status: in-sync` |

---

## Key Takeaway

For PostgreSQL on RDS, option groups are largely ceremonial. You create one, attach it, and forget about it. The real configuration work happens in **parameter groups** (BUILD 01) and **extensions** (BUILD 03).

---

## Next Steps

- [BUILD 03 - Core Extensions](03-extensions-core.md)
