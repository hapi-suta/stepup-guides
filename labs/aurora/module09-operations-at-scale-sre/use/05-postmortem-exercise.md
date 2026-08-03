# USE 05: Postmortem Exercise

**Module 09: Operations at Scale and SRE**
**Estimated Time:** 30-40 minutes

---

## Context

You are facilitating a post-incident review for a SEV1 outage that occurred last week. The incident involved an Aurora PostgreSQL cluster that became completely unresponsive for 8 minutes during a routine maintenance operation. Your job is to lead a blameless review, identify systemic causes, and produce actionable improvements.

---

## Part 1: Incident Reconstruction

<details>
<summary>Task 1.1: Read the following incident data and construct a complete timeline. Identify the trigger event, the failure cascade, and the recovery sequence.</summary>

**Incident Data:**

**Source: CloudWatch Metrics**
```
2026-06-05 14:00 UTC - DatabaseConnections: 280 (normal)
2026-06-05 14:00 UTC - CPUUtilization: 32% (normal)
2026-06-05 14:02 UTC - Parameter group modification applied (immediate)
2026-06-05 14:02 UTC - DatabaseConnections drops to 0
2026-06-05 14:02 UTC - CPUUtilization drops to 0%
2026-06-05 14:03 UTC - RDS Event: "DB instance restarted"
2026-06-05 14:05 UTC - DatabaseConnections: 15
2026-06-05 14:06 UTC - DatabaseConnections: 450 (connection storm)
2026-06-05 14:06 UTC - CPUUtilization: 95%
2026-06-05 14:07 UTC - WriteLatency: 3,200ms
2026-06-05 14:08 UTC - DatabaseConnections: 580 (exceeds healthy threshold)
2026-06-05 14:09 UTC - Application team reports: "payments failing"
2026-06-05 14:10 UTC - DBA terminates 300 idle connections manually
2026-06-05 14:11 UTC - CPUUtilization drops to 45%
2026-06-05 14:12 UTC - WriteLatency returns to 15ms
2026-06-05 14:12 UTC - DatabaseConnections stabilizes at 250
```

**Source: RDS Events Log**
```
14:01:55 - Applying parameter changes to devops-lab-cluster-instance-1
14:02:03 - DB instance restarted
14:02:45 - DB instance available
14:05:10 - Recovery complete
```

**Source: Slack Messages**
```
14:00 - Junior DBA: "Applying parameter change to fix log_min_duration issue"
14:02 - Junior DBA: "Um, the instance just restarted"
14:03 - PagerDuty: SEV1 alert - devops-lab-cluster unavailable
14:05 - Senior DBA: "I see the instance is back. Connections are flooding in."
14:06 - Senior DBA: "Connection storm - apps are all reconnecting at once"
14:09 - App Team: "Payments are failing - getting connection refused"
14:10 - Senior DBA: "Terminating idle connections to make room"
14:12 - Senior DBA: "Service restored. Monitoring."
```

**Source: Change Management System**
```
Change ticket: CHG-4521
Description: "Reduce log_min_duration_statement from 500 to 100"
Approval: Self-approved (Junior DBA)
Scheduled window: No maintenance window specified
Apply method: immediate
Risk assessment: "Low risk - logging parameter only"
```

Construct the timeline and identify:
1. The trigger event
2. The failure cascade
3. The recovery sequence

**Example answer:**

**Timeline:**

| Time (UTC) | Event | Source |
|-----------|-------|--------|
| 14:00:00 | Junior DBA applies parameter change (CHG-4521) | Change Mgmt |
| 14:01:55 | RDS begins applying parameter changes | RDS Events |
| 14:02:03 | Instance restarts unexpectedly | RDS Events |
| 14:02:03 | All 280 client connections dropped | CloudWatch |
| 14:02:45 | Instance becomes available again | RDS Events |
| 14:03:00 | PagerDuty SEV1 alert fires | PagerDuty |
| 14:05:10 | Recovery complete - instance accepting connections | RDS Events |
| 14:05:30 | Application reconnect storm begins | CloudWatch |
| 14:06:00 | 450 connections (all apps reconnecting simultaneously) | CloudWatch |
| 14:06:00 | CPU spikes to 95% from connection overhead | CloudWatch |
| 14:07:00 | Write latency degrades to 3,200ms | CloudWatch |
| 14:08:00 | Connections reach 580 (some apps retrying aggressively) | CloudWatch |
| 14:09:00 | Application team reports payment failures | Slack |
| 14:10:00 | Senior DBA terminates 300 idle connections | Manual action |
| 14:11:00 | CPU drops to 45% | CloudWatch |
| 14:12:00 | Service fully restored | CloudWatch |

