# SURVIVE Runbook: Financial-Services Model Must Pass an Audit

**Tier 16 - SURVIVE scenario 2 of 3.** Review-assessed. No script to run; a reviewer grades your response against the checklist.

## The situation

Your [CLIENT] is a lender. A model you helped deploy scores loan applications to prioritize them for human underwriters. A regulatory examination has begun. The examiner has picked one declined applicant and asked: **"Show me why this person was declined on this date - the model version, the data used, the reasons, who reviewed it, and your evidence that the model does not discriminate."** You have until end of week. Leadership wants to know: can we produce this, or are we exposed?

This scenario tests whether the auditability you designed is real or aspirational.

---

## Diagnosis: can you reconstruct the decision?

Auditability means you can answer the examiner's five questions with records, not memory. Check each.

### 1. Model version
Query the model registry for the version that was in production on the decision date. If you have a registry with version-to-date mapping, this is instant. If not, that gap is itself an audit finding.

### 2. Data used
Pull the decision log record for this applicant: the input features the model saw at scoring time. Confirm data lineage - you can trace each feature to its source. If features were computed on the fly and not stored, you have a reconstructability gap.

### 3. The reasons (explainability)
Retrieve the top contributing features for this decision and the adverse-action reason that was generated. The examiner expects human-readable reasons ("declined primarily due to X, Y, Z"), not raw model weights. If you stored only the score and not the reasons, that is a serious gap - regenerating reasons after the fact from a possibly-changed model is not credible.

### 4. Who reviewed it
Find the human sign-off. In a decision-support design, the underwriter is accountable for the action. Confirm the record shows an accountable human, with a timestamp, who had the reasons in front of them.

### 5. Fairness evidence
Produce the disparate-impact reports run at launch and on the periodic cadence. The examiner wants to see you test for discrimination across protected groups continuously, not once. If you have no fairness monitoring, this is the finding most likely to escalate.

---

## Recovery

### If all five are reconstructable
1. Assemble the audit package for the requested applicant: model version, stored inputs with lineage, top features, adverse-action reason, human sign-off, and the fairness reports.
2. Add a one-page cover memo mapping each of the examiner's five questions to its evidence.
3. Offer to demonstrate the reconstruction live for any applicant the examiner picks at random - that is the strongest possible signal.

### If there are gaps
Do not fabricate. Fabricated audit evidence is fraud and ends careers. Instead:
1. Disclose the gaps honestly, scoped precisely ("we can show version, inputs, reasons, and sign-off; our fairness monitoring began in [month], so evidence before then is limited").
2. Present a remediation plan with dates: stand up the model registry, backfill decision logging, implement stored adverse-action reasons, and start quarterly disparate-impact monitoring.
3. For the specific applicant, reconstruct everything possible and re-review the decision with a human now.
4. Prioritize fairness monitoring first - discrimination exposure is the highest legal risk.

---

## The lesson

In finance you design for the audit on day one. The seven things that make a model auditable - registry, decision log, explanation record, change control, fairness evidence, data lineage, retention - are not optional infrastructure. If any is missing, you are one examination away from a finding. Build them before you need them, because you cannot backfill a reason for a decision made a year ago.

---

## Review checklist (reviewer grades against this)

- [ ] Answered all five examiner questions with stored records, not reconstruction-from-memory
- [ ] Confirmed the exact model version in production on the decision date (registry)
- [ ] Showed data lineage for the features the model actually used
- [ ] Produced the stored, human-readable adverse-action reason (not raw weights)
- [ ] Showed an accountable human sign-off with timing and information context
- [ ] Produced launch and periodic disparate-impact / fairness evidence
- [ ] Chose honest gap disclosure over fabrication where evidence was missing
- [ ] Gave a dated remediation plan prioritizing fairness monitoring
- [ ] Offered a live, random-applicant reconstruction as proof of auditability

---

Prof. Happy (SUTA Labs)
