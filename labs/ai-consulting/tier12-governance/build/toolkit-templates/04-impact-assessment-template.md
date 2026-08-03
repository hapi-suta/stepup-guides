# AI Impact Assessment

**System assessed:** [SYSTEM NAME]
**Owner (accountable person):** [NAME, ROLE]
**Risk classification:** [minimal / limited / high / unacceptable]
**Version:** [VERSION] - **Date:** [DATE] - **Next review:** [DATE]
**Assessor:** [NAME]

**Aligns to:** NIST AI RMF (Map/Measure), ISO/IEC 42001 (AI system impact
assessment), Concepts 12.4.

> This is the most important governance artifact. Complete every section honestly.
> If you cannot answer a section, that gap is itself a finding. Sign and date it,
> and revisit on material change.

---

## 1. System summary
What does the system do, in two or three plain sentences? [ANSWER]

## 2. Affected people
- Directly affected: [WHO]
- Indirectly affected: [WHO]

## 3. Intended benefits
What good is this meant to achieve, and how will we measure it? [ANSWER]

## 4. Possible harms
List concrete harms across categories. Do not stop at one.
- Wrong decisions: [HARM]
- Unfair / discriminatory outcomes: [HARM]
- Privacy loss: [HARM]
- Safety: [HARM]
- Loss of trust / transparency: [HARM]
- Harm from unavailability or misuse: [HARM]

## 5. Data sources
- Where the data comes from and who owns it: [ANSWER]
- Accuracy and representativeness: [ANSWER]
- Lawful basis / consent for this use: [ANSWER]

## 6. Bias
- Which groups could be disadvantaged? [ANSWER]
- Are there proxy variables that could carry bias back in? [ANSWER]
- How is bias measured (metric + threshold)? [e.g. disparate-impact ratio,
  action if below 0.80]
- Result of the latest measurement: [ATTACH / SUMMARIZE - see fairness_check.py]

## 7. Human oversight
- Oversight posture: [in the loop / on the loop / in command]
- Who reviews outputs, and how often? [ANSWER]
- Who can override a decision, and how? [ANSWER]
- Who can stop the system entirely? [ANSWER]

## 8. Security
- Top security risks (link to the Tier 11 threat model): [ANSWER]
- Controls in place for each: [ANSWER]

## 9. Privacy
- Personal/confidential data involved: [ANSWER]
- Minimization, protection, retention, deletion: [ANSWER]
- Does any vendor train on this data? [ANSWER]

## 10. Complaints and appeals
- How does an affected person learn a decision was made about them? [ANSWER]
- How do they complain and get a human review? [ANSWER]
- Is an appeals path legally required here? [ANSWER]

## 11. Monitoring
- What is monitored after launch (accuracy, fairness, drift, safety, complaints)?
  [ANSWER]
- How often and by whom? [ANSWER]

## 12. Decommissioning
- How is the system retired safely? [ANSWER]
- What happens to data, model, and dependent users? [ANSWER]

---

## Decision

| Field | Answer |
|-------|--------|
| Residual risk after controls | [low / medium / high] |
| Recommendation | [proceed / proceed with conditions / do not proceed] |
| Conditions | [TEXT] |
| Approved by | [NAME, ROLE] |
| Date | [DATE] |

Prof. Happy (SUTA Labs)
