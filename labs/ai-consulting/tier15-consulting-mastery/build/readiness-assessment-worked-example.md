# BUILD: AI-Readiness Assessment - Worked Example

**Tier 15 - Consulting Mastery. A fully filled deliverable package for a fictional client. Study the depth, the evidence, and the numbers - then produce your own for a different industry.**

- `[CLIENT]` = **Cascade Regional Health** - a regional hospital network, 4,000 staff, 6 hospitals + 22 clinics, ~$1.2B annual revenue, US Pacific Northwest.
- `[COMPANY]` = **StepUp AI Advisory** (your consultancy).
- Strategic pressure: operating margin fell from 3.1% to 1.4% over two years; a competing system launched an AI scheduling product; the board asked "are we ready for AI, and where do we start?"

---

## 0. Engagement scope

| Field | Entry |
|---|---|
| Client | Cascade Regional Health |
| Prepared by | StepUp AI Advisory |
| Date | 2026-07 |
| Objective | Assess Cascade's readiness to adopt AI and deliver a prioritized, funded 3-year plan with a fundable first pilot. |
| In-scope | Revenue-cycle, clinical documentation, patient access/scheduling, IT/data platform, security & compliance. 3-year horizon. |
| Out-of-scope | Model building, production deployment, vendor contract negotiation, clinical decision-making tools requiring FDA clearance. |
| Duration / effort | 6 weeks, ~120 consultant hours |
| Stakeholders interviewed | CEO, CFO, CIO, Chief Medical Information Officer, Director of Data & Analytics, CISO, VP Revenue Cycle, Director of Patient Access |
| Sign-off owner | CIO |

---

## 1. Interview guide (excerpt of what was asked)

### CEO / Strategy
- Where do you expect the biggest margin pressure over the next three years?
- If AI worked perfectly in one area next year, where would you want it?
- What would make you consider an AI program a failure?

### CIO / CTO
- Walk me through your current cloud and integration footprint.
- Which systems hold the data you would want AI to use?
- What has blocked past analytics or automation efforts?

### Data lead
- Do you have a data catalog or single source of truth for patient and financial data?
- How is data quality measured today, if at all?
- Who can actually access integrated data, and how long does a request take?

### Security / Compliance
- How do you classify and protect PHI today?
- What is your process for evaluating a new vendor that would touch patient data?
- Have you assessed any AI-specific threats such as data leakage into external models?

### HR / Talent
- What data, analytics, or ML skills exist in-house today?
- Is there budget and appetite for upskilling clinical and admin staff?

### Business-unit owner (Revenue Cycle, Patient Access)
- Where does your team lose the most hours to manual, repetitive work?
- What is your current claim denial rate and what drives it?
- How long does it take a patient to get scheduled, and where do you lose them?

---

## 2. Readiness questionnaire (scored)

Scale 0-5. Dimension score = item average. Overall = mean of the 12.

### Scorecard summary
| Dimension | Score | Verdict |
|---|---|---|
| Strategy | 2.7 | Direction exists at board level but no documented AI strategy or funding line. |
| Leadership | 3.3 | Strong CEO/CFO sponsorship; leadership AI-literacy uneven below C-suite. |
| Data | 2.0 | Fragmented across Epic, legacy billing, and spreadsheets; no catalog. |
| Technology | 3.0 | Modern EHR and Azure tenancy, but weak integration and no MLOps. |
| Security | 3.4 | Solid PHI controls and IAM; no AI-specific threat modeling yet. |
| Governance | 2.3 | Data ownership unclear; no AI/model governance policy. |
| Talent | 2.2 | Two analysts, no ML engineers; no upskilling program. |
| Culture | 3.1 | Reporting culture is decent; change fatigue post-EHR migration. |
| Process maturity | 2.8 | Core revenue-cycle processes documented; metrics inconsistent. |
| Budget | 2.5 | No dedicated AI budget; ROI expectations vague. |
| Compliance | 3.6 | HIPAA program mature; AI/privacy guidance not yet written. |
| Vendor readiness | 2.9 | Procurement exists; no AI vendor eval criteria or exit strategy. |
| **Overall readiness** | **2.8 / 5** | **Emerging. Real appetite and clinical data, but data foundation, governance, and talent must come first. Start narrow.** |

