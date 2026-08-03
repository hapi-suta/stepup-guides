# SURVIVE 01: Error Budget Exhausted

**Module 07: Database SRE Practices**
**Difficulty: Medium**
**Estimated Time: 30-45 minutes**

---

## The Scenario

It is May 1st - one month into Q2. Your PostgreSQL service has an availability SLO of 99.9% measured quarterly. The quarterly error budget is 129.6 minutes (2.16 hours).

In April alone, you had:
- **April 3:** 45-minute outage (Patroni failover due to disk full on primary)
- **April 12:** 30-minute degradation (connection pool exhaustion during traffic spike)
- **April 21:** 20-minute outage (bad migration locked a table in production)
- **April 28:** 40-minute outage (network partition caused split-brain, manual intervention required)

**Total downtime: 135 minutes.** Your quarterly error budget of 129.6 minutes is exhausted - and there are still 2 months left in the quarter.

The engineering manager asks: "Can we deploy the new payment feature this week? It includes 3 schema migrations."

---

## Your Mission

1. **Acknowledge the budget breach** - calculate the exact status
2. **Implement a change freeze** - define the rules
3. **Analyze the incidents** - identify the top causes of unreliability
4. **Propose reliability fixes** - concrete actions to restore the budget
5. **Communicate to stakeholders** - write the email/Slack message

---

## Part 1: Calculate Error Budget Status

```bash
mkdir -p ~/dba-labs/sre-practice/survive-budget
cd ~/dba-labs/sre-practice/survive-budget
vi error-budget-status.md
```

```markdown
# Error Budget Status - Q2 2026

## SLO: 99.9% Availability (Quarterly)

| Metric | Value |
|--------|-------|
| Quarter period | April 1 - June 30 (91 days) |
| Total minutes in quarter | 131,040 |
| Error budget (0.1%) | 131.04 minutes |
| Budget consumed | 135 minutes |
| Budget remaining | -3.96 minutes |
| Budget status | EXHAUSTED (103.0% consumed) |
| Days remaining in quarter | 61 |

## Incident Log

| Date | Duration | Cause | Category |
|------|----------|-------|----------|
| Apr 3 | 45 min | Disk full -> Patroni failover | Capacity |
| Apr 12 | 30 min | Connection pool exhaustion | Scaling |
| Apr 21 | 20 min | Bad migration locked table | Change management |
| Apr 28 | 40 min | Network partition -> split-brain | Infrastructure |

## Availability This Quarter
(131,040 - 135) / 131,040 = 99.897%
SLO: 99.9% -- BREACHED
```

---

## Part 2: Implement a Change Freeze

When the error budget is exhausted, the SRE principle is clear: freeze non-critical changes. Every change carries risk of another outage, and you have no budget left.

```bash
vi change-freeze-policy.md
```

```markdown
# Change Freeze Policy - Q2 2026

## Effective: May 1, 2026
## Expires: June 30, 2026 (end of quarter) or when budget is restored

## What is Frozen
- [ ] All non-critical schema migrations
- [ ] New feature deployments that touch the database
- [ ] Configuration changes (postgresql.conf, pg_hba.conf)
- [ ] Index additions or removals
- [ ] Extension installations
- [ ] Any operation that requires PostgreSQL restart

## What is Allowed
- [ ] Critical security patches (CVEs with CVSS >= 7.0)
- [ ] Bug fixes for existing data corruption issues
- [ ] Reliability improvements that directly address the root causes of Q2 incidents
- [ ] Monitoring and alerting improvements (read-only changes)
- [ ] Backup and recovery testing (non-disruptive)

## Approval Process During Freeze
All allowed changes require:
1. Written justification linking to an incident action item
2. DBA team lead review
3. Tested on staging with production-scale data
4. Deployment during low-traffic window
5. Rollback plan tested and documented

## How to Restore the Budget
The freeze lifts when:
- All 4 incident root causes have been addressed (action items complete)
- A new quarter begins (budget resets)
- Management explicitly approves resuming deployments (accepting SLO risk)
```

