# Tier 8 Interview Questions - Operations at Scale and Mastery

**Level range:** Junior through Principal/Staff
**Topics covered:** T8.1 through T8.9

Questions are graduated from Junior (J) through Senior (S), Principal (P), and Master (M) levels. Master-level questions test architectural thinking and organizational leadership, not just technical recall.

---

## T8.1 - Cost Optimization

**J1.** What is the difference between Aurora Standard and Aurora I/O-Optimized storage pricing? When would you recommend switching to I/O-Optimized?

**J2.** What is an AWS Reserved Instance? What is the trade-off between Standard and Convertible Reserved Instances?

**S1.** You are told that switching a cluster from Aurora Standard to I/O-Optimized will save $2,400/month. The cluster is 500 GB with 150,000 IOPS. Walk through the break-even calculation and confirm or refute the savings claim. Show your math.

**S2.** An organization has 20 RDS `db.r6i.2xlarge` instances running 24/7. Cost Explorer recommends downsizing 8 of them to `db.r6i.xlarge`. What is your process for validating this recommendation before acting on it? What could go wrong if you act on it without validation?

**P1.** You are the DBA lead at a company spending $180,000/month on RDS. The CFO wants a 30% cost reduction without reducing performance. Design your cost optimization program: what do you analyze first, what levers do you pull in what order, and what risks do you communicate to leadership?

**P2.** A product team wants to run their new SaaS product on Aurora Serverless v2. Their projected workload is highly variable: near zero at night, peaks at 200 ACUs during business hours. A provisioned `db.r6g.4xlarge` costs $730/month. Model the Serverless v2 cost at this pattern and make a recommendation. What additional information would change your recommendation?

**P3.** Your company is evaluating migrating all Intel-based RDS instances to Graviton. Engineering leadership wants this done in 30 days across 40 production databases. What is your response to this timeline? What is the actual migration plan you propose?

**M1.** As the principal DBA, you are asked to design the cost governance model for the database platform at an organization running 200+ RDS instances across 15 teams. The goal is to achieve 25% cost reduction without a top-down mandate. How do you design the model? What metrics do you track, how do you create team accountability, and how do you handle teams that are not compliant?

**M2.** A senior engineer argues: "We should move everything to Aurora Serverless v2 for all environments - it scales to zero, so dev and staging are free when not in use." What is the architectural analysis you perform before accepting or rejecting this proposal? What are the failure modes of the proposal that the engineer has not considered?

---

## T8.2 - Fleet Management

**J1.** What is an AWS Config rule? Name three AWS managed Config rules that apply to RDS.

**J2.** Why is a consistent tagging strategy important for an RDS fleet? What information should a production database tag contain at minimum?

**S1.** You inherit a fleet of 50 RDS instances with inconsistent tagging. Some have no tags at all. Design a 30-day remediation plan to bring all instances to a consistent tag standard without disrupting operations. How do you handle instances where the owning team is unknown?

**S2.** Explain what "drift" means in the context of RDS fleet management. Give three examples of drift that would not be caught by standard CloudWatch monitoring but would be caught by AWS Config.

**P1.** You want to use AWS Config with automated remediation to enforce that all production RDS instances have deletion protection enabled. Walk through the full architecture: what Config rule triggers, what SSM Automation document executes, what IAM permissions are required, and what could go wrong with automated remediation.

**P2.** Your organization manages RDS across 8 AWS accounts. Design the fleet management architecture that provides a unified view of compliance status, tag coverage, and configuration drift across all accounts. What AWS services do you use, and what are the organizational prerequisites?

**P3.** A team bypasses your Terraform-managed infrastructure and creates an RDS instance directly in the console. Your Config rules flag it 20 minutes later. How does your remediation process work? How do you prevent recurrence without creating a bureaucratic barrier to the engineering team?

**M1.** At principal level, you are designing the database platform governance framework for a fintech company preparing for SOC 2 Type II audit. The auditors will want evidence that all database configuration changes are tracked, authorized, and compliant. Design the complete governance architecture, including the technical controls (Config, CloudTrail, IaC), the process controls (change management), and the evidence artifacts.

---

## T8.3 - Observability Pipelines

**J1.** What PostgreSQL log parameter would you configure to log only queries that take longer than 500 milliseconds? What is the parameter name and value?

**J2.** What is a CloudWatch metric filter? How does it differ from a CloudWatch Logs Insights query?

**S1.** Your RDS CloudWatch Logs bill has doubled this month. You traced it to a log group for a production Aurora cluster. What PostgreSQL parameters would you check first, and what changes would you make to reduce log volume without losing critical operational visibility?