### Selected item detail (evidence)
- Data - "Data inventoried/cataloged" = 1: no catalog; the data director maintains an informal spreadsheet of report sources.
- Data - "Data accessible/integrated" = 2: an ad hoc integrated dataset request takes 3-4 weeks and goes through one analyst.
- Talent - "In-house data/AI skills" = 2: two SQL analysts, zero ML engineers, no data engineer.
- Security - "AI-specific threat awareness" = 2: strong PHI baseline, but no one has assessed sending PHI to external LLM APIs.
- Governance - "Model/AI governance policy" = 0: does not exist.
- Budget - "Budget allocated for AI" = 1: no line item; pilots would come from IT discretionary.

---

## 3. Current-state report

### 3.1 Executive summary
Cascade Regional Health has genuine strategic pressure (margin down to 1.4%), executive sponsorship, and a rich clinical and financial data estate. But the foundation is not ready for broad AI adoption: data is fragmented and uncataloged, there is no AI governance policy, and there are no ML engineers on staff. Overall readiness scores 2.8/5 - "Emerging." The right move is not a platform buying spree; it is a narrow, high-value pilot in revenue cycle (claim-denial prediction) that pays for itself while the data, governance, and talent foundation is built in parallel. This report grounds a prioritized five-use-case shortlist, a 90-day pilot, and a funded three-year plan.

### 3.2 Scope recap
See section 0. Assessment covered revenue-cycle, clinical documentation, patient access, IT/data, and security over a 6-week engagement with 8 stakeholder interviews.

### 3.3 Readiness scorecard
Overall 2.8/5. Strongest: Compliance (3.6), Security (3.4), Leadership (3.3). Weakest: Data (2.0), Talent (2.2), Governance (2.3). See section 2 scorecard.

### 3.4 Strengths
- Executive alignment: CEO and CFO both name margin recovery as the #1 goal and back an AI effort.
- Mature HIPAA/security baseline - a hard prerequisite Cascade already largely meets.
- Modern EHR (Epic) and an existing Azure tenancy - the raw platform exists.
- A real, quantifiable pain with a data trail: 9.8% claim denial rate.

### 3.5 Gaps and constraints
- Data foundation weak (2.0): no catalog, 3-4 week turnaround on integrated data, spreadsheet sprawl.
- No AI governance (2.3) and no model policy - a blocker for anything touching PHI.
- Talent gap (2.2): no ML/data engineers; delivery will need partners initially.
- No dedicated budget (2.5): pilots currently funded from IT discretionary spend.

### 3.6 Key findings from interviews
- VP Revenue Cycle: "We rework the same denials every month. If we knew which claims would bounce before submission, we'd save a team's worth of hours." Denial rate 9.8%, ~$14M/yr in delayed/lost reimbursement.
- Director of Patient Access: new-patient scheduling takes 11 days on average; ~18% no-show rate.
- CISO: "Nobody has told me whether we're allowed to put patient notes into an outside AI. I'd block it today."
- Data Director: every integrated dataset flows through one analyst - a single point of failure.

### 3.7 Implications
Cascade should adopt AI in a sequenced way: fix data and governance foundations while running one contained, measurable pilot that generates ROI and organizational confidence. Broad rollout before the foundation is fixed would fail on data access and governance alone.

---

## 4. Use-case inventory (five)

