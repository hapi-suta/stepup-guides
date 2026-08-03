# Concepts: Business-Case Development

**Tier 14, Module 14.3** - How a consultant turns an AI idea into numbers a decision-maker will fund.

Executives fund business cases, not technology. Once you have found a real opportunity (14.1) and confirmed AI fits (14.2), you must show what it costs, what it returns, and how long until it pays back. This concept defines every building block of an AI business case, gives you the formulas, and ties them together in a worked example. Do this well and you become the consultant leadership trusts with budget decisions.

Two habits keep you honest: state your assumptions next to every number, and show a conservative case alongside the optimistic one. A defensible case with modest numbers beats a fragile one with big numbers. Every dollar figure in this concept is an illustrative placeholder to show the mechanics; substitute the client's real, sourced numbers before presenting anything.

---

## Benefits (money in)

### Baseline cost

**What it is:** The current fully-loaded cost of doing the work today, before AI. This is your reference point - every benefit is measured against it.

**How to estimate:** Count the people-hours spent, multiply by loaded hourly cost (salary plus overhead, often 1.3-1.5x salary), and add tooling, error, and delay costs. Example: 4 staff x 6 hrs/day x 250 days x $45/hr = $270,000/yr.

### Time saved

**What it is:** Labor hours the AI removes or shortens, converted to money.

**How to estimate:** (hours per task before - hours after) x volume x loaded hourly cost. Only count time actually redeployed to other value or removed from headcount plans - "soft" time that just becomes slack is not real savings; flag it as such.

### Revenue impact

**What it is:** New or protected revenue the AI enables - faster response winning more deals, higher conversion, upsell, reduced churn.

**How to estimate:** Change in a revenue driver x its value. Example: cutting quote turnaround lifts win rate by 2 points; 2% x 1,000 deals/yr x $5,000 avg = $100,000/yr. Be conservative; attribution is hard.

### Error reduction

**What it is:** Money saved by making fewer mistakes - rework, refunds, waste, penalties, lost customers.

**How to estimate:** (error rate before - error rate after) x volume x cost per error. Example: dropping a 5% error rate to 1% on 50,000 items at $12 per error saves 0.04 x 50,000 x $12 = $24,000/yr.

### Risk reduction

**What it is:** The expected value of avoided bad events - fraud losses, compliance fines, security incidents, outages.

**How to estimate:** (probability x impact) before minus after. Example: fraud losses expected at $200,000/yr reduced 30% = $60,000/yr avoided. Present as expected value and note the range, since these are probabilistic.

---

## Costs (money out)

### Implementation cost

**What it is:** One-time cost to build and launch - discovery, data prep, model development or vendor setup, integration, testing, training, change management.

**How to estimate:** Sum consultant/engineer time, data work, licenses bought during build, and infrastructure setup. This is capital-like: you pay it once. Add a contingency (15-25%) because AI projects overrun.

### Operating cost

**What it is:** The recurring cost to run the system - inference/API fees, compute and storage, monitoring, model retraining, support, license renewals.

**How to estimate:** For API-based LLMs: expected calls x tokens x price per token, per month, x 12. Add hosting, monitoring tooling, and a fraction of an engineer's time for upkeep. This is the number clients most often forget.

### Adoption rate

**What it is:** The fraction of the potential benefit actually realized, because people do not use the tool fully or trust it slowly. A powerful multiplier that turns paper savings into real savings.

**How to estimate:** Apply a realistic adoption factor to gross benefits, ramping over time. Example: 40% adoption in year 1, 75% in year 2. A brilliant tool at 20% adoption returns almost nothing - treat adoption as a first-class line, not an afterthought.

---

## Decision metrics (tying it together)

### Payback period

**What it is:** How long until cumulative net benefit repays the implementation cost. Shorter is safer.

```
Payback period = Implementation cost / (Annual net benefit)
   where Annual net benefit = (Annual benefits x adoption) - Annual operating cost
```

### Return on investment (ROI)

**What it is:** The percentage return over a chosen horizon. The headline number executives ask for.

```
ROI = (Total net benefit - Total cost) / Total cost x 100%
   over the horizon (e.g. 3 years),
   Total cost = Implementation cost + (Annual operating cost x years)
   Total net benefit = Realized annual benefits summed over the horizon
```

### Total cost of ownership (TCO)

**What it is:** Every cost over the system's life, not just the sticker price. Prevents the "cheap to build, expensive to run" trap.

```
TCO = Implementation cost + (Annual operating cost x N years)
   + retraining + upgrades + decommissioning
```

---

## Worked example

A support team wants an AI assistant for "where is my order?" tickets.

**Baseline:** 3 agents x 5 hrs/day on these tickets x 250 days x $40/hr loaded = **$150,000/yr** baseline cost on this task.

**Benefits (gross, at full adoption):**
- Time saved: AI handles 60% of the volume -> 0.60 x $150,000 = **$90,000/yr**.
- Error reduction: fewer wrong tracking answers, ~**$5,000/yr**.
- Gross annual benefit = **$95,000/yr**.

**Adoption:** 50% year 1, 80% years 2-3.
- Year 1 realized: 0.50 x 95,000 = $47,500
- Years 2 and 3 realized: 0.80 x 95,000 = $76,000 each

**Costs:**
- Implementation (one-time): **$60,000**
- Operating (API + monitoring + upkeep): **$18,000/yr**

**Annual net benefit:**
- Year 1: 47,500 - 18,000 = **$29,500**
- Years 2 and 3: 76,000 - 18,000 = **$58,000** each

**Payback period:** 60,000 / (steady-state 58,000) is about 1.0 year of steady-state, but using ramped cash: year 1 returns 29,500, leaving 30,500 to recover, covered ~6.3 months into year 2. **Payback approximately 1.5 years.**

**3-year TCO:** 60,000 + (18,000 x 3) = **$114,000**.

**3-year ROI:**
```
Total realized net benefit = 29,500 + 58,000 + 58,000 = 145,500
ROI = (145,500) / (60,000 + 54,000) x 100%
    = 145,500 / 114,000 x 100%
    ~ 128%
```
A roughly 128% three-year ROI with 1.5-year payback is a fundable case. Present the conservative (lower adoption) scenario next to it so leadership sees the downside.

---

## Check yourself (Exit gate for this concept)

You are ready to move on when you can:

1. Define all eleven line items (baseline cost through TCO) and say whether each is a benefit, a cost, or a decision metric.
2. Write the ROI, payback-period, and TCO formulas from memory and explain each term.
3. Build a small business case from a client scenario, applying an adoption factor and producing ROI, payback, and TCO with stated assumptions.

## References

- [McKinsey - The state of AI: how organizations are rewiring to capture value](https://www.mckinsey.com/capabilities/quantumblack/our-insights/the-state-of-ai-how-organizations-are-rewiring-to-capture-value) - why tracked KPIs and realized (not paper) value separate AI winners from the rest.
- [Gartner - Take This View to Assess ROI for Generative AI](https://www.gartner.com/en/articles/take-this-view-to-assess-roi-for-generative-ai) - analyst guidance on framing business value and cost for generative AI.
- [Harvard Business Review - Embracing Gen AI at Work (2024)](https://hbr.org/2024/09/embracing-gen-ai-at-work) - grounding benefit estimates in the tasks AI actually changes.
- [AWS - Cloud Financial Management](https://aws.amazon.com/cloud-financial-management/) - reference for total-cost-of-ownership and ongoing operating-cost estimation.
