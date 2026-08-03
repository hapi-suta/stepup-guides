# Runbook: Connection saturation

Symptom: connections is close to max_connections.

Steps:
1. Identify idle-in-transaction sessions and their sources.
2. Verify the connection pooler settings.
3. Consider raising max_connections only with human approval and a restart plan.

This is documentation only. Any operational action requires human approval.
