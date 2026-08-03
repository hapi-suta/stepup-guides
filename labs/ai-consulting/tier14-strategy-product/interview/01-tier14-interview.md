# INTERVIEW: Tier 14 - AI Business Strategy and Product Management

**Tier 14 - Interview preparation**

These are the questions a client, a hiring manager, or an executive sponsor might ask to test whether you can find AI value, kill bad ideas, and defend the numbers. This tier is about judgment and business sense, not model trivia, and the questions probe exactly that.

For each question you get:
- **The question** as it might be asked.
- **A strong answer** you can adapt in your own words.
- **How to answer** - the technique that makes it land.
- **Why they ask this** - the real thing being tested.

Practice out loud. Aim for a clear 60-90 second answer. Lead with judgment, back it with a number.

---

## Q1. How do you find high-value AI opportunities in an organization?

**Strong answer:**
"I do not start with AI, I start with where the organization loses time, money, or accuracy. I walk the actual workflows and look for a handful of patterns: repetitive high-volume work, large document workloads people read by hand, decision bottlenecks where everything waits on one expert, knowledge that is hard to find, and forecasting or anomaly problems. For each candidate I ask three things: is there enough data, is the value big enough to matter, and can the organization actually maintain the solution. Then I score every candidate on a prioritization matrix - business value, feasibility, data readiness, risk, cost, time, employee impact, and leadership sponsorship - so we invest in the two or three that are both high-value and feasible, not the flashiest. The output is a ranked list, not a hunch."

**How to answer:** Lead with "problems, not technology." Name a few concrete opportunity patterns, then the three go/no-go filters (data, value, maintainability), then the prioritization matrix. End on "ranked list, not a hunch" to show discipline.

**Why they ask this:** They want to know you hunt value systematically instead of chasing hype. Anyone can say "let's use AI"; they are paying for the judgment to pick the right two things.

---

## Q2. When would you advise a client NOT to use AI?

**Strong answer:**
"Whenever a simpler tool is the right one. Specifically: when clear deterministic rules already solve it - I will not train a model to reproduce an IF-statement, because rules are cheaper, 100 percent accurate, and auditable. When the data does not exist or is too poor to learn from. When errors are unacceptable and no human can supervise the output. When the organization cannot maintain the system after I leave. When the benefit is too small to justify the cost and risk. And when it conflicts with law or policy. My job includes saying no to AI where it is the wrong tool - that protects the client's money and my credibility. When I say no, I redirect the appetite to where AI genuinely pays off, so they do not feel the idea was just rejected."

**How to answer:** Give the disqualifiers crisply (rules solve it, no data, errors unacceptable + no supervision, cannot maintain, benefit too small, illegal). Emphasize that saying no is part of the value, and always pair it with a redirect.

**Why they ask this:** They are testing whether you will over-sell AI. A consultant who never says no is a salesperson; one who kills bad ideas is a trusted advisor.

---

## Q3. Walk me through an AI business case and ROI.

**Strong answer:**
"I build it bottom-up. First, the baseline: what the current process costs today in time and money. Then the benefits, quantified: time saved converted to dollars, revenue impact, error reduction, and risk reduction. Crucially I model adoption as a ramp to a realistic ceiling, not an instant 100 percent, because that is the assumption that usually breaks a case. Then the costs: implementation - build or integration, data, change management - and ongoing operating cost, which for LLMs is dominated by inference. From those I compute payback - implementation cost divided by monthly net benefit - ROI as net benefit over cost, and three-year total cost of ownership. Finally I add a sensitivity analysis across low, expected, and high adoption so leadership sees the range. A case that shows a believable 120 percent ROI with a 14-month payback and a sensitivity band is worth far more than a fragile 300 percent that assumes everything goes perfectly."

**How to answer:** Go in order - baseline, benefits, adoption ramp, costs, then payback/ROI/TCO, then sensitivity. Name the formulas plainly. Stress realistic adoption and sensitivity as the credibility markers.

**Why they ask this:** They want proof you can defend an investment to a CFO with real numbers and honest assumptions, not a spreadsheet built on wishes.

---

## Q4. Build versus buy - how do you decide?

**Strong answer:**
"I default to the simplest thing that solves the problem and only move up the ladder when it does not. The ladder is roughly: a SaaS tool if one already does the job; a frontier-model API with prompting or retrieval for most custom needs; a cloud-managed service if I want control without running infrastructure; an open-source or fine-tuned model when I have proprietary data or need cost control at scale; and a fully custom or self-hosted build only when data residency, cost at volume, or a genuinely unique need demands it. I stop at the first option that meets the requirements. Building is the most expensive and slowest path and only wins when off-the-shelf genuinely cannot meet the need - usually driven by proprietary data, data-residency rules, or economics at scale. I frame every recommendation around the client's cost, speed, and risk, not around what is technically interesting."

