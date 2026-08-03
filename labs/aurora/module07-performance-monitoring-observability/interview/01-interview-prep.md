# Module 07 - Performance, Monitoring and Observability: Interview Questions

**Level progression:** Junior (J) through Principal (P). Questions escalate in depth. Use the level labels to target your candidate appropriately.

---

## CloudWatch Metrics and Enhanced Monitoring

**J1.** What is the difference between standard CloudWatch metrics and Enhanced Monitoring for RDS? Name two things Enhanced Monitoring shows that CloudWatch Metrics does not.

**J2.** Name five RDS CloudWatch metrics you would include in a production alert set. For each, state what threshold you would use and why.

**J3.** What does FreeableMemory measure? Is it the same as "free RAM"? Why does this distinction matter?

**S1.** You have an Aurora cluster with 2 readers. CloudWatch shows CPUUtilization at 95% on the writer but 15% on both readers. What is your investigation plan? What could cause this pattern?

**S2.** A team asks you to set Enhanced Monitoring granularity to 1 second on all 20 production instances. What is the cost implication? What would you recommend instead?

**L1.** Design a complete CloudWatch monitoring strategy for a multi-region Aurora cluster with 3 readers per region. Include what metrics, at what granularity, with what alarms, and how you handle region-specific vs global alerting.

---

## Performance Insights

**J1.** What is DB Load in Performance Insights? What does it mean when DB Load exceeds the vCPU count?

**J2.** Explain the difference between Top SQL and Top Waits in Performance Insights. When would you look at each?

**J3.** A query shows DB Load contribution of 2.5 on a 4-vCPU instance. What does this mean? Is this a problem?

**S1.** Performance Insights shows IO:DataFileRead as the dominant wait event for the past 2 hours. Walk through your investigation: what do you check first, second, third? What are the possible root causes?

**S2.** A developer says "my query completes in 5ms" but PI shows it contributing 40% of total DB Load. How do you reconcile these two data points?

**L1.** You want to build an automated system that detects query regressions after deployments. Using the PI API, describe the architecture: when do you sample, what do you compare, what constitutes a regression, and how do you notify the team?

**P1.** You manage 50 Aurora instances across production, staging, and dev. Design a PI retention strategy that balances cost against diagnostic capability. Justify each decision.

---

## pg_stat_statements and Slow Query Analysis

**J1.** What does pg_stat_statements track? How is it different from the PostgreSQL slow query log?

**J2.** Write a query to find the top 5 queries by total execution time from pg_stat_statements. Explain what each column tells you.

**J3.** What does a high stddev_exec_time relative to mean_exec_time indicate about a query?

**S1.** A query's shared_blks_read is 50,000 per call but shared_blks_hit is only 200. What does this tell you? What would you do?

**S2.** pg_stat_statements shows a query running 100,000 times per day at 1ms average. Is this a problem? When would it become one? How would you know?

**S3.** You reset pg_stat_statements on Friday at 5 PM. On Monday at 9 AM, you find a query that was not in the top 10 before but is now #1 by total_exec_time. What is your investigation process?

**L1.** Design a system that stores pg_stat_statements snapshots every hour across 20 databases, detects regressions, and generates a weekly report. Include the schema for historical storage, the regression detection algorithm, and the report format.

---

## EXPLAIN ANALYZE and Query Optimization

**J1.** What is the difference between EXPLAIN and EXPLAIN ANALYZE? When should you NOT use EXPLAIN ANALYZE?

**J2.** You see "Seq Scan on orders (rows=5000000)" in an EXPLAIN plan. The query filters by customer_id. What is wrong and how do you fix it?

**J3.** What does "Sort Method: external merge Disk: 128MB" tell you? How do you fix it?

**S1.** A query plan shows "Nested Loop (actual rows=0 loops=500000)". The inner side is a Seq Scan. What is happening and why is it slow? What is the fix?

**S2.** After adding an index, EXPLAIN ANALYZE still shows a Seq Scan. Name three reasons PostgreSQL might ignore your index.

**L1.** You inherit a database with 500 tables and 2000 queries. You have 1 week to identify and fix the 10 highest-impact query optimizations. Describe your methodology step by step, including what tools you use and how you prioritize.

