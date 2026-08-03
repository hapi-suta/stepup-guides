# Phase 1: Provision Aurora Cluster

## Objective

Create an Aurora PostgreSQL cluster with proper networking. This draws on skills from Tier 0 (VPC fundamentals) and Tier 1 (provisioning).

## Requirements

You must create:

1. **VPC and networking** (or reuse existing lab VPC)
   - At least 2 private subnets in different AZs
   - A DB subnet group using those subnets
   - Security group allowing port 5432 from your IP only

2. **Aurora PostgreSQL cluster**
   - Engine: Aurora PostgreSQL 16.x (latest minor version)
   - Cluster identifier: use your `CAPSTONE_CLUSTER_ID` value
   - Instance class: db.t3.medium (minimum for Aurora)
   - Writer instance: `${CAPSTONE_CLUSTER_ID}-writer-1`

3. **Naming and tagging**
   - Tag all resources: `Environment=capstone`, `Project=suta-labs`

## Validation Criteria

- Cluster exists and status is "available"
- Writer instance exists and status is "available"
- Engine version is PostgreSQL 16.x

## Hints

- If you need a refresher on VPC setup, see T1 Build 01
- For Aurora cluster creation via CLI, see T4 Build 01
- Use `--engine aurora-postgresql --engine-version 16.6` (or latest 16.x)
- The writer instance name must match exactly for validate.sh to find it

## Reference Commands

These are NOT step-by-step instructions. Use them as a starting point:

```bash
# Create subnet group
aws rds create-db-subnet-group ...

# Create Aurora cluster
aws rds create-db-cluster ...

# Create writer instance
aws rds create-db-instance ...
```

If you get stuck, review: T1 Build 01-03, T4 Build 01.
