# Concepts 6.3: Model Providers

**Tier 6 - Generative AI and large language models.** Teaching reference. There is no single "the LLM". There is a market of providers, each with a family of models, different prices, different limits, different deployment options, and different strengths. A big part of the consultant's job is choosing the right provider and model for a client's job - and doing it without locking the client into a single vendor forever.

**Who this is for:** DBAs moving into AI consulting. You already think about vendor choice - Postgres vs MySQL, AWS vs on-prem. Same discipline applies here: pick for the workload, keep an exit path, do not marry a vendor.

**One rule above all: do not lock in to one provider.** This document deliberately treats the providers as interchangeable building blocks. The labs are written to read the API key from an environment variable and to swap providers behind a small interface, precisely so a client is never trapped.

---

## 1. The landscape (as of this writing - verify current details before advising a client)

The model market moves fast. Names, versions, prices, and context windows change every few months. Treat the specifics below as a snapshot and always confirm the live numbers from the provider before you put them in a client proposal. What does *not* change is the shape of the market and the questions you ask.

**Anthropic (Claude).** A family of models spanning fast/cheap to most-capable. Strong on long-context work, careful reasoning, tool use, and instruction following. Claude is what the BUILD and SURVIVE labs default to when a real key is present, but every lab is written to swap it out. Current model families include Claude Opus (most capable), Claude Sonnet (balanced), and Claude Haiku (fastest/cheapest); the specific version string is what you pass to the API, and you should always use the exact current ID from Anthropic's documentation rather than guessing one.

**OpenAI (GPT family).** The most widely adopted family, broad ecosystem and tooling. Similar tier structure: larger/more-capable models down to smaller/cheaper ones.

**Google (Gemini).** Google's family, strong multimodal support and very large context windows, tight integration with Google Cloud.

**Amazon Bedrock.** Not a model of its own - a *platform* that serves models from several providers (including Anthropic, Meta, and others) behind one AWS-native API, with AWS billing and IAM. Good fit for clients already deep in AWS who want one control plane.

**Microsoft (Azure / Foundry).** Microsoft's platform for serving models (including OpenAI and others) with Azure-native billing, identity, and compliance. Natural fit for Microsoft-shop clients.

**Open-source / open-weight models (e.g. Llama, Mistral, and others).** Models whose weights you can download and run yourself. You can host them on your own infrastructure or a rented GPU. More operational work, but maximum control and no per-token vendor bill.

**Local models.** The same open-weight models run on a laptop, workstation, or on-prem server via runtimes designed for local inference. Useful for privacy-sensitive work, offline use, prototyping, and cost control on high volume. Trade-off: smaller local models are less capable than the top hosted models, and you own the ops.

---

## 2. Hosted API vs self-hosted vs local

A crucial axis for client advice - it drives cost, control, and compliance.

