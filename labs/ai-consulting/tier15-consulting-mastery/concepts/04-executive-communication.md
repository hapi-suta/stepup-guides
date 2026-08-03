# Concepts: Executive Communication

**Tier 15, Module 15.4** - Translating AI work into language that lets busy decision-makers act with confidence.

The best technical recommendation dies in the room if the people paying for it cannot understand what they are buying, what it costs them, and what could go wrong. As a consultant, your value is not just knowing AI. It is making AI legible to a CEO who has ninety seconds, a CISO who assumes the worst, and a regulator who reads every word literally. This module is about saying true things clearly, without hype, and about saying the same true things differently to different audiences without ever contradicting yourself. If you learn one habit here, make it this: lead with the decision the listener has to make, not with the technology you find interesting.

---

## Part A - Explaining the Hard Things Without Hype

Hype is not enthusiasm. Hype is any claim you cannot defend when a skeptical person pushes back. The test for every sentence you write for an executive: "If [CLIENT]'s sharpest board member challenged this, could I hold the line with evidence?" If not, soften it or cut it.

A reusable framing template you can drop into any of the sections below:

```
CLAIM:        What is true (one sentence, no adjectives you can't defend)
EVIDENCE:     Why we believe it (data, benchmark, pilot result, or "we don't know yet")
BOUNDARY:     Where it stops being true (conditions, scope, assumptions)
SO WHAT:      What this means for the decision in front of you
```

### AI without hype

Describe capability in terms of tasks and error rates, not intelligence. Never say "the AI understands" or "it thinks." Say what it does, how often it is right, and what a person still has to do.

- Hype: "Our AI will transform [COMPANY]'s customer service and understand every request."
- Honest: "The system drafts a reply for about 70 percent of routine tickets. An agent reviews and sends. On the other 30 percent it hands off to a human. In the pilot this cut average handle time by [X] minutes."

Rule of thumb: replace every verb that implies a mind (understands, knows, learns, decides) with a verb that describes behavior (drafts, classifies, ranks, flags, predicts).

### Model limitations

State limitations before anyone asks. Naming a weakness first is a credibility move, not a weakness. Cover three standard ones: it can be confidently wrong (hallucination), it reflects the data it was trained on (bias and staleness), and it degrades when the real world drifts from the pilot conditions.

- Example phrasing: "This model is right most of the time and wrong with the same confident tone, so it needs a human check on anything that leaves the building. Its knowledge is frozen as of [DATE]. And accuracy we measured in the pilot will slip if the input mix changes, which is why we monitor it monthly."

Avoid absolute words: "always," "never," "fully automated," "zero errors." Prefer ranges and conditions.

### Risk

Frame risk as "what could go wrong, how likely, how bad, and what we do about it." Executives do not want risk hidden; they want it owned. Use a simple likelihood-by-impact framing and always pair each risk with a mitigation.

```
RISK               LIKELIHOOD   IMPACT     MITIGATION
Wrong output ships   Medium      High       Human review gate on external replies
Data leakage         Low         Severe     No customer PII sent to model; redaction layer
Vendor outage        Medium      Medium     Fallback to manual queue; SLA in contract
```

- Example phrasing: "The most severe risk is a wrong answer reaching a customer. It is unlikely because a person approves every external message, but if it slipped through the impact is reputational, so we treat that gate as non-negotiable."

### Cost

Give total cost of ownership, not the sticker price. Executives have been burned by the pilot that was cheap and the production system that was not. Break cost into build, run, and people.

- Build: one-time integration, data preparation, testing.
- Run: per-request or per-token model cost, hosting, monitoring. This is the number that scales with usage, so express it per unit ("about [X] cents per ticket") and at expected volume.
- People: the human review effort that does not go away, plus maintenance.

- Example phrasing: "Building it is roughly [X]. Running it is about [Y] cents per ticket, so at your volume that is [Z] per month. It does not remove the review team; it makes each reviewer faster. Total first-year cost is [total], and the ongoing run cost grows with volume, not with a fixed license."

Never quote only the model API price. That is the smallest line item and quoting it alone is a form of hype.

### Business value

