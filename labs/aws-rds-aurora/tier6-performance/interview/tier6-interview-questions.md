# Tier 6 - Performance and Monitoring: Interview Questions

**Level progression:** Junior (J) through Principal (P). Questions escalate in depth. Use the level labels to target your candidate appropriately.

---

## T6.1 - CloudWatch Metrics and Enhanced Monitoring

**J1.** What is the difference between standard CloudWatch metrics and Enhanced Monitoring for RDS? What additional information does Enhanced Monitoring provide?

**J2.** Name five RDS CloudWatch metrics you would include in a production alert set and explain the threshold you would use for each.

**J3.** What does the `FreeableMemory` metric measure? Is it the same as "free RAM"? Why or why not?

**S1.** A customer says "the database was using 100% CPU but I didn't get an alert." When you check CloudWatch you see the metric only hit 100% for 4 minutes and your alarm requires 5 minutes. What would you change and why? What trade-offs does lowering the threshold introduce?

**S2.** You have a database with Enhanced Monitoring enabled. You see that `wal` process is consuming 40% of CPU in the OS process list, but the standard CloudWatch CPUUtilization metric shows only 25%. Explain this discrepancy. What does it tell you about your workload?

**S3.** A DBA asks you to set a CloudWatch alarm for "high read latency" but you know the instance has mixed OLTP (1ms reads) and analytics queries (2+ second reads). How would you design the alarm to avoid false positives while catching real storage problems?

**L1.** Design a complete CloudWatch monitoring strategy for a multi-region Aurora PostgreSQL cluster with 3 readers per cluster. Include what metrics, at what granularity, with what alarms, and how you would handle region-specific vs. global alerting.

**L2.** You are migrating from on-premises PostgreSQL to RDS. The on-premises system had detailed OS-level monitoring (CPU per core, memory pages in/out, disk queue depth). Map each of those to their closest RDS/Enhanced Monitoring equivalents and identify which on-premises metrics have no direct RDS equivalent.

**P1.** CloudWatch metrics have a minimum 1-minute resolution in standard mode. Describe a production performance problem that would be invisible at 1-minute granularity but visible at 10-second or 1-second granularity. How would you detect and investigate such problems on RDS?

**P2.** A financial services company requires a 99.99% uptime SLA. Design a monitoring architecture where your alerting latency (time from incident to page) is consistently under 60 seconds. Include the CloudWatch configuration, SNS routing, and on-call process.

---

## T6.2 - Performance Insights

**J1.** What is DB Load in Performance Insights? What does a DB Load of 1.0 mean? What does a DB Load of 8.0 mean on a 4 vCPU instance?

**J2.** Performance Insights shows "Top SQL" and "Top waits." What is the difference and when would you look at each?

**J3.** How does Performance Insights normalize SQL statements? Why is normalization important?

**S1.** You open Performance Insights and see DB Load is 3x above the vCPU line, with `IO:DataFileRead` as the dominant wait event. Walk me through your next 5 minutes of investigation. What queries do you run? What are you looking for?

**S2.** A query appears in Performance Insights Top SQL consuming 40% of DB Load, but when developers look at it in their application metrics it completes in 50ms. How do you reconcile these two data points? What could cause this?

**S3.** You are enabling Performance Insights on a production database with 500GB of data and 200 concurrent connections. What retention period do you choose and why? What is the cost implication?

**L1.** A junior DBA comes to you and says "Performance Insights shows a query that runs 10,000 times per minute at 2ms average is consuming more DB Load than a query that runs once per minute at 30 seconds average." Is this correct? Explain DB Load calculation in enough detail that the junior DBA can reproduce it in a spreadsheet.

**L2.** You want to build an automated performance regression detection system that uses the Performance Insights API. If a new deployment causes a query's DB Load contribution to increase by more than 50% compared to the previous hour, you want to alert. Design the architecture (Lambda, EventBridge, PI API calls) and the detection algorithm.

**P1.** Performance Insights has a 7-day free tier and up to 2-year paid retention. You manage 50 RDS instances across 5 environments (prod, staging, dev, qa, test). Design a retention policy that balances cost and diagnostic capability. Justify every decision.

