# USE 05 - Architecture Design: Choose the Right HA Strategy
## Apply What You Learned | Module 05

---

## Instructions

Read each business scenario. Design the best Aurora architecture. Write your answers before revealing solutions. Focus on meeting requirements with the simplest, most cost-effective option.

---

## Exercise 1 - Small E-Commerce Store

**Business:** Online store. 100 orders per day. Team of 3 developers.

**Requirements:**
- Must survive a single AZ failure
- RTO: 2 minutes acceptable
- RPO: No data loss
- Read traffic: 90% reads, 10% writes
- Budget: Under $200/month
- Region: us-east-1

**Questions:**
1. What database option do you recommend (RDS Multi-AZ, Aurora, Aurora Serverless v2)?
2. Do you need read replicas?
3. What instance class?
4. Draw a simple ASCII diagram.

<details>
<summary>Click to reveal solution</summary>

**Recommended: RDS PostgreSQL with Multi-AZ Instance**

Why NOT Aurora: At 100 orders/day, traffic is very low. Aurora's minimum instance (db.t3.medium) costs more than RDS (db.t3.micro). The faster failover of Aurora is not needed when 2-minute RTO is acceptable.

1. RDS Multi-AZ Instance. Covers AZ failure. Failover time 60-120 seconds fits the 2-minute RTO. Synchronous replication means RPO = 0.

2. No read replicas needed. At 100 orders/day (~0.07 TPS), a single db.t3.micro handles everything easily.

3. db.t3.micro or db.t3.small. Well under $200/month.

4. Architecture:
```
[App] --> [RDS Endpoint DNS]
                |
         [Primary: us-east-1a]
                |
         [Standby: us-east-1b] (invisible until failover)
```

Estimated cost: ~$30-60/month (db.t3.micro Multi-AZ + 20 GB storage).

</details>

---

## Exercise 2 - SaaS Platform with Variable Traffic

**Business:** B2B SaaS. 500 active tenants. Business hours traffic (9 AM - 6 PM weekdays).

**Requirements:**
- RTO under 30 seconds
- RPO: Zero data loss
- Traffic drops to near-zero nights and weekends
- Budget: Flexible but cost-efficient
- Region: us-east-1

**Questions:**
1. Aurora provisioned, Serverless v2, or mixed?
2. If Serverless v2, what min/max ACU?
3. How does Serverless v2 help with the night/weekend pattern?
4. What failover tier for the reader?

<details>
<summary>Click to reveal solution</summary>

**Recommended: Aurora Serverless v2 (writer + reader)**

1. Serverless v2 for both writer and reader. The traffic pattern (high during business hours, near-zero nights/weekends) is the ideal Serverless v2 use case. A mixed cluster (provisioned writer + serverless reader) works too if you want predictable write performance.

2. Min=1 ACU, Max=8 ACU. Min=1 keeps the cluster warm enough to avoid cold-start latency on Monday morning. Max=8 handles peak business hours.

3. Nights and weekends, the cluster scales down to 1 ACU ($0.12/hr). During business hours, it scales up to handle 500 tenants. You only pay for what you use, unlike provisioned instances that cost the same 24/7.

4. Failover tier 0 for the reader. This ensures the reader is promoted first if the writer fails, meeting the 30-second RTO.

Cost estimate: Average ~3 ACU x $0.12 x 730 hrs = ~$263/month. Compare to provisioned db.r6g.large ($0.24 x 730 = $175/month) - but provisioned costs the same even when idle.

</details>

---

## Exercise 3 - Analytics Platform

**Business:** Production OLTP database on Aurora. 50 analysts run dashboards during business hours. Nightly ETL loads data.

**Requirements:**
- OLTP must NOT be affected by analytics queries
- Analytics can tolerate up to 5 minutes of replica lag
- BI dashboard is read-only
- ETL queries are large and resource-intensive
- Minimize additional cost

**Questions:**
1. How do you isolate analytics from OLTP?
2. Reader endpoint or custom endpoint for the BI tool?
3. What instance class for the analytics reader vs OLTP readers?
4. What failover tier for the analytics reader?

<details>
<summary>Click to reveal solution</summary>

1. **Dedicated analytics reader.** Add a large Aurora reader specifically for analytics workloads. OLTP reads go to the standard reader endpoint. Analytics reads go to a custom endpoint pointing to the dedicated reader.

