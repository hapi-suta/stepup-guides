# Concepts: Finding AI Opportunities

**Tier 14, Module 14.1** - How a consultant walks into a client organization and reliably spots where AI can create real value.

Most clients cannot tell you where AI belongs. They ask for "an AI strategy" or point at a competitor's chatbot. Your job as a consultant is to look past the hype and find the specific, high-value places where AI fits the work. This concept gives you a pattern library: recurring shapes of work that AI is good at, what each looks like, a concrete example, and the signals that reveal it inside a real organization. Learn to see these patterns and you can walk any process and name the opportunities out loud.

A useful opportunity has three properties: the work happens **often** (volume), it **costs** the business time or money or risk, and AI can do it **well enough** to matter. Keep those three in mind as you read every pattern below. This volume-cost-feasibility screen is a practitioner rule of thumb, not a formal standard; treat it as a starting filter, not a law.

---

### Repetitive work

**What to look for:** Tasks a human does the same way many times a day, following a mostly-fixed mental script, with little creative judgment. High volume, low variety.

**Example:** A billing team copies invoice totals from PDFs into an accounting system 400 times a day. An AI extraction model plus a review queue can do the first pass and let humans handle only the exceptions.

**How to spot it in a client org:** Listen for "we do this all day," "it's mind-numbing," or "we hired temps for it." Look at headcount assigned to a single narrow task. Ask "how many times a day does someone do exactly this?" If the answer is in the hundreds and the steps rarely change, it is a candidate.

---

### Large document workloads

**What to look for:** People who read, summarize, compare, or extract facts from long documents - contracts, reports, policies, research, tickets. The bottleneck is human reading speed.

**Example:** A legal team reviews 200-page vendor contracts to find liability and termination clauses. A large language model can surface the relevant clauses and draft a summary, cutting review from hours to minutes with a lawyer verifying.

**How to spot it in a client org:** Find teams whose "output" is a memo, summary, or "I read it so you don't have to." Look for shared drives full of PDFs, long email threads, or backlogs of "documents to review." Ask "who spends their day reading?"

---

### Decision bottlenecks

**What to look for:** A step where work piles up waiting for one person or a small group to make a routine judgment call. The decision is repeatable but currently gated on a scarce expert.

**Example:** Every expense over $500 waits for a manager's approval, and the manager is the queue. An AI assistant can pre-classify clear approvals and denials against policy, escalating only the genuinely ambiguous ones.

**How to spot it in a client org:** Look for queues, "waiting for sign-off," SLAs that slip, and one name that appears as the approver everywhere. Ask "what are people waiting on?" A single overloaded decision-maker is a classic bottleneck.

---

### Knowledge-access problems

**What to look for:** Employees who cannot find what the organization already knows. Answers exist somewhere - a wiki, old tickets, a veteran's head - but retrieving them is slow.

