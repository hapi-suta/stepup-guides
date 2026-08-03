# BUILD: AI-Readiness Assessment (End-to-End Engagement)

**Tier 15 - Consulting Mastery. Major Project 15: run a complete, simulated AI-readiness assessment for a fictional company and produce the full consultant deliverable package.**

This is a documents-only project. You are the consultant. You will scope an engagement, run discovery, analyze findings, and hand a client an executive-ready package. No code, no servers - just the artifacts a real AI-consulting engagement produces.

By the end you will have produced eleven deliverables:

1. Interview guide
2. Readiness questionnaire
3. Current-state report
4. Five use cases
5. Prioritization model
6. Risk register
7. 90-day pilot charter
8. Three-year roadmap
9. Budget estimate
10. Executive presentation
11. Statement of work (SOW)

Work from these three companion files in this folder:

- `readiness-assessment-package-template.md` - the blank template you fill in.
- `readiness-assessment-worked-example.md` - a fully worked example (a regional hospital network) to model tone, depth, and numbers.
- (USE phase) `../use/01-three-role-decks.md` and `../use/02-statement-of-work-template.md` - how to reframe the same assessment for CEO / CISO / Engineering and how to write the SOW.

---

## Step 0 - Pick your fictional client

Invent a realistic company and write a one-paragraph brief. Keep it specific: industry, headcount, revenue band, geography, and one strategic pressure ("margins compressing", "regulator tightening", "competitor shipped an AI feature").

Use `[CLIENT]` as a shorthand throughout (e.g. `[CLIENT]` = "a regional hospital network, 4,000 staff, 6 hospitals, $1.2B revenue"). The worked example uses exactly this client - study it, then choose a different industry so the work is your own.

> Deliverable framing: everything you produce is addressed to `[CLIENT]` and authored by `[COMPANY]` (your consultancy). Keep those placeholders in the template; resolve them in your worked package.

---

## Step 1 - Scope the engagement

Before any interviews, write the engagement scope. This becomes the top of the current-state report and the backbone of the SOW.

Define:

- **Objective** - one sentence. "Assess `[CLIENT]`'s readiness to adopt AI and produce a prioritized, funded 3-year plan."
- **In-scope** - which business units, which data domains, which time horizon.
- **Out-of-scope** - be explicit. This protects you later. (e.g. "No model building. No production deployment. No vendor contract negotiation.")
- **Duration and effort** - e.g. 6 weeks, ~120 consultant hours.
- **Stakeholders** - who you will interview (role, not name) and who signs off.
- **Deliverables** - the eleven above.

Fill the "Engagement scope" block in the template.

---

## Step 2 - Run discovery interviews

You will simulate interviews with 6-10 stakeholders. You do not need live people - you role-play both sides and record realistic answers.

Use the two discovery instruments in the template:

### 2a. Interview guide

Open the **Interview guide** section of `readiness-assessment-package-template.md`. It is a structured question list grouped by stakeholder type (CEO/strategy, CIO/CTO, data lead, security/compliance, HR/talent, business-unit owner). Tailor 3-5 questions per stakeholder. Questions are open-ended ("Where do you lose the most time to manual work?"), not yes/no.

### 2b. Readiness questionnaire

Open the **Readiness questionnaire** section. It scores the client across 12 dimensions:

Strategy, Leadership, Data, Technology, Security, Governance, Talent, Culture, Process maturity, Budget, Compliance, Vendor readiness.

Each dimension has 3-5 scored items (0-5 scale). During "interviews" you assign scores and jot the evidence that justifies each score. The dimension average is the dimension score; the mean of all 12 is the overall readiness score.

> Consultant tip: never give a score without one line of evidence behind it. "Data = 2.4: no data catalog, 60% of records in spreadsheets, one analyst owns all reporting." Evidence is what makes the report credible.

Record all interview notes and scores. See the worked example's completed questionnaire for the target level of detail.

---

## Step 3 - Write the current-state report

Synthesize discovery into a narrative the client recognizes as true. Use the **Current-state report** skeleton in the template:

- Executive summary (half a page, the whole story)
- Scope recap (from Step 1)
- Readiness scorecard (the 12-dimension table + overall score + a one-line verdict per dimension)
- Strengths (3-5)
- Gaps and constraints (3-5, tied to low-scoring dimensions)
- Key findings from interviews (the quotes and patterns)
- Implications ("what this means for adopting AI")

Keep it honest. If Data scored 2.4, say the data foundation is not ready and name what has to change first. Model the tone on the worked example's current-state narrative.

---

## Step 4 - Identify five use cases

From the interviews, harvest concrete AI use cases. Aim for a spread: at least one quick win, one high-value/high-effort bet, and nothing science-fiction.

For each use case, capture in the **Use-case inventory** table:

- Name and one-line description
- Business problem it solves
- Expected value (name a metric: hours saved, revenue, error rate, cycle time)
- Data required + whether it exists today
- AI approach (classification, retrieval/RAG, forecasting, document extraction, assistant/copilot - stay at capability level, no implementation)
- Rough effort (T-shirt: S / M / L)

Five is the target. The worked example lists five concrete ones for the hospital network - use them as a calibration, not a copy.

---

## Step 5 - Score them with the prioritization model

Turn the five use cases into a ranked list using a transparent scoring model so the client sees why the top pick won.

Use the **Prioritization model** table in the template. Score each use case 1-5 on:

