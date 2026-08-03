# Concepts: Capstone Blueprint - The Complete Engagement

**Tier 18, Module 18.0** - the map of the whole capstone and how it ties tiers 1 through 17 together.

This is the flagship. Every prior tier was a skill; the capstone is you doing the entire job for one client, end to end. Read this blueprint first. It shows the seven parts, how they connect, and which earlier tier each part draws on.

**Title:** Secure Responsible AI Adoption Program for a Public-Sector Organization.

**Scenario:** A public institution wants a secure, bilingual AI knowledge assistant but has nothing in place: no AI governance, no validated use case, unclean documents, no evaluation criteria, no security controls, no staff training, and no operating procedures. You take them from that starting point to a governed, secure, operating assistant with a board-approved program.

**Duration:** 12-16 weeks.

---

## The arc in one line

**Discovery -> Strategy -> Governance -> Build -> Secure -> Operate -> Present.**

You will produce a single client-ready package that a real public institution could act on, and defend it in front of a reviewer playing the board.

---

## The seven parts and what each requires

| Part | Phase | What you deliver | Draws on |
|---|---|---|---|
| 1 | Discovery (C) | Stakeholder interviews, process map, document inventory, data classification, technical + security review, skills assessment | Tiers 13-16 |
| 2 | Strategy (C) | AI readiness score, use-case prioritization, business case, risk classification, pilot charter, success metrics | Tiers 14-16 |
| 3 | Governance (C) | AI policy, impact assessment, human-oversight design, vendor assessment, incident process, AI system inventory | Tiers 12, 16 |
| 4 | Build (B) | Secure bilingual RAG assistant on PostgreSQL + pgvector, provider abstraction, auth, permissions, citations, logging, evaluation, monitoring, containerized + cloud deployment | Tiers 6-10 |
| 5 | Secure (S) | Threat model, prompt-injection / role-bypass / malicious-document / data-leakage testing, tool-permission review, remediation report | Tier 11 |
| 6 | Operate (U) | CI/CD, backup, recovery, monitoring, model-change process, knowledge-base maintenance, support workflow, cost controls | Tier 10 |
| 7 | Present (I) | Executive proposal, architecture diagram, financial model, 90-day / 1-year / 3-year roadmaps, board presentation, staff-training plan, final evaluation report | Tiers 14, 17 |

The mapping matters: the capstone is proof that every tier was real. If you cannot do a part, revisit its source tier.

---

## How the parts connect (do not skip the sequencing)

- **Discovery feeds Strategy.** You cannot prioritize use cases or score readiness without the interviews, inventory, and classification from Part 1.
- **Strategy feeds Governance.** Your risk classification and pilot charter define what governance the system needs.
- **Governance constrains Build.** Human-oversight design, the AI policy, and the impact assessment set the requirements the technical build must meet - not the other way around.
- **Build enables Secure.** You cannot threat-model and attack a system that does not exist yet.
- **Secure gates Operate and Present.** The assistant must pass its full security SURVIVE suite before you would ever put it in front of the board or into operations.
- **Operate makes it real.** A demo that cannot be backed up, recovered, updated, and paid for is not a program.
- **Present ties it together.** The board sees one coherent story: here is the need, here is the governed and secure solution, here is the cost and the roadmap.

A common failure is building first (Part 4) because it is the fun part, then retrofitting governance and security. Do it in order. Governance and security are requirements, not afterthoughts.

---

## What "done" looks like (the proof of competence)

All seven parts delivered as a single client-ready package; the RAG assistant passes its full security SURVIVE suite; and the board deck survives a live Q&A rehearsal in front of a real reviewer. This becomes your flagship case study for Tier 17.

Use the deliverables checklist (`build/00-deliverables-checklist.md`) to track completion and the proof-of-competence rubric (`interview/02-proof-rubric.md`) to grade the whole thing.

---

## The public-sector spine (never lose this)

Because the client is a public institution, the Tier 16 public-sector rules govern everything:
- AI supports; humans decide on anything consequential.
- Explainability and appeal-grade logging are requirements.
- Accessibility and equal bilingual quality are gates.
- Start administrative and internal; earn the way to citizen-facing.
- Every consequential interaction is reconstructable.

If any deliverable violates the spine, it is wrong, no matter how technically impressive. The public-sector rules, the governance approach, and the risk-classification method it references are grounded in the sector and framework sources cited in Tiers 16 and 12 (see: https://www.nist.gov/itl/ai-risk-management-framework).

---

## References

- NIST AI Risk Management Framework (AI RMF 1.0), National Institute of Standards and Technology: https://www.nist.gov/itl/ai-risk-management-framework
- Web Content Accessibility Guidelines (WCAG), W3C Web Accessibility Initiative (accessibility gate): https://www.w3.org/WAI/standards-guidelines/wcag/
- ISO/IEC 42001:2023, Artificial intelligence - Management system (AI governance): https://www.iso.org/standard/42001

Notes:
- The seven-part arc, the tier mapping, and the sequencing rules are the SUTA Labs capstone methodology - a teaching structure, not an external standard.
- The specific legal and accessibility obligations that apply depend on [CLIENT]'s jurisdiction and sector. See the Tier 16 concept references for the underlying public-sector, financial, healthcare, and education sources.

---

Prof. Happy (SUTA Labs)
