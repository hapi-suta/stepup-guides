# Concepts: AI Readiness Assessment

**Tier 15, Module 15.2** - A structured way to judge whether an organization can actually succeed with AI before you help them spend a dollar on it.

An AI readiness assessment is one of the most common paid engagements a new AI consultant will run, and it is the one that protects both you and the client from the most expensive mistake in the field: buying or building AI on top of an organization that is not ready to absorb it. A readiness assessment turns a vague "we want to do AI" conversation into a scored, defensible picture of where [CLIENT] stands across every dimension that matters, what to fix first, and what is safe to attempt now. Done well, it becomes the anchor document for the whole relationship. Every roadmap, budget request, and executive conversation that follows points back to it. This concept teaches you the twelve dimensions to score, what "ready" and "not ready" look like in each, a 1-to-5 maturity scale you can apply consistently, and a consolidated rubric you can hand a client as a deliverable.

---

## How to run the assessment

You are producing a document, not code. The workflow is the same every time:

```
1. SCOPE     Agree which business unit / use case the assessment covers.
2. GATHER    Interviews + document review + a light artifact audit per dimension.
3. SCORE     Rate each of the 12 dimensions on the 1-5 maturity scale.
4. WEIGHT    Some dimensions gate others (Data and Leadership carry more weight).
5. SYNTHESIZE  Overall readiness = weighted picture + top 3 gaps + top 3 quick wins.
6. RECOMMEND   "Ready to X, not ready to Y, fix Z first" - always actionable.
```

A score without a recommendation is a report card. A score with a recommendation is consulting. Always land on "what to do next."

Two scoring rules keep you honest:

- **Score evidence, not aspiration.** If a leader says "our data is great," you score what the artifacts show, not what they hope. Ask to see the thing.
- **The lowest gating dimension caps the ambition.** A client can be a 5 on Technology and a 1 on Data. Their real AI ceiling is closer to the 1. Say so plainly.

---

### Strategy

Strategy readiness asks whether AI is tied to a real business outcome or is just a buzzword the board wants to hear.

- **Ready looks like:** A specific problem statement ("cut invoice-processing time by 40 percent") with a named owner, a dollar value, and a reason AI is the right tool versus a spreadsheet or a hire.
- **Not ready looks like:** "We need an AI strategy" with no target metric, no priority use case, and AI treated as a goal instead of a means.

Scoring approach:

| Level | Strategy maturity |
|-------|-------------------|
| 1 | AI is a buzzword. No business problem attached. |
| 2 | General interest, but no prioritized use cases or metrics. |
| 3 | 1-2 use cases identified and loosely tied to a business goal. |
| 4 | Prioritized use-case portfolio with target metrics and owners. |
| 5 | AI strategy is a named line in the corporate strategy with funded outcomes and review cadence. |

---

### Leadership

Leadership readiness asks whether someone with real authority will sponsor, fund, and unblock the work when it gets hard.

- **Ready looks like:** A named executive sponsor with budget authority who can explain in one sentence why this matters and will defend it in a tough quarter.
- **Not ready looks like:** Enthusiasm confined to IT or an innovation lab, with no one at the leadership table accountable for the outcome.

Scoring approach:

| Level | Leadership maturity |
|-------|---------------------|
| 1 | No executive interest. Bottom-up only. |
| 2 | Curious executives, but no sponsor and no budget. |
| 3 | A sponsor exists but authority or funding is limited. |
| 4 | Committed sponsor with budget and a stake in the outcome. |
| 5 | AI is owned at the C-suite/board level with clear accountability and public commitment. |

---

### Data

Data readiness is the single most decisive dimension. Most failed AI projects are failed data projects wearing a costume.

- **Ready looks like:** Relevant data exists, is reasonably clean, is accessible without a three-month approval chain, is documented, and someone owns its quality.
- **Not ready looks like:** Data trapped in spreadsheets and silos, no lineage, unknown quality, and no one who can say what a given field means.

Scoring approach:

