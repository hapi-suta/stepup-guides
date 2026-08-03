# USE 04 - Global Database: Cross-Region Design
## Apply What You Learned | Module 05

---

## Instructions

Read each scenario. Design the architecture and answer the questions. Reveal solutions to compare.

---

## Exercise 1 - Global Database Failover Types

**Question:** Explain the difference between these two commands:

```bash
# Command A
aws rds switchover-global-cluster \
  --global-cluster-identifier my-global \
  --target-db-cluster-identifier arn:aws:rds:us-west-2:...:cluster:my-secondary

# Command B
aws rds remove-from-global-cluster \
  --global-cluster-identifier my-global \
  --db-cluster-identifier arn:aws:rds:us-west-2:...:cluster:my-secondary
```

When would you use each one?

<details>
<summary>Click to reveal solution</summary>

**Command A (switchover):** Planned, non-destructive failover.
- Drains replication lag to zero before switching
- Primary demotes to secondary, secondary promotes to primary
- Both regions remain in the Global Database with reversed roles
- Zero data loss
- Takes 5-20 minutes
- Use for: planned maintenance, region migration, DR testing

**Command B (remove-from-global-cluster):** Emergency detach for unplanned failover.
- Immediately detaches the secondary cluster
- The secondary becomes an independent read-write cluster
- The global database relationship is broken
- Possible data loss (RPO = last replicated transaction)
- Takes seconds to execute
- Use for: real disaster when the primary region is unreachable

After using Command B, you must manually re-create the global database relationship when the old primary recovers.

</details>

---

## Exercise 2 - Write Forwarding Trade-offs

Your Global Database has:
- Primary in us-east-1
- Secondary in eu-west-1 (Europe)

European users complain about write latency. You enable write forwarding.

**Question 1:** What is the expected latency for a write from eu-west-1 with write forwarding enabled?

**Question 2:** A European user inserts a row and immediately reads it back from the eu-west-1 reader. Will they see the row?

<details>
<summary>Click to reveal solution</summary>

**Q1:** Write forwarding adds cross-region round-trip latency. The write travels from eu-west-1 to us-east-1 (where it is committed), then the acknowledgment returns to eu-west-1. Typical round-trip: 80-150ms depending on the regions. So each write takes ~80-150ms longer than a direct write to us-east-1.

**Q2:** Not necessarily. The write is committed in us-east-1 and must replicate back to eu-west-1 (another 100-500ms). If the user reads immediately (within milliseconds), the secondary may not have received the replicated data yet.

Fix: set `aurora_replica_read_consistency = 'SESSION'` on the reader connection. This ensures the reader waits for the session's writes to be replicated before serving reads. Or, use `EVENTUAL` consistency with the understanding that the read may be briefly stale.

</details>

---

## Exercise 3 - DR Architecture Design

**Scenario:** A fintech company needs:
- RPO near-zero
- RTO under 5 minutes
- Two-region deployment for business continuity
- Secondary region must be readable for reporting

**Question:** Design the architecture. Address these points:
1. Which regions?
2. Instance types and sizes
3. How do reporting apps in the secondary read data?
4. What is the DR failover procedure (step by step)?
5. Is the 5-minute RTO achievable? What could prevent it?

<details>
<summary>Click to reveal solution</summary>

**Architecture:**
```
Primary: us-east-1
  Writer: db.r6g.xlarge (failover tier N/A)
  Reader-1: db.r6g.large (failover tier 0)
  Reader-2: db.r6g.large (failover tier 1)

Secondary: us-west-2
  Reader-3: db.r6g.large (reporting queries)
  Reader-4: db.r6g.large (additional reporting capacity)

Global Database: devops-aurora-global
```

**1. Regions:** us-east-1 (primary) and us-west-2 (secondary). Same continent minimizes replication lag.

**2. Instance types:** db.r6g.xlarge for the writer (handles write load). db.r6g.large for all readers (adequate for reads and potential promotion).

**3. Reporting:** Reporting apps connect to the secondary cluster's reader endpoint in us-west-2. They see data with < 1 second delay from the primary.

**4. DR Failover procedure:**
1. CloudWatch alarm fires: primary region connectivity lost (0:00)
2. On-call DBA confirms the outage via multiple checks (0:30-1:00)
3. Run `aws rds remove-from-global-cluster` to detach us-west-2 (1:00-1:30)
4. us-west-2 cluster becomes independent read-write cluster (1:30-2:00)
5. Update Route 53 DNS to point application to us-west-2 endpoints (2:00-3:00)
6. Verify application connectivity and run smoke tests (3:00-4:00)
7. Notify stakeholders (4:00-5:00)

**5. RTO assessment:** 5 minutes is achievable IF:
- The DR procedure is fully scripted (not manual CLI commands)
- Route 53 health checks trigger automatic DNS failover
- The team has practiced the procedure quarterly
- Steps 2-5 are automated or semi-automated

What could prevent it:
- Manual approval gates ("who approves the failover?") add time
- Application configuration changes beyond DNS (hardcoded connection strings)
- Secondary region's MaxCapacity is too low for production write load
- Team has never practiced the procedure

</details>

---

## Exercise 4 - Cost Estimation

Estimate the monthly cost for the architecture in Exercise 3.

Pricing (approximate, us-east-1):
- db.r6g.xlarge: $0.48/hr
- db.r6g.large: $0.24/hr
- Aurora storage: $0.10/GB-month
- Cross-region replication: included in Aurora pricing

**Question:** What is the total monthly cost? Is it under $2,000?

<details>
<summary>Click to reveal solution</summary>

**Compute:**
- us-east-1 writer (r6g.xlarge): $0.48 x 730 hrs = $350
- us-east-1 reader-1 (r6g.large): $0.24 x 730 = $175
- us-east-1 reader-2 (r6g.large): $0.24 x 730 = $175
- us-west-2 reader-3 (r6g.large): $0.24 x 730 = $175
- us-west-2 reader-4 (r6g.large): $0.24 x 730 = $175

**Storage** (assuming 100 GB):
- Primary: $0.10 x 100 = $10
- Secondary: $0.10 x 100 = $10

**Total: ~$1,070/month**

Yes, well under the $2,000 budget. You could even use a smaller writer (r6g.large) to reduce costs to ~$900/month, though this limits write capacity.

</details>

---

## Exercise 5 - Replication Lag Monitoring

You need to monitor your Global Database replication lag and alert if it exceeds 2 seconds.

**Question:** Write the CLI command to create this CloudWatch alarm.

<details>
<summary>Click to reveal solution</summary>

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name global-db-replication-lag-high \
  --alarm-description "Aurora Global DB replication lag exceeded 2 seconds" \
  --namespace AWS/RDS \
  --metric-name AuroraGlobalDBReplicationLag \
  --dimensions Name=DBClusterIdentifier,Value=devops-global-secondary \
  --statistic Maximum \
  --period 60 \
  --threshold 2000 \
  --comparison-operator GreaterThanThreshold \
  --evaluation-periods 3 \
  --region us-west-2
```

Key points:
- Metric is `AuroraGlobalDBReplicationLag` (in milliseconds), not `ReplicaLag`
- Dimension uses `DBClusterIdentifier` of the SECONDARY cluster
- Region must be the secondary region (us-west-2) where the metric is published
- Threshold is 2000 (milliseconds = 2 seconds)
- 3 evaluation periods prevents false alarms from momentary network blips

</details>