**S2.** Write a CloudWatch Logs Insights query that finds the top 10 most frequently occurring error messages from a PostgreSQL log group in the last 24 hours.

**P1.** Design the complete observability stack for a fleet of 30 Aurora PostgreSQL clusters. Include: what logs are exported, what metric filters are created, what alarms exist, what dashboards are built, and how alerts are routed to the appropriate team. The fleet spans three environments (production, staging, development). What is different between environments?

**P2.** An on-call engineer comes to you and says "I have logs, I have metrics, I have traces - but I still cannot figure out why the database was slow for 4 minutes last Tuesday at 2 PM." What is the structured debugging process you walk them through? What specific CloudWatch Logs Insights queries, metric comparisons, and pg_stat views would you look at?

**P3.** You are designing an observability system for a database fleet where the security team requires that all logs containing PHI be treated as sensitive data. How does this constraint affect your CloudWatch Logs architecture? What compensating controls do you implement?

**M1.** A large organization has 5 different monitoring stacks across its engineering teams: CloudWatch, Datadog, Splunk, PagerDuty, and a custom internal tool. You need to design a unified database observability strategy that feeds all five without creating 5 separate monitoring configurations. Describe the architecture, the trade-offs, and what standards you enforce at the organizational level.

---

## T8.4 - Incident Response Runbooks

**J1.** When a PostgreSQL database runs out of storage on RDS, what is the first action you take? Why is this action safe to perform without downtime?

**J2.** What SQL query would you run to find all sessions that are in the `idle in transaction` state and have been idle for more than 5 minutes?

**S1.** An application is reporting "too many connections" errors. You have just connected as the superuser. Walk through your diagnosis steps. What queries do you run, what are you looking for, and in what order do you take action?

**S2.** You are investigating a replication lag alert on an Aurora reader instance. The lag is 45 seconds and growing. What are the four most likely root causes, and what diagnostic query or metric confirms each one?

**P1.** A citext index bypass is causing sequential scans on a 500 million row table in production. Queries that previously ran in 5ms are now taking 30 seconds. You need to fix this without taking the table offline. Design the complete remediation, including how you verify the fix is in place before closing the incident.

**P2.** Your organization has 12 DBA team members at various experience levels. You are tasked with creating a runbook program that ensures any DBA can handle any of the 6 incident types from Build Guide 04 at 3 AM without escalating. How do you design this program? How do you validate the runbooks actually work?

**P3.** A production database is showing the warning: `"database must be vacuumed within 50,000,000 transactions"`. This is a business-hours weekday. The VACUUM FREEZE operation on the largest table is estimated to take 4 hours. The business cannot tolerate a 4-hour maintenance window. What do you do?

**M1.** You are the DBA lead at a company that has had three P1 database incidents in the past quarter, each caused by a different scenario covered in this tier. The CEO asks what systemic changes you will make to prevent a fourth. Describe your 90-day operational improvement program. What metrics demonstrate it is working?

---

## T8.5 - Capacity Planning with pgbench

**J1.** What does the `-s` (scale factor) flag control in the `pgbench --initialize` command? What scale factor would you use if you want a dataset roughly equivalent to 1 GB?

**J2.** What is the difference between a load test and a soak test? What type of problem does each one reveal?

**S1.** You run pgbench with 10 clients and get 890 TPS. You run it with 50 clients and get 2,800 TPS. You run it with 100 clients and get 3,100 TPS. You run it with 200 clients and still get 3,100 TPS. What does this pattern tell you about the system's saturation point? What resource is most likely the bottleneck at 200 clients?

**S2.** A soak test reveals that average query latency is stable for the first 2 hours but then gradually increases over the next 6 hours without any increase in load. FreeableMemory is also slowly declining. What is the most likely cause? How do you confirm it?

**P1.** A team asks you to right-size their `db.r6g.4xlarge` database. You have 30 days of CloudWatch data showing average CPU at 18%, FreeableMemory at 55%, and connections at 35% of max_connections. Cost Explorer recommends downsizing to `db.r6g.2xlarge`. Before making the recommendation, you run a load test. What specific scenario do you test in the load test, and what result would cause you to override Cost Explorer's recommendation?

**P2.** You need to project when the current `db.r6g.2xlarge` will become insufficient for a growing SaaS product. The product is growing at 15% month-over-month in active users. Current CPU average is 35%. What is your capacity planning model, and when do you recommend scheduling the upgrade?