**Hosted API (Anthropic, OpenAI, Google directly).** You send a request over the internet, they run the model, you pay per token. Zero infrastructure to manage, always the latest models, elastic scale. The default for most clients most of the time. The trade-off: your data leaves your network (subject to the provider's data-handling terms), and you depend on their uptime and pricing.

**Cloud-platform hosted (Bedrock, Azure/Foundry).** Same "someone else runs it" convenience, but inside a cloud you may already trust, with that cloud's IAM, billing, networking, and compliance certifications. Good for regulated clients who need the data-handling story to live inside AWS or Azure.

**Self-hosted (open-weight on your own GPUs).** You run an open-weight model on infrastructure you control. Data never leaves your environment. No per-token vendor bill (you pay for the hardware/GPU time instead). Best for high volume, strict data residency, or air-gapped environments. Costs shift from per-token to ops-and-hardware, and you are responsible for scaling, updates, and reliability.

**Local.** Runs entirely on a single machine. Maximum privacy, no network needed, no per-call cost. Limited by that machine's memory and speed; best for prototyping, privacy-critical single-user tools, and development.

The consultant's framing: hosted is fastest to value; cloud-platform hosted keeps you inside a trusted boundary; self-hosted/local buys you data control and volume economics at the cost of operational burden.

---

## 3. How the providers actually differ

When you compare providers for a client, these are the dimensions that matter (Concepts 6.4 turns several of these into concrete API mechanics, and the USE deliverable turns all of them into a scoring matrix):

- **Model quality** for the specific task. Do not trust marketing benchmarks; test on the client's real inputs.
- **Cost** - per input token and per output token, which differ. High-volume features live or die on this.
- **Latency / speed** - how fast the first token arrives and how fast tokens stream. Matters for interactive UX.
- **Context window** - how much you can fit in one request.
- **Rate limits** - how many requests and tokens per minute your account is allowed. This constrains real throughput.
- **Data handling** - does the provider train on your data? Retain it? For how long? Where physically? This is often the deciding factor for enterprise clients.
- **Deployment options** - hosted only, or also available via a cloud platform / self-hosted?
- **Regional availability and compliance** - can requests be pinned to a region? Does the provider hold the certifications the client needs (SOC 2, HIPAA-eligible configurations, etc.)?
- **Reliability and support** - uptime history, status transparency, enterprise support terms.
- **Feature surface** - streaming, structured outputs, tool/function calling, prompt caching, batch processing. Not every provider or every model supports every feature the same way.

---

## 4. Same job, different behavior

Even at similar "quality tiers", providers differ in personality and mechanics:

- **Prompting quirks.** A prompt tuned for one model may need adjustment for another. Some newer models even remove the temperature/top-p dials and steer through prompting plus an "effort" or "reasoning depth" setting instead. Do not assume a prompt is portable without re-testing.
- **Refusal behavior.** Different safety training means the same borderline request may be answered by one model and declined by another.
- **Structured-output support.** Some models guarantee schema-valid JSON; others only try. Verify before you rely on it.
- **Tool/function calling shapes.** The mechanic is the same idea everywhere (Concepts 6.4), but the exact request/response format differs per provider.

This is exactly why the BUILD project sends the *same* task to multiple models and compares - so you see these differences with your own eyes instead of taking a vendor's word.

---

## 5. Avoiding vendor lock-in (the core discipline)

Lock-in happens when swapping providers would be so painful that the client stays put even when it is no longer the best choice. It creeps in through:

- Hardcoding one provider's SDK all through the codebase.
- Depending on a provider-specific feature with no equivalent elsewhere.
- Tuning prompts so tightly to one model that they do not transport.

How you design against it (and what the labs demonstrate):

1. **Read credentials from environment variables**, never hardcoded. `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, etc. Swapping providers should not mean editing source.
2. **Put a thin abstraction between your app and the provider.** Your app calls `complete(prompt) -> text`; behind that interface sits whichever provider you chose. Swapping is a one-file change.
3. **Keep prompts in a portable library** (Concepts 6.2 / the USE deliverable), and re-test them when you change models.
4. **Have a mock/stub provider** you can run with no key at all - for development, for tests, and to prove the abstraction is clean. Every lab here includes exactly this.
5. **Write down an exit strategy** as part of the client engagement: which alternate provider you would move to, and what it would take. The USE selection matrix has a column for precisely this.

The abstraction has a happy side effect used throughout these labs: because the app talks to an interface, you can point it at a **local mock server** and exercise all the resilience logic - retries, backoff, budgets, fallback - without spending a cent on a real API or needing any key.

---

## Takeaways

- There is a market of providers (Anthropic, OpenAI, Google, plus platforms like Bedrock and Azure/Foundry, plus open-weight and local) - not one "the LLM".
- Deployment options run from hosted API (fastest to value) to cloud-platform hosted (trusted boundary) to self-hosted/local (data control and volume economics, more ops).
- Compare providers on quality-for-the-task, cost, latency, context, rate limits, data handling, deployment, region/compliance, reliability, and feature surface - and test on the client's real inputs.
- Providers differ in prompting quirks, refusals, structured-output guarantees, and tool-calling shapes; portability is never free.
- Design against lock-in: env-var credentials, a thin provider abstraction, a portable prompt library, a keyless mock provider, and a written exit strategy.

---

## References

Authoritative sources for the provider landscape in this document. The model market moves fast - model IDs, prices, context windows, and even provider names change every few months, so treat any specific detail below as a snapshot and confirm the live numbers from the provider before putting them in a client proposal.

- Anthropic / Claude models (families: Opus most capable, Sonnet balanced, Haiku fastest/cheapest; always use the exact current model ID from the docs): https://docs.anthropic.com/en/docs/about-claude/models
- OpenAI models: https://platform.openai.com/docs/models
- Google Gemini models: https://ai.google.dev/gemini-api/docs/models
- Amazon Bedrock (multi-provider platform behind one AWS API): https://docs.aws.amazon.com/bedrock/
- Microsoft Azure AI Foundry (multi-provider platform on Azure): https://learn.microsoft.com/en-us/azure/ai-foundry/
- Open-weight model families (comparison point): Llama (https://www.llama.com/) and Mistral (https://docs.mistral.ai/)

Prof. Happy (SUTA Labs)