| Level | Data maturity |
|-------|---------------|
| 1 | Data siloed, undocumented, quality unknown. |
| 2 | Data exists but is scattered and hard to access. |
| 3 | Key datasets are accessible and partially documented. |
| 4 | Governed, documented, quality-monitored data with clear ownership. |
| 5 | Trusted, well-governed data platform; datasets are discoverable and reusable across teams. |

---

### Technology

Technology readiness asks whether the client can host, integrate, and run AI workloads without a full re-platforming project first.

- **Ready looks like:** Cloud or hybrid infrastructure, APIs that expose core systems, and the ability to stand up an environment in days.
- **Not ready looks like:** Legacy systems with no APIs, no cloud footprint, and any new capability requiring a heavy custom integration.

Scoring approach:

| Level | Technology maturity |
|-------|---------------------|
| 1 | Legacy, on-prem, no APIs, no cloud. |
| 2 | Some modern systems, but integration is manual and painful. |
| 3 | Cloud presence and some APIs; new environments take weeks. |
| 4 | Cloud-first with APIs and self-service environments. |
| 5 | Modern, API-driven, scalable platform ready for AI workloads out of the box. |

---

### Security

Security readiness asks whether AI can be introduced without opening new attack surface or leaking sensitive data into third-party models.

- **Ready looks like:** Clear data classification, access controls, secrets management, and a stated position on what data may be sent to external AI services.
- **Not ready looks like:** No data classification, shared credentials, and staff already pasting confidential data into public chatbots with no policy.

Scoring approach:

