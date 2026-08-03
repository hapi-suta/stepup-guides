# Tier 12: Responsible AI and Governance

**Duration:** 12 weeks
**Purpose:** Govern an AI system against NIST AI RMF and ISO/IEC 42001 - produce the
policies, assessments, and controls that make AI validated, fair, private, and
accountable.
**References:** NIST AI RMF (Govern, Map, Measure, Manage) + the NIST Generative AI
Profile; ISO/IEC 42001:2023.
**Needs:** No API keys and no cloud account. The one runnable piece uses Python 3.12
with pandas + scikit-learn on the lab box (CPU only). Most of this tier is consultant
artifacts - documents, templates, matrices, and forms.

## CBUSI contents

- **C - Concepts:**
  - [`concepts/01-responsible-ai-principles.md`](concepts/01-responsible-ai-principles.md) - the twelve trustworthiness principles.
  - [`concepts/02-nist-ai-rmf.md`](concepts/02-nist-ai-rmf.md) - Govern/Map/Measure/Manage + the Generative AI Profile.
  - [`concepts/03-iso-iec-42001.md`](concepts/03-iso-iec-42001.md) - the certifiable AI management system (AIMS).
  - [`concepts/04-ai-impact-assessments.md`](concepts/04-ai-impact-assessments.md) - the assessment that decides go/no-go and risk class.
  - [`concepts/05-ai-policy-development.md`](concepts/05-ai-policy-development.md) - policies for the humans who build, buy, and use AI.
  - [`concepts/06-ai-vendor-assessment.md`](concepts/06-ai-vendor-assessment.md) - sizing and controlling vendor risk.
- **B - BUILD:** [`build/01-project12-governance-toolkit.md`](build/01-project12-governance-toolkit.md) - assemble the twelve-artifact **AI Governance Toolkit** plus a runnable fairness check (disparate-impact ratio). Templates in [`build/toolkit-templates/`](build/toolkit-templates/). *(fairness check tested + output captured)*
- **U - USE:**
  - [`use/01-impact-assessment-tier7-assistant.md`](use/01-impact-assessment-tier7-assistant.md) - run a real impact assessment against your Tier 7 assistant, with a measured language-parity finding. *(script tested)*
  - [`use/02-score-a-vendor.md`](use/02-score-a-vendor.md) - score a real vendor and write the recommendation. *(scorer tested)*
- **S - SURVIVE:**
  - [`survive/governance-gap-audit/`](survive/governance-gap-audit/) - a deployed high-risk system with no impact assessment or oversight plan; audit and remediate. *(inject + validate, script-tested)*
  - [`survive/biased-output-incident/`](survive/biased-output-incident/) - a model update pushes the disparate-impact ratio below 0.80; detect, run the incident process, remediate. *(inject + validate, script-tested)*
  - [`survive/vendor-terms-change/`](survive/vendor-terms-change/) - a vendor deprecates a model and changes data-usage terms; trigger the vendor-management and exit review. *(document/decision scenario - assessed by review, runbook only)*
- **I - Interview:** [`interview/01-tier12-interview.md`](interview/01-tier12-interview.md) - NIST AI RMF, ISO/IEC 42001, high-risk classification, vendor exit, proxy-variable fairness, incident response.

## The twelve toolkit deliverables

AI policy - use-case intake form - risk-classification matrix - impact-assessment
template - vendor questionnaire - model card - data sheet - human-oversight plan -
incident-report template - AI system inventory - project approval workflow - executive
dashboard.

## Exit standard

Govern an AI system against NIST AI RMF and ISO/IEC 42001: you can inventory it,
classify its risk, run its impact assessment, assign human oversight and accountability,
assess its vendor, and respond to an incident - and produce the evidence for each.

## Proof of competence

Your AI Governance Toolkit is complete and applied: a real impact assessment (against
your Tier 7 assistant, including a measured fairness/parity finding) and a real vendor
score, both produced against your own templates, each with a written recommendation.
Both script-tested SURVIVE scenarios (governance-gap audit and biased-output incident)
pass their validators, and your vendor-terms-change deliverables pass instructor review.

## Status

| Layer | State |
|---|---|
| Concepts | Drafted (6 modules) |
| BUILD | Drafted; fairness check tested locally (py3, pandas + scikit-learn) - pending lab test-box validation |
| USE | Drafted; both scripts tested locally - pending lab test-box validation |
| SURVIVE | governance-gap + biased-output cycles script-tested (fail-before / pass-after); vendor-terms-change is review-assessed |
| Interview | Drafted (10 Q + how-to-answer) |