**M1.** Your organization is launching a new product that expects 10x the traffic of your largest existing database at peak. The launch is in 60 days. You cannot replicate production traffic in staging. Design the capacity planning and load testing program that gives you the highest confidence that the database will survive launch day. What is your go/no-go decision criteria?

---

## T8.6 - Compliance

**J1.** What is pgaudit and what does it add that PostgreSQL's built-in logging does not provide?

**J2.** What parameter must be set in the RDS parameter group before you can use the pgaudit extension? Why does this parameter require a database restart to take effect?

**S1.** A HIPAA audit requires evidence that all access to PHI was logged for the last 6 years. Your current CloudWatch Logs retention is 30 days. You need to close this gap immediately and establish a sustainable solution. What is your remediation plan?

**S2.** Your company uses the AWS-managed KMS key (`aws/rds`) for all RDS encryption. A compliance consultant says this fails HIPAA requirements and you need to switch to customer-managed keys (CMK). Is the consultant correct? What is the actual HIPAA requirement, and if migration is needed, what is the process?

**P1.** You are onboarding a healthcare client whose application will store PHI in Aurora PostgreSQL. They ask you to confirm their AWS setup is HIPAA-ready. Design the complete HIPAA technical safeguards checklist you review. For each item that fails, what is the remediation order and timeline?

**P2.** A developer on your team argues that enabling `pgaudit.log = 'all'` (logging all reads and writes) is overkill and will cause performance problems and excessive storage costs. The compliance team says it is required. How do you resolve this conflict? Is there a middle ground that satisfies both concerns?

**P3.** Your organization is being assessed for FedRAMP Moderate authorization. The database team is responsible for the CM (Configuration Management) and AU (Audit) control families. Map your AWS Config rules and pgaudit configuration to specific FedRAMP control requirements. Which controls cannot be satisfied at the technical layer and require policy/process evidence?

**M1.** You are hired as the first DBA at a company that processes federal government data but has never been through a FedRAMP assessment. The assessment starts in 6 months. Design the complete database compliance program - technical controls, documentation, evidence collection, and team readiness. What are the three biggest risks to meeting the timeline?

---

## T8.7 - Disaster Recovery Design

**J1.** Define RTO and RPO in plain language. Which one measures downtime tolerance, and which one measures data loss tolerance?

**J2.** What is the typical RPO of Aurora Global Database replication? What is the typical RTO for a managed planned failover?

**S1.** A product manager tells you they want "zero RPO and zero RTO" for their database. How do you respond? What is technically achievable, and what does it cost?

**S2.** You have a business requirement: RTO < 15 minutes, RPO < 1 minute. You have a budget for one Aurora cluster with Multi-AZ. Does this architecture meet the requirements? What is missing, and what would you add?

**P1.** You are designing the DR architecture for an e-commerce platform with four databases: order processing (Tier 1), product catalog (Tier 2), analytics warehouse (Tier 3), and internal admin (Tier 4). Define the RTO/RPO requirements for each tier, the architecture that meets them, and the annual cost impact of the DR architecture (relative to a non-DR baseline).

**P2.** You have been tasked with running quarterly DR drills across 6 production Aurora clusters. Each drill requires approximately 90 minutes including failover, verification, and failback. The application teams want to minimize customer impact. Design the quarterly DR testing calendar, including how you minimize impact and what you do when a drill reveals a gap.

**P3.** After a DR failover, the application is running in the secondary region. Primary region recovery is estimated at 4 hours. Do you stay in the secondary region for those 4 hours and then fail back, or do you fail back immediately when the primary recovers? Walk through the decision framework.

**M1.** An organization's board requires a maximum 4-hour RTO for all Tier 1 systems after a complete data center failure. The current database architecture provides a 24-hour RTO (snapshot restore). You have been given 12 months and a $2M budget to close this gap across 25 databases. Design the program.

---

## T8.8 - Failure Injection and Resilience Testing

**J1.** What is the purpose of a "stop condition" in an AWS FIS experiment? What happens if the stop condition is triggered?

**J2.** What is the difference between measuring T3 and T4 in a failover experiment? Why is T4 more useful than T3 for measuring actual RTO?

**S1.** You run an Aurora failover experiment and discover that your actual RTO is 4 minutes, but your designed RTO is 30 seconds. After investigation, you trace the gap to DNS TTL caching in the application connection pool. Explain what DNS TTL caching is in this context, why it extends the RTO, and how to fix it.

**S2.** Design a FIS experiment that tests the resilience of your application when a single Aurora reader instance becomes unavailable. What is the hypothesis, what action do you inject, what stop condition do you use, and what does a successful result look like?

