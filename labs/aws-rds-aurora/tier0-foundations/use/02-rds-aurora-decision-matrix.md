# Exercise 02: RDS vs Aurora Decision Matrix

**Duration:** 25 minutes
**Objective:** Evaluate 5 real-world workload profiles and make a justified recommendation between RDS PostgreSQL and Aurora PostgreSQL, identifying the key deciding factor for each.
**Prerequisites:** Build guide 02 (RDS vs Aurora Comparison) complete

---

## Background

You are a senior DBA consultant at [COMPANY]. Your team has been brought in to advise 5 different clients on their AWS PostgreSQL strategy. Each client has different workload characteristics, team maturity, and budget constraints.

For each client profile below:
1. Recommend either RDS PostgreSQL or Aurora PostgreSQL
2. State the single most important deciding factor
3. List 2-3 supporting reasons
4. Call out any significant tradeoffs or caveats

Work through each scenario before looking at the answers.

---

## Task 1: Evaluate Each Client Profile

**Business question:** Which database service best fits each client's situation?

---

### Client A - [STARTUP]
**Profile:**
- Early-stage SaaS product, pre-revenue
- Database size: 15-40 GB, growing slowly
- Traffic: ~200 requests/day, very predictable, no spikes
- Team: 2 engineers, no dedicated DBA
- Budget: Extremely tight, every dollar matters
- PostgreSQL version: Needs latest stable (16+)
- Recovery requirements: RPO 24 hours, RTO 4 hours is acceptable
- Special requirements: None

---

### Client B - [ECOMMERCE CO]
**Profile:**
- Established e-commerce platform, 8 years old
- Database size: 1.8 TB, growing 200 GB/year
- Traffic: 500-2,000 requests/second normally; 8,000-15,000 during Black Friday
- Team: 3 DBAs, 20 developers
- Budget: Mid-range, can justify cost with revenue impact
- PostgreSQL version: Currently on 14, willing to upgrade
- Recovery requirements: RPO 1 hour, RTO 15 minutes
- Special requirements: Read-heavy workload (product catalog, search), write-heavy during order processing spikes

---

### Client C - [FINTECH CORP]
**Profile:**
- Financial services company, regulated industry (SOC 2, PCI-DSS)
- Database size: 800 GB
- Traffic: Steady, predictable (~1,000 req/sec), low tolerance for latency variance
- Team: 6 DBAs, dedicated security team
- Budget: Not a primary constraint, business risk is
- PostgreSQL version: Must be a specific certified version (13.x), no auto-upgrades
- Recovery requirements: RPO near-zero, RTO under 2 minutes, multi-region DR required
- Special requirements: All data must be encrypted at rest and in transit. Audit logging of all queries. Cross-region replication.

---

### Client D - [SAAS PLATFORM]
**Profile:**
- B2B SaaS company with 200 tenants
- Database size: 50-500 GB per tenant (wide range)
- Traffic: Highly variable - some tenants are power users, some are dormant
- Team: 4 engineers, 1 part-time DBA
- Budget: Mid-range, cost per tenant matters for unit economics
- PostgreSQL version: Flexible
- Recovery requirements: RPO 1 hour, RTO 30 minutes
- Special requirements: Dev/staging environments need to be cost-efficient (can be off during nights/weekends). Some tenants require dedicated instances for compliance. Needs to scale up quickly when a tenant has a growth event.

---

### Client E - [LEGACY ENTERPRISE]
**Profile:**
- 15-year-old enterprise software company migrating from on-prem PostgreSQL 12
- Database size: 3 TB
- Traffic: Moderate, internal users only (~150 concurrent connections)
- Team: 2 DBAs who know on-prem PostgreSQL very well but have limited AWS experience
- Budget: One-time migration project budget, then ongoing cost matters
- PostgreSQL version: Currently on PostgreSQL 12, target is PostgreSQL 15
- Recovery requirements: RPO 4 hours, RTO 2 hours
- Special requirements: Must minimize application changes during migration. Has custom PostgreSQL extensions (some may not be available on Aurora). Wants maximum compatibility with existing pg_dump backups and psql tooling.

---

## Task 2: Head-to-Head Cost Comparison

For Client A ([STARTUP]) specifically:

Estimate the approximate monthly cost difference between:
- `db.t3.micro` RDS PostgreSQL with 100 GB gp2 storage
- `db.t3.medium` Aurora PostgreSQL with equivalent storage

