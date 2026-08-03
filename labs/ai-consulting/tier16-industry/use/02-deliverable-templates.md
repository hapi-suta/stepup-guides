# USE: The Six Industry-Portfolio Deliverable Templates

**Tier 16 - USE phase.** These are fill-in templates for the six deliverables in the Tier 16 BUILD. Copy each into your sector folder, then replace every `[BRACKET]` and every "adapt for sector" note with the real, sector-specific content. Placeholders: `[CLIENT]`, `[COMPANY]`, `[INDUSTRY]`.

**Validated on:** consulting-artifact review, 2026-07-25.

Each template is followed by a short worked snippet so you can see the level of specificity expected.

---

## Template 1: Industry-specific AI readiness assessment

```
# AI Readiness Assessment - [CLIENT] ([INDUSTRY])
Prepared by: [YOUR NAME]   Date: [DATE]

## 1. Executive summary
[Two or three sentences: are they ready, what is the biggest gap, what to do next.]

## 2. Scored dimensions (0-5 each)
| Dimension | Score | Evidence | Gap |
|---|---|---|---|
| Data readiness | [ ] | [ ] | [ ] |
| Governance readiness | [ ] | [ ] | [ ] |
| Skills readiness | [ ] | [ ] | [ ] |
| Technical readiness | [ ] | [ ] | [ ] |
| Use-case readiness | [ ] | [ ] | [ ] |
| [SECTOR dimension, e.g. Accessibility / Auditability / PHI controls / Student privacy] | [ ] | [ ] | [ ] |

## 3. Overall verdict
[Plain-language: not ready / ready for a pilot / ready to scale, and why.]

## 4. Top three gaps to close first
1. [ ]
2. [ ]
3. [ ]

## 5. Recommended next step
[One concrete action, e.g. a scoped pilot on X.]
```

Worked snippet (public sector, data readiness):

```
| Data readiness | 2 | Policy documents exist but are scattered PDFs, no versioning, no classification tags. | Records are not classified, so access control cannot be enforced. Classify before ingestion. |
```

---

## Template 2: Governance policy

```
# AI Governance Policy - [CLIENT] ([INDUSTRY])
Version [ ]   Owner: [ROLE]   Review cadence: [e.g. quarterly]

## 1. Scope and definitions
## 2. Risk classification
[List this sector's high-risk use cases and why they are high-risk.]
## 3. Human-oversight requirements
[Who must review what, before what action.]
## 4. Sector hard rules
[The non-negotiables, e.g. "Human decides all high-impact citizen outcomes."]
## 5. Data-handling rules
[PHI / PII / records / student data controls.]
## 6. Incident and appeal process
## 7. Roles and accountability
## 8. Review and change control
```

Worked snippet (financial services, hard rules):

```
## 4. Sector hard rules
- Every credit or product decision affecting a customer produces an explainable, human-readable adverse-action reason.
- No model reaches production without documented review and sign-off (change control).
- Disparate-impact testing is run at launch and quarterly thereafter; results retained with the model.
- The assistant never gives financial advice; advice questions route to a licensed human.
```

---

## Template 3: Use-case roadmap

```
# AI Use-Case Roadmap - [CLIENT] ([INDUSTRY])

## Use-case inventory
| Use case | Value | Risk | Effort | Phase |
|---|---|---|---|---|
| [ ] | H/M/L | H/M/L | H/M/L | 1/2/3 |

## Sequencing rationale
[Start administrative/low-risk; earn the way to decisional.]

## Guardrails per use case
| Use case | Required guardrails |
|---|---|

## Out of scope (for now)
| Use case | Why deferred |
|---|---|
```

Worked snippet (healthcare, sequencing):

```
## Sequencing rationale
Phase 1 is strictly administrative (discharge-summary drafting, appointment routing) - real value, no clinical risk. Phase 2 adds internal clinician knowledge search (still administrative). Anything clinical (triage, diagnosis support) is explicitly out of scope until a validation and regulatory-clearance program exists.
```

---

## Template 4: Architecture

```
# Reference Architecture - [CLIENT] ([INDUSTRY]) AI Assistant

## Components
[ingestion -> vector store (pgvector) -> retrieval -> model-provider abstraction -> app -> auth -> logging -> evaluation -> monitoring]

## Sector constraint overlays
| Constraint | Design change |
|---|---|

## Data flow and boundaries
[Where sensitive data goes and, crucially, where it does not.]

## Provider strategy
[Which models, fallbacks, what never leaves the boundary.]
```

Worked snippet (public sector, constraint overlay):

```
| Constraint | Design change |
|---|---|
| Records classification | Retrieval filters by user clearance vs. document classification; refusal is logged. |
| Appeals | Per-response appeal-grade log: retrieved doc IDs+versions, citations, model version. |
| Accessibility | Front end audited to WCAG; conformance level documented for procurement. |
| Data residency | All PHI/records stay in-jurisdiction; no cross-border model calls for restricted data. |
```

---

## Template 5: Pilot proposal

```
# Pilot Proposal - [CLIENT] ([INDUSTRY])

## The use case
[The smallest valuable, appropriate thing.]

## Success metrics
| Metric | Baseline | Target | How measured |
|---|---|---|---|

## Scope / non-scope
In scope: [ ]
Explicitly NOT in scope: [ ]

## Timeline
| Week | Milestone |
|---|---|

## Cost estimate
[ ]

## Risks and mitigations (sector-specific)
| Risk | Likelihood | Mitigation |
|---|---|---|

## Exit criteria
Succeeds if: [ ]
Stops if: [ ]
```

Worked snippet (education, success metrics):

```
| Metric | Baseline | Target | How measured |
|---|---|---|---|
| Educator prep time per lesson | 90 min | 45 min | Weekly self-report, 20 educators |
| Generated-content accuracy | n/a | >=95% pass human review | Reviewer checklist per item |
| Student privacy incidents | n/a | 0 | Incident log |
```

---

## Template 6: Executive presentation (outline)

```
# Executive Presentation - [CLIENT] ([INDUSTRY])  (8-12 slides)

1. The opportunity (in [INDUSTRY] language)
2. Why now / what changed
3. Our approach: readiness -> pilot -> scale
4. Architecture at executive altitude (one clean diagram)
5. Governance and risk: how we keep you safe and compliant
6. The pilot ask: scope, cost, timeline
7. Expected value and how we measure it
8. Roadmap beyond the pilot
9. (optional) Team and credibility
10. (optional) FAQ / objections pre-answered
```

Worked snippet (slide 5, financial services):

```
Slide 5 - Governance and risk
- Every decision is auditable: model registry + reconstructable decision log.
- Every customer-facing decision is explainable (adverse-action reasons).
- Fairness is monitored quarterly, not assumed.
- Humans own all high-stakes actions; the model recommends, the officer signs.
Takeaway line: "You can defend every decision to your regulator."
```

---

## How to use these

1. Copy all six into each sector folder.
2. Replace every bracket and every "adapt for sector" note with real content from that sector's Concepts module.
3. Check the finished pack against the BUILD exit standard: two sectors should read as two mindsets, not one template twice.

---

Prof. Happy (SUTA Labs)
