# USE: Statement of Work - Template + Worked Example

**Tier 15 - Consulting Mastery. Draft a real, signable Statement of Work: scope, milestones, pricing, and acceptance criteria that hold up.**

An SOW is the document that actually gets signed and paid against. It converts a recommendation into a contained, priced, acceptance-gated engagement. This file gives you a reusable blank template, then a filled worked example for the Cascade Regional Health claim-denial pilot from `../build/readiness-assessment-worked-example.md`.

Placeholders in the blank version: `[CLIENT]`, `[COMPANY]`, `[PLACEHOLDER]`.

---

## Part A - Blank SOW template

### Statement of Work

**Between** [COMPANY] ("Consultant") and [CLIENT] ("Client").
**Effective date:** [PLACEHOLDER]
**SOW reference:** [PLACEHOLDER]

---

### 1. Parties
- Consultant: [COMPANY], [PLACEHOLDER address / entity].
- Client: [CLIENT], [PLACEHOLDER address / entity].
- Governed by the Master Services Agreement dated [PLACEHOLDER] (or, if none, this SOW is the full agreement).

### 2. Background and objectives
[PLACEHOLDER - why this engagement exists and the outcome it targets, in 2-4 sentences.]

### 3. Scope

**In scope**
- [PLACEHOLDER]
- [PLACEHOLDER]
- [PLACEHOLDER]

**Explicitly out of scope**
- [PLACEHOLDER]
- [PLACEHOLDER]
- [PLACEHOLDER]

### 4. Deliverables
| ID | Deliverable | Description |
|---|---|---|
| D1 | [PLACEHOLDER] | [PLACEHOLDER] |
| D2 | [PLACEHOLDER] | [PLACEHOLDER] |
| D3 | [PLACEHOLDER] | [PLACEHOLDER] |
| D4 | [PLACEHOLDER] | [PLACEHOLDER] |

### 5. Milestones and timeline
| Milestone | Deliverables | Target date | Payment trigger |
|---|---|---|---|
| M1 | [PLACEHOLDER] | [PLACEHOLDER] | [PLACEHOLDER] |
| M2 | [PLACEHOLDER] | [PLACEHOLDER] | [PLACEHOLDER] |
| M3 | [PLACEHOLDER] | [PLACEHOLDER] | [PLACEHOLDER] |

### 6. Fees and payment schedule
- **Pricing model:** [PLACEHOLDER - fixed-fee / time-and-materials / retainer / milestone-based].
- **Total fee:** [PLACEHOLDER].
- **Schedule:**

| Invoice | Amount | Due |
|---|---|---|
| [PLACEHOLDER] | [PLACEHOLDER] | [PLACEHOLDER] |
| [PLACEHOLDER] | [PLACEHOLDER] | [PLACEHOLDER] |
| [PLACEHOLDER] | [PLACEHOLDER] | [PLACEHOLDER] |

- Payment terms: net [PLACEHOLDER] days from invoice. Expenses [PLACEHOLDER].

### 7. Acceptance criteria
Objective, per deliverable. Client reviews within [PLACEHOLDER] business days; silence past the window = deemed accepted.

| Deliverable | Acceptance criterion |
|---|---|
| D1 | [PLACEHOLDER] |
| D2 | [PLACEHOLDER] |
| D3 | [PLACEHOLDER] |
| D4 | [PLACEHOLDER] |

### 8. Assumptions
- [PLACEHOLDER - what must be true for the plan/price to hold, e.g. access provided by day X.]
- [PLACEHOLDER]

### 9. Change-request process
Any change to scope, deliverables, timeline, or fees is documented in a written Change Request, estimated by Consultant, and takes effect only on Client's written approval. Work continues on the current scope until then.