| # | Use case | Business problem | Expected value (metric) | Data required (exists?) | AI approach | Effort |
|---|---|---|---|---|---|---|
| 1 | Claim-denial prediction | 9.8% denial rate, ~$14M/yr impact | Cut denials 25% -> ~$3.5M/yr recovered | Claims + remittance history (yes, in billing system) | Classification / ML scoring | M |
| 2 | Clinical-note summarization | Physicians spend ~2 hrs/day on documentation | Save 30 min/physician/day | Clinical notes in Epic (yes, PHI-sensitive) | LLM summarization (RAG over notes) | L |
| 3 | Patient scheduling optimization | 11-day scheduling lag, 18% no-show | Cut no-shows to 12%, lag to 7 days | Scheduling + demographic history (yes) | Forecasting + optimization | M |
| 4 | Prior-authorization document extraction | Manual review of auth packets, slow | Cut auth turnaround 40% | Auth documents (partial, unstructured) | Document extraction / OCR + LLM | M |
| 5 | Patient-facing FAQ assistant | Call center overloaded with routine questions | Deflect 30% of routine calls | Public policy + FAQ content (yes, non-PHI) | Retrieval / RAG assistant | S |

---

## 5. Prioritization model

Weights (sum 100%): Value 30, Feasibility 25, Time-to-value 20, Strategic fit 15, Risk (inverted) 10.

| Use case | Value | Feasibility | Time-to-value | Strategic fit | Risk (inv) | Weighted score | Rank |
|---|---|---|---|---|---|---|---|
| 1 Claim-denial prediction | 5 | 4 | 4 | 5 | 4 | **4.45** | 1 |
| 2 Clinical-note summarization | 4 | 2 | 2 | 4 | 2 | 3.00 | 5 |
| 3 Scheduling optimization | 4 | 3 | 3 | 4 | 3 | 3.45 | 3 |
| 4 Prior-auth extraction | 3 | 3 | 3 | 3 | 3 | 3.00 | 4 |
| 5 Patient FAQ assistant | 3 | 5 | 5 | 2 | 5 | **3.85** | 2 |

Calculation for #1: (5x0.30)+(4x0.25)+(4x0.20)+(5x0.15)+(4x0.10) = 1.50+1.00+0.80+0.75+0.40 = 4.45.

