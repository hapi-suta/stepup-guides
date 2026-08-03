# USE: Three Role-Specific Decks From One Assessment

**Tier 15 - Consulting Mastery. Deliver the SAME AI-readiness assessment three ways - to a CEO, a CISO, and an engineering audience - so each hears the version that lets them decide.**

The facts do not change. The emphasis, the vocabulary, and the ask do. This guide shows how to reframe, then gives three actual slide-by-slide deck outlines for the worked-example client (Cascade Regional Health - see `../build/readiness-assessment-worked-example.md`).

---

## How to reframe the same facts

Same assessment, three lenses:

| Element | CEO hears | CISO hears | Engineering hears |
|---|---|---|---|
| Readiness 2.8/5 | "We can start, narrowly" | "Data & governance gaps are the exposure" | "Here's the tech debt to fix" |
| 9.8% denial rate | "$14M/yr margin opportunity" | "in-tenant data, no external exposure" | "clean 24-mo dataset, classification model" |
| Data score 2.0 | "foundation investment needed" | "no catalog = uncontrolled PHI sprawl" | "no catalog, 3-4 wk data pulls, one analyst SPOF" |
| The pilot | "$180K -> $3.5M/yr, payback < Yr 2" | "in-tenant ML, no LLM, compliance gate" | "profiling -> model -> dashboard, 3 sprints" |
| The ask | "approve funding + name a sponsor" | "approve the controls + review gates" | "approve access + the platform build" |

Three rules:
1. **Lead with what the audience is accountable for.** CEO: value and strategy. CISO: risk and controls. Engineering: architecture, data, and effort.
2. **Translate the metric into their unit.** The same $14M is "margin" to the CEO, "attack surface" to the CISO, "training data" to engineering.
3. **The ask is different every time.** Never end all three decks with the same slide.

---

## Deck A - CEO deck (value / ROI / strategy)

10 slides. Vocabulary: margin, payback, competitive position, decision.

```
Slide 1  - AI Readiness: Where Cascade Starts
             - Assessment by StepUp AI Advisory
             - The board's question: are we ready, and where do we begin?

Slide 2  - Bottom line
             - Readiness 2.8/5: start narrow, build foundation in parallel
             - One pilot, $180K, targets ~$3.5M/yr recovered margin
             - Full 3-yr plan pays back inside Year 2

Slide 3  - The margin problem we can attack
             - Operating margin 3.1% -> 1.4% in two years
             - 9.8% claim denial rate = ~$14M/yr in delayed/lost reimbursement

Slide 4  - Where we stand (in plain terms)
             - Strong: leadership commitment, compliance, security
             - Needs work: data, talent, governance
             - Translation: we can start, we can't rush

Slide 5  - The competitive clock
             - A peer system shipped AI scheduling
             - Doing nothing is a decision with a cost

Slide 6  - The recommended first bet
             - Predict claim denials before submission
             - Cut denials 25% -> ~$3.5M/yr recovered

Slide 7  - What the first 90 days buys you
             - Measurable denial-rate drop (9.8% -> 7.5% target)
             - A go/no-go decision backed by real numbers, not a slide

Slide 8  - Three-year value story
             - Yr 1 foundation + first ROI; Yr 2 scale; Yr 3 differentiate
             - $3.07M invested; payback inside Year 2 on denials alone

Slide 9  - The ask
             - Approve $180K pilot + Year-1 budget ($817.6K)
             - Name the CIO as program sponsor

Slide 10 - Next steps
             - Sign SOW, kick off within 3 weeks
```

---

## Deck B - CISO deck (risk / controls / compliance / OWASP LLM)

11 slides. Vocabulary: PHI, exposure, controls, HIPAA, OWASP LLM Top 10, gates.

