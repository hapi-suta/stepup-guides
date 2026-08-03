# USE: AI Pilot Charter (Template + Worked Example)

**Tier 14 - Strategy & Product. A one-document charter that scopes an AI pilot, defines what success means in numbers, and sets a go/no-go decision up front so a pilot cannot quietly drift into a permanent unaccountable project.**

A pilot exists to answer one question: does this use case deliver the value the business case predicted, at acceptable risk, with real users? The charter is agreed and signed before work starts. If you cannot fill in the success metrics and acceptance criteria, you are not ready to pilot.

---

## Template (blank)

Copy this, replace every [PLACEHOLDER], and get it signed by the sponsor before day one.

---

### Pilot name
[SHORT, MEMORABLE NAME]

### Problem
[1-2 sentences: what business problem this pilot addresses, and the cost of leaving it unsolved.]

### Hypothesis
We believe that [AI CAPABILITY] will [OUTCOME] for [USER GROUP], resulting in [MEASURABLE CHANGE]. We will know we are right if [PRIMARY METRIC] reaches [TARGET].

### Scope

**In scope**
- [ITEM]
- [ITEM]

**Out of scope**
- [ITEM]
- [ITEM]

### Success metrics

Leading metrics move early and predict success. Lagging metrics confirm business impact.

| Type | Metric | Baseline | Target | How measured |
|------|--------|---------:|-------:|--------------|
| Leading | [METRIC] | [X] | [Y] | [METHOD] |
| Leading | [METRIC] | [X] | [Y] | [METHOD] |
| Lagging | [METRIC] | [X] | [Y] | [METHOD] |
| Lagging | [METRIC] | [X] | [Y] | [METHOD] |

### Acceptance criteria
The pilot is accepted only if ALL of these hold at day 90:
- [ ] [CRITERION with a number]
- [ ] [CRITERION with a number]
- [ ] [CRITERION with a number]

### Timeline (90-day)

| Phase | Days | Milestone |
|-------|------|-----------|
| Setup | [0-15] | [MILESTONE] |
| Rollout | [16-45] | [MILESTONE] |
| Steady state | [46-75] | [MILESTONE] |
| Evaluation | [76-90] | Go/no-go decision |

### Roles

| Role | Name | Responsibility |
|------|------|----------------|
| Executive sponsor | [NAME] | Funds, unblocks, owns go/no-go |
| Product / pilot lead | [NAME] | Runs the pilot, reports metrics |
| Technical lead | [NAME] | Builds/integrates, monitors model |
| Business owner | [NAME] | Represents end users, validates value |

### Budget
[AMOUNT] for the 90-day pilot, covering [WHAT].

### Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|-----------|
| [RISK] | [L/M/H] | [L/M/H] | [MITIGATION] |
| [RISK] | [L/M/H] | [L/M/H] | [MITIGATION] |

### Go/no-go decision criteria
At day 90 the sponsor decides:
- **GO (scale):** [CONDITIONS - which metrics/criteria must be met]
- **ITERATE (extend/adjust):** [CONDITIONS]
- **NO-GO (stop):** [CONDITIONS]

---

## Worked example

Filled charter for [CLIENT], a mid-size insurer, piloting the top-ranked use case (claims-document triage).

---

### Pilot name
Claims Triage Assist

### Problem
Claims clerks spend ~12 minutes manually reading and routing each of ~200 documents/day, and misroute ~8% of them, costing [COMPANY] roughly $690,000/year in labor and rework. Manual triage is the bottleneck delaying claim acknowledgement.

### Hypothesis
We believe that an AI triage assistant that pre-classifies document type and extracts key fields will cut clerk handling time and misrouting for the claims intake team, resulting in lower cost per document and faster acknowledgement. We will know we are right if clerk-minutes per document drops from 12 to 6 or less at 90 days.

### Scope

**In scope**
- Auto and property lines of business
- Documents arriving via email and portal upload
- Classification + field extraction (claimant, policy number, loss type, urgency)
- Human-in-the-loop review for low-confidence documents

**Out of scope**
- Health and commercial lines
- Fax-to-PDF ingestion (deferred to phase 2)
- Automated claim decisions or payouts
- Full retirement of the manual routing spreadsheet

### Success metrics

| Type | Metric | Baseline | Target | How measured |
|------|--------|---------:|-------:|--------------|
| Leading | Clerk-minutes per document | 12 | <=6 | Time study on pilot cohort |
| Leading | Model classification accuracy | n/a | >=90% | Weekly QA sample vs human label |
| Leading | Clerk adoption (docs run through tool) | 0% | >=80% | Tool usage logs |
| Lagging | Misrouting error rate | 8% | <=4% | QA audit sample |
| Lagging | Cost per document | $13.80 | <=$8 | Finance (labor + tool cost / volume) |

### Acceptance criteria
Accepted only if ALL hold at day 90:
- [ ] Clerk-minutes per document at 6 or below
- [ ] Classification accuracy at 90% or above on the QA sample
- [ ] Misrouting error rate at 4% or below
- [ ] At least 80% of eligible documents processed through the tool
- [ ] No PII or security incident during the pilot

### Timeline (90-day)

| Phase | Days | Milestone |
|-------|------|-----------|
| Setup | 0-15 | Vendor integrated, historical data loaded, 6 clerks trained |
| Rollout | 16-45 | Live on auto + property; human-in-the-loop on all docs |
| Steady state | 46-75 | Confidence threshold tuned; low-confidence-only human review |
| Evaluation | 76-90 | Metrics compiled; go/no-go decision with sponsor |

### Roles

| Role | Name | Responsibility |
|------|------|----------------|
| Executive sponsor | VP, Claims Operations | Funds, unblocks, owns go/no-go |
| Product / pilot lead | Claims Ops Manager | Runs pilot, reports weekly metrics |
| Technical lead | IT Integration Lead | Vendor integration, model monitoring |
| Business owner | Senior Claims Clerk | Represents clerks, validates real value |

### Budget
$55,000 for the 90-day pilot: vendor pilot license, integration time, and training. (If GO, rolls into the $210k full implementation in the business case.)

### Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|-----------|
| Clerks distrust the tool | Medium | High | Human-in-the-loop early, visible accuracy reporting, clerk champion |
| Accuracy low on messy scans | Medium | Medium | Route low-confidence docs to humans; weekly retraining on misses |
| Volume spike skews metrics | Low | Medium | Normalize metrics per document, not per day |

### Go/no-go decision criteria
At day 90 the sponsor decides:
- **GO (scale):** all 5 acceptance criteria met; proceed to full $210k implementation and expand to remaining lines.
- **ITERATE (extend 30 days):** accuracy or adoption within 10% of target and trending up; extend and re-tune.
- **NO-GO (stop):** clerk-minutes still above 8, or accuracy below 80%, or any security incident; stop and revisit assumptions in the business case.