### 10. Intellectual property
[PLACEHOLDER - who owns deliverables vs. Consultant's pre-existing methods/tools/templates.]

### 11. Confidentiality
Each party protects the other's confidential information and uses it only for this engagement. Survives termination for [PLACEHOLDER] years.

### 12. Data-processing terms
[PLACEHOLDER - data handling, security standards, sub-processors, and any BAA/DPA reference. State where data lives and whether it may leave the client's environment.]

### 13. Liability
Each party's aggregate liability under this SOW is capped at [PLACEHOLDER - e.g. total fees paid]. Neither party is liable for indirect or consequential damages.

### 14. Term and termination
Term: [PLACEHOLDER]. Either party may terminate for material breach with [PLACEHOLDER] days' written notice and a cure period. On termination, Client pays for work performed to date.

### 15. Signatures
| [CLIENT] | [COMPANY] |
|---|---|
| Name: __________ | Name: __________ |
| Title: __________ | Title: __________ |
| Date: __________ | Date: __________ |

---

## Part B - Worked example (Cascade Regional Health claim-denial pilot)

### Statement of Work

**Between** StepUp AI Advisory ("Consultant") and Cascade Regional Health ("Client").
**Effective date:** 2026-08-03
**SOW reference:** SUA-CRH-2026-001

---

### 1. Parties
- Consultant: StepUp AI Advisory, LLC, Portland, OR.
- Client: Cascade Regional Health, a nonprofit hospital network, Tacoma, WA.
- This SOW constitutes the full agreement between the parties for the engagement described.

### 2. Background and objectives
Cascade's operating margin has fallen from 3.1% to 1.4% and its claim denial rate stands at 9.8%, representing roughly $14M/yr in delayed or lost reimbursement. This engagement delivers a 90-day pilot that predicts claim denials before submission for the two highest-volume claim categories, plus a draft AI data-handling policy to enable future work. The objective is a measured reduction in the denial rate and an evidence-based decision on scaling.

### 3. Scope

**In scope**
- Data-quality profiling of 24 months of billing and remittance history for two claim categories.
- A claim-denial prediction (classification) model, trained and validated in the Client's Azure tenant.
- A review dashboard surfacing denial-risk scores to the revenue-cycle team pre-submission.
- Integration of scoring into the pre-submission review workflow.
- A draft AI data-handling policy for PHI.

**Explicitly out of scope**
- Automated claim resubmission or correction.
- EHR (Epic) write-back or two-way integration.
- Claim categories beyond the two piloted.
- Any use of external LLM APIs or any transfer of PHI outside the Client's tenant.
- Additional use cases (scheduling, note summarization, FAQ assistant, prior-auth).

### 4. Deliverables
| ID | Deliverable | Description |
|---|---|---|
| D1 | Data-quality baseline | Profiling report on the 24-mo dataset: completeness, quality issues, usable feature set. |
| D2 | Denial-scoring model | Trained, validated classification model in the Client tenant, with a performance report. |
| D3 | Review dashboard | Dashboard scoring live claim batches, embedded in the review workflow. |
| D4 | Impact report + scale recommendation | Measured denial-rate delta vs. target, go/no-go recommendation. |
| D5 | AI data-handling policy (draft) | PHI-safe AI usage policy for Client review. |

### 5. Milestones and timeline
| Milestone | Deliverables | Target date | Payment trigger |
|---|---|---|---|
| M1 | D1 + D5 | Day 30 | 30% (invoiced on signing) |
| M2 | D2 + D3 | Day 60 | 35% |
| M3 | D4 | Day 90 | 35% |

### 6. Fees and payment schedule
- **Pricing model:** fixed fee, milestone-based.
- **Total fee:** $180,000 USD.
- **Schedule:**

| Invoice | Amount | Due |
|---|---|---|
| On signing (M1 kickoff) | $54,000 (30%) | Net 15 |
| At M2 acceptance | $63,000 (35%) | Net 15 |
| At M3 acceptance | $63,000 (35%) | Net 15 |

- Payment terms: net 15 days from invoice. Reasonable pre-approved travel expenses billed at cost.

### 7. Acceptance criteria
Client reviews each deliverable within 5 business days; no written objection within the window = deemed accepted.

| Deliverable | Acceptance criterion |
|---|---|
| D1 | Client confirms the profiled dataset covers the two categories over 24 months with the agreed feature set documented. |
| D2 | Model achieves >= 0.75 AUC on held-out validation data, documented in the performance report. |
| D3 | Dashboard scores a live claim batch and is accessible to the revenue-cycle team in the review workflow. |
| D4 | Report states the measured denial-rate change on piloted categories against the 7.5% target with a clear go/no-go recommendation. |
| D5 | Policy draft covers PHI handling for AI use and is delivered for the CISO's review. |

### 8. Assumptions
- Client grants billing/remittance data access to the Azure tenant by day 5.
- CISO clears the data-handling review gate by day 20.
- A Client data analyst is available at 0.5 FTE for knowledge transfer throughout.
- Denial-rate measurement uses the Client's existing reporting definitions.

### 9. Change-request process
Any change to scope, deliverables, timeline, or fees is documented in a written Change Request, estimated by Consultant, and takes effect only on Client's written approval. Work continues on the current scope until a CR is approved.

### 10. Intellectual property
Client owns the deliverables and the trained model. Consultant retains ownership of its pre-existing methodologies, templates, and tooling, and grants Client a perpetual license to use them as embodied in the deliverables.

### 11. Confidentiality
Each party protects the other's confidential information and uses it solely for this engagement. Obligations survive termination for 3 years.

### 12. Data-processing terms
A Business Associate Agreement (BAA) is in force. All PHI remains within the Client's Azure tenant; no PHI is transferred to Consultant systems or any external model or API. Consultant follows the Client's security standards and uses no sub-processors without written approval.

### 13. Liability
Each party's aggregate liability under this SOW is capped at the total fees paid ($180,000). Neither party is liable for indirect or consequential damages.

### 14. Term and termination
Term: 90 days from the effective date. Either party may terminate for material breach with 15 days' written notice and a cure period. On termination, Client pays for work performed and deliverables accepted to date.

### 15. Signatures
| Cascade Regional Health | StepUp AI Advisory |
|---|---|
| Name: __________ | Name: __________ |
| Title: CIO | Title: Managing Partner |
| Date: __________ | Date: __________ |

---

## What good looks like

- [ ] Scope has both an **in-scope and an explicit out-of-scope** list.
- [ ] Every deliverable maps to a **milestone and a payment**.
- [ ] Pricing states a **named model** and a schedule that sums to the total.
- [ ] Acceptance criteria are **objective and measurable** per deliverable (numbers or sign-off, not "looks good").
- [ ] Data terms state **where data lives and whether it may leave** the client environment.
- [ ] A **liability cap**, **IP ownership**, **change-request process**, and **termination** clause are all present.
- [ ] The worked example's numbers match the SOW summary in `../build/readiness-assessment-worked-example.md` ($180K; 30/35/35).