You don't need exact numbers - use ballpark estimates and explain the cost model difference between RDS (provisioned storage) and Aurora (per-GB consumed storage).

---

## Answers

### Client A - [STARTUP]: Recommend RDS PostgreSQL

**Key deciding factor:** Cost. Aurora has a minimum cost floor that makes it economically impractical for very small workloads.

**Supporting reasons:**
- Aurora does not offer a free tier equivalent for micro/nano instances. At low traffic volumes, the Aurora cost premium provides no measurable benefit.
- At 15-40 GB with predictable, low traffic, there is nothing to scale. Aurora's auto-scaling storage and reader replicas are solving problems this client does not have.
- A `db.t3.micro` or `db.t3.small` RDS instance with 100 GB gp2 storage and daily automated backups fully covers their RPO/RTO requirements.
- The engineering team has no DBA. RDS is simpler to reason about and has more community tutorials.

**Tradeoff to mention:** If this startup suddenly goes viral and needs to scale fast, they will face a migration to Aurora later. Document this decision and revisit when the database exceeds 100 GB or traffic becomes unpredictable.

**Approximate cost:** ~$15-30/month for `db.t3.micro` + 100 GB gp2. Aurora equivalent starts at ~$60-80/month for the smallest meaningful configuration.

---

### Client B - [ECOMMERCE CO]: Recommend Aurora PostgreSQL

**Key deciding factor:** Read traffic spikes. Aurora's ability to add up to 15 read replicas with near-instant provisioning and Aurora Auto Scaling makes it the right tool for Black Friday-style traffic patterns.

**Supporting reasons:**
- Black Friday spikes of 8-15x normal traffic cannot be handled by a single RDS instance without significant over-provisioning the rest of the year.
- Aurora replicas share the same underlying storage, so lag is typically under 100ms (vs. streaming replication lag on RDS replicas which can spike under heavy write load).
- Aurora Serverless v2 can be applied to read replicas to auto-scale reader capacity during spikes and scale down afterward - directly addressing the cost concern of over-provisioning.
- The 1.8 TB database will continue to grow. Aurora's storage grows automatically in 10 GB increments with no downtime, while RDS storage modifications can take significant time and may require instance restart depending on the storage type change.
- RTO of 15 minutes is achievable with Aurora's Multi-AZ failover (typically under 30 seconds), well within the requirement.

**Tradeoff to mention:** Aurora costs more per instance hour than equivalent RDS. The ROI argument here is that preventing even 1 hour of Black Friday downtime or degradation likely pays for months of Aurora cost premium.

---

### Client C - [FINTECH CORP]: Recommend Aurora PostgreSQL

**Key deciding factor:** Multi-region DR with near-zero RPO. Aurora Global Database provides cross-region replication with typical lag under 1 second, which is the only AWS-managed PostgreSQL option that meets their RPO requirement without complex custom solutions.

**Supporting reasons:**
- Aurora Global Database replicates to a secondary region using dedicated infrastructure (not over public internet) with sub-second lag. If the primary region fails, promotion of the secondary takes under 1 minute in most cases, meeting the 2-minute RTO.
- Aurora encrypts storage at rest by default and supports TLS for all connections. Advanced Auditing (via `pgaudit` extension) is supported.
- SOC 2 and PCI-DSS compliance requirements are well-documented for Aurora. AWS publishes compliance reports via AWS Artifact.

**Tradeoff to mention:** The requirement for PostgreSQL 13.x with no auto-upgrades is a real constraint. Check that the specific 13.x minor version they require is supported on Aurora. Aurora sometimes lags behind RDS in supporting the latest minor versions. If the specific minor version is unavailable, this might push toward RDS PostgreSQL with cross-region read replicas as an alternative - though RDS read replicas have higher replication lag than Aurora Global Database.

---

### Client D - [SAAS PLATFORM]: Recommend Aurora PostgreSQL (with caveats)

**Key deciding factor:** Aurora Serverless v2 scale-to-zero capability for dev/staging environments directly addresses the unit economics concern for non-production databases.