**Trigger event:** Parameter modification with `ApplyMethod=immediate` on a parameter that requires instance restart (`shared_preload_libraries` was also in the parameter group and was modified).

**Failure cascade:**
1. Instance restart dropped all connections (2 minutes of unavailability)
2. After restart, all application servers reconnected simultaneously
3. Reconnection storm overwhelmed the instance (CPU 95%, 580 connections)
4. Overwhelmed instance could not process writes (3,200ms latency)
5. Some applications received connection refused, leading to payment failures

**Recovery sequence:**
1. Senior DBA manually terminated 300 idle connections
2. Connection count dropped to healthy levels
3. CPU and latency returned to normal

</details>

---

## Part 2: Root Cause Analysis

<details>
<summary>Task 2.1: Apply the "Five Whys" technique to identify the root cause. Remember: the root cause is systemic, not "someone made a mistake."</summary>

**Example answer:**

**Why 1:** Why did the database restart?
- Because a parameter requiring restart was modified with `ApplyMethod=immediate`.

**Why 2:** Why was a restart-requiring parameter modified with immediate apply?
- Because the DBA did not know that `shared_preload_libraries` was also modified in the same parameter group change, and that parameter requires a restart.

**Why 3:** Why did the DBA not know the change would cause a restart?
- Because the change management process does not require verifying the `ApplyMethod` for each parameter in a batch modification. The DBA assumed all parameters in the change were `immediate`-safe.

**Why 4:** Why does the change management process not catch restart-requiring changes?
- Because there is no pre-flight check that validates parameter apply methods before execution. The process relies on the DBA's knowledge of each parameter's behavior.

**Why 5:** Why is there no pre-flight check?
- Because parameter changes are treated as low-risk operations in the runbook, and no automation validates the impact before applying.

**Root Cause:** The parameter change process lacks automated validation that identifies parameters requiring instance restart. This allowed a change intended as non-disruptive to trigger an unplanned restart during business hours.

**Contributing Factor 1:** No connection pooler (RDS Proxy or PgBouncer) to handle reconnection gracefully after restart.

**Contributing Factor 2:** Self-approval for what was classified as a "low-risk" change. The risk assessment did not account for the batch nature of parameter group modifications.

**Contributing Factor 3:** Applications lack exponential backoff with jitter for database reconnection, causing a thundering herd on restart.

</details>

<details>
<summary>Task 2.2: Identify the difference between the "proximate cause" and the "root cause" in this incident. Why does this distinction matter for preventing recurrence?</summary>

**Example answer:**

**Proximate cause:** The Junior DBA applied a parameter change that caused an unexpected restart.

**Root cause:** The system (process + tooling) allowed a disruptive change to be executed without safeguards.

**Why this distinction matters:**

If you fix the proximate cause ("tell the Junior DBA to be more careful"), you prevent THIS specific mistake by THIS specific person. The same class of failure can still happen:
- A different DBA could make the same mistake
- The same DBA could make a similar mistake with a different parameter
- An automated process could apply a parameter change with the same risk

If you fix the root cause (automated pre-flight check, change approval for restart-requiring changes, connection pooler), you prevent the entire CLASS of failures. Every parameter change, by every person, gets validated before execution.

Blameless postmortems focus on root causes because fixing systems is more reliable than fixing people.

</details>

---

## Part 3: Action Items

<details>
<summary>Task 3.1: Write action items that address the root cause and contributing factors. Each action item must have an owner, priority, and deadline. Prioritize by risk reduction impact.</summary>

**Example answer:**

