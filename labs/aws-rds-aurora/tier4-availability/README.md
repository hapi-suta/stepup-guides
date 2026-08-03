# Tier 4 - Availability and Replication
## AWS RDS and Aurora PostgreSQL - Intermediate Level

This tier covers the availability and replication features of AWS RDS and Amazon Aurora. You will learn how to design, build, and test highly available database architectures using AWS-native tools.

---

## Who This Is For

You should already be comfortable with:
- Launching RDS and Aurora clusters (Tier 1-3)
- Connecting to databases from an EC2 instance or Cloud Shell
- Basic PostgreSQL queries
- AWS Console navigation and basic CLI usage

---

## What You Will Build

| Lab | Topic | Time |
|-----|-------|------|
| BUILD 01 | RDS Multi-AZ - Enable and test failover | 40 min |
| BUILD 02 | RDS Read Replicas - Create, monitor lag, promote | 45 min |
| BUILD 03 | Aurora Storage Architecture - Observe and compare | 30 min |
| BUILD 04 | Aurora Replicas - Add, prioritize, test failover | 40 min |
| BUILD 05 | Aurora Endpoints - All 4 types, custom endpoints | 30 min |
| BUILD 06 | Aurora Global Database - Cross-region, failover | 50 min |
| BUILD 07 | Aurora Serverless v2 - Scale, observe, cost | 40 min |

---

## USE Exercises (Apply What You Learned)

| Exercise | Topic |
|----------|-------|
| USE 01 | Design an HA architecture for given requirements |
| USE 02 | Manage read replicas under load |
| USE 03 | Plan and execute a failover test |
| USE 04 | Route application traffic to correct endpoints |
| USE 05 | Right-size Serverless v2 ACU ranges |

---

## SURVIVE Scenarios (Break Things on Purpose)

| Scenario | What Breaks |
|----------|-------------|
| SURVIVE 01 | Unexpected Multi-AZ failover - app drops connections |
| SURVIVE 02 | Replica lag spikes to minutes - stale reads |
| SURVIVE 03 | Aurora writer fails - observe automatic promotion |
| SURVIVE 04 | Primary region "fails" - Global Database failover |
| SURVIVE 05 | Serverless ACU maxed - queries queuing |

---

## Concepts Covered

All seven topics are explained with ASCII diagrams in `concepts/availability.md`:

- T4.1 RDS Multi-AZ Instance vs Multi-AZ DB Cluster
- T4.2 RDS Read Replicas
- T4.3 Aurora Storage Architecture
- T4.4 Aurora Replicas and Failover Tiers
- T4.5 Aurora Endpoints Deep Dive
- T4.6 Aurora Global Database
- T4.7 Aurora Serverless v2

---

## Prerequisites

Before starting BUILD 01, you need:

1. An AWS account with AdministratorAccess (or a scoped IAM role with RDS full access)
2. AWS CLI v2 installed and configured with your credentials
3. A VPC with at least 2 subnets in different Availability Zones
4. A DB subnet group covering those subnets
5. A security group that allows PostgreSQL (port 5432) from your IP

If you completed Tier 3, you already have all of this.

---

## Cost Warning

These labs use real AWS resources. Estimated costs if you run everything in sequence and tear down the same day:

| Resource | Approx Cost |
|----------|-------------|
| RDS Multi-AZ db.t3.micro | ~$0.04/hr |
| Read replicas (1-2) | ~$0.02/hr each |
| Aurora cluster (2 instances) | ~$0.06/hr |
| Aurora Global Database (2 regions) | ~$0.12/hr |
| Serverless v2 (0.5 ACU min) | ~$0.01/hr idle |

Always delete resources you are not using. BUILD 06 (Global Database) is the most expensive lab.

---

## Folder Structure

```
tier4-availability/
  README.md               <- You are here
  concepts/
    availability.md       <- All 7 concept topics with diagrams
  build/
    01-rds-multi-az.md
    02-rds-read-replicas.md
    03-aurora-storage.md
    04-aurora-replicas.md
    05-aurora-endpoints.md
    06-aurora-global-database.md
    07-aurora-serverless-v2.md
  use/
    01-ha-design.md
    02-replica-management.md
    03-failover-testing.md
    04-endpoint-routing.md
    05-serverless-sizing.md
  survive/
    config.sh
    lib/
      common.sh
    01-multi-az-failover/
    02-replica-lag-spike/
    03-aurora-writer-failover/
    04-global-db-region-failure/
    05-serverless-scaling-stuck/
  interview/
    tier4-interview-questions.md
```

---

## How to Use This Tier

1. Read `concepts/availability.md` first. Do not skip this. The concepts make every lab easier.
2. Work through BUILD labs in order. Each one builds on the previous.
3. After each BUILD lab, do the matching USE exercise if one exists.
4. SURVIVE scenarios are done after all BUILD labs are complete.
5. Use the interview questions to self-test before your next job interview or client conversation.

---

## Getting Help

- Check the expected output blocks in each guide - your output should match the shape
- AWS Console: use the Events tab on any RDS/Aurora resource to see what happened
- AWS CLI: add `--debug` to any command for verbose output
- CloudWatch Logs: most RDS and Aurora errors appear in the PostgreSQL log group