Tie value to a metric the executive already tracks, and be honest about what is measured versus modeled. Distinguish hard savings (cost removed), capacity (same people doing more), and revenue or risk-reduction (harder to attribute, so hedge).

- Example phrasing: "In the pilot, handle time dropped [X] percent, which at full rollout is roughly [Y] freed hours per month. We are confident in the time saving because we measured it. The revenue upside from faster responses is plausible but we have not proven it, so I am not putting it in the business case yet."

Avoid the unqualified ROI headline. "10x productivity" is hype. "[X] percent faster on the measured task, which maps to [Y] at your volume" is defensible.

### Implementation options

Give a small number of clearly different options, not a menu of twenty. Two or three is ideal, usually along the lines of buy versus build versus hybrid, or crawl-walk-run. For each, state what it gets them, what it costs, and how fast.

```
OPTION A - Buy (vendor platform):   fastest, least control, ongoing fee
OPTION B - Build (custom):          slowest, most control, higher upfront
OPTION C - Hybrid (vendor + glue):  middle path, moderate cost, some lock-in
```

- Example phrasing: "There are three realistic paths. Buying gets you live in [weeks] but you rent it forever and customize little. Building takes [months] but it is yours. The hybrid is where most of your peers land. My recommendation is [option] because [reason tied to their constraints]."

### Tradeoffs

Every serious option gives something up. Name the tradeoff plainly so no one feels ambushed later. The most common AI tradeoffs: speed versus accuracy, automation versus control, cost versus quality, and capability versus explainability.

- Example phrasing: "The faster, cheaper option automates more but explains its answers less. In a regulated context that matters, so if audit is a priority we accept a slower, costlier design that shows its work. You cannot have maximum automation and maximum explainability at the same time; we have to choose which one this use case needs more."

Avoid pretending a favored option has no downside. An option with no stated tradeoff reads as a sales pitch and erodes trust.

### Decisions required

End every executive conversation by naming the specific decisions only they can make, with a recommendation and a deadline. Do not leave the room with an open "let us know what you think." Make the ask concrete.

```
DECISION 1: Approve pilot budget of [X]?          Recommend: Yes   Needed by: [DATE]
DECISION 2: Buy vs build vs hybrid?               Recommend: Hybrid Needed by: [DATE]
DECISION 3: Who owns human-review staffing?       Recommend: [Team] Needed by: [DATE]
```

- Example phrasing: "You have three decisions today. I recommend a decision on each and I have flagged which is time-sensitive because [reason]. Everything else my team can carry."

---

## Part B - Same Project, Different Audiences

The project does not change. The framing does. The discipline is consistency: a CISO and a CEO should hear two versions of the truth that would never contradict each other if both were in the room. You are re-weighting, not re-writing. Below, each audience gets what they care about, what to lead with, and what to avoid.

### CEO

The CEO thinks in outcomes, competition, and time. They have the least patience for mechanism.

- Cares about: business impact, competitive position, cost versus return, and whether this is a distraction.
- Lead with: the outcome and the decision. "This frees [X] and pays back in [Y] months. I need a yes on the pilot budget by [DATE]."
- Avoid: architecture, model names, and jargon. Do not explain how it works unless asked.

### CIO

The CIO owns whether it fits the estate and survives contact with existing systems and teams.

- Cares about: integration, maintainability, vendor lock-in, total cost of ownership, and fit with the current roadmap.
- Lead with: how it plugs into what [COMPANY] already runs and who maintains it. "This sits alongside your existing stack, one new integration, owned by [team]."
- Avoid: business-value hand-waving without an ownership and support story, and hype about capability that ignores operational load.

### CISO

The CISO assumes something will go wrong and wants to know you have already thought about it.

- Cares about: data handling, attack surface, access control, third-party exposure, and incident response.
- Lead with: where the data goes and where it does not. "No customer PII leaves your boundary; the model sees redacted text only; here is the failure and response plan."
- Avoid: minimizing risk or saying "it's secure." Never oversell safety. Bring the threat model, not reassurance.

### Legal counsel

Legal reads for liability, obligation, and words that create exposure.

- Cares about: contracts, liability, IP ownership of outputs, data rights, and regulatory obligations.
- Lead with: who is liable for a wrong output, who owns what the system produces, and what the vendor terms say.
- Avoid: casual capability claims. Do not say "it's always accurate" or "fully compliant." Legal will hold you to every adjective, so use conditions and cite obligations precisely.

