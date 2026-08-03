# BUILD: Industry-Specialization Portfolio

**Tier 16 - BUILD phase.** This is the worked structure for the Tier 16 project: a complete, industry-specific consulting package for each of your two chosen sectors.

**What you produce.** For **two** chosen sectors, you create six deliverables each (twelve artifacts total):

1. Industry-specific AI readiness assessment
2. Governance policy
3. Use-case roadmap
4. Architecture
5. Pilot proposal
6. Executive presentation

This is not a coding project. It is a consulting-artifact project. The value is in judgment adapted to a sector's real constraints, not in new code. You are proving you can take one method and land it in two very different rooms.

**Validated on:** consulting-artifact review, 2026-07-25. No servers required; this is authored and reviewed work.

---

## Step 0: Choose your two sectors (do this first)

Do not market to every industry. Pick two where you have credibility or interest and where the constraints differ enough to prove range. Recommended pairings:

- **Public sector + Financial services** - both high-accountability, but legitimacy vs. auditability. Strong contrast.
- **Public sector + Education** - both mission-driven; privacy and accessibility focus.
- **Financial services + Healthcare** - both heavily regulated; auditability vs. clinical safety.

Write your choice and one sentence on why into `PORTFOLIO.md` before you build anything. Example:

```
Chosen sectors:
1. Public sector - my target market; legitimacy and appeals focus.
2. Financial services - adjacent, high-value; auditability focus.
```

---

## Step 1: Set up the portfolio folder

On your **lab server**, as **ec2-user**:

```
mkdir -p ~/industry-portfolio/{sector-a,sector-b}
```

The `mkdir -p` command creates the folders and does not error if they exist. Rename `sector-a` and `sector-b` to your real sectors once chosen.

Inside each sector folder you will produce the six deliverables. Copy the templates from the Tier 16 USE phase into each sector folder and adapt them - do not start from a blank page.

---

## The six deliverables (worked structure)

Each deliverable below has a required outline. The USE phase gives you a fill-in template and a worked example for each. Here in BUILD you produce the real, sector-adapted version.

### Deliverable 1: Industry-specific AI readiness assessment

A structured scorecard that tells the client, honestly, whether they are ready for AI and where the gaps are - in this sector's terms.

Required sections:
- Data readiness (quality, access, sensitivity in this sector - e.g. PHI, PII, records classification)
- Governance readiness (existing policy, accountability, regulatory posture for this sector)
- Skills readiness (staff capability, change appetite)
- Technical readiness (infrastructure, security baseline, provider constraints)
- Use-case readiness (are there clear, appropriate first use cases for this sector?)
- Scored summary (a number per dimension, plus a plain-language verdict)
- Top three gaps to close before proceeding

The sector shows up in what you score. Public sector adds accessibility and appeals readiness. Finance adds audit and fairness-monitoring readiness. Healthcare adds the clinical/administrative line and PHI controls. Education adds student-privacy and assessment-integrity readiness.

### Deliverable 2: Governance policy

A sector-specific adaptation of your Tier 12 governance toolkit. It states what AI use is allowed, who is accountable, and what controls apply - in this sector's regulatory language.

Required sections:
- Scope and definitions
- Risk classification (which use cases are high-risk in this sector, and why)
- Human-oversight requirements (who must review what)
- The sector's specific hard rules (e.g. "no clinical use without validation"; "explainable adverse-action reasons on all credit decisions"; "human decides all high-impact citizen outcomes")
- Data-handling rules (PHI / PII / records / student data)
- Incident and appeal process
- Review cadence and ownership

### Deliverable 3: Use-case roadmap

An ordered plan of AI use cases for this sector, sequenced from low-risk/high-value to higher-risk, with the guardrails each requires.

Required sections:
- Use-case inventory (candidates for this sector)
- Scoring (value vs. risk vs. effort)
- Sequencing (start administrative/low-risk, earn the way up)
- Guardrails per use case
- What is explicitly out of scope for now and why

### Deliverable 4: Architecture

A reference architecture for this sector's assistant, based on your Tier 7 RAG assistant and hardened for the sector's constraints.

Required sections:
- Component diagram (ingestion, vector store, retrieval, model-provider abstraction, app, auth, logging, evaluation, monitoring)
- Where the sector's constraints change the design (data residency, access control mapped to records classification, audit-grade logging, multilingual quality, PHI isolation)
- Data-flow and where sensitive data does and does not go
- Provider strategy (which models, what falls back to what, what never leaves the boundary)

### Deliverable 5: Pilot proposal

A concrete, scoped, time-boxed pilot the client can say yes to.

Required sections:
- The one use case (the smallest valuable, appropriate thing)
- Success metrics (measurable, tied to sector value)
- Scope and explicit non-scope
- Timeline and milestones
- Cost estimate
- Risks and mitigations (sector-specific)
- Exit criteria (what "the pilot succeeded" means, and what stops it)

### Deliverable 6: Executive presentation

A short, board-ready deck that a non-technical executive in this sector can act on.

Required structure (roughly 8-12 slides):
- The opportunity, in this sector's language
- Why now / what changed
- The proposed approach (readiness -> pilot -> scale)
- The architecture, at an executive altitude (one clean diagram)
- Governance and risk (how you keep them safe and compliant)
- The pilot ask (scope, cost, timeline)
- Expected value and how you will measure it
- The roadmap beyond the pilot

Keep it plain-language. No jargon that the sector's leadership would not use.

---

## Step 2: Produce all six, for both sectors

Work sector by sector. For each of the twelve artifacts:
1. Copy the matching USE template into the sector folder.
2. Adapt every section to the sector's real constraints (use your Concepts module for that sector).
3. Have it reviewed against the exit standard (below).

Your final tree should look like:

```
~/industry-portfolio/
  sector-a/
    01-readiness-assessment.md
    02-governance-policy.md
    03-usecase-roadmap.md
    04-architecture.md
    05-pilot-proposal.md
    06-executive-presentation.md
  sector-b/
    (same six)
  PORTFOLIO.md
```

---

## Exit standard for the BUILD

You have adapted your method to two industries with their specific constraints. Concretely: for each of two sectors you have all six deliverables, and each deliverable visibly reflects that sector's constraints (not a generic document with the sector name pasted in). A reviewer reading the finance package and the public-sector package should immediately see two different mindsets - auditability vs. legitimacy - not one template twice.

---

Prof. Happy (SUTA Labs)
