# USE Exercise 05 - Backup Strategy Design

| | |
|---|---|
| **Time** | 20 minutes |
| **What you'll practice** | Designing a production backup strategy from scratch, understanding RPO/RTO trade-offs, calculating storage requirements, and planning monitoring |
| **Prerequisites** | Completed all BUILD guides 01-07 and USE exercises 01-04 |

---

## The Scenario

You just got hired as the DBA for a mid-size e-commerce company. Your first assignment:

> "Design a backup strategy for our main production database. It is 500 GB, runs 24/7, and processes customer orders around the clock. We cannot afford to lose more than 1 hour of data. Downtime for recovery should be under 4 hours."

This is a thinking exercise. You will use what you have learned from the hands-on exercises to make real architectural decisions. Grab a notebook or open a text file - you will be writing your answers.

---

## Exercise 1: Define RPO and RTO

Before designing anything, you need to understand the two most important numbers in backup strategy.

**RPO - Recovery Point Objective**

This is the maximum amount of data you can afford to lose, measured in time. If your RPO is 1 hour, that means in the worst case, you could lose up to 1 hour of transactions.

**RTO - Recovery Time Objective**

This is the maximum amount of time it should take to get the database back online after a failure. If your RTO is 4 hours, the database must be serving requests again within 4 hours of the outage.

**Your assignment says:**
- RPO: less than 1 hour
- RTO: under 4 hours

**Question A:** What does an RPO of "less than 1 hour" mean for WAL archiving?

Think about it: if the database crashes and the last archived WAL is 45 minutes old, you lose 45 minutes of data. If WAL archiving is continuous (every WAL file archived as soon as it fills), your actual data loss is only the transactions in the current, not-yet-full WAL segment - usually seconds to minutes.

Write your answer: does continuous WAL archiving meet the 1-hour RPO requirement?

**Question B:** What does an RTO of "4 hours" mean for your restore process?

You need to be able to restore a 500 GB database and replay WAL files in under 4 hours. This means your backup infrastructure (disk I/O, network, CPU for decompression) must be fast enough.

> **Concept: RPO and RTO Drive Every Decision**
> Every choice you make in your backup strategy - how often to back up, what type of backup, where to store it, how to compress it - flows from your RPO and RTO requirements. Start here, then work backward to the technical design.

---

## Exercise 2: Full Backup Frequency

**Question:** How often should you take full backups?

Consider these trade-offs:

| Frequency | Pros | Cons |
|-----------|------|------|
| Daily full | Fast restore (only 1 day of WAL to replay) | High storage cost, long backup window |
| Weekly full | Lower storage cost | Restore needs up to 7 days of WAL replay |
| Bi-weekly full | Lowest storage cost | Very long restore times, more risk |

For a 500 GB database:
- A full backup might take 30-60 minutes (depends on disk speed and compression)
- Each day of WAL replay adds time to recovery

**Write your answer:** How often would you schedule full backups? Why?

Consider: if your RTO is 4 hours and a full restore takes 1 hour, you have 3 hours left for WAL replay. How many days of WAL can you replay in 3 hours?

> **Concept: Full Backup Frequency vs. RTO**
> More frequent full backups mean faster restores (less WAL to replay) but more storage. Less frequent full backups save storage but increase recovery time. Your RTO defines the upper bound.

---

## Exercise 3: Diff or Incr Between Fulls?

Between full backups, you need either differential or incremental backups. Let's compare them.

**Differential Backup:**
- Backs up everything that changed since the last FULL backup
- Restore needs: last full + latest diff
- Gets larger as the week progresses (more changes accumulate)

**Incremental Backup:**
- Backs up everything that changed since the last backup (any type)
- Restore needs: last full + every incr in the chain
- Stays small (only changes since yesterday)
- More risk: if any incr in the chain is corrupted, the entire chain breaks

**Question A:** For a 500 GB e-commerce database with 24/7 write activity, which would you choose?

**Question B:** What happens if Wednesday's backup file gets corrupted?
- With diff: you still have Thursday's diff, which is independent of Wednesday's. You can restore from full + Thursday's diff.
- With incr: the chain is broken. Thursday's incr depends on Wednesday's. You must go back to the last full backup.

**Write your answer:** diff or incr? Explain your reasoning.

> **Concept: Diff Is Safer, Incr Is Smaller**
> Differential backups are more resilient to individual backup corruption because each one is independent from other diffs. Incremental backups use less storage because each one is smaller. For most production systems, differential is the safer choice unless storage is extremely limited.

---

## Exercise 4: Retention Policy

How long should you keep backups? This depends on several factors.

**Question A:** What is the minimum retention your business needs?

Think about: how far back might someone discover a data problem? If a bug corrupted data 3 weeks ago and nobody noticed until today, you need a backup from at least 3 weeks ago.

**Question B:** Are there regulatory requirements?

Common requirements:
- PCI DSS (credit card data): backup retention policy required, specifics vary
- HIPAA (health data): 6 years
- SOX (financial data): 7 years
- GDPR (EU personal data): keep only as long as necessary

**Question C:** What are your storage constraints?

Calculate: if your full backup is 500 GB compressed at 7x = ~72 GB, and you keep 4 weeks of backups with weekly fulls and daily diffs:
- 4 full backups: 4 x 72 GB = 288 GB
- 24 diff backups (6 per week x 4 weeks): varies, but assume average 15 GB each = 360 GB
- WAL archive for 4 weeks: depends on write volume

**Write your answer:** What retention policy would you recommend? How many full backups to keep?

> **Concept: Retention Is a Business Decision**
> The DBA proposes retention based on technical constraints and recovery needs. The business and legal teams approve based on regulatory requirements and risk tolerance. Always document the agreed retention policy.

