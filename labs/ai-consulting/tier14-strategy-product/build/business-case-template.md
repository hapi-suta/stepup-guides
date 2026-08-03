# BUILD: AI Business Case Template (Blank)

**Tier 14 - Strategy & Product. Copy this file, replace every [PLACEHOLDER], and fill every table. Delete guidance in parentheses when done. Keep the recommendation on page one.**

---

### 1. Recommendation (one page - write this last)

- **The ask:** Approve $[AMOUNT] to [ACTION] for [CLIENT].
- **Headline numbers:** Baseline cost $[BASELINE]/yr | ROI [X]% over [N] years | Payback [N] months | [N]-yr TCO $[TCO] | Net benefit $[NET].
- **Recommended path:** [BUILD / BUY / HYBRID] because [ONE-SENTENCE REASON].
- **Top risks:** [RISK 1], [RISK 2], [RISK 3] (mitigations in Section 9).
- **To proceed we need:** [BUDGET], [SPONSOR], [PILOT WINDOW].

---

### 2. Use case summary

Today, [ROLE] at [COMPANY] spends [TIME] doing [TASK] [FREQUENCY]. We propose [AI CAPABILITY] to [OUTCOME], measured by [PRIMARY METRIC].

- **Process owner:** [NAME / TITLE]
- **Current tools:** [TOOLS]
- **Trigger event:** [WHAT STARTS THE WORKFLOW]
- **Primary metric:** [METRIC]

---

### 3. Baseline (current cost of doing nothing)

| Input | Value | Source |
|-------|------:|--------|
| Volume (units per day) | [VOL] | [SOURCE] |
| Working days per year | [DAYS] | [SOURCE] |
| Minutes per unit | [MIN] | [SOURCE] |
| Fully loaded hourly rate | $[RATE] | [SOURCE] |
| Current error rate | [ERR]% | [SOURCE] |
| Cost per error | $[ERRCOST] | [SOURCE] |

```
Annual volume        = [VOL] x [DAYS] = [ANNUAL_VOL]
Annual labor hours   = [ANNUAL_VOL] x [MIN] / 60 = [HOURS]
Annual labor cost    = [HOURS] x $[RATE] = $[LABOR]
Annual error cost    = [ANNUAL_VOL] x [ERR]% x $[ERRCOST] = $[ERRTOTAL]
Baseline annual cost = $[LABOR] + $[ERRTOTAL] = $[BASELINE]
```

---

### 4. Benefits (gross annual, before adoption ramp)

**4a. Time saved**

```
Reduction %          = [RED]%
Time saved per unit  = [MIN] x [RED]% = [SAVED_MIN] min
Annual hours saved   = [ANNUAL_VOL] x [SAVED_MIN] / 60 = [SAVED_HRS]
Time saved value     = [SAVED_HRS] x $[RATE] = $[TIME_VALUE]
```
Hard or soft saving? [HARD (headcount) / SOFT (capacity)]

**4b. Revenue impact**

```
Incremental units = [INC_UNITS]
Margin per unit   = $[MARGIN]
Revenue benefit   = [INC_UNITS] x $[MARGIN] = $[REVENUE]
```

**4c. Error / risk reduction**

```
New error rate        = [NEW_ERR]%
Error reduction value = [ANNUAL_VOL] x ([ERR]% - [NEW_ERR]%) x $[ERRCOST] = $[ERR_VALUE]
```

**Total gross annual benefit = $[TIME_VALUE] + $[REVENUE] + $[ERR_VALUE] = $[GROSS_BENEFIT]**

---

### 5. Costs

**5a. Implementation (one-time)**

| Line item | Cost |
|-----------|-----:|
| [ITEM] | $[X] |
| [ITEM] | $[X] |
| [ITEM] | $[X] |
| Subtotal | $[SUBTOTAL] |
| Contingency ([C]%) | $[CONT] |
| **Implementation total** | **$[IMPL]** |

**5b. Operating (recurring, annual)**

| Line item | Annual cost |
|-----------|------------:|
| [ITEM] | $[X] |
| [ITEM] | $[X] |
| **Annual operating total** | **$[OPEX]** |

---

### 6. Adoption assumptions

| Period | Adoption % | Realized benefit (gross x adoption) |
|--------|-----------:|------------------------------------:|
| Year 1 | [A1]% | $[R1] |
| Year 2 | [A2]% | $[R2] |
| Year 3 | [A3]% | $[R3] |

Ramp rationale: [WHY THIS RAMP]

---

### 7. ROI / payback / TCO

```
TCO = [IMPL] + ([OPEX] x [N]) = $[TCO]
```

| Year | Realized benefit | Operating cost | Net benefit | Cumulative (incl. implementation) |
|------|-----------------:|---------------:|------------:|----------------------------------:|
| 0 | - | - | - | -$[IMPL] |
| 1 | $[R1] | $[OPEX] | $[NB1] | $[CUM1] |
| 2 | $[R2] | $[OPEX] | $[NB2] | $[CUM2] |
| 3 | $[R3] | $[OPEX] | $[NB3] | $[CUM3] |

```
Net benefit over horizon = ([R1]+[R2]+[R3]) - [TCO] = $[NET]
ROI = ($[NET] / $[TCO]) x 100 = [ROI]% over [N] years
Payback = [READ FROM CUMULATIVE TABLE = month [M]]
```

---

### 8. Build vs buy

| Factor | Buy (vendor) | Build (in-house) |
|--------|-------------|------------------|
| Implementation cost | $[X] | $[X] |
| [N]-yr operating cost | $[X] | $[X] |
| Time to value | [WEEKS/MONTHS] | [WEEKS/MONTHS] |
| Customization / control | [LOW/MED/HIGH] | [LOW/MED/HIGH] |
| Vendor lock-in risk | [LOW/MED/HIGH] | [LOW/MED/HIGH] |
| Internal capability needed | [LOW/MED/HIGH] | [LOW/MED/HIGH] |
| [N]-yr TCO | $[X] | $[X] |

**Recommendation: [BUILD / BUY / HYBRID]** - [REASONING].

---

### 9. Risks and assumptions

**Assumptions**

| Assumption | Value | Source (measured / estimate / benchmark) |
|------------|------:|------------------------------------------|
| [ASSUMPTION] | [VALUE] | [SOURCE] |
| [ASSUMPTION] | [VALUE] | [SOURCE] |

**Risks**

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|-----------|
| [RISK] | [L/M/H] | [L/M/H] | [MITIGATION] |
| [RISK] | [L/M/H] | [L/M/H] | [MITIGATION] |

**Sensitivity check:** If [BIGGEST BENEFIT] is 30% lower, ROI becomes [X]% over [N] years. Case is [ROBUST / FRAGILE].