```
Slide 1  - AI Adoption: The Security & Compliance View
             - What must be true before AI touches our data

Slide 2  - Bottom line for security
             - The first pilot is deliberately low-risk: in-tenant ML, no external LLM, no PHI leaves the tenant
             - The real exposure is our data sprawl and missing AI governance

Slide 3  - Current security posture (the good)
             - HIPAA program mature (3.6/5)
             - IAM and encryption controls solid (3.4/5)

Slide 4  - The gaps that create exposure
             - Governance 2.3: no data ownership, no AI/model policy
             - Data 2.0: no catalog = uncontrolled PHI sprawl
             - No AI-specific threat modeling done yet

Slide 5  - AI-specific threats we must plan for
             - Sensitive-data leakage into external models
             - Prompt injection / data exfiltration (OWASP LLM Top 10)
             - Model hallucination in patient-facing surfaces

Slide 6  - How the pilot stays safe
             - Claim-denial model runs in-tenant, no external LLM API
             - No PHI in the FAQ assistant (public content only)
             - Compliance review gate before any deliverable touches PHI

Slide 7  - Risk register (security items)
             - PHI leakage: Med/High -> in-tenant only + AI policy
             - Prompt injection: Med/Med -> input validation, output filtering
             - HIPAA new-flow risk: Med/High -> BAA + compliance gate

Slide 8  - Controls we need in Year 1
             - AI data-handling policy (currently score 0)
             - Data catalog + ownership
             - Vendor eval criteria + BAAs + exit strategy

Slide 9  - Governance roadmap
             - Yr1 policy + catalog; Yr2 model monitoring; Yr3 org-wide enablement with audit

Slide 10 - The ask
             - Approve the pilot's control set + review gates
             - Fund the AI data-handling policy + catalog in Year 1
             - CISO named as the standing review authority

Slide 11 - Next steps
             - Sign off on data-handling gate before pilot phase 1 day 20
```

---

## Deck C - Engineering deck (architecture / data / effort / dependencies)

12 slides. Vocabulary: pipeline, features, MLOps, dependencies, sprints, SPOF.

```
Slide 1  - AI Readiness: Engineering Assessment
             - What we have, what we lack, what we build

Slide 2  - Bottom line for engineering
             - Data is the constraint, not the model
             - Pilot is a straightforward classification build; the hard part is data access + governance plumbing

Slide 3  - Current technical estate
             - Epic EHR + Azure tenancy (score 3.0)
             - Weak integration, no MLOps, no feature store

Slide 4  - The data reality
             - Score 2.0: no catalog, 3-4 week integrated-data pulls
             - Single-analyst SPOF for every dataset request
             - Billing + remittance history is usable (24 mo clean)

Slide 5  - Pilot architecture (claim-denial)
             - Ingest billing/remittance -> Azure tenant
             - Feature engineering on 24-mo history
             - Classification model -> scoring API -> review dashboard
             - No external LLM, no EHR write-back

Slide 6  - Effort breakdown (3 sprints / 90 days)
             - Sprint 1: data profiling + clean dataset
             - Sprint 2: model + dashboard
             - Sprint 3: shadow -> live -> measure

Slide 7  - Dependencies
             - Billing data access by day 5
             - CISO data-handling gate by day 20
             - Cascade analyst 0.5 FTE for knowledge transfer

Slide 8  - Talent gap
             - Two SQL analysts, zero ML/data engineers
             - Partner-led delivery Yr1 + hire 1 data engineer

Slide 9  - Platform roadmap
             - Yr2: feature store, MLOps, model monitoring
             - Yr3: reusable pipeline for note-summarization + prior-auth extraction

Slide 10 - Later use cases + their tech asks
             - FAQ assistant: RAG, non-PHI, low effort (S)
             - Note summarization: LLM + PHI controls, high effort (L)

Slide 11 - The ask
             - Approve data access + tenant environment
             - Fund the data engineer hire + Year-2 platform build

Slide 12 - Next steps
             - Stand up the tenant workspace in week 1 of the pilot
```

---

## What good looks like

- [ ] All three decks assert the **same facts** (readiness 2.8, denial 9.8%, pilot $180K, ~$3.5M/yr).
- [ ] Each deck **leads with what that role owns** (CEO value, CISO risk, Engineering architecture).
- [ ] The **ask slide differs** across all three.
- [ ] The CISO deck names **at least one OWASP-LLM-class threat** and a control.
- [ ] The Engineering deck shows **effort, dependencies, and the data constraint** explicitly.
- [ ] No fact contradicts the worked-example package.
