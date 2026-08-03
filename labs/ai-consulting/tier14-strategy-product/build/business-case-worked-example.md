# BUILD: AI Business Case - Worked Example

**Tier 14 - Strategy & Product. A fully filled business case for [CLIENT] = a mid-size insurer automating claims-document triage. Numbers are internally consistent and computable. Use it as a reference for structure and math.**

---

### 1. Recommendation (one page)

- **The ask:** Approve $210,000 to deploy a vendor AI claims-triage assistant for [CLIENT].
- **Headline numbers:** Baseline cost $690,000/yr | ROI 165% over 3 years | Payback ~14 months | 3-yr TCO $480,000 | Net benefit $792,037.
- **Recommended path:** BUY (vendor) because triage is a non-differentiating, solved capability and a vendor reaches value in 8-10 weeks at a lower 3-year TCO than building.
- **Top risks:** slow user adoption, model accuracy on edge-case documents, vendor lock-in (mitigations in Section 9).
- **To proceed we need:** $210k capital approval, the Claims Operations VP as sponsor, and a 90-day pilot window on the auto and property lines.

---

### 2. Use case summary

Today, claims clerks at [COMPANY] spend ~12 minutes manually reading and routing each incoming claims document, ~200 documents per day. We propose an AI triage assistant that pre-classifies document type and extracts key fields (claimant, policy number, loss type, urgency), to cut clerk handling time and misrouting, measured by clerk-minutes per document.

- **Process owner:** VP, Claims Operations
- **Current tools:** shared email inbox, document management system, manual routing spreadsheet
- **Trigger event:** a claims document arrives (email, fax-to-PDF, or portal upload)
- **Primary metric:** clerk-minutes per document

---

### 3. Baseline (current cost of doing nothing)

| Input | Value | Source |
|-------|------:|--------|
| Volume (units per day) | 200 | ops dashboard, measured |
| Working days per year | 250 | HR calendar |
| Minutes per unit | 12 | time study, process owner confirmed |
| Fully loaded hourly rate | $45 | finance (salary + benefits + overhead) |
| Current error rate | 8% | QA audit sample |
| Cost per error | $60 | rework time-study estimate |

```
Annual volume        = 200 x 250 = 50,000 documents
Annual labor hours   = 50,000 x 12 / 60 = 10,000 hours
Annual labor cost    = 10,000 x $45 = $450,000
Annual error cost    = 50,000 x 8% x $60 = $240,000
Baseline annual cost = $450,000 + $240,000 = $690,000
```

---

### 4. Benefits (gross annual, before adoption ramp)

**4a. Time saved**

```
Reduction %          = 67% (12 min -> 4 min)
Time saved per unit  = 12 x 67% = 8 min
Annual hours saved   = 50,000 x 8 / 60 = 6,667 hours
Time saved value     = 6,667 x $45 = $300,015
```
Hard or soft saving? SOFT initially (freed clerk capacity redeployed to complex claims); converts to hard as attrition is not backfilled.

**4b. Revenue impact**

```
Incremental units = faster triage lets the same team absorb a 15% claims-volume increase without new hires
Margin per unit   = $[implied] -> throughput-driven benefit valued at $80,000/yr
Revenue benefit   = $80,000
```

**4c. Error / risk reduction**

```
New error rate        = 3%
Error reduction value = 50,000 x (8% - 3%) x $60 = 50,000 x 0.05 x $60 = $150,000
```

**Total gross annual benefit = $300,015 + $80,000 + $150,000 = $530,015**

---

### 5. Costs

**5a. Implementation (one-time)**

| Line item | Cost |
|-----------|-----:|
| Vendor integration engineering | $120,000 |
| Data preparation (historical docs, labeling) | $40,000 |
| Change management + training | $25,000 |
| Subtotal | $185,000 |
| Contingency (15%) | $27,750 |
| **Implementation total (rounded)** | **$210,000** |

**5b. Operating (recurring, annual)**

| Line item | Annual cost |
|-----------|------------:|
| Vendor platform subscription + usage | $60,000 |
| Monitoring, maintenance, periodic retraining | $30,000 |
| **Annual operating total** | **$90,000** |

