# Concepts: AI Product Management

**Tier 14, Module 14.4** - The product-management toolkit adapted for AI, so a consultant can steer an AI initiative from idea to adopted product.

Finding an opportunity and proving the business case is not enough; someone has to shape and ship the product. AI product management borrows the classic PM toolkit but bends every tool around four realities that ordinary software does not have: **uncertainty** (outputs are probabilistic, not exact), **evaluation** (you measure quality statistically, not with pass/fail tests), **model drift** (the world changes and the model quietly gets worse), and **human-in-the-loop** (people must often review or override the AI). As a consultant you either fill this role or coach the client's PM to. This concept defines each tool and calls out how it differs for AI.

---

### User research

**What it is:** Talking to and observing the people who will use the product to learn their real tasks, pain, and context - before building.

**AI difference:** Also probe users' trust, mental models, and tolerance for wrong answers. People forgive a slow tool but abandon one that confidently lies. Learn where a mistake is annoying versus catastrophic.

### Problem statements

**What it is:** A crisp sentence naming who has what problem in what context and why it matters. Keeps the team honest about the "why."

**AI difference:** State the problem in outcome terms, not "add AI." Good: "Agents take 8 minutes to find order status; we need under 1 minute." Never let "use a large language model" be the problem statement.

### Personas

**What it is:** Short profiles of representative users capturing goals, skills, and constraints, so the team designs for real humans.

**AI difference:** Add each persona's AI literacy and trust level, and whether they are the end user or the human reviewer. The reviewer persona is often overlooked and is critical for human-in-the-loop designs.

### User journeys

**What it is:** The end-to-end path a user takes to accomplish a goal, step by step, including feelings and friction.

**AI difference:** Explicitly map what happens when the AI is uncertain or wrong - the fallback path, the "I don't know" response, the escalation to a human. The unhappy path is a first-class part of an AI journey, not an edge case.

### Requirements

**What it is:** The specific capabilities and constraints the product must satisfy - functional and non-functional.

**AI difference:** Include quality thresholds (target accuracy/precision/recall), latency budgets, cost per call, fallback behavior, and data/privacy constraints. "Correct output" becomes "at least X% correct with a defined behavior for the rest."

### Acceptance criteria

**What it is:** The testable conditions that say a feature is done and correct.

**AI difference:** Replace pass/fail with statistical bars on an evaluation set: "achieves >= 90% precision and >= 85% recall on the held-out test set, p95 latency < 2s, and always shows a source citation." You accept a distribution of behavior, not a single deterministic result. The specific numbers here are illustrative; set real thresholds against the client's tolerance for error. Measuring quality this way is the "measure" discipline the NIST AI RMF calls for. (see: https://www.nist.gov/itl/ai-risk-management-framework)

### Backlog

**What it is:** The ordered list of work to do next - features, fixes, improvements.

**AI difference:** Includes data work (collection, labeling, cleaning), evaluation work (building and expanding test sets), and model improvements - not just UI and features. Prompt/model iteration and eval-set growth are recurring backlog items, not one-time tasks.

### Roadmap

**What it is:** The time-phased plan of what the product delivers and when, tied to goals.

**AI difference:** Plan for a data-and-eval foundation phase, a pilot, then scale - and build in ongoing model maintenance forever. AI roadmaps have no "done"; they have a steady-state monitoring and retraining lane.

### Pilot design

**What it is:** A small, bounded first deployment to a limited audience to learn whether the product works in the real world before scaling.

**AI difference:** The pilot is also how you gather real usage data and validate quality outside the lab, where inputs are messier than your test set. Define success metrics and a stop rule up front. Prefer a shadow or suggestion-only mode first so real errors do not reach customers.

### Product metrics

**What it is:** The numbers that tell you if the product is succeeding - adoption, engagement, task completion, satisfaction, business outcome.

**AI difference:** Track two layers together: **model metrics** (accuracy, precision, recall, hallucination rate, latency, cost) and **product metrics** (adoption, deflection rate, time saved, user trust, override rate). A model can score well while the product fails on adoption, and vice versa. Watch the override/correction rate as an early quality signal.

### Feedback loops

**What it is:** Mechanisms to capture how the product performs in the wild and feed that back into improvement.

**AI difference:** User corrections, thumbs up/down, and reviewer overrides become labeled training and evaluation data - the flywheel that improves the model over time. Design capture in from day one; without it you cannot detect drift or retrain effectively.

### Change management

**What it is:** Helping the organization adopt the new way of working - communication, training, incentives, addressing fear.

**AI difference:** Directly address job-loss fear and trust. Position AI as augmenting people, train reviewers on when to trust versus override, and set expectations that the AI is helpful-but-fallible. Adoption (see 14.3) lives or dies here; the best model fails if people refuse to use it.

---

## How AI PM differs at a glance

| Reality | What it forces the PM to do |
|---|---|
| Uncertainty | Design fallback/unhappy paths; set quality thresholds not pass/fail |
| Evaluation | Build eval sets; accept statistical acceptance criteria |
| Model drift | Plan permanent monitoring + retraining; no "done" |
| Human-in-the-loop | Design the reviewer role, override paths, and trust |

---

## Check yourself (Exit gate for this concept)

You are ready to move on when you can:

1. Define all twelve PM tools and explain the purpose of each in one sentence.
2. For any three tools, explain concretely how they change for an AI product versus ordinary software.
3. Write statistical acceptance criteria for an AI feature and list both the model metrics and product metrics you would track for it.

## References

- [Google - People + AI Guidebook](https://pair.withgoogle.com/guidebook/) - human-centered patterns for AI products: mental models, errors, feedback, and trust.
- [Silicon Valley Product Group (Marty Cagan) - articles](https://www.svpg.com/articles/) - the classic product-management toolkit this concept adapts for AI.
- [Harvard Business Review - Embracing Gen AI at Work (2024)](https://hbr.org/2024/09/embracing-gen-ai-at-work) - how AI products change the shape of work and adoption.
- [NIST AI Risk Management Framework (AI RMF 1.0) - Measure and Manage functions](https://www.nist.gov/itl/ai-risk-management-framework) - statistical evaluation and ongoing monitoring as core product duties, not extras.
