# Interview Questions: Database SRE Practices

**Module 07**

---

## Question 1: What is an error budget and how does it influence your decision to deploy changes?

### What the interviewer is looking for
- Clear definition of error budget with math
- Understanding of how it connects SLOs to deployment decisions
- Practical examples of budget-driven decisions

### Strong Answer Framework

"An error budget is the amount of unreliability your SLO allows. It is calculated as `1 - SLO target`, expressed in minutes of allowed downtime per measurement period."

**The math:**

"If our PostgreSQL service has a 99.9% quarterly availability SLO, our error budget is 0.1% of the quarter. For a 90-day quarter, that is 129,600 minutes * 0.001 = 129.6 minutes of allowed downtime."

**How it drives deployment decisions:**

"The error budget creates a direct link between reliability and velocity. When the budget is healthy (say, 80% remaining with 60% of the quarter elapsed), we deploy freely - we have room for risk. When the budget is low (less than 25% remaining), we slow down - only critical fixes and reliability improvements."

"If the budget is exhausted, we implement a change freeze. This is not punitive - it is a signal that we need to focus on reliability before shipping more features. We analyze the incidents that consumed the budget, fix the root causes, and resume deployments once the underlying issues are addressed."

**Real-world example:**

"In a previous quarter, we consumed 80% of our error budget in the first month due to a recurring replication issue. We froze feature deployments for two weeks, invested that time in fixing the replication automation, and finished the quarter at 95% budget consumption instead of breaching. The engineering team was initially frustrated by the freeze, but after seeing that the fix eliminated the recurring outages, they understood the trade-off."

---

## Question 2: Walk through your incident response process for a database outage

### What the interviewer is looking for
- Structured approach (not ad-hoc debugging)
- Clear communication practices
- Post-incident learning

### Strong Answer Framework

"I follow a structured 5-phase incident response process:"

**Phase 1: Detection and Declaration (0-5 minutes)**
- Alert fires (PagerDuty, monitoring)
- Acknowledge the alert
- Assess severity: SEV1 (total outage), SEV2 (degraded), SEV3 (minor)
- Declare the incident: "This is a SEV1. I am the Incident Commander."
- Send initial communication to stakeholders

**Phase 2: Triage (5-15 minutes)**
- Run the standard diagnostic queries:
  - `pg_isready` - is PostgreSQL accepting connections?
  - `pg_stat_activity` - what is happening right now?
  - `pg_stat_replication` - is replication healthy?
  - System metrics: CPU, memory, disk, network
- Identify: is this a known incident type with a runbook?
- If yes, follow the runbook. If no, investigate further.

**Phase 3: Mitigation (15-60 minutes)**
- Focus on restoring service first, root cause analysis second
- Apply the safest mitigation that restores service
- Examples: failover to standby, kill blocking query, increase connection limit
- Provide status updates every 15 minutes

**Phase 4: Resolution and Verification**
- Confirm all SLIs are back within SLO
- Monitor for 30 minutes to ensure stability
- Declare resolution: "Service is restored. We will schedule a PIR."

**Phase 5: Post-Incident Review (within 48 hours)**
- Blameless review: "what allowed this to break" not "who broke it"
- Document timeline, root cause, contributing factors
- Assign action items with owners and due dates
- Share learnings with the broader team

"The key principle is: mitigate first, investigate later. During a SEV1, I do not spend 30 minutes understanding the root cause while users are affected. I restore service, then do the deep analysis in the PIR."

---

## Question 3: What is toil and how do you measure it?

### What the interviewer is looking for
- Precise definition of toil
- Awareness of the 50% target
- Practical examples and measurement approach

### Strong Answer Framework

"Toil is work that is manual, repetitive, automatable, tactical, and has no enduring value. It scales linearly with the number of systems you manage."

**How I measure it:**

"I track my tasks for a representative week, categorizing each as toil or engineering work. For each toil task, I record the frequency, time per occurrence, and whether it is automatable."

**Concrete examples from my experience:**

| Task | Frequency | Time | Annual Hours | Automated? |
|------|-----------|------|-------------|------------|
| Create database users | 3x/week | 30 min | 78 hrs | Yes - built self-service script |
| Verify backup integrity | Daily | 15 min | 65 hrs | Yes - automated restore + verify |
| Check disk across servers | Daily | 20 min | 87 hrs | Yes - monitoring dashboard |
| Weekly capacity report | Weekly | 2 hrs | 104 hrs | Yes - automated with Python + cron |
| SSL certificate rotation | Monthly | 30 min | 6 hrs | Yes - certbot + Ansible |

