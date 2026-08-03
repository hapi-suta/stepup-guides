# USE Exercise 01: Full Cost Audit of an RDS Fleet

**Objective:** Perform a comprehensive cost audit of your RDS/Aurora fleet and produce a prioritized savings recommendation report.
**Time:** 30-45 minutes
**Level:** Expert
**infra_required:** true - Requires a live AWS account with RDS instances. Cost Explorer must be enabled.
**Prerequisites:** Build Guide 01 completed.

---

## Context

You have been asked by [COMPANY]'s engineering leadership to perform a full cost audit of the RDS fleet before the Q3 budget review. You have 45 minutes to produce a prioritized recommendations report with estimated monthly savings.

---

## Part 1: Inventory the Fleet

Start with a complete picture of what you are working with.

**Task 1.1:** List all RDS instances and Aurora clusters in your account with their instance class, engine version, storage type, Multi-AZ status, and whether they have Reserved Instance coverage.

Use the CLI commands from Build Guide 01 to gather:
- All RDS instances: `aws rds describe-db-instances`
- All Aurora clusters: `aws rds describe-db-clusters`
- Existing RIs: `aws rds describe-reserved-db-instances`

Create a table with columns:
```
Identifier | Type | Engine | Class | Multi-AZ | Storage Type | RI Coverage | Est. Monthly Cost
```

**Task 1.2:** Identify instances by processor family.

Separate your inventory into:
- Intel-based (`m5`, `r5`, `m6i`, `r6i`)
- Graviton-based (`m6g`, `r6g`, `m7g`, `r7g`)
- Any other families

**Deliverable:** A complete fleet inventory table. Mark any instance not matching your organization's approved instance families.

---

## Part 2: Storage Cost Analysis

**Task 2.1:** For each Aurora cluster, determine whether it uses Standard or I/O-Optimized storage. Run:

```bash
aws rds describe-db-clusters \
  --query 'DBClusters[?Engine==`aurora-postgresql`].[DBClusterIdentifier,StorageType,AllocatedStorage]' \
  --output table \
  --region [REGION]
```

**Task 2.2:** Open Cost Explorer and find the `Aurora:StorageIOUsage` line item for the last 30 days.

For each Aurora cluster on Standard storage:
- Find its I/O charge in Cost Explorer
- Calculate what percentage of total Aurora spend is I/O
- If I/O > 25% of Aurora spend, flag it as an I/O-Optimized candidate

**Deliverable:** For each Aurora cluster - current storage mode, I/O charge, percentage of Aurora spend, and recommendation (stay on Standard or switch to I/O-Optimized).

---

## Part 3: Reserved Instance Gap Analysis

**Task 3.1:** Compare your RI coverage against your On-Demand instances.

For each On-Demand instance not covered by an RI:
- Calculate its monthly On-Demand cost (use `aws rds describe-reserved-db-instances-offerings`)
- Calculate 1-year All Upfront RI cost
- Calculate annual savings

**Task 3.2:** For existing RIs, check expiration dates:

```bash
aws rds describe-reserved-db-instances \
  --query 'ReservedDBInstances[*].[ReservedDBInstanceId,DBInstanceClass,State,StartTime,Duration,FixedPrice]' \
  --output table \
  --region [REGION]
```

Flag any RI expiring within 90 days for renewal review.

**Deliverable:** RI gap analysis - which On-Demand instances should be reserved, estimated annual savings per instance, and any expiring RIs requiring renewal.

---

## Part 4: Right-Sizing Analysis

**Task 4.1:** Retrieve Cost Explorer right-sizing recommendations for RDS:

```bash
aws ce get-rightsizing-recommendation \
  --service "AmazonRDS" \
  --region us-east-1
```

**Task 4.2:** For each right-sizing recommendation, validate it by checking CloudWatch:
- Average CPU utilization over 30 days
- Maximum CPU utilization over 30 days
- Average `DatabaseConnections` over 30 days
- `FreeableMemory` minimum over 30 days

An instance is a valid downsize candidate only if:
- Average CPU < 30% AND
- Maximum CPU < 60% AND
- Connections are well below the smaller instance's max_connections

**Deliverable:** Validated list of right-sizing candidates with CPU, memory, and connection data supporting each recommendation.

---

## Part 5: Graviton Migration Candidates

**Task 5.1:** For each Intel-based instance in your inventory, assess Graviton migration viability:

| Check | Question |
|-------|----------|
| Extension compatibility | Does the instance use any custom compiled extensions? |
| Migration method | Can Blue/Green be used, or is snapshot/restore required? |
| Downtime tolerance | Can the application tolerate a brief switchover? |
| Performance risk | Has this instance class been tested on Graviton in staging? |

**Task 5.2:** Calculate the monthly savings for each Graviton migration candidate:

- Find On-Demand price for current Intel class
- Find On-Demand price for equivalent Graviton class
- Calculate: `(Intel price - Graviton price) x 730 hours` = monthly savings per instance

**Deliverable:** Prioritized list of Graviton migration candidates, expected monthly savings, and migration method.

---

## Deliverable: Prioritized Recommendations Report

Produce a one-page summary structured as follows:

```
RDS FLEET COST AUDIT - [DATE]
Auditor: [YOUR NAME]
Account: [ACCOUNT-ID]
Region: [REGION]

EXECUTIVE SUMMARY
Total estimated monthly RDS spend: $[AMOUNT]
Identified savings opportunities: $[AMOUNT]/month ($[AMOUNT]/year)

PRIORITY 1 - IMMEDIATE ACTION (implement within 30 days)
[Item] - Expected saving: $[AMOUNT]/month
Rationale: [1 sentence]

PRIORITY 2 - PLAN FOR NEXT QUARTER
[Item] - Expected saving: $[AMOUNT]/month
Rationale: [1 sentence]

PRIORITY 3 - LONG-TERM (roadmap item)
[Item] - Expected saving: $[AMOUNT]/month
Rationale: [1 sentence]

RISKS AND CAVEATS
[Any risks associated with recommendations]

ASSUMPTIONS
[List any assumptions made in cost calculations]
```

---

## Reflection Questions

Answer these in writing. They will be discussed in the group session.

1. Which optimization lever - storage pricing, RIs, Graviton, or right-sizing - offered the largest opportunity in your specific fleet? Why do you think that is?

2. One of your recommendations was to downsize a `db.r6g.4xlarge` to `db.r6g.2xlarge` based on Cost Explorer data. Your manager asks: "What could go wrong if we downsize this?" What do you tell them?

3. You identified three instances running Intel (`r6i`) that are candidates for Graviton migration. The application team says "we can't test in staging because staging doesn't exist for this service." How do you proceed?

4. Cost Explorer shows that one Aurora cluster spent $1,200 on I/O charges last month (45% of total Aurora spend for that cluster). The cluster is 300GB. Calculate whether switching to I/O-Optimized is cost-effective. Show your math.