---

## T6.3 - Wait Event Tuning

**J1.** Name 5 PostgreSQL wait events and what each one indicates about database behavior.

**J2.** Your database shows `Lock:relation` as the dominant wait event. What are the possible causes? What query would you run to find the specific cause?

**J3.** What does `IO:BufFileRead` tell you? What parameter change usually fixes it?

**S1.** You see high `LWLock:buffer_mapping` in Performance Insights. Explain what this means at the PostgreSQL internal level. What are the fix options? What are the trade-offs of each?

**S2.** A database has `CPU` as its dominant "wait" event (meaning sessions are actively computing, not waiting). What queries would you run in pg_stat_statements to identify which queries are responsible? How do you distinguish a CPU-heavy query that is unavoidable from one that has a missing index?

**S3.** You are tuning a database that shows alternating between `IO:DataFileRead` and `IO:WALWrite` as dominant wait events throughout the day. The IO pattern correlates with business hours. What does this tell you, and what tuning options do you consider?

**L1.** Design a systematic wait event tuning process for a new production database you have taken over. You have no previous baseline. Walk through how you establish a baseline, identify the top 3 wait events, prioritize which to fix first, and measure improvement.

**P1.** You are presenting a post-mortem for a 4-hour performance incident. The incident started with `IO:DataFileRead`, then transitioned to `Lock:relation`, then `Client:ClientRead`. Explain the cascade: how does high disk I/O cause lock contention, which then causes client waits? What is the single root cause and where would you apply the fix?

---

## T6.4 - DevOps Guru

**J1.** What is the difference between a reactive and proactive DevOps Guru insight?

**J2.** How long does DevOps Guru need before it can generate useful insights? Why?

**J3.** What data sources does DevOps Guru analyze for RDS instances?

**S1.** DevOps Guru fires a proactive insight: "Storage growth rate suggests disk exhaustion in 4 days." You investigate and find this is due to a temporary bulk load that is now complete. How do you handle this without disabling DevOps Guru's future alerts?

**S2.** A team wants to use DevOps Guru on all 200 of their RDS instances. They are concerned about cost. How would you estimate the monthly cost, and what strategy would you recommend for prioritizing which instances to cover?

**L1.** You want to integrate DevOps Guru insights with your existing PagerDuty setup so that HIGH severity insights create P1 incidents and MEDIUM severity insights create P2 tickets. Design the EventBridge + Lambda architecture. Include the EventBridge event pattern, Lambda logic, and PagerDuty API calls.

---

## T6.5 - pg_stat_statements

**J1.** What does pg_stat_statements track? How does it differ from looking at the PostgreSQL log?

**J2.** What does `shared_blks_read` measure and what does a high value indicate?

**J3.** Why is `stddev_exec_time` a useful column? What does high standard deviation relative to the mean indicate?

**S1.** A developer says "this query runs fine in staging but is slow in production." Both environments have the same code. Using pg_stat_statements, what queries would you run on each environment to identify the difference? What specific columns would you compare?

**S2.** You run the top-10-by-total-time query and see one query consuming 60% of all execution time. It runs 50,000 times per day at an average of 200ms. The query is: `SELECT * FROM orders WHERE customer_id = $1`. What is your next step and why?

**S3.** pg_stat_statements.max defaults to 5000 on RDS. A production database with many microservices is evicting queries from pg_stat_statements before you can investigate them. You see `pg_stat_statements_dealloc` is very high. What do you change and what is the trade-off?

**L1.** You are building a weekly automated performance report for 20 production databases. The report should identify: top 5 queries by total time, queries with significant regression (worse than last week), and newly appeared queries not seen the previous week. Design the system including how you store historical pg_stat_statements data, how you detect regression, and how you distribute the report.

**P1.** A database runs 500 unique parameterized queries from 10 microservices. pg_stat_statements normalizes them all correctly. However, you suspect one microservice is causing issues but cannot identify which because pg_stat_statements does not capture the calling service. What approaches would you use to attribute database load to specific application services?

---

## T6.6 - Optimized Reads

