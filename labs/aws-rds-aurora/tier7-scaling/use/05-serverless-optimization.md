# Tier 7 - USE Exercise 05: Serverless v2 Optimization

**Exercise type:** Hands-on analysis and tuning
**Time:** 35 minutes
**Goal:** Analyze Aurora Serverless v2 scaling behavior under different workload patterns, optimize ACU ranges, and produce a cost comparison report.
**Prerequisites:** Build 02 completed. Aurora Serverless v2 cluster running. CloudWatch access.

---

## Overview

You will run three different workload patterns against your Serverless v2 cluster, observe how ACU capacity responds, and tune the configuration for each. Then you will produce a cost vs. provisioned comparison.

---

## Part 1: Baseline ACU Profile

Before tuning, understand what your cluster does at rest.

**Step 1.** Let the cluster sit idle for 5 minutes, then check the minimum ACU it settled at:

```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name ServerlessDatabaseCapacity \
  --dimensions Name=DBClusterIdentifier,Value=tier7-asv2-lab \
  --start-time $(date -u -d '10 minutes ago' +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 60 \
  --statistics Minimum \
  --region [REGION]
```

Record the minimum value. This is your idle ACU floor.

**Step 2.** Check the current ACU range configuration:

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier tier7-asv2-lab \
  --region [REGION] \
  --query 'DBClusters[0].ServerlessV2ScalingConfiguration'
```

Expected output:
```json
{
    "MinCapacity": 0.5,
    "MaxCapacity": 8.0
}
```

---

## Part 2: Workload Pattern A - Bursty with Long Idle Periods

This pattern simulates an application that is active in short bursts (e.g., a batch job every hour) and idle the rest of the time.

**Step 1.** Simulate a burst:

```bash
# Rapid concurrent queries for 60 seconds
END=$((SECONDS+60))
while [ $SECONDS -lt $END ]; do
  psql -h [CLUSTER-ENDPOINT] -U postgres -d postgres \
    -c "SELECT COUNT(*), SUM(unit_price * quantity) FROM orders WHERE status = 'completed';" \
    > /dev/null 2>&1 &
done
wait
echo "Burst complete"
```

**Step 2.** Immediately after the burst completes, start monitoring ACU every 30 seconds for 5 minutes:

```bash
for i in {1..10}; do
  TIMESTAMP=$(date -u +%H:%M:%S)
  ACU=$(aws cloudwatch get-metric-statistics \
    --namespace AWS/RDS \
    --metric-name ServerlessDatabaseCapacity \
    --dimensions Name=DBClusterIdentifier,Value=tier7-asv2-lab \
    --start-time $(date -u -d '1 minute ago' +%Y-%m-%dT%H:%M:%SZ) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
    --period 60 \
    --statistics Maximum \
    --region [REGION] \
    --query 'Datapoints[0].Maximum' \
    --output text)
  echo "$TIMESTAMP: $ACU ACUs"
  sleep 30
done
```

Record how quickly ACU scaled up during the burst and how quickly it scaled back down after.

**Step 3.** Analysis questions:

- How many seconds did it take for ACU to reach peak during the burst?
- How many minutes did it take for ACU to return to the minimum after the burst ended?
- For this bursty pattern with long idle periods, what minimum ACU would you set? What maximum?

---

## Part 3: Workload Pattern B - Sustained Steady Load

This pattern simulates a transactional application with continuous traffic.

**Step 1.** Modify the ACU range for sustained load testing:

```bash
aws rds modify-db-cluster \
  --db-cluster-identifier tier7-asv2-lab \
  --serverless-v2-scaling-configuration MinCapacity=2,MaxCapacity=8 \
  --apply-immediately \
  --region [REGION]
```

Setting minimum to 2 ACUs ensures the instance is always warm enough for immediate response.

**Step 2.** Generate sustained load for 3 minutes:

```bash
# Sustained load - 10 concurrent connections, continuous queries
for conn in {1..10}; do
  (
    END=$((SECONDS+180))
    while [ $SECONDS -lt $END ]; do
      psql -h [CLUSTER-ENDPOINT] -U postgres -d postgres \
        -c "
          BEGIN;
          INSERT INTO load_test (payload) VALUES (repeat('y', 500));
          SELECT count(*) FROM load_test WHERE id % 7 = 0;
          COMMIT;
        " > /dev/null 2>&1
    done
  ) &