---

## Part 3: Analyze the Root Causes

Categorize the four incidents and identify patterns:

```bash
vi root-cause-analysis.md
```

```markdown
# Root Cause Analysis - Q2 Incidents

## Pattern Analysis

| Category | Incidents | Total Downtime | % of Budget |
|----------|-----------|---------------|-------------|
| Capacity/Monitoring | 1 (disk full) | 45 min | 34% |
| Scaling | 1 (connection pool) | 30 min | 23% |
| Change Management | 1 (bad migration) | 20 min | 15% |
| Infrastructure | 1 (network partition) | 40 min | 31% |

## Root Cause 1: Disk Full (April 3)
**What happened:** WAL files accumulated because archive_command was failing silently.
Disk reached 100%, PostgreSQL crashed, Patroni failover took 45 minutes because
the standby also had high disk usage.

**Root cause:** No monitoring on archive success/failure. No alert on disk > 80%.

**Fix:**
- Add disk usage alerts at 70% (warning) and 85% (critical)
- Add archive lag monitoring (alert if archive falls behind by > 100 WAL files)
- Implement WAL cleanup automation (pg_archivecleanup)
- Estimated effort: 4 hours

## Root Cause 2: Connection Pool Exhaustion (April 12)
**What happened:** Marketing campaign drove 3x normal traffic. Connection pool
hit max. New connections queued, then timed out. Application reported 500 errors.

**Root cause:** PgBouncer default_pool_size was 20 (adequate for normal load,
not for spikes). No connection count alerting.

**Fix:**
- Increase default_pool_size to 50 with reserve_pool_size of 10
- Add connection utilization alerts at 70% and 85%
- Implement connection queuing monitoring in PgBouncer
- Load test at 3x normal traffic before next marketing campaign
- Estimated effort: 2 hours

## Root Cause 3: Bad Migration (April 21)
**What happened:** A migration ran `ALTER TABLE orders ADD CONSTRAINT chk_status ...`
without NOT VALID. This acquired an ACCESS EXCLUSIVE lock on the busiest table,
blocking all queries for 20 minutes until the constraint scan completed.

**Root cause:** No migration review process. No CI check for dangerous DDL patterns.
No lock_timeout set in production migrations.

**Fix:**
- Add CI lint step checking for dangerous DDL (CREATE INDEX without CONCURRENTLY,
  ADD CONSTRAINT without NOT VALID)
- Require `SET lock_timeout = '5s'` in all production migration files
- Require DBA review on all migration PRs (branch protection rule)
- Test all migrations on production-scale data copy before deployment
- Estimated effort: 8 hours

## Root Cause 4: Network Partition (April 28)
**What happened:** Network partition between AZs caused etcd to lose quorum.
Patroni could not determine the leader. Both standbys refused to promote because
they could not confirm the primary was down. Manual intervention was required.

**Root cause:** etcd cluster was in a single AZ. Network partition took out
all etcd nodes simultaneously.

**Fix:**
- Spread etcd nodes across 3 AZs (currently all in us-east-1a)
- Configure Patroni watchdog for faster failure detection
- Write and test a manual failover runbook for when automatic failover fails
- Schedule quarterly chaos experiment: network partition test
- Estimated effort: 16 hours
```

---

## Part 4: Reliability Improvement Plan

```bash
vi reliability-plan.md
```