**P1.** You want to run a quarterly automated resilience testing pipeline for your production Aurora clusters. The pipeline must: run during a pre-approved maintenance window, abort if customer-visible error rate exceeds 1%, measure actual RTO, store results in S3, and alert if actual RTO exceeds designed RTO. Design the complete pipeline architecture.

**P2.** Your resilience tests show that the database failover completes in 25 seconds, but end-to-end application health does not restore until 4.5 minutes later. You have measured this three times and gotten consistent results. The application team says "the database is the bottleneck." You disagree. How do you prove or disprove this, and what is the most likely cause of the 4-minute application recovery lag?

**P3.** Chaos engineering is controversial in some organizations. The security team says "deliberately breaking things in production is irresponsible." The reliability team says "not testing our failure modes is the actual irresponsibility." How do you facilitate this organizational discussion and reach a policy decision that both teams can work with?

**M1.** You are proposing a company-wide resilience engineering program. Senior leadership asks: "What is the ROI of breaking our systems on purpose?" How do you answer this question? What metrics do you use to demonstrate value, and how long does it take before the program shows measurable results?

---

## T8.9 - Autonomous Diagnostics

**J1.** Why is it important that all automated diagnostic queries are read-only? Give an example of a diagnostic action that could cause an incident if it were not read-only.

**J2.** What is the `pg_monitor` role in PostgreSQL? What does granting it to a user provide?

**S1.** Write a SQL query that identifies the top 5 tables by dead tuple count and includes the dead tuple percentage. What threshold would you use to flag a table as having problematic bloat?

**S2.** Your fleet health check Lambda function takes 8 minutes to run across 40 instances because it makes sequential API calls. Redesign the function to complete in under 1 minute. What Python pattern do you use, and what AWS service limits do you need to be aware of?

**P1.** Design the autonomous diagnostic system for a fleet of 60 RDS instances. Include: what checks run on what schedule, what data sources each check uses (CloudWatch vs SQL vs RDS API), how findings are stored and surfaced, and what actions the system can take automatically vs what requires human decision. What is the false positive rate you are willing to tolerate, and how do you tune the system over time?

**P2.** Your autonomous diagnostic system pages the on-call engineer 200 times per week, but the engineer reports that 95% of pages are non-actionable noise. How do you reduce the noise without missing real incidents? Walk through your approach to threshold calibration and alert deduplication.

**P3.** You want the autonomous diagnostic system to predict database problems before they cause incidents, not just detect them after they occur. For each of the following incident types, describe the leading indicators you would monitor and the prediction logic: (a) storage exhaustion, (b) connection storm, (c) wraparound emergency.

**M1.** At principal level, your goal is that no DBA needs to be paged for a routine database health event. Define what "routine" means for your fleet, design the system that handles it autonomously, and articulate what remains in the "human judgment required" category. How do you build organizational trust in an autonomous system that takes corrective actions without human approval?

**M2.** You are presenting to the CTO on the database platform's operational maturity. You want to show a clear progression from "reactive" (we fix problems after users report them) to "proactive" (we prevent problems before they occur) to "predictive" (we address trends before they become problems). Describe the three-year journey, the investments required at each stage, and how you measure maturity.

---

## Master-Level Synthesis Questions

These questions deliberately span multiple topics. They test whether you can think across domains, not just within them.

**MS1.** A company is preparing its RDS fleet for a Series B due diligence process. The investor's technical team will audit: cost efficiency, security and compliance posture, operational resilience, and observability maturity. You have 60 days to prepare. Design the complete preparation program. Which topics in this tier are most critical, which are nice-to-have, and where do you find the biggest gaps typically?

**MS2.** You are the new DBA lead at a company where the previous team left under difficult circumstances. The fleet has: no tagging, no Config rules, no pgaudit, no DR plan, inconsistent backups, one wraparound near-miss last year, and a history of unexplained cost spikes. The company is growing rapidly. Design your first 90 days. What do you fix first and why?

**MS3.** Describe the relationship between cost optimization (T8.1), capacity planning (T8.5), and disaster recovery design (T8.7). Give a concrete example where a decision in one area directly creates a constraint in another area. How do you make these decisions holistically rather than in silos?

**MS4.** The engineering team proposes replacing all manual operational runbooks with an LLM-powered autonomous incident response system. The system would detect incidents, diagnose root cause, and execute remediation automatically. What is your position on this proposal? What would you require to be in place before you would trust such a system with a production database? What would never be delegated to it?
