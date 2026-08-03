# USE 04: Terraform Refactoring Exercise

**Module 08: CI/CD for Database Changes**
**Track:** DevOps DBA Training
**Cluster:** devops-lab-cluster

---

## Objective

Refactor a monolithic Terraform configuration into modules, add a new Aurora reader instance, and ensure Flyway migrations still work after infrastructure changes. This exercise tests your ability to modify infrastructure and schema together.

---

## Setup

Use the Terraform configuration from BUILD 06 as your starting point.

**On your Mac terminal:**

```bash
cp -r ~/dba-labs/iac-pipeline ~/dba-labs/use-terraform-refactor
```

```bash
cd ~/dba-labs/use-terraform-refactor
```

---

## Task 1: Extract an Aurora Module

Take the Aurora resources from `terraform/main.tf` and extract them into a reusable module.

### Requirements

Create the following structure:

```
terraform/
  main.tf              # Root module - calls the Aurora module
  variables.tf         # Root variables
  outputs.tf           # Root outputs
  modules/
    aurora/
      main.tf          # Aurora cluster + instances
      variables.tf     # Module inputs
      outputs.tf       # Module outputs
```

The Aurora module should accept these inputs:

| Variable | Type | Description |
|----------|------|-------------|
| `cluster_identifier` | string | Unique name for the cluster |
| `engine_version` | string | Aurora PostgreSQL version |
| `database_name` | string | Default database name |
| `master_username` | string | Master user |
| `master_password` | string (sensitive) | Master password |
| `instance_class` | string | Instance size |
| `instance_count` | number | Number of instances (writer + readers) |
| `vpc_security_group_ids` | list(string) | Security groups |
| `db_subnet_group_name` | string | Subnet group |
| `backup_retention_period` | number | Backup retention days |
| `backtrack_window` | number | Backtrack window in seconds |

The module should output:

| Output | Description |
|--------|-------------|
| `cluster_endpoint` | Writer endpoint |
| `reader_endpoint` | Reader endpoint |
| `cluster_port` | Port number |
| `database_name` | Database name |

### Acceptance Criteria

<details>
<summary>Click to expand</summary>

- [ ] Aurora resources moved to `modules/aurora/`
- [ ] Root `main.tf` calls the module with `module "aurora" { ... }`
- [ ] All variables are parameterized (no hardcoded values in the module)
- [ ] `terraform validate` passes
- [ ] `terraform plan` shows no changes (refactoring should not alter infrastructure)

</details>

---

## Task 2: Add a Reader Instance

Modify the Aurora module to support multiple instances (1 writer + N readers).

### Requirements

1. Change the module to accept `instance_count` (default: 1)
2. The first instance is the writer, additional instances are readers
3. Reader instances should use a smaller instance class (`db.r6g.medium` vs `db.r6g.large`)

### Acceptance Criteria

<details>
<summary>Click to expand</summary>

- [ ] Setting `instance_count = 2` creates one writer and one reader
- [ ] Writer uses `db.r6g.large`, reader uses `db.r6g.medium`
- [ ] Reader instance has the tag `Role = reader`
- [ ] `terraform plan` shows only the new reader instance being added

</details>

---

## Task 3: Add a Migration for Read Replicas

Write a Flyway migration that creates a materialized view optimized for the reader endpoint.

### Requirements

Create `migrations/sql/V3__create_analytics_views.sql`:

1. Create a materialized view `mv_daily_revenue` that aggregates order data by day
2. Create a unique index on the materialized view for concurrent refresh
3. Create a function `refresh_analytics()` that refreshes the materialized view
4. The materialized view should be safe to query on the reader endpoint

### Key Points

- Materialized views are replicated to reader instances automatically in Aurora
- The refresh must run on the writer endpoint
- Use `CONCURRENTLY` for the refresh (requires a unique index on the materialized view)

### Acceptance Criteria

<details>
<summary>Click to expand</summary>

- [ ] Materialized view created with proper aggregation
- [ ] Unique index exists on the materialized view
- [ ] Refresh function uses `REFRESH MATERIALIZED VIEW CONCURRENTLY`
- [ ] Migration includes `SET lock_timeout = '5s'`
- [ ] `flyway migrate` applies cleanly

</details>

---

## Task 4: Update the Pipeline

Modify `.github/workflows/infra-and-schema.yml` to:

1. Run `terraform plan` and show the planned changes in the PR
2. After infrastructure apply, wait 60 seconds for Aurora instances to be ready
3. Run migrations against the writer endpoint (not the reader)

### Acceptance Criteria

<details>
<summary>Click to expand</summary>

- [ ] Terraform plan output is visible in the workflow logs
- [ ] A wait step exists between infrastructure apply and migration
- [ ] Flyway runs against the writer endpoint specifically
- [ ] The pipeline still follows: test -> plan -> apply -> migrate

</details>

---

## Verification

### Check Terraform

```bash
cd terraform
```

```bash
terraform validate
```

Expected output:
```
Success! The configuration is valid.
```

```bash
terraform plan
```

Review the plan output. A pure refactoring should show no changes. Adding a reader instance should show only the new instance.

### Check Migrations

```bash
cd ~/dba-labs/use-terraform-refactor/migrations
```

```bash
flyway -configFiles=flyway-dev.conf info
```

```bash
flyway -configFiles=flyway-dev.conf migrate
```

```bash
flyway -configFiles=flyway-dev.conf validate
```

---

## Hints

<details>
<summary>Click if you are stuck on the module call</summary>

```hcl
# terraform/main.tf
module "aurora" {
  source = "./modules/aurora"

  cluster_identifier     = var.cluster_identifier
  engine_version         = var.engine_version
  database_name          = var.database_name
  master_username        = var.master_username
  master_password        = var.master_password
  instance_class         = var.instance_class
  instance_count         = 2
  vpc_security_group_ids = var.vpc_security_group_ids
  db_subnet_group_name   = var.db_subnet_group_name
  backup_retention_period = 7
  backtrack_window       = 86400
}
```

</details>

<details>
<summary>Click if you are stuck on multiple instances</summary>

```hcl
resource "aws_rds_cluster_instance" "instances" {
  count = var.instance_count

  identifier         = "${var.cluster_identifier}-${count.index == 0 ? "writer" : "reader-${count.index}"}"
  cluster_identifier = aws_rds_cluster.aurora.id
  instance_class     = count.index == 0 ? var.instance_class : "db.r6g.medium"
  engine             = aws_rds_cluster.aurora.engine
  engine_version     = aws_rds_cluster.aurora.engine_version

  tags = {
    Role = count.index == 0 ? "writer" : "reader"
  }
}
```

</details>

<details>
<summary>Click if you are stuck on the materialized view</summary>

```sql
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_daily_revenue AS
SELECT
    DATE(o.ordered_at) AS order_date,
    COUNT(o.order_id)  AS order_count,
    SUM(o.total_amount) AS daily_revenue
FROM orders o
WHERE o.status != 'cancelled'
GROUP BY DATE(o.ordered_at)
ORDER BY order_date;

CREATE UNIQUE INDEX IF NOT EXISTS idx_mv_daily_revenue_date
    ON mv_daily_revenue (order_date);

CREATE OR REPLACE FUNCTION refresh_analytics()
RETURNS void AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_daily_revenue;
END;
$$ LANGUAGE plpgsql;
```

</details>

---

## Clean Up

If you created real AWS resources, destroy them:

```bash
cd terraform
```

```bash
terraform destroy
```

Type `yes` when prompted.