**Example:** New support agents ask senior colleagues the same product questions repeatedly. A retrieval-augmented assistant grounded in the internal knowledge base answers instantly with citations. (Retrieval-augmented generation, or RAG, grounds a model in your own documents so answers cite real sources rather than being generated from memory. see: https://github.com/OWASP/www-project-top-10-for-large-language-model-applications)

**How to spot it in a client org:** Listen for "just ask Maria, she knows," "I couldn't find the doc," or heavy reliance on tribal knowledge. Long onboarding times and repeated Slack questions are strong signals. Ask "where does knowledge live, and how do people get to it?"

---

### Customer-service delays

**What to look for:** Customers wait for answers to common, well-understood questions. High ticket volume, repetitive queries, long response times.

**Example:** An e-commerce company gets thousands of "where is my order?" tickets. An AI assistant integrated with the order system answers those instantly, freeing agents for complex cases.

**How to spot it in a client org:** Check ticket volume, first-response time, and the top 10 ticket categories. If a handful of question types make up most of the volume and they are answerable from data the company holds, that is the opportunity. Ask "what do customers ask over and over?"

---

### Forecasting problems

**What to look for:** The business guesses at future quantities - demand, staffing, inventory, cash - and pays when the guess is wrong (stockouts, overstock, idle staff).

**Example:** A retailer over-orders perishable stock and writes off waste. A demand-forecasting model using history, seasonality, and promotions tightens ordering and cuts spoilage.

**How to spot it in a client org:** Look for spreadsheets full of manual projections, "gut feel" planning, and recurring pain from being wrong (waste, missed sales, overtime). Ask "what are you trying to predict, and what happens when you miss?"

---

### Fraud and anomaly patterns

**What to look for:** Rare, costly, hard-to-define bad events hidden in large streams of normal activity - fraudulent transactions, defective units, unusual logins.

**Example:** A payments company loses money to fraud that fixed rules keep missing. An anomaly-detection model scores each transaction and flags the suspicious ones for review.

**How to spot it in a client org:** Look for known losses that current rules cannot catch, big volumes of transactions or events, and teams doing manual spot-checks. Ask "what bad thing slips through, and how do you catch it today?"

---

### Data-entry work

**What to look for:** Humans transcribing information from one format into another - forms into databases, handwriting into fields, images into records. Pure translation, no judgment.

**Example:** A clinic types data from paper intake forms into an EHR. Document AI reads the forms and pre-fills the fields, with staff confirming.

**How to spot it in a client org:** Watch for people typing from a screen or paper into another system, double-entry across tools, and "we key it in manually." Ask "where do people retype information that already exists somewhere?"

---

### Compliance tasks

**What to look for:** Recurring checks required by regulation or policy - reviewing documents for required clauses, monitoring communications, verifying controls, generating audit evidence. High stakes, high volume, rule-driven.

**Example:** A bank must screen communications for prohibited language. An AI classifier flags likely violations for compliance officers instead of random sampling.

**How to spot it in a client org:** Find teams that exist to satisfy regulators, audits that consume weeks, and manual sampling because full coverage is too expensive. Ask "what must you check by law, and can you check all of it today?" AI can often move them from sampling to full coverage.

---

## The consultant's opportunity-hunting method

Combine the patterns above with a simple walk-the-process routine:

```
1. Map the process        -> steps, who does what, handoffs
2. Find the pain          -> queues, delays, errors, cost, complaints
3. Match to a pattern     -> which of the 9 shapes above fits?
4. Score the opportunity  -> volume x cost x AI-feasibility
5. Shortlist              -> the few with high score AND available data
```

The best first project is usually high volume, clear cost, forgiving of small errors, and sitting on data the client already has. Chase those before the flashy ones.

---

## Check yourself (Exit gate for this concept)

You are ready to move on when you can:

1. Name all nine opportunity patterns from memory and give one real-world example of each.
2. Walk a described business process and point to at least two AI opportunities, naming the pattern and the signal that revealed it.
3. Explain the three properties (volume, cost, feasibility) that make an opportunity worth pursuing, and rank a short list of candidates by them.

## References

- [McKinsey - The state of AI: how organizations are rewiring to capture value](https://www.mckinsey.com/capabilities/quantumblack/our-insights/the-state-of-ai-how-organizations-are-rewiring-to-capture-value) - where AI value and adoption concentrate across functions.
- [Harvard Business Review - Embracing Gen AI at Work (2024)](https://hbr.org/2024/09/embracing-gen-ai-at-work) - which categories of work AI can augment, automate, or reinvent.
- [NIST AI Risk Management Framework (AI RMF 1.0)](https://www.nist.gov/itl/ai-risk-management-framework) - trustworthy-AI framing for judging whether an opportunity is safe to pursue.
- [a16z - Navigating the High Cost of AI Compute](https://a16z.com/navigating-the-high-cost-of-ai-compute/) - why compute and inference cost shape AI feasibility.
