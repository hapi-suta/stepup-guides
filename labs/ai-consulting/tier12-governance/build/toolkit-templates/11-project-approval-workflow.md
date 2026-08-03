# AI Project Approval Workflow

**Purpose:** the gate every AI use case passes before it is built or bought. It
connects the intake form, the risk-classification matrix, and the impact
assessment into one repeatable decision process. This is how ungoverned AI is
prevented from appearing (NIST AI RMF Govern/Map, ISO/IEC 42001 operational
controls).

**Owner:** [POLICY OWNER ROLE] - **Version:** [VERSION] - **Date:** [DATE]

---

## The workflow

```
[Idea]
   |
   v
1. Submit AI use-case intake form
   |
   v
2. Triage + risk classification (risk-classification matrix)
   |
   +--> Unacceptable? -----> REJECT (record reason). Stop.
   |
   v
3. Route by risk class:
   - Minimal  -> lightweight approval by [APPROVER]
   - Limited  -> approval by [APPROVER] + transparency + monitoring plan
   - High     -> full impact assessment + vendor questionnaire (if vendor)
                 + human-oversight plan + [LEGAL/COMPLIANCE] review
   |
   v
4. Decision: approve / approve with conditions / reject / request more info
   |
   v
5. If approved: register in the AI system inventory (owner, risk class, dates)
   |
   v
6. Build or buy. Before production: confirm controls in place.
   |
   v
7. Ongoing: monitoring + periodic review + re-assessment on material change
```

## Who approves what

| Risk class | Required before approval | Approver |
|------------|--------------------------|----------|
| Minimal | Intake form | [APPROVER ROLE] |
| Limited | Intake + transparency + monitoring plan | [APPROVER ROLE] |
| High | Intake + full impact assessment + oversight plan + vendor questionnaire (if vendor) + legal review | [SENIOR APPROVER + LEGAL] |
| Unacceptable | n/a | Rejected, reason recorded |

## Rules

- No AI system enters production without an inventory entry and a named owner.
- High-risk cannot be approved without a completed impact assessment and a
  human-oversight plan.
- Any vendor requires a completed vendor questionnaire before contract signing.
- Approvals are recorded (who, when, conditions) for audit.

## Records

Each decision is logged with: use-case ID, risk class, artifacts produced,
decision, conditions, approver, and date. Retain per the records-retention policy.

Prof. Happy (SUTA Labs)