---

### 6. Adoption assumptions

| Period | Adoption % | Realized benefit (gross x adoption) |
|--------|-----------:|------------------------------------:|
| Year 1 | 50% | $265,008 |
| Year 2 | 90% | $477,014 |
| Year 3 | 100% | $530,015 |

Ramp rationale: year 1 covers rollout, clerk trust-building, and human-in-the-loop review while accuracy is validated on live traffic; near-full capture by year 2 once confidence thresholds and exception handling are tuned.

---

### 7. ROI / payback / TCO

```
TCO = 210,000 + (90,000 x 3) = 210,000 + 270,000 = $480,000
```

| Year | Realized benefit | Operating cost | Net benefit | Cumulative (incl. implementation) |
|------|-----------------:|---------------:|------------:|----------------------------------:|
| 0 | - | - | - | -$210,000 |
| 1 | $265,008 | $90,000 | $175,008 | -$34,992 |
| 2 | $477,014 | $90,000 | $387,014 | $352,022 |
| 3 | $530,015 | $90,000 | $440,015 | $792,037 |

```
Net benefit over horizon = (265,008 + 477,014 + 530,015) - 480,000
                         = 1,272,037 - 480,000 = $792,037
ROI = (792,037 / 480,000) x 100 = 165% over 3 years
Payback: cumulative is -$34,992 at end of year 1 and +$352,022 at end of year 2.
Breakeven falls ~2 months into year 2. Payback ~ 14 months.
```

Payback detail: at end of year 1 the case is $34,992 short of breakeven. Year 2 net benefit is $387,014, or ~$32,251/month. $34,992 / $32,251 = ~1.1 months into year 2, so total payback = 12 + ~2 = ~14 months.

---

### 8. Build vs buy

| Factor | Buy (vendor) | Build (in-house) |
|--------|-------------|------------------|
| Implementation cost | $210,000 | $260,000 |
| 3-yr operating cost | $270,000 ($90k/yr) | $360,000 ($120k/yr ML + MLOps staff) |
| Time to value | 8-10 weeks | 6-9 months |
| Customization / control | Medium | High |
| Vendor lock-in risk | High | Low |
| Internal capability needed | Low | High (ML + MLOps team [COMPANY] lacks) |
| **3-yr TCO** | **$480,000** | **$620,000** |

**Recommendation: BUY (vendor).** Claims triage is a common, non-differentiating capability where a vendor delivers value in 8-10 weeks at a lower 3-year TCO ($480k vs $620k), and avoids standing up an ML/MLOps team [COMPANY] does not have. Negotiate a data-export clause to blunt lock-in. Revisit build only if usage-based fees at scale exceed a fixed-cost internal system.

---

### 9. Risks and assumptions

**Assumptions**

| Assumption | Value | Source |
|------------|------:|--------|
| Volume | 200 docs/day | measured (ops dashboard) |
| Minutes per unit | 12 | measured (time study) |
| Time reduction | 67% | vendor benchmark + pilot target |
| Error rate improvement | 8% -> 3% | vendor benchmark, to be confirmed in pilot |
| Adoption ramp | 50/90/100% | estimate |
| Fully loaded rate | $45/hr | finance |

**Risks**

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|-----------|
| Slow user adoption | Medium | High | Phased rollout, clerk training, keep humans in the loop early |
| Model accuracy on edge-case docs | Medium | Medium | Route low-confidence docs to human review; monitor accuracy weekly |
| Vendor lock-in | High | Medium | Data-export + model-portability clauses in contract |
| Operating cost creep at scale | Low | Medium | Cap usage tier; annual build-vs-buy re-review |

**Sensitivity check:** If time-saved value drops 30% ($300,015 -> $210,011 gross), total gross benefit falls to ~$440,011/yr. Three-year realized benefit (50/90/100% ramp) = $220,006 + $396,010 + $440,011 = $1,056,027. Net over TCO = $1,056,027 - $480,000 = $576,027. ROI = 120% over 3 years. Case remains ROBUST.
