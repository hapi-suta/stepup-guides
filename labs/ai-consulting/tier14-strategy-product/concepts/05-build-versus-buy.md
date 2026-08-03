# Concepts: Build-Versus-Buy Analysis

**Tier 14, Module 14.5** - How a consultant chooses the right way to deliver an AI capability, from buying a SaaS tool to training a custom model.

"Should we build it or buy it?" is one of the highest-leverage questions you will answer for a client, and it is rarely a clean binary. Modern AI offers a spectrum of options from fully bought (a SaaS product someone else runs) to fully built (a model you train and host yourself), with many stops in between. Each option trades off cost, control, speed, data privacy, and the skill needed to sustain it. Pick wrong and the client either overpays for capability they will not use or underdelivers on a hard problem. This concept walks the spectrum and gives you a decision heuristic.

The governing principle: **buy the commodity, build the differentiator.** If the capability is not what makes the client special, prefer to buy it. Reserve building for what creates competitive advantage. This is a widely-held practitioner heuristic, not a proven law; it is a good default, but a specific client's economics, risk, or data-sensitivity can override it.

---

### SaaS tool

**What it is:** A finished AI product you subscribe to; the vendor runs everything.

**Pros:** Fastest to value, no ML skill needed, vendor handles maintenance and updates, predictable subscription cost.

**Cons:** Least control and customization, your data goes to the vendor, feature roadmap not yours, lock-in.

**Cost profile:** Low upfront, recurring per-seat or per-usage subscription.

**When to choose it:** The need is common and non-differentiating (e.g., meeting transcription, generic chatbot) and a good product already exists.

**Risk:** Vendor lock-in, price hikes, data-handling and compliance concerns, product discontinued.

---

### Frontier-model API

**What it is:** Calling a top commercial large language model (or similar) over an API and building your logic and prompts around it.

**Pros:** Access to state-of-the-art capability with no training, fast to build, scales elastically, you control the application logic.

**Cons:** Ongoing per-token cost that grows with usage, dependency on the provider, data leaves your environment (unless a private/enterprise tier), model can change under you.

**Cost profile:** Low upfront, variable operating cost that scales with volume - can get expensive at scale.

**When to choose it:** You need strong general intelligence quickly, volume is moderate, and you want to own the product but not the model.

**Risk:** Cost blowout at scale, provider outages or policy changes, data governance, model version drift.

---

### Cloud-managed service

**What it is:** A cloud provider's managed AI building block (managed vector search, document AI, speech-to-text, a hosted model endpoint) that you wire into your app.

**Pros:** Less ops than self-hosting, integrates with existing cloud, keeps data within your cloud account, scalable.

**Cons:** Some cloud lock-in, still needs engineering, capability set fixed by the provider.

**Cost profile:** Usage-based operating cost, modest setup.

**When to choose it:** The client is already on a cloud, wants managed infrastructure, and needs a standard component rather than a bespoke model.

**Risk:** Cloud lock-in, service limits, cost sprawl across many managed services.

---

### Custom application

**What it is:** Bespoke software your team builds around AI components (often orchestrating APIs or managed services) tailored to the client's exact workflow.

**Pros:** Fits the business precisely, owns the differentiating logic and UX, integrates deeply with internal systems.

**Cons:** Significant build cost and time, requires engineering skill, you own maintenance.

**Cost profile:** High upfront build, ongoing operating and maintenance cost.

**When to choose it:** The workflow is core to the business and no product fits, but you can still lean on bought models underneath.

**Risk:** Overrun, key-person dependency, maintenance burden if the client lacks engineering capacity.

---

### Open-source model

**What it is:** Using a freely available pre-trained model that you run yourself instead of a commercial API.

**Pros:** No per-token vendor fee, full control, data stays in your environment, no vendor lock-in, inspectable.

**Cons:** You must host, scale, secure, and maintain it; may lag frontier quality; needs ML/infra skill.

**Cost profile:** No license fee but real infrastructure and engineering operating cost.

**When to choose it:** Data privacy or cost-at-scale rules out APIs, and the client has (or will build) the skills to run it.

**Risk:** Underestimating operating and ops burden, quality gap versus frontier models, security of self-hosting.

---

### Fine-tuned model