---

## Connection Management

**J1.** Why does PostgreSQL use one OS process per connection? What problems does this cause at high connection counts?

**J2.** What is the difference between idle_session_timeout and idle_in_transaction_session_timeout? Why do you need both?

**J3.** A user reports "too many clients already." You connect as the superuser. What are your first three queries?

**S1.** An application uses a connection pool (HikariCP). Do you still need RDS Proxy? Explain the scenarios where application-level pooling is sufficient and where RDS Proxy adds value.

**S2.** RDS Proxy shows 70% of connections are pinned. What are the top 3 causes of pinning? How would you investigate and fix each?

**L1.** You have 200 Lambda functions, 10 EC2-based microservices, and 5 batch jobs all connecting to the same Aurora cluster. Design the connection management architecture including: pooling strategy, max_connections setting, timeout values, and monitoring approach.

---

## Alerting Strategy

**J1.** What is the difference between a critical alert and a warning alert? Give a database example of each.

**J2.** What is alert fatigue? Name three practices that prevent it.

**S1.** Your team receives 50 CloudWatch alerts per week but only 5 require action. The on-call DBA has started ignoring alerts. How do you fix this?

**S2.** Design an alert for "database is approaching connection exhaustion" that has zero false positives. What metric, threshold, evaluation period, and statistic would you use?

**L1.** You are implementing SLOs for your database tier. Define SLIs for availability, latency, and data freshness. For each SLI, specify the SLO target, measurement method, error budget, and what happens when the budget is exhausted.

---

## Prometheus and Grafana

**J1.** What is the pull model in Prometheus? How is it different from push-based monitoring? Give an analogy.

**J2.** What is a Prometheus exporter? Why do you need postgres_exporter to monitor PostgreSQL?

**S1.** Write a PromQL query that calculates the buffer cache hit ratio from postgres_exporter metrics. Then write one that alerts when the hit ratio drops below 95% for more than 10 minutes.

**S2.** You are asked to monitor 50 PostgreSQL databases across 3 environments. Should you deploy one postgres_exporter per database or one per server? What are the trade-offs?

**L1.** Design a Grafana dashboard for an on-call DBA. It must answer these questions within 30 seconds of looking at it: (1) Is the database up? (2) What is the current load? (3) Are any alerts firing? (4) What changed recently? Describe each panel, its data source, and the PromQL query.

---

## TXID Wraparound

**J1.** What is TXID wraparound? What happens when PostgreSQL reaches the limit?

**J2.** At what XID age should you start worrying? At what age does PostgreSQL shut down?

**S1.** Your CloudWatch alarm fires for MaximumUsedTransactionIDs exceeding 1 billion. Walk through the investigation and remediation steps.

**S2.** Autovacuum is running on the table with the highest XID age but the age is not decreasing. What could be preventing it from freezing? List three possible causes.

**P1.** A database processes 50,000 transactions per second. Calculate how quickly XIDs are consumed and how often VACUUM FREEZE must complete a full pass to stay safe. What autovacuum tuning parameters would you set for this workload?

---

## Scenario-Based Questions

**S1.** At 3 AM, your pager fires: "Aurora-HighCPU-writer at 98%." Walk through your first 10 minutes of investigation. What tools do you open? What queries do you run? What are you looking for? How do you decide whether to wake up more people?

**S2.** After a deployment, the application team reports that "the database is slow." You check CloudWatch - CPU is 25%, connections are at 15%, FreeableMemory is normal. Where do you look next and why?

**L1.** You are tasked with reducing the on-call page volume for your database team from 30 pages per month to fewer than 5. Current pages are: connection exhaustion (10), high CPU (8), replica lag (5), storage (3), TXID (2), other (2). For each category, describe the structural fix that prevents the page from occurring, not just adjusting the threshold.

**P1.** Design a complete observability stack for a financial services company running 100 Aurora PostgreSQL databases across 5 AWS regions. Requirements: 99.99% uptime SLA, SOC2 compliance, alert latency under 60 seconds, capacity to retain 2 years of performance data. Include architecture, tooling choices, cost estimates, and staffing requirements.
