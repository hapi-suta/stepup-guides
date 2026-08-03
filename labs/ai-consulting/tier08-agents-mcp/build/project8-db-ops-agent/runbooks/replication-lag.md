# Runbook: High replication lag

Symptom: replication_lag_s is at or above 30 seconds.

Steps:
1. Confirm the standby is applying WAL (check the WAL receiver).
2. Check network throughput between primary and standby.
3. Check for long-running transactions on the primary holding back WAL.
4. Do not fail over automatically; propose failover for human approval.

This is documentation only. Any operational action requires human approval.