```markdown
# Reliability Improvement Plan - Q2 2026

## Priority Ranking (by incident prevention impact)

| Priority | Action | Effort | Prevents | Budget Saved |
|----------|--------|--------|----------|-------------|
| P1 | Add disk and archive monitoring | 4 hrs | 45 min incidents | 34% of budget |
| P1 | Migration CI lint + DBA review gate | 8 hrs | 20 min incidents | 15% of budget |
| P2 | PgBouncer tuning + connection alerts | 2 hrs | 30 min incidents | 23% of budget |
| P2 | Spread etcd across AZs | 16 hrs | 40 min incidents | 31% of budget |
| P3 | Quarterly chaos experiments | 4 hrs/quarter | Unknown future incidents | Proactive |
| P3 | Manual failover runbook | 4 hrs | Reduces MTTR | Time savings |

## Sprint Plan (May)

### Week 1 (May 1-7) - Quick Wins
- [x] Deploy disk monitoring alerts (P1)
- [x] Deploy archive lag monitoring (P1)
- [x] Increase PgBouncer pool sizes (P2)
- [x] Deploy connection utilization alerts (P2)

### Week 2 (May 8-14) - Migration Safety
- [ ] Build CI lint step for dangerous DDL
- [ ] Add lock_timeout requirement check
- [ ] Configure branch protection requiring DBA review

### Week 3 (May 15-21) - Infrastructure
- [ ] Plan etcd AZ migration
- [ ] Deploy etcd to 3 AZs

### Week 4 (May 22-31) - Testing
- [ ] Write manual failover runbook
- [ ] Run chaos experiment: network partition
- [ ] Run chaos experiment: disk fill
```

---

## Part 5: Stakeholder Communication

Write the message to the engineering manager:

```bash
vi stakeholder-communication.md
```

```markdown
Subject: Database Change Freeze - Error Budget Exhausted for Q2

Team,

Our PostgreSQL service has consumed 103% of its quarterly error budget
(135 minutes of downtime against a 131-minute budget). We have breached
our 99.9% availability SLO for Q2.

**What this means:**
We are implementing a change freeze on non-critical database changes for
the remainder of Q2. This includes the payment feature migrations planned
for this week.

**What caused this:**
Four incidents in April consumed our entire budget. The root causes are
disk monitoring gaps, connection pool sizing, lack of migration review,
and single-AZ etcd deployment. None of these were caused by feature work,
but deploying more changes while the underlying issues are unfixed increases
the risk of further outages.

**What we are doing:**
We have a 4-week reliability improvement sprint:
- Week 1: Deploy monitoring for disk, connections (done)
- Week 2: Add migration safety checks in CI
- Week 3: Spread etcd across AZs
- Week 4: Chaos testing to verify fixes

**When the freeze lifts:**
Once all four root causes are addressed (target: end of May), we will
resume normal deployment velocity. The payment feature migrations can
be scheduled for the first week of June.

**What is still allowed:**
Security patches, bug fixes for data integrity issues, and reliability
improvements are exempt from the freeze.

I am happy to discuss this in our next sync.

- [Your Name], DBRE
```

---

## Validation Checklist

- [ ] Error budget calculation is correct (show the math)
- [ ] Change freeze policy defines what is frozen AND what is allowed
- [ ] All 4 incidents have documented root causes
- [ ] Each root cause has a concrete fix with effort estimate
- [ ] Reliability plan is prioritized by budget impact
- [ ] Sprint plan has weekly milestones
- [ ] Stakeholder communication explains the "why" and "when it lifts"
- [ ] The payment feature deployment is rescheduled, not cancelled

---

## Lessons Learned

1. **Error budgets force hard conversations.** Without an error budget, the answer to "can we deploy?" is always "yes." With a budget, you have data to justify a freeze.
2. **Four small incidents add up.** No single incident was catastrophic, but together they consumed the entire budget. Track cumulative impact, not just individual incidents.
3. **Monitoring gaps cause the worst incidents.** The disk full outage (45 min) was entirely preventable with a $0 monitoring check. Invest in monitoring before it costs you.
4. **Change freezes are temporary.** The goal is not to stop deploying - it is to fix the root causes so you can deploy safely. Time-box the freeze and use it to drive reliability work.
5. **Communicate proactively.** Stakeholders respect data-driven decisions. "We consumed 103% of our error budget" is more compelling than "we feel like we should slow down."
