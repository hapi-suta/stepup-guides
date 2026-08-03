# USE: Capstone Part 6 - Operations

**Tier 18 - USE phase (Part 6).** A system that works in a demo is not a program. Operations is what makes the assistant something a public institution can run, recover, update, and afford after you leave. This part turns the built-and-secured assistant into a maintainable service, and produces the operational artifacts the board expects.

**Validated on:** operations review, 2026-07-25.

**Prerequisite:** Part 4 built, Part 5 security suite PASSES. Do not operationalize a system that has not passed security.

---

## The eight operational deliverables

Each is a documented, tested procedure - not a promise. The rule of operations: **if it is not written down and tested, it does not exist.**

### 1. CI/CD
An automated pipeline that tests and deploys changes safely.
- Run the test suite (including the security validate.sh scripts) on every change.
- Block deploy if any test or security check fails.
- Deploy to a staging environment, then production, with the ability to roll back.
Produce: a working pipeline and a one-page description of it.

### 2. Backup
A tested procedure to back up what matters: the PostgreSQL database (documents, chunks, and the appeal-grade audit_log), the corpus, and configuration.
- Regular, automated backups.
- Backups stored per the data-residency rules from governance (restricted data stays in-boundary).
- The audit_log is backed up with integrity, because it is legally significant.
Produce: a backup procedure with schedule and retention.

### 3. Recovery
A tested procedure to restore service after a failure.
- Documented restore steps from backup.
- A recovery-time expectation the board can be told.
- **Actually tested** - a backup you have never restored is a guess. Restore into a test environment and confirm it works.
Produce: a recovery runbook, with the date you last tested it.

### 4. Monitoring
Live visibility into health and behavior.
- Uptime, latency, error rate, retrieval hit-rate.
- Per-language quality tracking (the weakest language is the real quality).
- Alerts to an accountable owner when something breaks.
Produce: monitoring dashboards/alerts and who receives them.

### 5. Model-change process
A controlled way to change the model or provider.
- Change control: no model change reaches production without documented review (from governance).
- Re-run the evaluation harness (per language) and the security suite before promoting a new model.
- Record the change in the AI system inventory.
Produce: a model-change procedure with the required checks.

### 6. Knowledge-base maintenance
A process to keep the corpus correct and current.
- How documents are added (with provenance and human approval, from the malicious-document defense).
- How outdated documents are retired.
- How re-embedding is handled if the embedding model changes.
Produce: a knowledge-base maintenance procedure with an owner.

### 7. Support workflow
How users get help and how problems are triaged.
- How a staff user reports a wrong or harmful answer.
- Triage: is it a content issue, a bug, a security event, or an appeal?
- Escalation to the incident process when needed.
Produce: a support workflow with clear routing.

### 8. Cost controls
Keep the running cost predictable and bounded.
- Rate limits (also a defense against unbounded consumption, OWASP LLM10).
- The per-provider cost counter from Part 4, with a budget alert.
- A ceiling that pauses or degrades gracefully rather than running up an unbounded bill.
Produce: cost controls with a budget and an alert threshold.

---

## Step 1: Set up the operations folder

On your **lab server**, as **ec2-user**:

```
mkdir -p ~/capstone-assistant/ops
```

Keep every operational procedure here as a markdown runbook, version-controlled.

---

## Step 2: Write and TEST each procedure

For backup and recovery specifically, do not just write them - run them. Restore a backup into a test environment and confirm the assistant comes back with its data and audit log intact. Record the test date in the recovery runbook.

---

## Step 3: Wire monitoring and cost alerts

Confirm alerts actually fire to a real recipient. An alert nobody receives is not monitoring.

---

## Exit standard for Part 6

All eight operational procedures are documented and, where testable, tested. Backup and recovery have been exercised at least once. Monitoring and cost alerts reach an accountable owner. The model-change process enforces re-evaluation and re-security-testing. The assistant is now a maintainable, affordable, recoverable service - a program, not a demo.

---

Prof. Happy (SUTA Labs)