| ID | Action | Owner | Priority | Due | Risk Addressed |
|----|--------|-------|----------|-----|---------------|
| 1 | Build parameter change pre-flight script that checks ApplyMethod for all parameters in a group modification | DBA Team | P1 | 2026-06-12 | Prevents unplanned restarts |
| 2 | Require manager approval for any parameter change with ApplyMethod=pending-reboot | DBA Team Lead | P1 | 2026-06-12 | Process guardrail |
| 3 | Deploy RDS Proxy for payments-cluster to handle connection pooling and reconnection | DBA Team | P1 | 2026-06-19 | Eliminates reconnection storms |
| 4 | Add exponential backoff with jitter to application database connection retry logic | App Team Lead | P2 | 2026-06-26 | Reduces thundering herd on restart |
| 5 | Create runbook: "Planned Instance Restart Procedure" with pre/during/post steps | DBA Team | P2 | 2026-06-19 | Standardized restart process |
| 6 | Schedule all non-emergency parameter changes during maintenance window (Sunday 2-4 AM) | DBA Team Lead | P2 | 2026-06-12 | Reduces business-hours risk |
| 7 | Add CloudWatch alarm: connection rate-of-change > 100 connections in 1 minute | DBA Team | P3 | 2026-06-19 | Faster detection of connection storms |

</details>

<details>
<summary>Task 3.2: For each P1 action item, define "done criteria" - how do you verify the action item actually prevents recurrence?</summary>

**Example answer:**

**Action 1: Pre-flight script**
- Done criteria: Script exists, is tested, and is integrated into the change management workflow
- Verification: Run the script against the exact change from CHG-4521 - it must flag `shared_preload_libraries` as restart-requiring and block the change
- Test: Apply a test parameter change in staging using the script and confirm it catches restart-requiring parameters

**Action 2: Manager approval for restart changes**
- Done criteria: Change management system requires manager approval for any change where the pre-flight script identifies restart-requiring parameters
- Verification: Submit a test change ticket with a restart-requiring parameter - it must route to manager for approval instead of self-approval
- Test: Junior DBA attempts to self-approve a restart-requiring change - system must reject

**Action 3: RDS Proxy deployment**
- Done criteria: RDS Proxy deployed, application endpoints updated to connect through proxy, connection pooling verified
- Verification: Simulate an instance restart in staging and measure reconnection behavior through RDS Proxy
- Test: Restart staging instance and verify: no connection storm, connections maintained through proxy, recovery time < 30 seconds with no application errors

</details>

---

## Part 4: Facilitation

<details>
<summary>Task 4.1: You are facilitating the PIR meeting. The Junior DBA who applied the change is visibly anxious. How do you ensure the meeting remains blameless? Write your opening statement and describe how you would redirect any blame-oriented comments.</summary>

**Example answer:**

**Opening statement:**

"Thank you all for joining. The purpose of this post-incident review is to understand what happened and prevent it from happening again. This is a blameless review. We are here to improve the system, not to assign blame.

Every person involved in this incident made reasonable decisions based on the information available to them at the time. Our job today is to ask: what about the system made this failure possible? What safeguards were missing? What could we build to make this class of failure impossible?

The ground rules are:
1. We focus on systems, processes, and tools - not individuals
2. We assume everyone acted with good intent
3. We look for what the system allowed to happen, not what someone should have known
4. Action items fix the system, not the person

Let's start with the timeline."

**Redirecting blame-oriented comments:**

If someone says: "The DBA should have known that parameter requires a restart."

Redirect: "That is a reasonable observation. Let's reframe it as a system question: why does our process allow someone to apply a restart-requiring change without the system warning them? If our tooling validated the ApplyMethod before execution, no one would need to memorize which parameters require restarts. That is the kind of fix that prevents this for everyone, forever."

If someone says: "Why was this change self-approved? That should not be allowed."

Redirect: "Good question about the process. Our change management system currently allows self-approval for changes classified as low-risk. The systemic issue is: how do we define 'low-risk' for parameter changes? Our current definition did not account for batch modifications where one parameter might require restart even if others do not. Let's add that to our action items."

</details>

---

## Deliverables

By the end of this exercise, you should have:

1. Complete incident timeline with trigger, cascade, and recovery identified
2. Five Whys root cause analysis
3. Distinction between proximate cause and root cause
4. Prioritized action items with owners, deadlines, and done criteria
5. PIR facilitation plan with opening statement and blame-redirection techniques

---

## Reflection Questions

1. Why is "the DBA made a mistake" not a valid root cause?
2. How do you track action item completion after the PIR meeting?
3. What would you do if the same type of incident occurs again within 90 days?
4. How does the error budget connect to the urgency of completing action items?