**Chosen pilot (#1 ranked): Claim-denial prediction.** Highest value, strong feasibility (data exists in one system), and directly on the margin-recovery strategy. The FAQ assistant (#2) is held as a fast, low-risk follow-on.

---

## 6. Risk register

| # | Risk | Category | Likelihood | Impact | Mitigation | Owner |
|---|---|---|---|---|---|---|
| 1 | Denial-history data incomplete or dirty, degrading model accuracy | Data quality | High | High | Data-quality profiling in pilot phase 1; scope to last 24 months of clean records | Director of Data & Analytics |
| 2 | PHI leaks into an external LLM API | Security / privacy (LLM) | Medium | High | Pilot #1 uses in-tenant ML, no external LLM; write AI data-handling policy before any LLM use case | CISO |
| 3 | Prompt injection / data exfiltration in later assistant use cases | Security (LLM) | Medium | Medium | Input validation, output filtering, no PHI in FAQ assistant; follow OWASP LLM Top 10 | CISO |
| 4 | HIPAA non-compliance from new data flows | Compliance | Medium | High | Compliance review gate before any deliverable touches PHI; BAA with any vendor | Compliance Officer |
| 5 | No in-house ML talent to sustain the model | Talent | High | Medium | Partner-led delivery + knowledge transfer; hire one data engineer in Year 1 | CIO |
| 6 | Clinician / staff adoption resistance (change fatigue) | Change management | Medium | Medium | Involve VP Revenue Cycle as champion; keep pilot workflow-embedded, not extra work | VP Revenue Cycle |
| 7 | Cost overrun from scope creep | Cost | Medium | Medium | Fixed-fee pilot, change-request process, 12% contingency in budget | Program Sponsor (CFO) |

---

## 7. 90-day pilot charter

| Field | Entry |
|---|---|
| Use case | Claim-denial prediction (ranked #1) |
| Objective | Predict which claims will be denied before submission so staff can fix them, reducing the denial rate. |
| Success metric + target | Reduce denial rate on piloted claim categories from 9.8% to <= 7.5% within the 90 days (a 25% relative cut). |
| In-scope | Two highest-volume claim categories; last 24 months of billing/remittance data; a scoring dashboard for the revenue-cycle team. |
| Out-of-scope | Auto-resubmission, EHR write-back, other claim categories, any PHI to external LLMs. |
| Team / roles | 1 partner data scientist, 1 partner data engineer, Cascade data analyst (0.5 FTE), VP Revenue Cycle (sponsor), CISO (review gate). |
| Data needed / access | Claims + remittance history from the billing system, pulled to the Azure tenant; no external transfer. |
| Pilot budget | $180,000 |

### Phased approach
| Phase | Days | Activities | Exit |
|---|---|---|---|
| 1 - Discovery / setup | 1-30 | Data profiling, quality baseline, feature definition, security/compliance gate | Clean training dataset + signed data-handling approval |
| 2 - Build / integrate | 31-60 | Train scoring model, build review dashboard, integrate into pre-submission workflow | Working dashboard scoring live claim batches |
| 3 - Measure / decide | 61-90 | Run in shadow then live, measure denial delta, go/no-go review | Measured denial-rate impact + scale decision |

### Go / no-go gate
Scale if the piloted categories show a >= 15% relative reduction in denials by day 90 with no compliance findings. Below that, iterate one more cycle before deciding.

### Pilot risks (from register)
- Data quality (Risk 1) - profiling in phase 1 is the mitigation.
- Talent sustainability (Risk 5) - knowledge transfer to the Cascade analyst is built into every phase.

---

## 8. Three-year roadmap

| Horizon | Initiative | Expected outcome | Dependency |
|---|---|---|---|
| Year 1 - Foundation | Claim-denial pilot -> production | ~$3.5M/yr recovered reimbursement | Pilot go decision |
| Year 1 - Foundation | Data catalog + governance policy + AI data-handling policy | Single source of truth; PHI-safe AI path | Data director + CISO |
| Year 1 - Foundation | Hire 1 data engineer; launch upskilling for 2 analysts | In-house capability begins | Budget approval |
| Year 2 - Scale | Patient FAQ assistant + scheduling optimization | 30% call deflection; no-shows 18% -> 12% | Governance policy live |
| Year 2 - Scale | Central AI platform (feature store, MLOps, monitoring) | Repeatable delivery, model monitoring | Data engineer hired |
| Year 3 - Differentiate | Clinical-note summarization + prior-auth extraction | 30 min/physician/day saved; 40% faster auth | PHI LLM policy + BAAs |
| Year 3 - Differentiate | Org-wide AI enablement + ROI measurement office | Sustained value tracking; culture shift | Platform + talent in place |

---

## 9. Budget estimate

USD, three-year plan. Contingency 12%.

| Line item | Year 1 | Year 2 | Year 3 | 3-yr total |
|---|---|---|---|---|
| Platform / tooling | 60,000 | 140,000 | 160,000 | 360,000 |
| Cloud / infra | 40,000 | 90,000 | 120,000 | 250,000 |
| Data engineering | 120,000 | 150,000 | 150,000 | 420,000 |
| Model / API spend | 20,000 | 60,000 | 110,000 | 190,000 |
| Security & compliance | 50,000 | 60,000 | 60,000 | 170,000 |
| Talent (hires + upskilling) | 180,000 | 260,000 | 300,000 | 740,000 |
| Consulting / services | 260,000 | 200,000 | 150,000 | 610,000 |
| Subtotal | 730,000 | 960,000 | 1,050,000 | 2,740,000 |
| Contingency (12%) | 87,600 | 115,200 | 126,000 | 328,800 |
| **Total** | **817,600** | **1,075,200** | **1,176,000** | **3,068,800** |

Return context: the claim-denial use case alone targets ~$3.5M/yr recovered reimbursement, so the full three-year program (~$3.07M) is expected to pay back inside Year 2 on that single use case, before counting scheduling, call deflection, and documentation savings.

---

## 10. Executive presentation (outline with bullets)

```
Slide 1  - Title: "AI-Readiness Assessment - Cascade Regional Health"
             - Prepared by StepUp AI Advisory, 2026-07
Slide 2  - Bottom line up front
             - Readiness is 2.8/5 (Emerging): real appetite, weak data/governance/talent
             - Recommendation: fund a 90-day claim-denial pilot ($180K), build foundation in parallel
             - Expected: ~$3.5M/yr recovered; full 3-yr plan pays back inside Year 2
Slide 3  - Readiness scorecard (12 dimensions, overall 2.8)
             - Strong: Compliance, Security, Leadership
             - Weak: Data (2.0), Talent (2.2), Governance (2.3)
Slide 4  - Top findings
             - 9.8% denial rate = ~$14M/yr impact
             - Data flows through one analyst; no AI governance policy
Slide 5  - Five use cases (the shortlist)
Slide 6  - The ranked pick: claim-denial prediction (score 4.45)
             - Highest value + feasible + on-strategy
Slide 7  - 90-day pilot: target denials 9.8% -> 7.5%, $180K, go/no-go at day 90
Slide 8  - Three-year roadmap: Foundation -> Scale -> Differentiate
Slide 9  - Budget $3.07M over 3 years; payback inside Year 2
Slide 10 - Risks: PHI leakage, data quality, talent - each mitigated
Slide 11 - The ask
             - Approve $180K pilot + Year-1 foundation budget ($817.6K)
             - Name CIO as program sponsor
Slide 12 - Next steps: sign SOW, kick off pilot phase 1 within 3 weeks
```

---

## 11. Statement of work (summary)

| Section | Content |
|---|---|
| Parties | StepUp AI Advisory ("Consultant") and Cascade Regional Health ("Client") |
| Background / objectives | Deliver a 90-day claim-denial prediction pilot plus foundational data/governance groundwork. |
| Scope - in | Data profiling, model build, review dashboard, workflow integration for two claim categories; governance policy draft. |
| Scope - out | Production auto-resubmission, other claim categories, EHR write-back, external LLM use, additional use cases. |
| Deliverables | (D1) Data-quality baseline, (D2) trained denial-scoring model, (D3) review dashboard, (D4) impact report + scale recommendation, (D5) AI data-handling policy draft. |
| Milestones + timeline | M1 day 30, M2 day 60, M3 day 90 (see table). |
| Fees + payment schedule | Fixed fee $180,000. 30% on signing, 35% at M2, 35% at M3 acceptance. |
| Acceptance criteria | Each deliverable accepted on written Client sign-off within 5 business days of delivery; D4 accepted when the measured denial-rate delta is reported against the day-90 target. |
| Assumptions | Client provides billing data access to the Azure tenant by day 5; CISO gate cleared by day 20. |
| Change-request process | Scope changes via written CR, priced before work proceeds. |
| IP ownership | Client owns deliverables and trained model; Consultant retains pre-existing methods/templates. |
| Confidentiality / data terms | Mutual NDA; BAA in force; no PHI leaves Client tenant. |
| Liability cap | Fees paid under this SOW. |
| Term & termination | 90 days; either party may terminate for material breach with 15 days' cure. |

### Milestones + timeline
| Milestone | Deliverable | Due | Payment |
|---|---|---|---|
| M1 | D1 data-quality baseline + D5 policy draft | Day 30 | 30% (on signing) |
| M2 | D2 model + D3 dashboard | Day 60 | 35% |
| M3 | D4 impact report + scale recommendation | Day 90 | 35% |