**J1.** What is RDS Optimized Reads and what types of I/O does it accelerate?

**J2.** What is the difference between RDS Optimized Reads and Aurora's tiered cache?

**J3.** Which instance families support Optimized Reads? How do you identify them?

**S1.** Your database has `IO:BufFileRead` as a significant wait event. You have two options: increase work_mem or switch to an instance with Optimized Reads. How do you decide which to use?

**S2.** Aurora tiered cache is enabled. How do you measure whether it is actually helping? What metrics or queries tell you the cache hit rate for the NVMe tier?

**L1.** You have an OLTP database that runs alongside 20 analytical reporting queries per hour. The analytical queries do large GROUP BY operations on 100GB of data, causing significant `IO:BufFileRead`. The OLTP queries are 1-5ms and must stay that way. Design a solution that isolates the analytical query impact from the OLTP queries.

---

## T6.7 - Optimized Writes and Aurora I/O-Optimized

**J1.** What is a full-page image in PostgreSQL WAL? Why is it normally written?

**J2.** How does RDS Optimized Writes eliminate full-page images safely?

**J3.** What is the break-even point for switching from Aurora Standard to Aurora I/O-Optimized?

**S1.** After enabling Optimized Writes, you observe that WAL volume decreased by 35% and replica lag improved. Your write IOPS did not change. Explain exactly what happened.

**S2.** A customer has an Aurora cluster with 500GB of data. They are running 5 billion I/Os per month. Calculate their monthly storage cost under Aurora Standard and Aurora I/O-Optimized. Which should they use? Use current AWS us-east-1 pricing.

**L1.** You are advising a company to switch their Aurora clusters to I/O-Optimized. They have 30 clusters ranging from 50GB to 10TB. Describe the methodology for evaluating each cluster, including what data you would collect, how you would calculate the break-even, and how you would prioritize the migration.

---

## T6.8 - Cluster Cache Management

**J1.** What problem does Cluster Cache Management solve?

**J2.** What is a "cold cache" and how long does it typically take for a new Aurora primary to warm up without CCM?

**J3.** What parameter enables CCM at the cluster level? What parameter is required on the designated reader?

**S1.** You enable CCM on an Aurora cluster with 3 readers. Only one reader is designated as the CCM failover target. A failover occurs to a non-designated reader. What happens to cache warmth? How do you ensure the right reader is always promoted?

**S2.** CCM requires the designated reader to have the same instance class as the writer. Your company policy allows reader instances to be smaller than the writer to save cost. How do you balance the CCM requirement against the cost policy?

**L1.** You are designing an Aurora architecture for a financial application where post-failover performance degradation of more than 5% for more than 2 minutes is unacceptable. Describe all the components you would put in place (CCM, connection pooling, DNS TTL, application retry logic) to meet this requirement.

---

## T6.9 - Connection Management and RDS Proxy

**J1.** Why does PostgreSQL's process-per-connection model cause problems at high connection counts?

**J2.** What is connection pinning in RDS Proxy? Name 3 things that cause pinning.

**J3.** What is the primary benefit of RDS Proxy for serverless applications?

**S1.** You have RDS Proxy deployed. Your CloudWatch metrics show `Pinned Connections` is consistently 70% of total connections. This means you are not getting the multiplexing benefit. What would you investigate to reduce pinning?

**S2.** An application developer argues that they do not need RDS Proxy because their application already uses a connection pool (HikariCP in Java). Is the developer correct? When does application-level pooling make RDS Proxy unnecessary, and when does it not?

**S3.** A security team requires that database passwords must never be visible to application servers. They should be rotated automatically every 30 days. How does RDS Proxy enable this? Walk through the architecture.

**L1.** You have 200 Lambda functions that each connect to the same RDS database. Without a proxy, 200 concurrent invocations = 200 connections. With a proxy, the pool is managed. However, Lambda cold starts mean connections are opened and closed frequently. Describe how RDS Proxy handles this Lambda connection pattern, including what happens to connections during Lambda cold starts, warm reuse, and scaling events.

