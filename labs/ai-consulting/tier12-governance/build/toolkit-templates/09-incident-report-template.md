# AI Incident Report

**Purpose:** capture what happened when an AI system misbehaves (a biased or
harmful output, a data leak, a security event, an outage) so it can be contained,
fixed, and learned from. Feeds NIST AI RMF (Manage) and ISO/IEC 42001
(improvement / corrective action).

**Incident ID:** [ID] - **Reported by:** [NAME] - **Date/time reported:** [WHEN]
**System involved:** [SYSTEM NAME] - **Severity:** [low / medium / high / critical]

> Fill this in as the incident unfolds; do not wait for it to be over. Facts first,
> blame never. The goal is containment and learning.

---

## 1. What happened
Plain description of the incident: [ANSWER]

## 2. When
- First occurred: [WHEN]
- Detected: [WHEN]
- Detected by: [PERSON / MONITOR / USER REPORT]

## 3. Who / what was affected
- People affected: [WHO, roughly how many]
- Data affected: [ANSWER]
- Systems affected: [ANSWER]

## 4. Severity and why
Severity rating and the reasoning (harm, scale, reversibility): [ANSWER]

## 5. Immediate action taken (containment)
What was done right away to stop the harm (disable system, roll back, block a
user, revoke a key)? [ANSWER]

## 6. Root cause
Why did it happen? Go past the symptom (e.g. "biased output") to the cause (e.g.
"proxy variable in the training data", "prompt-injection via an ingested
document", "no fairness monitoring"). [ANSWER]

## 7. Remediation
- Fix applied: [ANSWER]
- Retest / evidence the fix works: [ANSWER]
- Longer-term prevention: [ANSWER]

## 8. Notifications
- Who was notified (leadership, affected people, legal, regulator, vendor) and
  when: [ANSWER]
- Any regulatory / contractual reporting obligation triggered? [ANSWER]

## 9. Lessons learned
- What will change to prevent recurrence (policy, control, monitoring, training)?
  [ANSWER]
- Which governance artifact needs updating (impact assessment, oversight plan,
  model card)? [ANSWER]

## 10. Closure
| Field | Answer |
|-------|--------|
| Status | [open / contained / resolved / closed] |
| Owner | [NAME, ROLE] |
| Date closed | [DATE] |
| Approved by | [NAME, ROLE] |

Prof. Happy (SUTA Labs)
