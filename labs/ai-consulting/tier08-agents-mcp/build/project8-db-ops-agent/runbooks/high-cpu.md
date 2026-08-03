# Runbook: High CPU on a database instance

Symptom: cpu_pct is at or above 85% for a sustained period.

Steps:
1. Identify the top queries by CPU (pg_stat_statements).
2. Check for a missing index or a runaway analytical query.
3. If a read replica exists, consider routing read traffic to it.
4. Escalate to on-call DBA if CPU stays above 85% for more than 15 minutes.

This is documentation only. Any operational action requires human approval.
