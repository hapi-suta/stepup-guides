# SURVIVE Runbook: Public-Sector Decision Challenged on Appeal

**Tier 16 - SURVIVE scenario 1 of 3.** Review-assessed. There is no script to run; this scenario tests judgment and process, so a reviewer grades your response against the checklist at the end.

## The situation

Your [CLIENT], a public institution, deployed the bilingual assistant you helped build. It supports caseworkers making eligibility decisions on a citizen service. A citizen has been denied. They have formally appealed, and their representative claims the decision was "made by an AI with no human involvement and no explanation." A regulator is now watching. Leadership calls you: **"Prove that human oversight and explainability held for this decision, or we have a serious problem."**

This is the moment the whole public-sector design either pays off or fails. Everything you built for accountability - the appeal-grade logs, the human-oversight step, the citations - is now on trial.

---

## Diagnosis: what actually happened?

Do not assume the system failed. Do not assume it worked. Find out. Work through these in order.

### 1. Locate the decision record
Pull the appeal-grade log for this specific decision (by citizen case ID and date). You are looking for the reconstructable record: the query, the retrieved documents with versions, the citations shown, the model version, and - critically - the `human_decision` field.

Three possible findings:
- **The human_decision field is populated** with an accountable officer and a timestamp -> a human did decide. Good. Move to explainability.
- **The human_decision field is empty** -> the system may have been used to auto-decide, which the design forbids. This is a real problem. Go to "If oversight failed" below.
- **There is no record at all** -> logging failed for this case, which is itself a serious accountability gap. Go to "If the record is missing" below.

### 2. Verify the human step was genuine, not a rubber-stamp
A populated field is not enough. Ask: did the officer have time and information to actually review, or did they click "approve" on hundreds of cases in an hour? Check the time between the AI output and the human decision, and whether the officer had the citations and reasoning in front of them. Rubber-stamp oversight is fictional oversight, and a regulator will see through it.

### 3. Reconstruct the explanation
Using the citations and retrieved documents in the log, reconstruct the plain-language reason the decision was made: which rule, which facts, which policy version. If you can produce "denied because policy [X] version [Y] requires [Z], and the application showed [fact]", explainability held.

---

## Recovery

### If oversight and explainability held
1. Produce the reconstructed decision record: the human officer, the timestamp, the policy cited, the plain-language reason.
2. Write a one-page appeal response showing the human made the decision, informed by the assistant, with a documented reason.
3. Offer the citizen the appeal on its merits (the human can still be wrong - honor the appeal), but the "AI decided with no oversight" claim is disproven with evidence.
4. Report to leadership and the regulator: the control worked; here is the evidence.

### If oversight failed (empty human_decision)
1. Stop the bleeding: if the assistant is being used to auto-decide, pause that use immediately until a human step is enforced.
2. Be honest with leadership and the regulator. Concealment turns a control failure into misconduct.
3. Overturn or re-review the affected decision(s) with a human now.
4. Root-cause: was the human step removed, bypassed, or never enforced in the UI? Fix the enforcement so the decision cannot be issued without a recorded human sign-off.
5. Audit for other affected cases and remediate them too.

### If the record is missing (logging failed)
1. Treat as a control failure even if the decision was fine - you cannot prove it was.
2. Reconstruct what you can from other systems, and be transparent that the primary record is missing.
3. Re-review the decision with a human and issue a fresh, fully logged decision.
4. Fix logging so no consequential decision can be issued without an appeal-grade record. This is a design defect, not an operational blip.

---

## The lesson

Public-sector accountability is not proven by intentions; it is proven by records. The appeal is a test of whether your design produces evidence. Build the appeal-grade log and enforce the human step BEFORE go-live, because you cannot retrofit a record for a decision that already happened.

---

## Review checklist (reviewer grades against this)

- [ ] Located the specific decision record before drawing any conclusion
- [ ] Distinguished genuine human oversight from a rubber-stamp (checked timing and information)
- [ ] Reconstructed a plain-language explanation from citations and policy versions
- [ ] Chose honesty with the regulator over concealment when a gap was found
- [ ] Paused unsafe auto-decisioning immediately if oversight had failed
- [ ] Remediated the affected citizen decision, not just the process
- [ ] Fixed the root cause so the decision cannot be issued without human sign-off and a full log
- [ ] Audited for other affected cases
- [ ] Produced evidence, not assertions, in the appeal response

---

Prof. Happy (SUTA Labs)
