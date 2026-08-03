# USE 01 - Failover Planning and Execution
## Apply What You Learned | Module 05

---

## Instructions

Complete each exercise. Write your answers before revealing the solutions. Use your Aurora cluster (`devops-lab-cluster`) for hands-on exercises.

---

## Exercise 1 - Write a Failover Test Plan

You are the DBA for a production Aurora cluster. Management wants proof that failover works within the 30-second RTO requirement.

Write a complete failover test plan using this template. Fill in every field.

```
FAILOVER TEST PLAN
==================
Date: [DATE]
Cluster: devops-lab-cluster
Region: us-east-1
Tester: [YOUR NAME]

PRE-TEST CHECKS:
- [ ] Current writer instance: ____________
- [ ] Current reader instances: ____________
- [ ] Baseline replica lag: ____________ ms
- [ ] Application connection uses cluster endpoint (not instance endpoint): YES / NO

TEST GOAL:
- Verify failover completes within ____________ seconds
- Verify application reconnects automatically

RECOVERY TIME OBJECTIVE (RTO): ____________ seconds

FAILOVER METHOD:
- [ ] CLI: aws rds failover-db-cluster

POST-FAILOVER CHECKS:
- [ ] New writer is a different instance
- [ ] Cluster endpoint DNS points to new IP
- [ ] Reader endpoint still works
- [ ] Write operation succeeds
- [ ] Read operation succeeds

ROLLBACK PLAN:
- ____________________________________________
```

<details>
<summary>Click to reveal solution</summary>

```
FAILOVER TEST PLAN
==================
Date: 2026-06-09
Cluster: devops-lab-cluster
Region: us-east-1
Tester: [YOUR NAME]

PRE-TEST CHECKS:
- [x] Current writer instance: devops-lab-writer
- [x] Current reader instances: devops-lab-reader-1, devops-lab-reader-2
- [x] Baseline replica lag: 20 ms
- [x] Application connection uses cluster endpoint: YES

TEST GOAL:
- Verify failover completes within 35 seconds
- Verify application reconnects automatically

RECOVERY TIME OBJECTIVE (RTO): 30 seconds

FAILOVER METHOD:
- [x] CLI: aws rds failover-db-cluster

POST-FAILOVER CHECKS:
- [ ] New writer is a different instance
- [ ] Cluster endpoint DNS points to new IP
- [ ] Reader endpoint still works
- [ ] Write operation succeeds
- [ ] Read operation succeeds

ROLLBACK PLAN:
- Run aws rds failover-db-cluster with --target-db-instance-identifier devops-lab-writer to fail back
```

</details>

---

## Exercise 2 - Measure Actual RTO

Run a failover and measure the actual downtime. Compare it to the 30-second RTO target.

1. Start the connection monitor from BUILD 02
2. Trigger a failover
3. Count the number of FAIL lines (each = 1 second)
4. Record the measured RTO

**Question:** Did the failover meet the 30-second RTO? If not, what could cause it to exceed 30 seconds?

<details>
<summary>Click to reveal solution</summary>

Typical Aurora failover completes in 20-35 seconds. If it exceeds 30 seconds, common causes:

- The reader being promoted was under heavy load (processing large queries)
- DNS caching on the client side held the old IP longer than 5 seconds
- The connection monitor's `psql` command took time to timeout before retrying
- Network latency between your terminal and the Aurora cluster added time

To improve RTO:
- Set the preferred failover reader to tier 0 with adequate instance size
- Ensure application DNS TTL is 5 seconds or less
- Use RDS Proxy which detects failover faster than DNS

</details>

---

## Exercise 3 - Verify Data Integrity After Failover

After the failover from Exercise 2:

1. Connect to the writer endpoint
2. Insert a row: `INSERT INTO failover_test (message) VALUES ('post-failover-exercise');`
3. Query all rows: `SELECT * FROM failover_test ORDER BY id;`

**Question:** Is the pre-failover data (rows written before failover) still present? Why or why not?

<details>
<summary>Click to reveal solution</summary>

Yes, all pre-failover data is present. Aurora uses synchronous storage replication - all committed writes are stored across 6 storage nodes in 3 AZs before being acknowledged. During failover, the new writer reads from the same shared storage. No data is lost.

This gives Aurora an RPO of 0 (zero data loss) for in-region failover.

</details>

---

## Exercise 4 - Test Reader Endpoint During Writer Failover

During a writer failover, does the reader endpoint experience downtime?

1. Open two terminals
2. Terminal 1: monitor the reader endpoint (`cluster-ro-xxxx`)
3. Terminal 2: trigger a writer failover
4. Observe Terminal 1

**Question:** What happens to the reader endpoint during a writer failover?

<details>
<summary>Click to reveal solution</summary>

The reader endpoint may briefly be affected. Here is what happens:

1. The tier-0 reader is promoted to writer - it is removed from the reader pool
2. The old writer becomes a reader - it is added to the reader pool
3. DNS for the reader endpoint is updated

During the transition (a few seconds), the reader endpoint may route to fewer instances or briefly fail. However, the disruption to reads is much shorter than the disruption to writes.

If you have 2+ readers, the reader endpoint usually stays available because at least one reader remains throughout the failover.

</details>

---

## Exercise 5 - Failover Priority Verification

Your cluster has these instances:
- `devops-lab-writer` (current writer, tier 1)
- `devops-lab-reader-1` (tier 0)
- `devops-lab-reader-2` (tier 1)

**Question:** If the writer fails, which reader becomes the new writer? Why?

**Follow-up:** If you want `devops-lab-reader-2` to never become the writer (it is your analytics reader), what tier should you set it to?

<details>
<summary>Click to reveal solution</summary>

`devops-lab-reader-1` becomes the new writer because it has the lowest tier number (tier 0 = highest priority).

To prevent `devops-lab-reader-2` from ever becoming the writer, set it to tier 15 (lowest priority):

```bash
aws rds modify-db-instance \
  --db-instance-identifier devops-lab-reader-2 \
  --promotion-tier 15 \
  --apply-immediately \
  --region us-east-1
```

At tier 15, it would only be promoted if ALL other readers at lower tiers are unavailable - extremely unlikely.

</details>