2. **Custom endpoint.** Create a custom endpoint with `--static-members devops-lab-analytics-reader`. The BI tool connects to this custom endpoint. The standard reader endpoint serves only OLTP application reads.

3. Analytics reader: db.r6g.2xlarge or db.r6g.4xlarge (large instance for complex queries, hash joins, sorts). OLTP readers: db.r6g.large (smaller, handles simple lookups).

4. Failover tier 15 (lowest priority). The analytics reader should NEVER become the writer during failover. It has a different instance size, different workload profile, and different connection patterns. Setting tier 15 ensures OLTP readers (tier 0-1) are promoted first.

Architecture:
```
[OLTP App]    --> [Reader Endpoint]   --> [r6g.large reader-1, tier 0]
                                          [r6g.large reader-2, tier 1]
[BI Dashboard]--> [Custom Endpoint]  --> [r6g.4xlarge analytics, tier 15]
[All Writes]  --> [Writer Endpoint]  --> [r6g.xlarge writer]
```

</details>

---

## Exercise 4 - Global Mobile App

**Business:** Consumer mobile app. Users in North America (primary) and Europe (growing).

**Requirements:**
- European users complain about read latency (>500ms)
- Europeans can tolerate 1 second of eventual consistency
- Writes can go to us-east-1
- If us-east-1 has an outage, Europe must write within 5 minutes
- Budget: ~$500/month

**Questions:**
1. What architecture serves European reads locally?
2. How does the European app write data?
3. Is 5-minute RTO achievable? What is required?

<details>
<summary>Click to reveal solution</summary>

**Recommended: Aurora Global Database with write forwarding**

1. Aurora Global Database with primary in us-east-1 and secondary in eu-west-1. European users read from the eu-west-1 secondary - local reads with < 1 second lag (acceptable for eventual consistency).

2. Enable write forwarding on the secondary. European app writes to the eu-west-1 endpoint. Aurora forwards writes to us-east-1 automatically. This adds ~100-150ms latency per write (cross-Atlantic round trip) but simplifies application code.

3. 5-minute RTO is achievable but requires preparation:
- Script the entire DR procedure (detect, detach, update DNS)
- Use Route 53 health checks for automatic DNS failover
- Set the secondary's instance size to handle production write load after promotion
- Test the procedure quarterly
- Without automation, manual failover takes 10-15 minutes (too slow)

Budget check:
- us-east-1: db.r6g.large writer = $175/month
- eu-west-1: db.r6g.large reader = $175/month (eu-west-1 pricing is similar)
- Storage: ~$20/month
- Total: ~$370/month (within $500 budget)

</details>

---

## Exercise 5 - Design Review Checklist

You are reviewing another team's Aurora architecture before it goes to production. They have:
- Aurora cluster in us-east-1
- 1 writer (db.r6g.large)
- 2 readers (db.r6g.large, both tier 1)
- Application uses the writer endpoint for ALL queries (reads and writes)
- No custom endpoints
- No auto-scaling
- No CloudWatch alarms

**Question:** List at least 5 issues or improvements you would recommend.

<details>
<summary>Click to reveal solution</summary>

Issues and improvements:

1. **Application reads should use the reader endpoint.** Sending all reads to the writer wastes the two readers and overloads the writer. Route reads to the reader endpoint.

2. **Failover tiers are both 1.** Set one reader to tier 0 so there is a clear primary failover target. Both at tier 1 means Aurora picks arbitrarily during failover.

3. **No CloudWatch alarms.** At minimum, set alarms for:
   - `AuroraReplicaLag > 5000ms` (reader falling behind)
   - `CPUUtilization > 80%` (capacity issue)
   - `DatabaseConnections > 400` (connection exhaustion)
   - Failover event notification

4. **No auto-scaling.** If read traffic varies, consider Aurora Auto Scaling or Serverless v2 readers to handle peaks without overprovisioning.

5. **No custom endpoint for analytics/reporting.** If any team runs analytical queries, they should use a custom endpoint to isolate from OLTP reads.

6. **No connection retry logic verified.** Before production, test failover and confirm the application reconnects automatically within the expected RTO.

7. **No Global Database for DR.** If the application is critical, consider a secondary region for disaster recovery.

8. **No RDS Proxy.** If the application uses Lambda or microservices with many connections, RDS Proxy would reduce connection overhead and improve failover behavior.

</details>