### Business leader (functional / line-of-business)

This is the person whose team uses the thing and whose numbers it should move.

- Cares about: impact on their team's workload, workflow disruption, training, and whether it makes their metrics better.
- Lead with: what changes for their people day to day and the metric it moves. "Your agents review instead of type; handle time drops [X]; here is the two-hour training."
- Avoid: enterprise-wide abstractions and technical depth. Keep it grounded in their team's reality.

### Engineering team

The engineers will build, run, and be paged for it. They want the truth at full resolution.

- Cares about: architecture, data flows, failure modes, latency, observability, and maintenance burden.
- Lead with: the technical design, the interfaces, and the known limitations and edge cases. Give them the detail you hide from the CEO.
- Avoid: business fluff and hype. Do not oversell; engineers detect it instantly and it costs you credibility for the whole engagement.

### Regulator

The regulator reads literally, on the record, and against a standard.

- Cares about: compliance with specific rules, transparency, fairness and bias, auditability, and accountability.
- Lead with: how the system meets the applicable requirement and how it is documented and auditable. Map to the framework they use (for example NIST AI RMF functions, see: https://www.nist.gov/itl/ai-risk-management-framework, or ISO/IEC 42001 controls, see: https://www.iso.org/standard/42001).
- Avoid: speculation, informality, and marketing language. Every claim must be evidenced and traceable. Say "we do not know" rather than guess.

### Audience map

| Audience | Cares about | Lead with | Avoid |
|---|---|---|---|
| CEO | Outcome, competition, ROI, time | The decision and the payback | Architecture, jargon, mechanism |
| CIO | Integration, maintainability, lock-in, TCO | How it fits the estate and who owns it | Value hand-waving, capability hype |
| CISO | Data handling, attack surface, incident response | Where data goes and the failure plan | Minimizing risk, "it's secure" |
| Legal counsel | Liability, IP, data rights, obligations | Who is liable and who owns outputs | Absolute claims, loose adjectives |
| Business leader | Team workload, workflow, their metrics | What changes day to day and the metric | Enterprise abstractions, deep tech |
| Engineering team | Architecture, failure modes, maintenance | Full-resolution technical design | Business fluff, any hype |
| Regulator | Compliance, transparency, auditability | How it meets the specific rule, documented | Speculation, informality, marketing |

A working move for a mixed room: open with the CEO framing (decision plus payback), then say "for [CISO], the data path is X; for [engineering], the design is Y" so each person hears their thread without you losing the room. One truth, several doors into it.

---

## Check yourself (Exit gate for this concept)

You are ready to move on when you can:

1. Take one real AI project and write a five-sentence summary with zero hype, covering value, cost, limitation, risk, and the decision required - and defend every sentence against a skeptical challenge.
2. Present that same project three ways (CEO, CISO, and engineering team) so that the versions differ in emphasis but never contradict each other.
3. Close any executive conversation by naming the specific decisions the client must make, each with a recommendation and a deadline.

## References

- [NIST AI Risk Management Framework (AI RMF 1.0)](https://www.nist.gov/itl/ai-risk-management-framework) - authoritative language for describing AI risk, governance, and trustworthiness to executives and regulators.
- [ISO/IEC 42001:2023 - Information technology - Artificial intelligence - Management system](https://www.iso.org/standard/42001) - the AI management-system standard to map to when speaking with legal and regulators.
- [OWASP Top 10 for LLM Applications](https://genai.owasp.org/llm-top-10/) - the named LLM risks (prompt injection, data leakage) to bring to a CISO conversation rather than reassurance.
- [Harvard Business Review - Embracing Gen AI at Work (2024)](https://hbr.org/2024/09/embracing-gen-ai-at-work) - executive framing of where AI changes work, and the value and limits to communicate honestly.
- [McKinsey - The state of AI: how organizations are rewiring to capture value](https://www.mckinsey.com/capabilities/quantumblack/our-insights/the-state-of-ai-how-organizations-are-rewiring-to-capture-value) - defensible value and adoption data for business-value conversations.