| Level | Security maturity |
|-------|-------------------|
| 1 | No data classification or access controls. Shadow AI use is uncontrolled. |
| 2 | Basic controls, but AI-specific risks are unaddressed. |
| 3 | Data classified; a stated policy on external AI tools exists. |
| 4 | AI risks in threat models; controls enforced on AI data flows. |
| 5 | Security-by-design for AI, including model and prompt-injection risks (the top item in the OWASP Top 10 for LLM Applications, see: https://genai.owasp.org/llm-top-10/), continuously monitored. |

---

### Governance

Governance readiness asks whether there is a way to decide who can build what, approve it, and be accountable when a model behaves badly.

- **Ready looks like:** A defined approval path for AI use cases, a risk-tiering approach, and named owners for model behavior and outcomes.
- **Not ready looks like:** Anyone can spin up any tool with no review, and no one owns the question "was this AI decision fair and correct?"

Scoring approach:

| Level | Governance maturity |
|-------|---------------------|
| 1 | No AI governance. Ad hoc, uncontrolled adoption. |
| 2 | Informal reviews; no policy or risk framework. |
| 3 | A written AI policy and basic approval process exist. |
| 4 | Risk-tiered governance with named accountable owners. |
| 5 | Mature governance aligned to a recognized framework - for example the NIST AI RMF (see: https://www.nist.gov/itl/ai-risk-management-framework) or ISO/IEC 42001 (see: https://www.iso.org/standard/42001) - with audits and monitoring. |

---

### Talent

Talent readiness asks whether the people who will build, operate, and use the AI have the skills, or a credible plan to get them.

- **Ready looks like:** A mix of technical builders and business translators, plus a training plan for the wider workforce.
- **Not ready looks like:** No internal AI skills, no hiring or upskilling plan, and reliance entirely on vendors with no knowledge transfer.

Scoring approach:

| Level | Talent maturity |
|-------|-----------------|
| 1 | No AI skills internally; no plan. |
| 2 | Isolated individuals with interest but no mandate. |
| 3 | A small capable team; broad workforce not yet enabled. |
| 4 | Cross-functional AI capability plus an upskilling program. |
| 5 | Deep bench of builders and translators; continuous learning is embedded. |

---

### Culture

Culture readiness asks whether the organization will actually use what is built, or quietly route around it.

- **Ready looks like:** Curiosity, tolerance for experimentation and small failures, and trust that AI augments rather than threatens staff.
- **Not ready looks like:** Fear that AI means layoffs, a "not invented here" reflex, and past tech rollouts that were ignored.

Scoring approach:

| Level | Culture maturity |
|-------|-----------------|
| 1 | Fear and resistance; AI seen as a threat. |
| 2 | Skepticism; low trust in new tools. |
| 3 | Open to AI but cautious; adoption is uneven. |
| 4 | Experimentation is encouraged and rewarded. |
| 5 | Data- and AI-informed decisions are the cultural default. |

---

### Process maturity

Process maturity asks whether the workflows AI will touch are stable and documented enough to automate or augment.

- **Ready looks like:** Core processes are documented, measured, and consistent, so AI has a clear thing to improve.
- **Not ready looks like:** Every team does the same task differently, nothing is measured, and "the process" lives in one person's head.

Scoring approach:

| Level | Process maturity |
|-------|------------------|
| 1 | Ad hoc, undocumented, person-dependent processes. |
| 2 | Some documentation; inconsistent execution. |
| 3 | Key processes documented and mostly consistent. |
| 4 | Processes measured with KPIs and improved regularly. |
| 5 | Optimized, instrumented processes ready for automation and augmentation. |

---

### Budget

Budget readiness asks whether there is realistic, sustained funding, not just a pilot slush fund that vanishes at renewal.

- **Ready looks like:** A funded line item that covers build, run, and the often-underestimated ongoing costs of tokens, infrastructure, and maintenance.
- **Not ready looks like:** A one-time pilot budget with no plan for what production and scale actually cost.

Scoring approach:

| Level | Budget maturity |
|-------|-----------------|
| 1 | No budget allocated. |
| 2 | Small one-off pilot funds only. |
| 3 | Project budget exists but ignores run/scale costs. |
| 4 | Funded across build and run with a TCO view. |
| 5 | Sustained multi-year funding tied to expected returns. |

---

### Compliance

Compliance readiness asks whether the client understands and can meet the legal and regulatory obligations that AI triggers in their industry and geography.

- **Ready looks like:** Awareness of relevant regimes (privacy law, sector rules, emerging AI regulation), and a way to document and defend AI decisions.
- **Not ready looks like:** No awareness of AI-specific obligations, no record-keeping, and use cases in regulated areas with no legal review.

Scoring approach:

| Level | Compliance maturity |
|-------|---------------------|
| 1 | No awareness of AI-related compliance obligations. |
| 2 | Aware of general data rules but not AI-specific ones. |
| 3 | Relevant regimes identified; some controls in place. |
| 4 | Compliance built into the AI lifecycle with documentation. |
| 5 | Auditable, defensible AI decisions aligned to current and emerging regulation. |

---

### Vendor readiness

Vendor readiness asks whether the client can select, contract with, and manage AI vendors without getting locked in or exposed.

- **Ready looks like:** A vendor evaluation process, contract terms that cover data use and model changes, and an avoid-lock-in posture.
- **Not ready looks like:** Buying the first tool a salesperson demos, with no data-use terms, no exit plan, and no comparison.

Scoring approach:

| Level | Vendor maturity |
|-------|-----------------|
| 1 | No process; buys reactively on sales pressure. |
| 2 | Informal selection; weak contract terms. |
| 3 | Basic evaluation criteria and standard contracts. |
| 4 | Structured selection with data-use and exit clauses. |
| 5 | Portfolio approach: benchmarked vendors, lock-in managed, terms enforced. |

---

## Consolidated readiness scoring rubric

Hand this to [CLIENT] as the core of the deliverable. Score each dimension 1-5, then summarize.

| Dimension | 1 - Absent | 2 - Emerging | 3 - Developing | 4 - Managed | 5 - Optimized |
|-----------|-----------|--------------|----------------|-------------|---------------|
| Strategy | Buzzword only | Interest, no use cases | Use cases tied to goals | Prioritized portfolio w/ metrics | AI in corporate strategy, funded |
| Leadership | No interest | Curious, no sponsor | Limited sponsor | Committed sponsor w/ budget | C-suite/board owned |
| Data | Siloed, unknown quality | Scattered, hard to access | Key sets accessible | Governed, quality-monitored | Trusted, reusable platform |
| Technology | Legacy, no APIs | Manual integration | Cloud + some APIs | Cloud-first, self-service | AI-ready platform |
| Security | No controls | Basic controls | Policy on external AI | AI risks in threat model | Security-by-design for AI |
| Governance | None | Informal reviews | Written policy | Risk-tiered w/ owners | Framework-aligned, audited |
| Talent | No skills | Isolated interest | Small team | Cross-functional + upskilling | Deep bench, continuous learning |
| Culture | Fear/resistance | Skepticism | Open but cautious | Experimentation rewarded | AI-informed by default |
| Process maturity | Ad hoc | Some docs | Documented, consistent | Measured w/ KPIs | Optimized, instrumented |
| Budget | None | Pilot only | Ignores run costs | Funded w/ TCO | Sustained, ROI-tied |
| Compliance | Unaware | General rules only | Regimes identified | Built into lifecycle | Auditable, defensible |
| Vendor readiness | Reactive buying | Weak terms | Basic evaluation | Structured w/ exit clauses | Managed portfolio |

**Reading the scores:**

- **Overall 1.0-2.0:** Foundation-building phase. Recommend fixing data, leadership, and governance before any AI build. Sell a roadmap, not a model.
- **Overall 2.1-3.0:** Pilot-ready in narrow, low-risk areas. Recommend a scoped proof of value plus parallel foundation work.
- **Overall 3.1-4.0:** Scale-ready. Recommend a use-case portfolio and operating-model work.
- **Overall 4.1-5.0:** Optimize and differentiate. Recommend advanced use cases and continuous governance.

**Weighting note:** Data and Leadership are gating dimensions. If either scores 1, cap the recommended ambition regardless of a high average - a high average built on a Data 1 is a false positive.

---

## Glossary

| Term | Plain meaning |
|------|---------------|
| Gating dimension | A dimension so foundational that a low score caps overall readiness (Data, Leadership). |
| Shadow AI | Staff using AI tools with no policy or oversight. A security and governance red flag. |
| TCO | Total cost of ownership - build plus the ongoing run, token, and maintenance costs. |
| Proof of value | A scoped pilot that proves business impact, not just that the tech works. |
| Business translator | A person who bridges technical builders and business stakeholders. |
| Lock-in | Dependence on one vendor that makes switching costly or impractical. |

---

## Check yourself (Exit gate for this concept)

You are ready to move on when you can:

1. Score all twelve dimensions for a sample client from interview notes and artifacts, and defend each score with evidence rather than the client's aspiration.
2. Explain why Data and Leadership are gating dimensions and demonstrate how a low score in either caps overall readiness even when the average looks healthy.
3. Turn a completed rubric into a one-page recommendation stating what [CLIENT] is ready to do now, what they are not ready to do, and the top three gaps to fix first.

---

## References

- [NIST AI Risk Management Framework (AI RMF 1.0)](https://www.nist.gov/itl/ai-risk-management-framework) - the governance framework a mature (level 5) client aligns to.
- [ISO/IEC 42001:2023 - Information technology - Artificial intelligence - Management system](https://www.iso.org/standard/42001) - the AI management-system standard behind the governance dimension.
- [OWASP Top 10 for LLM Applications](https://genai.owasp.org/llm-top-10/) - prompt injection and the LLM-specific risks the Security dimension scores against.
- [McKinsey - The state of AI: how organizations are rewiring to capture value](https://www.mckinsey.com/capabilities/quantumblack/our-insights/the-state-of-ai-how-organizations-are-rewiring-to-capture-value) - evidence that data, leadership, and workflow readiness gate AI value.
- [Harvard Business Review - Building the AI-Powered Organization (2019)](https://hbr.org/2019/07/building-the-ai-powered-organization) - why culture and organizational readiness, not technology, are the binding constraint.
