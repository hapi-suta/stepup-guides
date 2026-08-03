# Module 09: Operations at Scale and SRE

**Track:** DevOps DBA Training
**Duration:** ~14 hours
**Week:** 7
**Prerequisites:** Module 01-08

---

## What You Will Learn

This module shifts your mindset from reactive firefighting to proactive engineering. By the end, you will:

- Define SLOs, SLIs, and error budgets for Aurora databases
- Build automated cost monitoring and optimization workflows
- Create incident response playbooks that reduce mean time to recovery
- Automate routine DBA tasks with Lambda and EventBridge
- Write runbooks that anyone on-call can follow at 3 AM
- Conduct effective postmortems that lead to real improvements
- Understand how SRE principles apply specifically to managed databases

---

## Module Contents

### Concepts (read first)
1. [SRE for Databases](concepts/01-sre-for-databases.md) - SLOs, SLIs, error budgets, toil reduction, on-call for DBAs
2. [Cost Optimization](concepts/02-cost-optimization.md) - Reserved instances, right-sizing, storage optimization, cost anomaly detection
3. [Incident Management](concepts/03-incident-management.md) - Severity levels, escalation paths, communication templates, blameless postmortems

### BUILD (hands-on, follow step by step)
1. [SLO Definition](build/01-slo-definition.md) - Define availability and latency SLOs for your cluster (30 min)
2. [Error Budget Tracking](build/02-error-budget-tracking.md) - Build an error budget dashboard in CloudWatch (45 min)
3. [Cost Monitoring](build/03-cost-monitoring.md) - AWS Budgets, Cost Explorer, anomaly alerts (30 min)
4. [Automated Maintenance](build/04-automated-maintenance.md) - Lambda functions for routine tasks - stats, cleanup, health checks (60 min)
5. [Event-Driven Automation](build/05-event-driven-automation.md) - EventBridge rules, RDS events, auto-remediation (45 min)
6. [Runbook Automation](build/06-runbook-automation.md) - SSM documents, parameterized runbooks, execution history (45 min)

### USE (practice with less hand-holding)
1. [SLO Design Exercise](use/01-slo-design-exercise.md)
2. [Cost Optimization Exercise](use/02-cost-optimization-exercise.md)
3. [Automation Building Exercise](use/03-automation-building-exercise.md)
4. [Incident Simulation Exercise](use/04-incident-simulation-exercise.md)
5. [Postmortem Exercise](use/05-postmortem-exercise.md)

### SURVIVE (break it, fix it)
1. [Cost Spike](survive/01-cost-spike/) - AWS bill jumps unexpectedly, find the source and stop the bleeding
2. [Compliance Violation](survive/02-compliance-violation/) - Audit finds unencrypted data, remediate under deadline
3. [Connection Storm](survive/03-connection-storm/) - Application opens thousands of connections, stabilize the cluster
4. [Wraparound Emergency](survive/04-wraparound-emergency/) - Transaction ID nearing wraparound with autovacuum stuck

### Interview Prep
1. [Interview Questions](interview/01-interview-prep.md) - 15-20 questions, Junior to Senior

---

## What is Next

After completing this module, you will move to [Module 10: Capstone - Production-Ready Aurora Stack](../module10-capstone-production-ready-aurora/) where you combine everything into a fully production-ready Aurora deployment and prove you can handle real-world scenarios.

---

## Cost Warning

Lambda functions and EventBridge rules fall within the AWS free tier for the volume used in these labs. SSM documents are free. AWS Budgets allows up to two free budgets. CloudWatch custom metrics from automation may add minor charges. Total additional cost for this module is near zero.