- **Value** (business impact if it works)
- **Feasibility** (data + tech readiness, inverse of effort)
- **Time-to-value** (how fast it pays off)
- **Risk** (score inverted: low risk = high score)
- **Strategic fit** (aligns with the pressure from Step 0)

Apply weights (they must sum to 100%). A reasonable default: Value 30, Feasibility 25, Time-to-value 20, Strategic fit 15, Risk 10. Compute the weighted score, rank, and pick the #1 as your pilot candidate.

> Show your weights. A prioritization model the client cannot see inside is just an opinion.

---

## Step 6 - Build the risk register

Every AI engagement carries risk. Fill the **Risk register** table with 6-8 real risks spanning categories: data quality, security/privacy (include an LLM-specific risk - prompt injection or data leakage), compliance/regulatory, change management/adoption, vendor lock-in, cost overrun, model quality/hallucination, talent gap.

For each risk record: description, category, likelihood (Low/Med/High), impact (Low/Med/High), mitigation, and owner (role). The worked example has a filled 7-risk register - match that specificity.

---

## Step 7 - Design a 90-day pilot

Take the #1 use case and write a pilot charter using the **90-day pilot charter** section:

- Objective and the single success metric (with a target number)
- Scope (what is in, what is deliberately excluded)
- Approach in three 30-day phases (Discovery/setup -> Build/integrate -> Measure/decide)
- Team and roles
- Data needed and how it is accessed
- Success criteria (go/no-go gate)
- Pilot budget
- Risks pulled from the register that apply to the pilot

Keep it to one page of substance. The pilot must be small enough to finish in 90 days and real enough to prove the value metric.

---

## Step 8 - Draft the three-year roadmap and budget

### 8a. Roadmap

Fill the **Three-year roadmap** table. Organize by horizon:

- Year 1: foundation (data, governance, the pilot, first production use case)
- Year 2: scale (2-3 more use cases, platform, upskilling)
- Year 3: differentiate (advanced use cases, org-wide enablement, measurement)

Each row: horizon, initiative, expected outcome, dependency. Tie initiatives back to the low-scoring dimensions so the plan visibly fixes the gaps.

### 8b. Budget

Fill the **Budget estimate** table. Line items across three years: platform/tooling, cloud/infra, data engineering, model/API spend, security & compliance, talent (hires + upskilling), consulting/services, contingency (10-15%). Sub-total per year and a grand total. Numbers must add up and be defensible against the roadmap - if Year 2 adds three use cases, Year 2 spend should rise accordingly. See the worked example for a budget that ties out.

---

## Step 9 - Prepare the executive presentation

Distill the whole package into a decision-focused deck outline in the **Executive-presentation outline** section: 10-14 slides. Structure:

- Title + engagement recap
- Bottom line up front (the recommendation, on slide 2)
- Readiness scorecard
- Top findings
- Use-case shortlist + the ranked pick
- The 90-day pilot
- Three-year roadmap
- Budget + expected return
- Risks + mitigations
- The ask (decision + funding)
- Next steps

This is the artifact the client remembers. In the USE phase you will render this same content three ways (CEO / CISO / Engineering) in `../use/01-three-role-decks.md`.

---

## Step 10 - Draft the Statement of Work

Turn the recommendation into a sellable engagement. Fill the **SOW skeleton** in the template (a fuller reusable version lives in `../use/02-statement-of-work-template.md`):

- Parties, background/objectives
- Scope (in and explicitly out)
- Deliverables (map to milestones)
- Milestones + timeline
- Fees and payment schedule (pick a pricing model - fixed-fee by phase is common for pilots)
- Acceptance criteria per deliverable
- Assumptions, change-request process, IP, confidentiality, data terms, liability cap, term & termination, signatures

The SOW is what actually gets signed. Acceptance criteria must be objective ("client sign-off on the readiness scorecard within 5 business days of delivery"), not vibes.

---

## What good looks like

A reviewer accepts the package when all of the following are true:

- [ ] **Engagement scope** written, with an explicit out-of-scope list.
- [ ] **Interview guide** completed - stakeholder-grouped, open-ended questions, 3-5 per role.
- [ ] **Readiness questionnaire** fully scored across all 12 dimensions, every score backed by one line of evidence, overall readiness score computed.
- [ ] **Current-state report** reads as a coherent narrative with scorecard, strengths, gaps, findings, and implications - honest, not a sales pitch.
- [ ] **Five use cases** captured with value metric, data availability, approach, and effort - spread across quick-win to strategic bet.
- [ ] **Prioritization model** shows visible weights (summing to 100%), weighted scores, a ranking, and a clearly chosen #1.
- [ ] **Risk register** has 6-8 risks including at least one LLM-specific security risk, each with likelihood, impact, mitigation, and a named owner role.
- [ ] **90-day pilot charter** targets the #1 use case, has a single measurable success metric with a target, three 30-day phases, and a go/no-go gate.
- [ ] **Three-year roadmap** is horizon-based and visibly closes the gaps found in the scorecard.
- [ ] **Budget** ties out - line items sum correctly, totals match the roadmap, contingency included.
- [ ] **Executive presentation** outline leads with the recommendation (BLUF on slide 2) and ends with a clear ask.
- [ ] **SOW** is signable - scope, milestones, pricing model, and objective acceptance criteria per deliverable.
- [ ] The whole package is **internally consistent**: the low scores drive the gaps, the gaps drive the roadmap, the roadmap drives the budget, the #1 use case drives the pilot, and the recommendation in the deck matches the SOW.