**What it is:** Taking a base model (open-source or via a provider's fine-tuning) and further training it on the client's own data for a specific task or style.

**Pros:** Better performance on the narrow task, can encode domain language and tone, smaller/cheaper model may match a bigger one.

**Cons:** Needs quality labeled data, ML expertise, and re-tuning as data changes; adds an evaluation and maintenance burden.

**Cost profile:** Moderate-to-high upfront (data + training), plus operating cost.

**When to choose it:** A general model is close but not good enough on a specialized, stable task and you have the data to close the gap.

**Risk:** Data quality issues, overfitting, drift requiring re-tuning, wasted effort if prompting alone would have sufficed - always try prompting/retrieval first.

---

### Local deployment

**What it is:** Running the AI entirely on the client's own hardware or private network, with nothing leaving their walls.

**Pros:** Maximum data control and privacy, no external dependency, can meet strict regulatory or air-gapped requirements, no per-call cloud fee.

**Cons:** High hardware and ops cost, hardest to scale, limited to models that fit local resources, you own everything.

**Cost profile:** High capital (hardware) plus ongoing ops; no usage fees.

**When to choose it:** Regulation, secrecy, or connectivity forbids sending data out (defense, healthcare, sensitive on-prem environments).

**Risk:** Capacity limits, expensive hardware refresh, heavy operational responsibility, falling behind on model updates.

---

### Hybrid approach

**What it is:** Mixing options - e.g., a frontier API for hard queries with a cheap local/open model for easy ones, or SaaS for commodity tasks and a custom build for the differentiator.

**Pros:** Optimizes cost, performance, and privacy per use case; avoids all-eggs-one-basket lock-in; route sensitive data locally and general work to APIs.

**Cons:** More complex architecture, more to integrate and monitor, needs good routing logic.

**Cost profile:** Mixed - tuned to spend where it matters.

**When to choose it:** Needs vary across use cases or data-sensitivity tiers, and the client is mature enough to run a more complex system.

**Risk:** Integration complexity, harder debugging and monitoring, governance across multiple providers.

---

## Decision heuristic

Work down this ladder and stop at the first "yes":

```
1. Is it a common, non-differentiating need with a good product?   -> SaaS tool
2. Need strong general AI fast, moderate volume, own the app?       -> Frontier-model API
3. Already on a cloud, want a managed standard component?           -> Cloud-managed service
4. Is data too sensitive / cost-at-scale too high for APIs,
   and do you have the skills to run a model?                       -> Open-source model
5. Must the data never leave the premises (regulation/secrecy)?     -> Local deployment
6. Is a general model close but not good enough on a stable task,
   and do you have labeled data?                                    -> Fine-tuned model
7. Is this workflow core to the business with no fitting product?   -> Custom application
8. Do needs vary widely by use case or data sensitivity?           -> Hybrid approach
```

### Decision table

| Option | Upfront cost | Operating cost | Control | Data privacy | Skill needed | Speed to value |
|---|---|---|---|---|---|---|
| SaaS tool | Low | Subscription | Low | Low | Low | Fastest |
| Frontier-model API | Low | High at scale | Medium | Low-Medium | Low-Medium | Fast |
| Cloud-managed service | Low-Med | Usage-based | Medium | Medium | Medium | Fast |
| Custom application | High | Medium-High | High | High | High | Slow |
| Open-source model | Low license | Infra + ops | High | High | High | Medium |
| Fine-tuned model | Med-High | Medium | High | High | High | Medium |
| Local deployment | High (hardware) | Ops | Highest | Highest | High | Slow |
| Hybrid approach | Mixed | Mixed | High | Tunable | High | Medium |

Rule of thumb: start as far up the "buy" end as the requirements allow, and only move toward "build" when differentiation, privacy, or cost-at-scale forces you. Try prompting and retrieval (RAG) before fine-tuning, and fine-tuning before training from scratch - this "prompt, then retrieve, then fine-tune" ladder is the standard vendor recommendation because each rung is cheaper and lower-risk than the next. (see: https://docs.aws.amazon.com/prescriptive-guidance/latest/retrieval-augmented-generation-options/rag-vs-fine-tuning.html)

---

## Check yourself (Exit gate for this concept)

You are ready to move on when you can:

1. Name all eight delivery options and give the one situation where each is the right call.
2. Apply the "buy the commodity, build the differentiator" principle to a client scenario and justify your recommendation.
3. Fill in the decision table for a given use case and defend your choice on cost, control, privacy, and skill.

## References

- [a16z - Emerging Architectures for LLM Applications](https://a16z.com/emerging-architectures-for-llm-applications/) - the component landscape (APIs, vector stores, orchestration) behind the build/buy spectrum.
- [Gartner - Artificial Intelligence insights](https://www.gartner.com/en/topics/artificial-intelligence) - analyst framing for AI build-versus-buy decisions.
- [McKinsey - The state of AI: how organizations are rewiring to capture value](https://www.mckinsey.com/capabilities/quantumblack/our-insights/the-state-of-ai-how-organizations-are-rewiring-to-capture-value) - where custom builds versus bought capability tend to pay off.
- [AWS Prescriptive Guidance - Comparing Retrieval Augmented Generation and fine-tuning](https://docs.aws.amazon.com/prescriptive-guidance/latest/retrieval-augmented-generation-options/rag-vs-fine-tuning.html) - vendor guidance for the prompt, then RAG, then fine-tune ladder.