**P1.** Your company is moving to a microservices architecture with 50 services, each connecting to the same Aurora cluster. You need to design the connection management strategy. Some services are always-on, some are event-driven (Lambda), and some are batch jobs. Design a comprehensive connection management architecture that optimizes for both performance and cost.

---

## T6.10 - Autovacuum at Scale

**J1.** What happens if autovacuum never runs on a table? Name three consequences.

**J2.** What is the default `autovacuum_vacuum_scale_factor`? Why is this inappropriate for a table with 100 million rows?

**J3.** What is TXID wraparound and what does PostgreSQL do if it is not prevented?

**S1.** You have a table with 500 million rows. It is updated approximately 10% per day. Calculate: at what dead tuple count does autovacuum trigger with default settings? With a 0.01 scale factor? How does this affect the amount of bloat allowed to accumulate?

**S2.** A DBA reports that autovacuum runs continuously on a busy table but dead tuples never drop below 30%. What are the possible explanations? How would you diagnose which is causing the problem?

**S3.** A production database is experiencing transaction ID wraparound warnings (age > 1.5 billion). Autovacuum has not been able to keep up. The database serves 10,000 transactions per minute. Describe the exact steps you take to resolve this without application downtime.

**L1.** You are inheriting a database that has never been properly tuned for autovacuum. It has 400 tables, ranging from 10MB to 2TB. Describe a systematic process to assess and tune autovacuum for each table, including how you prioritize, what settings you apply for each category of table, and how you validate the changes.

**P1.** A team argues that VACUUM FULL is better than autovacuum for reclaiming bloat because it compacts the table fully. Counter this argument. When would you use VACUUM FULL and when not? What are the operational risks and what alternatives exist?

---

## T6.11 - Query Plan Management

**J1.** What is query plan instability? Why is it a problem?

**J2.** Name the four plan statuses in Aurora QPM and what each means.

**J3.** What does `evolve_plan_baselines` do and when would you use it?

**S1.** You are about to run a PostgreSQL minor version upgrade on an Aurora cluster. You are worried about plan regressions. Describe a pre-upgrade process using QPM to protect your top 50 most critical queries.

**S2.** A developer complains that after enabling QPM with `use_plan_baselines = true`, their new index is not being used even though EXPLAIN shows it would be beneficial. What is causing this? How do you fix it without disabling QPM?

**L1.** You are implementing QPM in a production environment with 500+ unique query types. You cannot approve plans manually for all of them. Design an automated process for: (1) capturing plans during a staging load test, (2) automatically approving stable plans, (3) identifying and flagging potentially unstable plans for manual review, and (4) monitoring for plan regressions in production.

---

## T6.12 - Memory Parameter Tuning

**J1.** What is the rule of thumb for `shared_buffers`? What happens if you set it too high?

**J2.** Why does `effective_cache_size` not actually allocate memory? What does it affect?

**J3.** You have a 16GB instance with 100 connections. Calculate a safe global `work_mem` value. Show your work.

**S1.** A developer wants to increase `work_mem` to 1GB globally to speed up analytical queries. The instance has 32GB RAM and 200 max connections. What is the worst-case memory consumption if all sessions run large joins? What would you recommend instead?

**S2.** A database's buffer hit ratio is 94% for OLTP queries. The instance is a db.r6g.xlarge with 32GB RAM. What does 94% tell you, and what are your options for improving it to 99%?

**S3.** A DBA proposes increasing `shared_buffers` to 50% of RAM because "more cache = better." Explain why this is often wrong and what problems it can cause.

**L1.** You are given a new production database with a 64GB Aurora instance. You have no prior metrics. Describe the 30-day memory tuning process: what you measure in week 1, what changes you make in week 2, how you validate in week 3, and what ongoing monitoring you put in place in week 4.

**P1.** A company runs a PostgreSQL database that serves both high-frequency OLTP (5000 transactions/second) and large analytical queries (10 per hour, each scanning billions of rows). These two workloads have conflicting memory requirements: OLTP needs low work_mem and fast cache hits, analytics needs very high work_mem and doesn't benefit from the OLTP cache. Design a complete memory architecture that serves both workloads on the same instance, including any parameter group tricks, per-session settings, and application-level connection management.