---

## Exercise 5: Draw a Weekly Schedule

Sketch out a one-week backup schedule. Use ASCII art or a simple table.

Here is an example format:

```
Day        | Time  | Type         | Notes
-----------|-------|--------------|---------------------------
Sunday     | 02:00 | Full         | Weekly full backup
Monday     | 02:00 | Differential | Changes since Sunday's full
Tuesday    | 02:00 | Differential | Changes since Sunday's full
Wednesday  | 02:00 | Differential | Changes since Sunday's full
Thursday   | 02:00 | Differential | Changes since Sunday's full
Friday     | 02:00 | Differential | Changes since Sunday's full
Saturday   | 02:00 | Differential | Changes since Sunday's full
Continuous |  --   | WAL archive  | Every WAL segment as it fills
```

**Question A:** Why 02:00 AM?

Most e-commerce sites have their lowest traffic in the early morning hours. Backups consume disk I/O and CPU, so running them during low-traffic periods minimizes impact on customers.

**Question B:** What if your business has no "quiet hours" (global customers, 24/7 traffic)?

pgBackRest supports process-level resource limits. You can limit backup I/O and CPU usage so it does not significantly impact database performance.

**Write your answer:** Draw YOUR weekly schedule. It might differ from the example above - that is fine. Explain your choices.

---

## Exercise 6: Calculate Storage Requirements

Now use the compression ratio from your own backups (Exercise 01 of the USE series) to estimate storage.

Open a calculator or use psql for math:

```
Full backup compressed size:     _____ MB  (from your pgbackrest info)
Number of fulls to keep:         _____     (from your retention policy)
Average diff backup size:        _____ MB  (estimate or from your info)
Number of diffs per week:        _____
Weeks of retention:              _____
Estimated daily WAL volume:      _____ MB  (check your archive directory size)
```

Total estimated storage:

```
(full_size x num_fulls) + (diff_size x diffs_per_week x weeks) + (daily_wal x 7 x weeks)
```

**Question:** Is this amount of storage reasonable for your infrastructure? If not, what would you adjust?

Options to reduce storage:
1. Reduce retention (keep fewer weeks)
2. Use incremental instead of differential (smaller backups, more risk)
3. Increase compression level (slower backups, smaller files)
4. Use a remote repository with cheaper storage (S3, GCS)

> **Concept: Storage Planning Prevents Emergencies**
> Running out of backup storage is a common cause of backup failures. If your backup repository fills up, pgBackRest cannot write new backups or archive WAL files. Plan capacity ahead and set up monitoring alerts at 70% and 85% usage.

---

## Exercise 7: Monitoring and Alerting

A backup strategy without monitoring is incomplete. What alerts would you set up?

**Write your monitoring plan.** For each item, specify what to monitor and what threshold triggers an alert:

1. **WAL archiving lag** - Alert if `last_archived_time` in `pg_stat_archiver` is more than _____ minutes old
2. **Backup success** - Alert if the nightly backup has not completed by _____ AM
3. **Backup repository disk usage** - Alert at _____% full
4. **Backup duration** - Alert if a backup takes more than _____x its normal duration
5. **Archive failure count** - Alert if `failed_count` in `pg_stat_archiver` increases

**Question:** Which of these alerts is the most critical (should page you at 3 AM)?

> **Concept: Monitor the Archive, Not Just the Backup**
> Most DBAs monitor nightly backups but forget to monitor WAL archiving. A failed nightly backup means you lost today's backup. Failed WAL archiving means you are actively losing your ability to do PITR - every minute that passes without archiving is a minute of data you cannot recover.

---

## Exercise 8: Restore Testing Plan

**Question A:** How often should you test restores?

Industry best practice: at least quarterly. For critical systems: monthly.

**Question B:** What should a restore test verify?

1. The backup can be restored without errors
2. All databases are present
3. Row counts match expected values
4. Application-specific queries return correct results
5. Restore completes within the RTO window

**Question C:** Should restore tests be automated or manual?

Both. Automated tests catch regressions and run frequently. Manual tests catch issues that automated tests miss (like verifying data correctness for specific business scenarios).

**Write your answer:** How often would you test restores? What would you verify?

---

## Exercise 9: Compare to a Reference Strategy

Here is a solid production backup strategy used by many organizations:

```
Full Backup:       Weekly (Sunday 02:00)
Diff Backup:       Daily (02:00 Mon-Sat)
WAL Archiving:     Continuous
Retention:         4 full backups (4 weeks)
Repository:        Local + remote copy (S3)
Compression:       lz4 (fast, good ratio)
Encryption:        AES-256 (for remote repository)
Monitoring:        Archive lag > 5 min = warning
                   Archive lag > 15 min = critical
                   Backup failure = critical
                   Repo usage > 80% = warning
Restore Testing:   Monthly automated, quarterly manual
```

**Question:** How does your design compare? What would you change in your strategy after seeing this reference?

There is no single "correct" answer. Different databases have different needs. The key is that every decision is intentional and based on your RPO, RTO, and business requirements.

> **Concept: Defense in Depth**
> The best backup strategies have multiple layers: frequent backups, continuous WAL archiving, off-site copies, encryption, monitoring, and regular testing. Each layer protects against a different type of failure. No single layer is sufficient on its own.

---

## What You Learned

- How to define and use RPO and RTO to drive backup decisions
- How to choose between differential and incremental backups
- How to design a retention policy based on business and regulatory needs
- How to calculate storage requirements for a backup strategy
- How to plan monitoring alerts for backup and archiving health
- How to plan a restore testing program
- How real production backup strategies are structured