done
wait
echo "Sustained load complete"
```

**Step 3.** Get the ACU profile during load:

```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name ServerlessDatabaseCapacity \
  --dimensions Name=DBClusterIdentifier,Value=tier7-asv2-lab \
  --start-time $(date -u -d '5 minutes ago' +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 30 \
  --statistics Average,Maximum \
  --region [REGION]
```

Record:
- Peak ACU during load
- Average ACU during load
- Did ACU reach or approach the 8-ACU maximum?

**Step 4.** Sustained load cost calculation:

Calculate the cost for 3 minutes of load at the average ACU you observed:

```
Cost = Average ACU * $0.12/ACU-hour * (3/60 hours) = ?
```

Now calculate what a db.t3.large ($0.182/hr) would cost for the same 3 minutes:

```
Cost = $0.182/hr * (3/60 hours) = $0.0091
```

At this load level, which is cheaper? Note: the comparison is more meaningful at the monthly level.

---

## Part 4: Workload Pattern C - Analytics Query Burst

This pattern simulates an BI/analytics query that is CPU-intensive but infrequent.

**Step 1.** Set ACU range back to minimum-friendly:

```bash
aws rds modify-db-cluster \
  --db-cluster-identifier tier7-asv2-lab \
  --serverless-v2-scaling-configuration MinCapacity=0.5,MaxCapacity=8 \
  --apply-immediately \
  --region [REGION]
```

**Step 2.** Wait 5 minutes for the cluster to scale down toward 0.5 ACU.

**Step 3.** Run an expensive analytical query and time it:

```bash
time psql -h [CLUSTER-ENDPOINT] -U postgres -d postgres -c "
SELECT
  EXTRACT(hour FROM created_at) AS hour_of_day,
  COUNT(*) AS orders,
  SUM(unit_price * quantity) AS revenue,
  AVG(unit_price * quantity) AS avg_order,
  PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY unit_price * quantity) AS p95_order
FROM load_test
JOIN orders ON load_test.id % 100 = orders.order_id % 100
GROUP BY EXTRACT(hour FROM created_at)
ORDER BY hour_of_day;
"
```

Record the wall-clock time.

**Step 4.** Immediately run the same query again and record the time:

```bash
time psql -h [CLUSTER-ENDPOINT] -U postgres -d postgres -c "
SELECT
  EXTRACT(hour FROM created_at) AS hour_of_day,
  COUNT(*) AS orders,
  SUM(unit_price * quantity) AS revenue,
  AVG(unit_price * quantity) AS avg_order,
  PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY unit_price * quantity) AS p95_order
FROM load_test
JOIN orders ON load_test.id % 100 = orders.order_id % 100
GROUP BY EXTRACT(hour FROM created_at)
ORDER BY hour_of_day;
"
```

The second run should be faster because:
- The instance has already scaled up to handle the first query.
- The data is warm in the buffer cache.

**Step 5.** Observation: what is the difference in execution time between the first and second run? This difference represents the "cold start" penalty of running from near-minimum ACU.

---

## Part 5: Cost Comparison Report

Produce a written cost comparison using the data you collected in this exercise.

**Given data (use your actual observed values):**

- Your cluster's idle ACU: ___
- Peak ACU during bursty workload: ___
- Average ACU during sustained load: ___

**Template to complete:**

```
Aurora Serverless v2 Cost Analysis
===================================

Workload Profile: [describe your workload - bursty/sustained/analytical]

Observed ACU Data:
  - Idle ACU floor:       ___ ACUs
  - Peak ACU (burst):     ___ ACUs
  - Average ACU (3 min):  ___ ACUs

Monthly Cost Estimate (Serverless v2):
  Assumption: 8 hours/day at average load, 16 hours/day at idle
  Active hours/month:  8 * 30 = 240 hours
  Idle hours/month:   16 * 30 = 480 hours

  Active cost:  [average ACU] * $0.12 * 240 hours = $___
  Idle cost:    [idle ACU]    * $0.12 * 480 hours = $___
  Total monthly: $___

Provisioned Comparison:
  db.t3.large  ($0.182/hr):  $0.182 * 730 = $132.86/month
  db.r6g.large ($0.260/hr):  $0.260 * 730 = $189.80/month
  db.r6g.xlarge($0.520/hr):  $0.520 * 730 = $379.60/month

Break-even ACU:
  At what average ACU is Serverless v2 equivalent to db.t3.large?
  $132.86 / ($0.12 * 730 hours) = ___ average ACU break-even

Recommendation:
  [Serverless v2 / db.t3.large / db.r6g.large] because [justification]
```

---

## Part 6: Configuration Recommendations

Based on your observations, answer each question with a specific ACU value and justification:

1. **Development database** (used 8 hours/day, 5 days/week, idle all other times): What min/max ACU? Should you allow pause (minimum 0.5 ACU)?

2. **Production database** (used 24/7, traffic peaks 10 AM - 8 PM at 3x baseline, drops to baseline overnight): What min/max ACU?

3. **Analytics database** (used only during business hours by 5 data analysts running ad-hoc queries, completely idle nights and weekends): What min/max ACU?

4. **Multi-tenant SaaS database** (thousands of customers, each with low individual usage, but aggregate traffic is high and unpredictable): Is Serverless v2 appropriate? What alternatives would you consider?

---

## Validation Checklist

- [ ] Observed ACU scaling behavior under all three workload patterns.
- [ ] Recorded peak ACU, average ACU, and scale-down time for each pattern.
- [ ] Calculated cost for 3-minute sustained load period.
- [ ] Quantified the cold-start penalty (difference between first and second analytical query run).
- [ ] Completed cost comparison report with real observed ACU values.
- [ ] Provided specific ACU recommendations for all four configuration scenarios.