"Before automation, my toil percentage was around 65%. After building these five automations (about 40 hours of development time), I brought it down to 30%. The SRE target is under 50%. The time freed up went into building better monitoring and chaos engineering practices."

**The business case for reducing toil:**

"Every hour I spend on toil is an hour I am not spending on engineering work that permanently improves reliability. If I am manually creating users 78 hours per year, spending 16 hours to build a self-service tool saves 62 hours per year. That is over 7 days of engineering time recovered."

---

## Question 4: How would you design a chaos experiment for a PostgreSQL HA cluster?

### What the interviewer is looking for
- Structured experiment design (not just "kill a server")
- Awareness of blast radius and safety
- Measurement and learning focus

### Strong Answer Framework

"I would design the experiment using the standard chaos engineering process: steady state, hypothesis, injection, observation, learning."

**Experiment: Kill the Primary - Test Automatic Failover**

**Steady state definition:**
- Patroni cluster with 1 primary, 2 standbys
- Availability SLI: health check succeeds every 10 seconds
- Latency SLI: p95 < 50ms
- Replication lag: < 1 second on both standbys

**Hypothesis:**
"When the primary is killed, Patroni will promote a standby within 30 seconds. Write operations will fail for at most 30 seconds. Read operations on standbys will continue uninterrupted. No committed transactions will be lost."

**Blast radius:**
- The primary PostgreSQL instance will be stopped
- Application writes will fail temporarily
- Standbys and PgBouncer are not directly affected

**Rollback plan:**
- If failover does not complete in 60 seconds, manually promote a standby
- If data inconsistency is detected, halt the experiment and restore from backup

**Execution:**

1. Record baseline SLIs (5 minutes of monitoring)
2. Start a continuous write test: INSERT a row every second with a sequence number
3. Kill Patroni on the primary: `sudo systemctl stop patroni`
4. Monitor:
   - Patroni logs on standbys (watching for promotion)
   - PgBouncer reconnection to new primary
   - Application error rates
   - Continuous write test for gaps in sequence numbers
5. Record: time to failover, number of failed writes, whether any sequence numbers are missing
6. After failover completes, restart Patroni on old primary (it should rejoin as standby)

**Measurements:**

| Metric | Target | Actual |
|--------|--------|--------|
| Failover time | < 30s | ___ |
| Failed writes | < 30 | ___ |
| Lost transactions | 0 | ___ |
| Read availability during failover | 100% | ___ |
| Time for old primary to rejoin | < 5 min | ___ |

"I would run this in staging first with production-equivalent configuration. After confirming it works in staging, I would schedule a production gameday with the application team present, during a low-traffic window."

---

## Question 5: Explain the difference between a traditional DBA and a Database Reliability Engineer

### What the interviewer is looking for
- Understanding of the SRE mindset shift
- Not dismissive of traditional DBA skills
- Practical understanding of the DBRE role

### Strong Answer Framework

"A traditional DBA and a DBRE solve the same fundamental problem - keeping databases reliable and performant. The difference is in approach and mindset."

**Traditional DBA focuses on:**
- Direct, hands-on management of individual databases
- Manual performance tuning (EXPLAIN ANALYZE, index analysis)
- Reactive incident response (fix it when it breaks)
- Change avoidance (stability through minimizing changes)
- Deep expertise in one or two database platforms
- Knowledge as the primary tool (the DBA's brain is the system)

**DBRE focuses on:**
- Building systems that manage databases at scale
- Automated performance monitoring and alerting (SLI-based)
- Proactive reliability engineering (chaos experiments, error budgets)
- Controlled change velocity (error budgets, CI/CD, automated testing)
- Platform thinking (self-service, guardrails, automation)
- Code as the primary tool (if a human does it twice, automate it)

**Where they overlap:**
Both need deep PostgreSQL knowledge. A DBRE who cannot read an EXPLAIN plan or tune autovacuum is not effective. The database expertise is the foundation - the SRE practices are built on top of it.

**The key mindset shifts:**

| Aspect | Traditional DBA | DBRE |
|--------|----------------|------|
| Reliability | "Is it up?" | "Is it meeting its SLO?" |
| Changes | "Changes are risky" | "Error budget determines deployment speed" |
| Outages | "Fix it and move on" | "Blameless PIR, prevent recurrence" |
| Manual work | "It is part of the job" | "It is toil - automate it" |
| Scaling | "Add more RAM" | "Add more automation" |
| Testing | "Test in staging" | "Also test in production (chaos engineering)" |

"In my experience, the best DBREs are traditional DBAs who learned software engineering practices. The database knowledge takes years to build. The SRE practices can be learned in months. The combination is what makes a DBRE effective - you know what to automate because you have done it manually thousands of times."
