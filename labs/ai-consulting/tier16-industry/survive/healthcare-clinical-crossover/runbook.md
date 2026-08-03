# SURVIVE Runbook: Healthcare Use Case Crosses Into Clinical Without Validation

**Tier 16 - SURVIVE scenario 3 of 3.** Review-assessed. No script to run; a reviewer grades your response against the checklist.

## The situation

Your [CLIENT] is a health system. You helped them deploy an assistant scoped as strictly **administrative**: it summarizes a patient's record so a nurse can find information faster. It was never validated as a clinical tool because it was never meant to influence care.

A team lead just told you, proudly, that nurses have started using the summary to decide which patients to see first - effectively using it for triage. Triage is a clinical decision. Your administrative tool has silently crossed the line into clinical use, unvalidated, and it is being used on real patients right now. **You must stop and remediate.**

This is the most common serious failure in healthcare AI: an administrative tool drifting into clinical use. It tests whether you recognize the line and act, even when the client is happy.

---

## Diagnosis: how far across the line are you, and how much risk is live?

Speed matters here because patients are being affected. But diagnose before you act.

### 1. Confirm the crossover is real, not a misunderstanding
"Using the summary to prioritize" could mean (a) nurses read it then apply their own clinical judgment (administrative, acceptable) or (b) nurses order their queue by the tool's output without independent assessment (clinical, unvalidated, unacceptable). Talk to the nurses. Find out what they actually do. The difference is everything.

### 2. Assess the harm exposure
If it is genuine unvalidated triage: how many patients, since when, with what possible harm? A summary that omits or misstates a critical detail could cause a sicker patient to be seen later. Treat this as a potential patient-safety event.

### 3. Check what the tool was validated for
Confirm the record: this tool was validated and cleared for administrative summarization only. That is the documented boundary that has been breached.

---

## Recovery

### Stop first
1. Immediately inform clinical leadership and the safety/quality function. Patient safety escalations do not wait for a tidy plan.
2. Instruct that the tool must not be used to prioritize or triage patients - the summary is a reference, the clinician's independent assessment sets priority. Communicate this now, in writing, to every user.
3. If the risk is acute and you cannot enforce correct use quickly, restrict or pause the tool until you can. A paused productivity tool beats an unvalidated clinical one.

### Then remediate
4. Review affected patients: was anyone harmed or nearly harmed by mis-prioritization? Follow the client's patient-safety incident process for any suspected event.
5. Root-cause the drift: why did it cross the line? Usually the tool was too useful and no control stopped clinical use. Add controls - UI language that says "reference only, not for triage", scope reminders, and monitoring for clinical-style usage.
6. Decide the future of the clinical use case honestly. If triage support has real value, it can be built - but as a separate, deliberately clinical project: formal clinical validation across the patient population, regulatory clearance, genuine human oversight, and post-market monitoring. It cannot be a side effect of an administrative tool.
7. Document everything: the crossover, the response, the remediation, and the decision. In healthcare, the record is part of the safety system.

---

## The lesson

The clinical/administrative line is the most important idea in healthcare AI, and drift across it is silent. A tool being loved by users is not evidence it is safe - it can be the exact reason it drifted. Your value as a consultant is that you named the line, watched for the drift, and had the discipline to stop a happy client. Build the controls that prevent crossover before launch, and monitor for clinical-style usage after.

---

## Review checklist (reviewer grades against this)

- [ ] Distinguished real clinical crossover from acceptable administrative use before acting
- [ ] Treated genuine unvalidated triage as a potential patient-safety event
- [ ] Escalated to clinical leadership and the safety function immediately
- [ ] Communicated in writing that the tool is reference-only, not for triage
- [ ] Restricted or paused the tool if correct use could not be enforced quickly
- [ ] Reviewed affected patients and followed the incident process for suspected harm
- [ ] Root-caused the drift and added controls to prevent recurrence
- [ ] Insisted any clinical use be a separate, validated, cleared, overseen project
- [ ] Documented the crossover, response, and decision fully
- [ ] Held the line even though the client was happy with the tool

---

Prof. Happy (SUTA Labs)