**How to answer:** Present it as a ladder from cheapest/fastest to most custom, and say "stop at the first yes." Name the specific triggers that justify building (proprietary data, residency, scale economics). Tie back to cost/speed/risk.

**Why they ask this:** They are checking business judgment. A good consultant steers clients away from expensive over-engineering and can name exactly when the expensive option is actually warranted.

---

## Q5. A stakeholder is convinced AI will cut their team's costs by 50 percent. How do you handle it?

**Strong answer:**
"I neither agree nor dismiss it - I turn it into a testable business case. I ask what the current process costs today so we have a baseline, then estimate the realistic time or error savings, model adoption honestly, and subtract implementation and operating cost. Often the true number is real but smaller - say 20 to 30 percent - and it arrives over a ramp, not overnight. I would rather present a defensible 25 percent that materializes than endorse a 50 percent that collapses and burns my credibility. And I would validate it with a small pilot before anyone commits headcount decisions to it."

**How to answer:** Reframe an assertion into a measurable case. Show you protect them from their own optimism, and insist on a pilot before big decisions. Give a believable smaller number.

**Why they ask this:** They want to see if you will rubber-stamp an executive's excitement or bring discipline. The willingness to deflate a number gently is the tell.

---

## Q6. What makes an AI product different to manage than a normal software product?

**Strong answer:**
"Three things. First, uncertainty: a normal feature either works or does not, but an AI feature is probabilistic, so I plan for it being right most of the time, not all the time, and design a human-in-the-loop where errors matter. Second, evaluation: I cannot rely on pass/fail tests alone, I need an evaluation harness that scores output quality, safety, and relevance, and I treat that as core product infrastructure. Third, drift: the model's performance changes as the world and the data change, so monitoring and re-evaluation are ongoing, not one-time. So an AI roadmap includes evaluation, guardrails, and monitoring as first-class items, not afterthoughts, and success metrics measure behaviour and outcome, not just shipped features."

**How to answer:** Name the three AI-specific realities - uncertainty, evaluation, drift - and what each forces you to do differently (human-in-the-loop, eval harness, ongoing monitoring). Keep it concrete.

**Why they ask this:** They want to know you will not manage an AI product like a deterministic one and be surprised when it behaves probabilistically.

---

## Q7. How do you write a good pilot so we actually learn something?

**Strong answer:**
"A pilot is an experiment, so it starts with a written hypothesis: we believe this intervention will improve this outcome by this amount within this timeframe. Then a baseline measured before we start, or reconstructed honestly if we missed it. Then metrics - leading signals like usage quality and lagging outcomes like time saved or error rate - with real targets. Then acceptance criteria and a go/no-go rule agreed with the sponsor before results come in, so the decision is evidence-based, not political. I scope it tight - one use case, a defined group, 90 days - and I measure the outcome the client cares about, never vanity metrics like logins. The point of a pilot is a clean decision to scale, iterate, or stop."

**How to answer:** Hypothesis, baseline, leading + lagging metrics with targets, go/no-go rule agreed up front, tight scope. End on "a clean decision to scale, iterate, or stop."

**Why they ask this:** Pilots that measure nothing waste money and drift forever. They want proof you design pilots that produce decisions.

---

## Q8. How do you present a business case to a skeptical CFO?

**Strong answer:**
"I lead with the number that matters to them - payback and ROI - then show my work briefly so they trust it. I am explicit about the assumptions, especially adoption, and I show a sensitivity analysis so they see the range rather than a single fragile figure. I state the costs fully, including operating cost, so there is no hidden surprise later. I name the risks and how the pilot de-risks the decision before any big commitment. And I make an honest recommendation, including being willing to say the case does not clear their hurdle rate. A CFO trusts the consultant who shows the downside case, not the one who only shows the upside."

**How to answer:** Lead with payback/ROI, expose assumptions, show sensitivity, state full costs, name risks, and be willing to recommend "no." Honesty about the downside is the credibility move.

**Why they ask this:** The CFO controls the money and has seen optimistic cases fail. They are testing whether your numbers are honest and whether you will tell them when a project is not worth it.

---

## Practice tips

- Always lead with judgment ("problems, not technology"; "the simplest tool that works") and back it with a number.
- Have the three core formulas ready in plain words: ROI is net benefit over cost; payback is implementation cost over monthly net benefit; TCO is build plus operating cost over the horizon.
- Adoption is the assumption that breaks cases - mention modelling it as a realistic ramp whenever you talk numbers.
- Be willing to say "no" and "stop" in your answers. The discipline to kill a bad idea is what they are buying.
- Keep answers to 60-90 seconds. Answer the actual question, then stop.

Prof. Happy (SUTA Labs)