**Supporting reasons:**
- Aurora Serverless v2 can scale to 0 ACUs (Aurora Capacity Units) during inactivity - meaning dev/staging databases that are idle nights and weekends cost near-zero during those periods. This is not possible with standard RDS.
- For the active tenants with unpredictable growth, Aurora's compute can scale up without a maintenance window or instance type change.
- For compliance tenants needing dedicated instances, Aurora allows provisioned instances on the same cluster infrastructure, giving flexibility to mix serverless and provisioned.

**Caveats:**
- At 200 tenants with wide size variation, evaluate whether a single large Aurora cluster with per-tenant schemas makes more sense than per-tenant databases. This is an architecture decision with significant cost and isolation tradeoffs.
- Aurora Serverless v2 scale-to-zero is available but the cold start (warming up from zero) can add several seconds of latency to the first connection. For dev tools this is acceptable; set expectations accordingly.
- Cost modeling per tenant is more complex with Aurora's consumption-based pricing. Build a cost calculator before committing.

---

### Client E - [LEGACY ENTERPRISE]: Recommend RDS PostgreSQL

**Key deciding factor:** Extension compatibility and migration risk. RDS PostgreSQL has broader support for community PostgreSQL extensions and behaves more like standard PostgreSQL, reducing migration surprises.

**Supporting reasons:**
- Custom PostgreSQL extensions on Aurora must be specifically supported by AWS. Extensions that involve low-level hooks or system catalog modifications may not work at all on Aurora. RDS PostgreSQL supports a wider set of extensions and generally behaves closer to a standard PostgreSQL installation.
- The existing team knows PostgreSQL deeply but not AWS. RDS PostgreSQL is conceptually identical to their on-prem setup - same pg_dump/pg_restore workflow, same psql behavior, same postgresql.conf parameters (via parameter groups). Aurora has enough differences (custom storage engine, different system tables, modified superuser model) to add learning curve during an already risky migration.
- `pg_dump` backups from PostgreSQL 12 restore cleanly into RDS PostgreSQL 15 using standard pg_restore. The upgrade path is well-documented and predictable.
- RPO of 4 hours and RTO of 2 hours are easily achievable with standard RDS Multi-AZ + automated backups. No need for Aurora's more complex HA features.

**Tradeoff to mention:** If the client's workload grows significantly after migration and they later need Aurora's scaling capabilities, a migration from RDS to Aurora is straightforward using a snapshot restore. Start with RDS, migrate to Aurora later if the need arises.

---

## Task 2 Answer - Cost Comparison for [STARTUP]

**RDS PostgreSQL (`db.t3.micro`, 100 GB gp2, single-AZ):**
- Instance: ~$12-15/month
- Storage (100 GB gp2): ~$11.50/month
- Automated backups (7 days, same region): included in storage pricing for backup storage up to the DB size
- **Total: ~$25/month**

**Aurora PostgreSQL (smallest practical config, 100 GB consumed):**
- Aurora does not offer `db.t3.micro`. Smallest available is `db.t3.medium`.
- Instance: ~$60-75/month for `db.t3.medium`
- Storage: Aurora charges per GB consumed (~$0.10/GB/month), so 100 GB = $10/month
- I/O: Aurora charges per million requests (~$0.20/million). At low traffic this might add $5-15/month.
- **Total: ~$75-100/month**

**Key difference in cost model:**
- RDS uses provisioned storage (you pay for allocated capacity whether you use it or not). Predictable billing.
- Aurora uses consumed storage (you pay only for what is stored). No upfront allocation needed. But Aurora adds a per-I/O charge that RDS does not have, which can make Aurora more expensive at high I/O workloads even though storage itself is cheaper.

For a 15-40 GB database with low traffic, Aurora's I/O charges are minimal - but the instance cost floor alone makes RDS the clear choice.

---

## Summary of Key Takeaways

- Cost is the primary filter for small workloads. Aurora has a meaningful cost floor; RDS goes much lower.
- Scaling read traffic and handling unpredictable spikes is Aurora's strongest advantage over RDS.
- Multi-region DR with near-zero RPO requires Aurora Global Database - RDS cross-region replicas have higher lag.
- Extension compatibility and migration risk favor RDS when moving from on-prem PostgreSQL with custom extensions.
- Aurora Serverless v2 is the right answer when dev/staging environments need to scale to near-zero cost during inactivity.
- The key deciding factor is rarely the same for two different clients. Identify the most important constraint first, then choose the service that best addresses it.
- Start with RDS if unsure. Migrating from RDS to Aurora later is much easier than the reverse.
