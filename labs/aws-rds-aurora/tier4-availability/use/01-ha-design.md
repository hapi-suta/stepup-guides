# USE 01 - HA Architecture Design
## Apply What You Learned | Tier 4

---

## Instructions

Read each scenario. Design the best AWS database architecture. Write your answers in a text file or notebook.

After you finish, read the solution notes at the bottom of this file. Compare your design to the suggestions.

There are no trick questions. Focus on:
- Meeting the stated RTO and RPO requirements
- Staying within the stated budget
- Choosing the simplest option that meets requirements

> **Concept:** RTO = Recovery Time Objective (maximum acceptable downtime). RPO = Recovery Point Objective (maximum acceptable data loss).

---

## Scenario 1 - Small E-Commerce Store

**Business:** Online store. 100 orders per day. Small team of 3 developers.

**Requirements:**
- Must survive a single AZ failure
- RTO: 2 minutes is acceptable
- RPO: No data loss after failover
- Read traffic: 90% reads, 10% writes
- Budget: Under $200/month for the database layer
- Region: us-east-1

**Questions:**

1. What RDS/Aurora option do you recommend?
2. Do you need read replicas? Why or why not?
3. What instance class would you pick?
4. Draw a simple ASCII diagram of your architecture.

---

## Scenario 2 - SaaS Application

**Business:** B2B SaaS platform. 500 active tenants. Business hours traffic (9 AM - 6 PM weekdays).

**Requirements:**
- Must survive AZ failure with RTO under 30 seconds
- RPO: Zero data loss
- Read traffic: 70% reads, 30% writes
- Traffic drops to near-zero nights and weekends
- Budget: Flexible, but cost-efficiency matters
- Region: us-east-1

**Questions:**

1. What would you choose: Aurora provisioned, Aurora Serverless v2, or mixed?
2. If using Serverless v2, what min/max ACU would you set?
3. How does Serverless v2 help with the night/weekend traffic pattern?
4. What failover tier would you set on the reader?

---

## Scenario 3 - Financial Services Application

**Business:** Fintech app. Processes payments. Regulated - must pass SOC 2 audit.

**Requirements:**
- RTO: Under 30 seconds
- RPO: ZERO data loss (absolutely none)
- Must be available in two AWS regions for business continuity plan
- DR region must be readable for reporting
- Write traffic: moderate but mission-critical
- Budget: $2,000/month maximum for database layer

**Questions:**

1. What architecture spans two regions?
2. Can the secondary region serve read traffic? How?
3. For the DR failover: is it automatic or manual? What do you do?
4. What instance class minimum does the architecture require?
5. Estimate monthly cost.

---

## Scenario 4 - Data Analytics Platform

**Business:** A company runs nightly ETL jobs and serves a BI dashboard to 50 analysts during business hours. The production OLTP database is Aurora PostgreSQL.

**Requirements:**
- OLTP workload must NOT be affected by analytics queries
- Analytics can tolerate up to 5 minutes of replica lag
- BI dashboard is read-only
- ETL and BI queries are large and resource-intensive
- Budget: Minimize additional cost

**Questions:**

1. How do you isolate analytics from OLTP reads?
2. Do you use the reader endpoint or a custom endpoint for the BI tool?
3. What instance class would you choose for the analytics reader vs the OLTP readers?
4. Would you use the same replica for both ETL and BI, or separate ones? Why?

---

## Scenario 5 - Global Mobile App

**Business:** Consumer mobile app. Users in North America (primary) and Europe (growing market).

**Requirements:**
- European users complain about read latency (>500ms for DB queries)
- European users can tolerate 1 second of eventual consistency for reads
- Writes can go to North America (us-east-1) - latency for writes is acceptable
- If us-east-1 has an outage, Europe must be able to write within 5 minutes
- Budget: ~$500/month

**Questions:**

1. What architecture serves European reads locally?
2. How does the European app write data?
3. If you enable write forwarding, what latency do writes have from Europe?
4. Is the 5-minute RTO achievable with automatic failover? What is required?

---

## Solution Notes

### Scenario 1 - Small E-Commerce Store

Recommended: **RDS PostgreSQL with Multi-AZ Instance**

- Multi-AZ Instance covers the AZ failure requirement
- Failover time: 60-120 seconds - acceptable for 2-minute RTO
- No read replicas needed at 100 orders/day - traffic is too low to justify cost
- Instance: db.t3.micro or db.t3.small - well under $200/month
- Total cost: ~$30-60/month

Aurora is overkill here. The simplicity and cost of RDS is the right call.

```
[App] --> [Endpoint DNS]
                |
         [Primary: us-east-1a]
                |
         [Standby: us-east-1b] (invisible until failover)
```

---

### Scenario 2 - SaaS Application

Recommended: **Aurora Serverless v2 writer + Serverless v2 reader**

- Aurora failover is under 35 seconds - meets the 30-second RTO requirement
- Serverless v2 scales down nights/weekends - saves significant cost
- ACU range: min=1, max=8 (adjust based on actual peak load)
- Reader failover tier: 0 (immediate promotion)
- Mixed cluster can work too: provisioned writer for predictable OLTP, serverless reader for variable reads

Cost comparison: if OLTP peaks need 4 ACU, Serverless v2 is roughly $0.48/hr peak but ~$0.12/hr average. A provisioned db.r6g.large costs $0.24/hr 24/7. For nights/weekends = clear Serverless win.

---

### Scenario 3 - Financial Services Application

Recommended: **Aurora Global Database**

- Two regions: us-east-1 (primary) + us-east-2 or us-west-2 (secondary)
- Secondary is readable - use for compliance reporting
- Failover is MANUAL (unplanned) - no automatic cross-region failover
- DR process: detect outage, run `detach-and-promote` on secondary, update app DNS
- Min instance: db.r6g.large (required for Global Database)
- Estimated cost: 2x db.r6g.large across 2 regions + storage = ~$800-1200/month (under $2k budget)

RPO is near-zero with Global Database (sub-1-second replication lag). Not absolute zero, but as close as AWS offers for cross-region.

---

### Scenario 4 - Data Analytics Platform

Recommended: **Custom endpoint pointing to a dedicated large Aurora reader**

- Add a large reader (db.r6g.2xlarge or db.r6g.4xlarge) specifically for analytics
- Create a custom endpoint including only that instance
- BI tool and ETL connect to the custom endpoint
- OLTP app connects to the standard reader endpoint (smaller instances)
- Separate readers for ETL and BI if they both run at the same time (avoid resource contention)
- Failover tier: set the analytics reader to tier 15 (lowest priority) - do not promote it to writer

```
[OLTP App]  --> [Reader Endpoint]  --> [r6g.large x2]
[ETL / BI]  --> [Custom Endpoint]  --> [r6g.4xlarge]
[Writes]    --> [Writer Endpoint]  --> [Writer]
```

---

### Scenario 5 - Global Mobile App

Recommended: **Aurora Global Database with write forwarding**

- Primary: us-east-1. Secondary: eu-west-1
- European reads go to the eu-west-1 secondary (low latency, sub-1-second lag for eventual reads)
- European writes use write forwarding - Aurora forwards to us-east-1 (adds 100-200ms round trip latency for writes - acceptable)
- 5-minute RTO: achievable with a fast manual failover process (script it). Automatic failover is NOT available for Global Database.
- Budget: Two r6g.large instances across 2 regions ~$500-600/month - slightly over budget. Consider one r6g.large each.
